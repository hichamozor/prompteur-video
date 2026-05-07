import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/settings_model.dart';
import '../providers/scripts_provider.dart';
import '../providers/settings_provider.dart';
import '../services/logger.dart';
import '../services/markdown_parser.dart';
import '../services/wifi_server.dart';

// ── Conversion YUV → JPEG en isolate ─────────────────────────────────────────

class _YuvParams {
  final int width, height, yStride, uvStride, uvPixelStride, rotation;
  final Uint8List y, u, v;

  const _YuvParams({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yStride,
    required this.uvStride,
    required this.uvPixelStride,
    required this.rotation,
  });
}

Uint8List _convertYuvToJpeg(_YuvParams p) {
  final outW = p.width ~/ 4;
  final outH = p.height ~/ 4;
  final base = img.Image(width: outW, height: outH);

  for (int row = 0; row < outH; row++) {
    for (int col = 0; col < outW; col++) {
      final srcRow = row * 4;
      final srcCol = col * 4;
      final yIdx = srcRow * p.yStride + srcCol;
      final uvRow = srcRow >> 1;
      final uvCol = (srcCol >> 1) * p.uvPixelStride;
      final uvIdx = uvRow * p.uvStride + uvCol;

      if (yIdx >= p.y.length || uvIdx >= p.u.length) continue;

      final yv = p.y[yIdx].toDouble();
      final uv = p.u[uvIdx].toDouble() - 128;
      final vv = p.v[uvIdx].toDouble() - 128;

      final r = (yv + 1.402 * vv).clamp(0, 255).toInt();
      final g = (yv - 0.344 * uv - 0.714 * vv).clamp(0, 255).toInt();
      final b = (yv + 1.772 * uv).clamp(0, 255).toInt();

      base.setPixelRgb(col, row, r, g, b);
    }
  }

  final rotated = p.rotation != 0 ? img.copyRotate(base, angle: p.rotation) : base;
  return img.encodeJpg(rotated, quality: 50);
}

// ── Widget ───────────────────────────────────────────────────────────────────

class PrompterScreen extends StatefulWidget {
  final String scriptId;
  const PrompterScreen({super.key, required this.scriptId});

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen>
    with TickerProviderStateMixin {
  // ── Caméra
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  double _minZoom = 1.0, _maxZoom = 10.0, _currentZoom = 1.0, _baseZoom = 1.0;
  double _minExp = -2.0, _maxExp = 2.0, _currentExp = 0.0;
  bool _hideTextForZoom = false;
  int _sensorRotation = 90;
  bool _aeLocked = false;

  // ── Tap-to-focus reticle
  Offset? _focusReticle;
  Timer? _focusReticleTimer;

  // ── Défilement
  final ScrollController _scroll = ScrollController();
  Ticker? _ticker;
  double _lastTickUs = -1;
  bool _isPlaying = false;
  bool _isCountingDown = false;
  int _countdownValue = 0;
  Timer? _countdownTimer;
  bool _showControls = true;

  // ── Enregistrement
  bool _isRecording = false;
  Duration _recDuration = Duration.zero;
  Timer? _recTimer;

  // ── MJPEG
  bool _isConvertingFrame = false;

  // ── Serveur WiFi
  final WifiServer _wifi = WifiServer();
  StreamSubscription<String>? _wsSub;
  Timer? _statusTimer;

  late SettingsProvider _settingsProvider;
  late ScriptsProvider _scriptsProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsProvider = context.read<SettingsProvider>();
    _scriptsProvider = context.read<ScriptsProvider>();
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCamera();
      await _startWifi();
      _statusTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => _broadcastStatus());
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _ticker?.dispose();
    _scroll.dispose();
    _recTimer?.cancel();
    _statusTimer?.cancel();
    _countdownTimer?.cancel();
    _focusReticleTimer?.cancel();
    _wsSub?.cancel();
    _wifi.dispose();
    _cam?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Caméra ─────────────────────────────────────────────────────────────────

  ResolutionPreset _resolutionPreset() {
    switch (_settingsProvider.settings.videoResolution) {
      case 'high':
        return ResolutionPreset.high;
      case 'ultraHigh':
        return ResolutionPreset.ultraHigh;
      default:
        return ResolutionPreset.veryHigh;
    }
  }

  Future<void> _initCamera() async {
    final settings = _settingsProvider.settings;
    if (settings.keepScreenOn) WakelockPlus.enable();

    if (!settings.showCamera) {
      if (mounted) setState(() => _cameraReady = true);
      _startCountdown();
      return;
    }

    final camPerm = await Permission.camera.request();
    await Permission.microphone.request();

    if (!camPerm.isGranted) {
      Log.w('Prompter', 'camera permission refused');
      if (mounted) setState(() => _cameraReady = true);
      _startCountdown();
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        Log.w('Prompter', 'no cameras available');
        if (mounted) setState(() => _cameraReady = true);
        _startCountdown();
        return;
      }

      final desc = _pickCamera(settings.useFrontCamera);
      _sensorRotation = desc.sensorOrientation;

      _cam = CameraController(desc, _resolutionPreset(), enableAudio: true);
      await _cam!.initialize();

      _minZoom = await _cam!.getMinZoomLevel();
      _maxZoom = await _cam!.getMaxZoomLevel();
      _minExp = await _cam!.getMinExposureOffset();
      _maxExp = await _cam!.getMaxExposureOffset();

      _startImageStream();

      if (mounted) {
        setState(() => _cameraReady = true);
        _startCountdown();
      }
    } catch (e, st) {
      Log.e('Prompter', 'camera init failed', e, st);
      if (mounted) {
        setState(() => _cameraReady = true);
        _startCountdown();
      }
    }
  }

  CameraDescription _pickCamera(bool front) {
    final dir = front ? CameraLensDirection.front : CameraLensDirection.back;
    return _cameras.firstWhere((c) => c.lensDirection == dir,
        orElse: () => _cameras.first);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _cam == null) return;
    final wasPlaying = _isPlaying;
    if (_isPlaying) _pauseScrolling();
    if (_isRecording) await _stopRecording();

    await _stopImageStream();
    _settingsProvider.switchCamera();
    await _cam!.dispose();

    final desc = _pickCamera(_settingsProvider.settings.useFrontCamera);
    _sensorRotation = desc.sensorOrientation;
    _cam = CameraController(desc, _resolutionPreset(), enableAudio: true);
    try {
      await _cam!.initialize();
      _minZoom = await _cam!.getMinZoomLevel();
      _maxZoom = await _cam!.getMaxZoomLevel();
      _startImageStream();
    } catch (e, st) {
      Log.e('Prompter', 'switch camera failed', e, st);
    }

    if (mounted) {
      setState(() {
        _currentZoom = 1.0;
        _currentExp = 0.0;
        _aeLocked = false;
      });
      if (wasPlaying) _startScrolling();
    }
  }

  // ── MJPEG ──────────────────────────────────────────────────────────────────

  void _startImageStream() {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_cam!.value.isStreamingImages) return;

    try {
      _cam!.startImageStream((CameraImage frame) {
        if (!_wifi.hasMjpegClients || _isConvertingFrame) return;
        if (frame.planes.length < 3) return;

        _isConvertingFrame = true;
        final params = _YuvParams(
          width: frame.width,
          height: frame.height,
          y: Uint8List.fromList(frame.planes[0].bytes),
          u: Uint8List.fromList(frame.planes[1].bytes),
          v: Uint8List.fromList(frame.planes[2].bytes),
          yStride: frame.planes[0].bytesPerRow,
          uvStride: frame.planes[1].bytesPerRow,
          uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
          rotation: _sensorRotation,
        );

        compute(_convertYuvToJpeg, params).then((jpeg) {
          _wifi.sendMjpegFrame(jpeg);
          _isConvertingFrame = false;
        }).catchError((e) {
          Log.w('Prompter', 'jpeg convert error: $e');
          _isConvertingFrame = false;
        });
      });
    } catch (e, st) {
      Log.e('Prompter', 'startImageStream failed', e, st);
    }
  }

  Future<void> _stopImageStream() async {
    try {
      if (_cam != null && _cam!.value.isStreamingImages) {
        await _cam!.stopImageStream();
      }
    } catch (e) {
      Log.w('Prompter', 'stopImageStream error: $e');
    }
  }

  // ── Tap-to-focus / tap-to-expose ───────────────────────────────────────────

  Future<void> _focusAtPoint(Offset localPos, Size widgetSize) async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    final nx = (localPos.dx / widgetSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / widgetSize.height).clamp(0.0, 1.0);
    final point = Offset(nx, ny);
    try {
      await _cam!.setFocusMode(FocusMode.auto);
      await _cam!.setExposureMode(ExposureMode.auto);
      await _cam!.setFocusPoint(point);
      await _cam!.setExposurePoint(point);
      _aeLocked = false;
      Log.d('Prompter', 'focus @ ${nx.toStringAsFixed(2)}, ${ny.toStringAsFixed(2)}');
    } catch (e) {
      Log.w('Prompter', 'focus failed: $e');
    }
    if (!mounted) return;
    setState(() => _focusReticle = localPos);
    _focusReticleTimer?.cancel();
    _focusReticleTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focusReticle = null);
    });
  }

  Future<void> _toggleAeLock() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    try {
      final mode = _aeLocked ? ExposureMode.auto : ExposureMode.locked;
      await _cam!.setExposureMode(mode);
      setState(() => _aeLocked = !_aeLocked);
      HapticFeedback.lightImpact();
      _showHint(_aeLocked ? 'Expo verrouillée' : 'Expo automatique');
    } catch (e) {
      Log.w('Prompter', 'AE lock failed: $e');
    }
  }

  String? _hintMessage;
  Timer? _hintTimer;
  void _showHint(String msg) {
    setState(() => _hintMessage = msg);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _hintMessage = null);
    });
  }

  // ── Zoom & Exposition ──────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _baseZoom = _currentZoom;
    if (d.pointerCount >= 2) setState(() => _hideTextForZoom = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_cam == null || d.pointerCount < 2) return;
    final zoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    setState(() => _currentZoom = zoom);
    try {
      await _cam!.setZoomLevel(zoom);
    } catch (_) {}
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (mounted) setState(() => _hideTextForZoom = false);
  }

  Future<void> _setExposure(double v) async {
    setState(() => _currentExp = v);
    try {
      await _cam?.setExposureOffset(v);
    } catch (_) {}
  }

  // ── Compte à rebours ───────────────────────────────────────────────────────

  void _startCountdown() {
    final secs = _settingsProvider.settings.countdownSeconds;
    if (secs <= 0) {
      _startScrolling();
      return;
    }
    setState(() {
      _isCountingDown = true;
      _countdownValue = secs;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdownValue--);
      if (_countdownValue <= 0) {
        t.cancel();
        setState(() => _isCountingDown = false);
        _startScrolling();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted && _isCountingDown) setState(() => _isCountingDown = false);
  }

  // ── Défilement ─────────────────────────────────────────────────────────────

  void _startScrolling() {
    if (!mounted) return;
    _lastTickUs = -1;
    setState(() => _isPlaying = true);
    _ticker?.dispose();
    _ticker = createTicker((elapsed) {
      if (!_scroll.hasClients) return;
      final now = elapsed.inMicroseconds.toDouble();
      if (_lastTickUs < 0) {
        _lastTickUs = now;
        return;
      }
      final delta = (now - _lastTickUs) / 1000000.0;
      _lastTickUs = now;
      final next =
          _scroll.offset + _settingsProvider.settings.scrollSpeed * delta;
      if (next >= _scroll.position.maxScrollExtent) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _ticker?.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        _scroll.jumpTo(next);
      }
    })
      ..start();
  }

  void _pauseScrolling() {
    _ticker?.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  void _togglePlay() {
    if (_isCountingDown) return;
    _isPlaying ? _pauseScrolling() : _startScrolling();
    _broadcastStatus();
  }

  void _adjustSpeed(double delta) {
    final s =
        (_settingsProvider.settings.scrollSpeed + delta).clamp(20.0, 300.0);
    _settingsProvider.updateScrollSpeed(s);
    _broadcastStatus();
  }

  void _rewind(double seconds) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset - _settingsProvider.settings.scrollSpeed * seconds)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
    _broadcastStatus();
  }

  void _resetScroll() {
    _pauseScrolling();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _broadcastStatus();
  }

  // ── Enregistrement ─────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    _isRecording ? await _stopRecording() : await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    try {
      await _stopImageStream();
      await _cam!.startVideoRecording();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recDuration += const Duration(seconds: 1));
          _broadcastStatus();
        }
      });
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recDuration = Duration.zero;
        });
      }
      _broadcastStatus();
      HapticFeedback.mediumImpact();
    } catch (e, st) {
      Log.e('Prompter', 'start recording failed', e, st);
      _startImageStream();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_cam == null) return;
    _recTimer?.cancel();
    try {
      final file = await _cam!.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      _broadcastStatus();
      _startImageStream();
      await _saveToGallery(file.path);
      HapticFeedback.mediumImpact();
    } catch (e, st) {
      Log.e('Prompter', 'stop recording failed', e, st);
      if (mounted) setState(() => _isRecording = false);
      _startImageStream();
    }
  }

  Future<void> _saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putVideo(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vidéo sauvegardée dans la Galerie ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      Log.e('Prompter', 'save to gallery failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur sauvegarde: $e'),
              backgroundColor: Colors.orange),
        );
      }
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Serveur WiFi ───────────────────────────────────────────────────────────

  Future<void> _startWifi() async {
    _wifi.scriptProvider = () =>
        _scriptsProvider.findById(widget.scriptId)?.content ?? '';
    await _wifi.start();
    _wsSub = _wifi.onWsMessage.listen(_handleWsMessage);
  }

  void _handleWsMessage(String raw) {
    if (raw.startsWith('script:')) {
      final text = raw.substring(7);
      _scriptsProvider.update(widget.scriptId, content: text).then((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        if (_isPlaying) _pauseScrolling();
      });
      return;
    }
    if (raw == 'ping') return;
    switch (raw) {
      case 'toggle': _togglePlay(); break;
      case 'pause':  _pauseScrolling(); break;
      case 'play':   if (!_isCountingDown) _startScrolling(); break;
      case 'rewind2': _rewind(2.0); break;
      case 'home':   _resetScroll(); break;
      case 'speed+': _adjustSpeed(10); break;
      case 'speed-': _adjustSpeed(-10); break;
      case 'rec':    _toggleRecording(); break;
    }
    _broadcastStatus();
  }

  void _broadcastStatus() {
    if (!_wifi.running) return;
    double progress = 0;
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      progress = _scroll.offset / _scroll.position.maxScrollExtent;
    }
    _wifi.broadcastStatus({
      'playing': _isPlaying,
      'speed': _settingsProvider.settings.scrollSpeed.round(),
      'progress': (progress * 100).round(),
      'recording': _isRecording,
      'duration': _fmtDuration(_recDuration),
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final script =
        context.watch<ScriptsProvider>().findById(widget.scriptId);
    final content = script?.content ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showControls = !_showControls),
            onDoubleTapDown: (d) => _focusAtPoint(d.localPosition, size),
            onDoubleTap: () {}, // reserved to make double-tap detector active
            onLongPress: _toggleAeLock,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              children: [
                // ── Fond caméra (sans distorsion)
                if (_cameraReady &&
                    _cam != null &&
                    _cam!.value.isInitialized &&
                    settings.showCamera)
                  Positioned.fill(
                    child: ClipRect(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(settings.mirrorMode ? -1.0 : 1.0, 1.0),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cam!.value.previewSize?.height ?? 1920,
                            height: _cam!.value.previewSize?.width ?? 1080,
                            child: CameraPreview(_cam!),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Masque focus haut/bas
                if (_cameraReady &&
                    settings.focusMaskOpacity > 0 &&
                    !_hideTextForZoom)
                  IgnorePointer(
                    child: _FocusMask(opacity: settings.focusMaskOpacity),
                  ),

                // ── Texte défilant
                if (_cameraReady && !_hideTextForZoom)
                  _buildTextOverlay(settings, content, size),

                // ── Ligne de lecture
                if (_cameraReady && settings.showReadingLine && !_hideTextForZoom)
                  IgnorePointer(child: _ReadingLine(top: size.height / 3)),

                // ── Safe-zone TikTok / Reels
                if (_cameraReady && settings.showSafeZone && !_hideTextForZoom)
                  IgnorePointer(child: _SafeZoneOverlay(size: size)),

                // ── Reticle focus
                if (_focusReticle != null)
                  IgnorePointer(
                    child: _FocusReticle(position: _focusReticle!),
                  ),

                // ── Indicateur AE lock
                if (_aeLocked && !_hideTextForZoom)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock, size: 11, color: Colors.black),
                        SizedBox(width: 4),
                        Text('AE',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),

                // ── Hint / message éphémère
                if (_hintMessage != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_hintMessage!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ),
                  ),

                // ── Indicateur zoom
                if (_hideTextForZoom)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('x${_currentZoom.toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),

                // ── Chargement
                if (!_cameraReady)
                  const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF6C63FF))),

                // ── REC indicator
                if (_isRecording)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.fiber_manual_record,
                            color: Colors.white, size: 10),
                        const SizedBox(width: 5),
                        Text(_fmtDuration(_recDuration),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace')),
                      ]),
                    ),
                  ),

                // ── Compte à rebours
                if (_isCountingDown)
                  Center(
                    child: GestureDetector(
                      onTap: _cancelCountdown,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.78),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF6C63FF), width: 3)),
                        child: Center(
                          child: Text('$_countdownValue',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 76,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),

                // ── Contrôles
                if (_showControls && !_isCountingDown) _buildControls(settings),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextOverlay(PrompterSettings settings, String content, Size size) {
    return Positioned.fill(
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: settings.marginHorizontal,
          vertical: size.height * 0.45,
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(settings.mirrorMode ? -1.0 : 1.0, 1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: settings.backgroundColor
                  .withOpacity(settings.backgroundOpacity),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(height: settings.lineSpacing),
              child: Text.rich(
                PrompterMarkdown.parse(
                  content,
                  textColor: settings.textColor,
                  sectionColor: const Color(0xFFFFC857),
                  commentColor: Colors.white38,
                  fontSize: settings.fontSize,
                  baseWeight: FontWeight.w500,
                  fontFamily: settings.fontFamily == 'Default'
                      ? null
                      : settings.fontFamily,
                ),
                textAlign: settings.textAlign,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(PrompterSettings settings) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Stack(children: [
      // ── Barre haute
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(4, topPad + 4, 4, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
            ),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            if (_wifi.ip.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(
                      text: 'http://${_wifi.ip}:${WifiServer.port}'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Adresse copiée !'),
                      duration: Duration(seconds: 1)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi,
                        color: Color(0xFF6C63FF), size: 13),
                    const SizedBox(width: 4),
                    Text('${_wifi.ip}:${WifiServer.port}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Safe-zone',
              icon: Icon(Icons.crop_free,
                  color: settings.showSafeZone
                      ? const Color(0xFF6C63FF)
                      : Colors.white),
              onPressed: () =>
                  context.read<SettingsProvider>().toggleSafeZone(),
            ),
            IconButton(
              tooltip: 'Mode miroir',
              icon: Icon(Icons.flip,
                  color: settings.mirrorMode
                      ? const Color(0xFF6C63FF)
                      : Colors.white),
              onPressed: () =>
                  context.read<SettingsProvider>().toggleMirror(),
            ),
            if (_cameras.length >= 2)
              IconButton(
                tooltip: 'Changer de caméra',
                icon: const Icon(Icons.flip_camera_android,
                    color: Colors.white),
                onPressed: _switchCamera,
              ),
            IconButton(
              tooltip: 'Caméra',
              icon: Icon(
                settings.showCamera ? Icons.videocam : Icons.videocam_off,
                color: settings.showCamera ? Colors.white : Colors.red,
              ),
              onPressed: () =>
                  context.read<SettingsProvider>().toggleCamera(),
            ),
          ]),
        ),
      ),

      // ── Slider exposition (droite)
      if (_cam != null && _cam!.value.isInitialized)
        Positioned(
          right: 10,
          top: topPad + 70,
          bottom: botPad + 110,
          child: Column(children: [
            const Icon(Icons.wb_sunny, color: Colors.white38, size: 14),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Colors.white54,
                    thumbColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _currentExp.clamp(_minExp, _maxExp),
                    min: _minExp,
                    max: _maxExp,
                    onChanged: _setExposure,
                  ),
                ),
              ),
            ),
            const Icon(Icons.wb_shade, color: Colors.white38, size: 14),
          ]),
        ),

      // ── Barre basse
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, botPad + 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.75), Colors.transparent],
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _CtrlBtn(
                icon: Icons.remove_circle_outline,
                label: 'Lent',
                onTap: () => _adjustSpeed(-15)),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                    color: Color(0xFF6C63FF), shape: BoxShape.circle),
                child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(width: 14),
            _CtrlBtn(
                icon: Icons.add_circle_outline,
                label: 'Vite',
                onTap: () => _adjustSpeed(15)),
            const SizedBox(width: 24),
            _CtrlBtn(
              icon: Icons.vertical_align_top,
              label: 'Début',
              onTap: _resetScroll,
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Colors.red
                      : Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.red, width: _isRecording ? 0 : 2),
                ),
                child: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    color: Colors.white,
                    size: _isRecording ? 28 : 22),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Widgets locaux ───────────────────────────────────────────────────────────

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ]),
      );
}

class _ReadingLine extends StatelessWidget {
  final double top;
  const _ReadingLine({required this.top});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.85),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              color: const Color(0xFF6C63FF).withOpacity(0.35),
            ),
          ),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.85),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusMask extends StatelessWidget {
  final double opacity;
  const _FocusMask({required this.opacity});
  @override
  Widget build(BuildContext context) {
    final dark = Colors.black.withOpacity(opacity);
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Expanded(
              flex: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [dark, Colors.transparent],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 0),
            Expanded(
              flex: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, dark],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeZoneOverlay extends StatelessWidget {
  final Size size;
  const _SafeZoneOverlay({required this.size});
  @override
  Widget build(BuildContext context) {
    // TikTok / Reels safe zone (approximative en portrait 9:16) :
    //   Top    : 8% (handle + username)
    //   Bottom : 22% (caption + boutons + nav)
    //   Right  : 14% (boutons d'actions)
    final topInset = size.height * 0.08;
    final bottomInset = size.height * 0.22;
    final rightInset = size.width * 0.14;
    return Positioned.fill(
      child: CustomPaint(
        painter: _SafeZonePainter(
          topInset: topInset,
          bottomInset: bottomInset,
          rightInset: rightInset,
        ),
      ),
    );
  }
}

class _SafeZonePainter extends CustomPainter {
  final double topInset, bottomInset, rightInset;
  _SafeZonePainter(
      {required this.topInset,
      required this.bottomInset,
      required this.rightInset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellowAccent.withOpacity(0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTRB(
      4,
      topInset,
      size.width - rightInset,
      size.height - bottomInset,
    );
    _drawDashedRect(canvas, rect, paint);

    // Label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'SAFE ZONE',
        style: TextStyle(
          color: Colors.yellowAccent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + 4, rect.top + 3));
  }

  void _drawDashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 6.0;
    const gap = 5.0;
    void line(Offset a, Offset b) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = (dx == 0 ? dy.abs() : dx.abs());
      double drawn = 0;
      while (drawn < len) {
        final t1 = drawn / len;
        final t2 = ((drawn + dash) / len).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(a.dx + dx * t1, a.dy + dy * t1),
          Offset(a.dx + dx * t2, a.dy + dy * t2),
          p,
        );
        drawn += dash + gap;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_SafeZonePainter old) =>
      old.topInset != topInset ||
      old.bottomInset != bottomInset ||
      old.rightInset != rightInset;
}

class _FocusReticle extends StatefulWidget {
  final Offset position;
  const _FocusReticle({required this.position});
  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final scale = 1.6 - 0.6 * t; // 1.6 → 1.0
        final opacity = (t < 0.6 ? 1.0 : (1.0 - (t - 0.6) / 0.4)).clamp(0.0, 1.0);
        return Positioned(
          left: widget.position.dx - 30,
          top: widget.position.dy - 30,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.yellowAccent, width: 1.4),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 8,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.yellowAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

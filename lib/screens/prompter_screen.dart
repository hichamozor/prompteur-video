import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/settings_provider.dart';
import '../models/settings_model.dart';

class PrompterScreen extends StatefulWidget {
  const PrompterScreen({super.key});

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;

  final ScrollController _scrollController = ScrollController();
  Ticker? _scrollTicker;
  double _lastTickUs = -1;
  bool _isPlaying = false;
  bool _isCountingDown = false;
  int _countdownValue = 0;
  bool _showControls = true;

  late SettingsProvider _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<SettingsProvider>();
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollTicker?.dispose();
    _scrollController.dispose();
    _cameraController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final settings = _provider.settings;

    if (settings.keepScreenOn) WakelockPlus.enable();

    if (!settings.showCamera) {
      if (mounted) setState(() => _cameraReady = true);
      _startCountdown();
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _cameraReady = true);
      _startCountdown();
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraReady = true);
        _startCountdown();
        return;
      }

      final camDesc = _pickCamera(settings.useFrontCamera);
      _cameraController = CameraController(camDesc, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _cameraReady = true);
        _startCountdown();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cameraReady = true);
        _startCountdown();
      }
    }
  }

  CameraDescription _pickCamera(bool useFront) {
    final dir = useFront ? CameraLensDirection.front : CameraLensDirection.back;
    return _cameras.firstWhere((c) => c.lensDirection == dir, orElse: () => _cameras.first);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final wasPlaying = _isPlaying;
    if (_isPlaying) _pauseScrolling();

    _provider.switchCamera();
    await _cameraController?.dispose();

    final camDesc = _pickCamera(_provider.settings.useFrontCamera);
    _cameraController = CameraController(camDesc, ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();

    if (mounted) {
      setState(() {});
      if (wasPlaying) _startScrolling();
    }
  }

  void _startCountdown() {
    final secs = _provider.settings.countdownSeconds;
    if (secs == 0) {
      _startScrolling();
      return;
    }
    setState(() {
      _isCountingDown = true;
      _countdownValue = secs;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdownValue--);
      if (_countdownValue <= 0) {
        setState(() => _isCountingDown = false);
        _startScrolling();
        return false;
      }
      return true;
    });
  }

  void _startScrolling() {
    if (!mounted) return;
    _lastTickUs = -1;
    setState(() => _isPlaying = true);
    _scrollTicker?.dispose();
    _scrollTicker = createTicker((elapsed) {
      if (!_scrollController.hasClients) return;
      final now = elapsed.inMicroseconds.toDouble();
      if (_lastTickUs < 0) { _lastTickUs = now; return; }
      final delta = (now - _lastTickUs) / 1000000.0;
      _lastTickUs = now;
      final newOffset = _scrollController.offset + _provider.settings.scrollSpeed * delta;
      if (newOffset >= _scrollController.position.maxScrollExtent) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        _scrollTicker?.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        _scrollController.jumpTo(newOffset);
      }
    });
    _scrollTicker!.start();
  }

  void _pauseScrolling() {
    _scrollTicker?.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  void _togglePlay() {
    if (_isCountingDown) return;
    _isPlaying ? _pauseScrolling() : _startScrolling();
  }

  void _adjustSpeed(double delta) {
    final newSpeed = (_provider.settings.scrollSpeed + delta).clamp(20.0, 300.0);
    _provider.updateScrollSpeed(newSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final script = context.watch<SettingsProvider>().script;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // Fond caméra
            if (_cameraReady &&
                _cameraController != null &&
                _cameraController!.value.isInitialized &&
                settings.showCamera)
              Positioned.fill(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(settings.mirrorMode ? -1.0 : 1.0, 1.0),
                  child: CameraPreview(_cameraController!),
                ),
              ),

            // Texte défilant
            if (_cameraReady) _buildTextOverlay(settings, script),

            // Chargement
            if (!_cameraReady)
              const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),

            // Compte à rebours
            if (_isCountingDown)
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$_countdownValue',
                      style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),

            // Contrôles
            if (_showControls && !_isCountingDown) _buildControls(settings),
          ],
        ),
      ),
    );
  }

  Widget _buildTextOverlay(PrompterSettings settings, String script) {
    final screenH = MediaQuery.of(context).size.height;
    return Positioned.fill(
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: settings.marginHorizontal,
          vertical: screenH * 0.45,
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scale(settings.mirrorMode ? -1.0 : 1.0, 1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: settings.backgroundColor.withOpacity(settings.backgroundOpacity),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              script,
              textAlign: settings.textAlign,
              style: TextStyle(
                color: settings.textColor,
                fontSize: settings.fontSize,
                height: settings.lineSpacing,
                fontFamily: settings.fontFamily == 'Default' ? null : settings.fontFamily,
                fontWeight: FontWeight.w500,
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

    return Stack(
      children: [
        // Barre haute
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(4, topPad + 4, 4, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.flip, color: settings.mirrorMode ? const Color(0xFF6C63FF) : Colors.white),
                  onPressed: () => context.read<SettingsProvider>().toggleMirror(),
                  tooltip: 'Miroir',
                ),
                if (_cameras.length >= 2)
                  IconButton(
                    icon: const Icon(Icons.flip_camera_android, color: Colors.white),
                    onPressed: _switchCamera,
                    tooltip: 'Changer caméra',
                  ),
                IconButton(
                  icon: Icon(
                    settings.showCamera ? Icons.videocam : Icons.videocam_off,
                    color: settings.showCamera ? Colors.white : Colors.red,
                  ),
                  onPressed: () => context.read<SettingsProvider>().toggleCamera(),
                  tooltip: 'Caméra',
                ),
              ],
            ),
          ),
        ),

        // Barre basse
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CtrlBtn(icon: Icons.remove_circle_outline, label: 'Lent', onTap: () => _adjustSpeed(-15)),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 64, height: 64,
                    decoration: const BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                    child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(width: 16),
                _CtrlBtn(icon: Icons.add_circle_outline, label: 'Vite', onTap: () => _adjustSpeed(15)),
                const SizedBox(width: 28),
                _CtrlBtn(
                  icon: Icons.vertical_align_top,
                  label: 'Début',
                  onTap: () {
                    _pauseScrolling();
                    _scrollController.jumpTo(0);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CtrlBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

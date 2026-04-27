import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import '../providers/settings_provider.dart';

// ── Données pour l'isolate de conversion YUV → JPEG ───────────────────────

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

// Fonction top-level appelée dans un isolate via compute()
Uint8List _convertYuvToJpeg(_YuvParams p) {
  // Quart de résolution pour la performance (~480x270 pour source 1080p)
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

  final rotated =
      p.rotation != 0 ? img.copyRotate(base, angle: p.rotation) : base;
  return img.encodeJpg(rotated, quality: 50);
}

// ── Widget ─────────────────────────────────────────────────────────────────

class PrompterScreen extends StatefulWidget {
  const PrompterScreen({super.key});

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen>
    with TickerProviderStateMixin {
  // Caméra
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  double _minZoom = 1.0, _maxZoom = 10.0, _currentZoom = 1.0, _baseZoom = 1.0;
  double _minExp = -2.0, _maxExp = 2.0, _currentExp = 0.0;
  bool _hideTextForZoom = false;
  int _sensorRotation = 90;

  // Défilement
  final ScrollController _scroll = ScrollController();
  Ticker? _ticker;
  double _lastTickUs = -1;
  bool _isPlaying = false;
  bool _isCountingDown = false;
  int _countdownValue = 0;
  bool _showControls = true;

  // Enregistrement
  bool _isRecording = false;
  Duration _recDuration = Duration.zero;
  Timer? _recTimer;

  // MJPEG stream
  final List<HttpResponse> _mjpegClients = [];
  bool _isConvertingFrame = false;
  int _frameCounter = 0;

  // Serveur WiFi
  HttpServer? _server;
  final Set<WebSocket> _wsClients = {};
  String _serverIp = '';
  static const int _port = 8080;
  Timer? _statusTimer;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCamera();
      await _startWifiServer();
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
    _server?.close(force: true);
    for (final ws in List.of(_wsClients)) {
      try { ws.close(); } catch (_) {}
    }
    for (final r in List.of(_mjpegClients)) {
      try { r.close(); } catch (_) {}
    }
    _cam?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Caméra ──────────────────────────────────────────────────────────────

  ResolutionPreset _resolutionPreset() {
    switch (_provider.settings.videoResolution) {
      case 'high': return ResolutionPreset.high;
      case 'ultraHigh': return ResolutionPreset.ultraHigh;
      default: return ResolutionPreset.veryHigh;
    }
  }

  Future<void> _initCamera() async {
    final settings = _provider.settings;
    if (settings.keepScreenOn) WakelockPlus.enable();

    if (!settings.showCamera) {
      if (mounted) setState(() => _cameraReady = true);
      _startCountdown();
      return;
    }

    final camPerm = await Permission.camera.request();
    await Permission.microphone.request();

    if (!camPerm.isGranted) {
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
    } catch (_) {
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
    _provider.switchCamera();
    await _cam!.dispose();

    final desc = _pickCamera(_provider.settings.useFrontCamera);
    _sensorRotation = desc.sensorOrientation;
    _cam = CameraController(desc, _resolutionPreset(), enableAudio: true);
    await _cam!.initialize();

    _minZoom = await _cam!.getMinZoomLevel();
    _maxZoom = await _cam!.getMaxZoomLevel();

    _startImageStream();

    if (mounted) {
      setState(() { _currentZoom = 1.0; _currentExp = 0.0; });
      if (wasPlaying) _startScrolling();
    }
  }

  // ── MJPEG stream ─────────────────────────────────────────────────────────

  void _startImageStream() {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_cam!.value.isStreamingImages) return;

    try {
      _cam!.startImageStream((CameraImage frame) {
        if (_mjpegClients.isEmpty || _isConvertingFrame) return;
        _frameCounter++;
        if (_frameCounter % 3 != 0) return; // ~10 fps

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
          _sendMjpegFrame(jpeg);
          _isConvertingFrame = false;
        }).catchError((_) {
          _isConvertingFrame = false;
        });
      });
    } catch (_) {}
  }

  Future<void> _stopImageStream() async {
    try {
      if (_cam != null && _cam!.value.isStreamingImages) {
        await _cam!.stopImageStream();
      }
    } catch (_) {}
  }

  void _sendMjpegFrame(Uint8List jpeg) {
    if (_mjpegClients.isEmpty) return;
    final header =
        '--mjpeg\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n';
    for (final client in List.of(_mjpegClients)) {
      try {
        client.write(header);
        client.add(jpeg);
        client.write('\r\n');
      } catch (_) {
        _mjpegClients.remove(client);
      }
    }
  }

  // ── Zoom & Exposition ────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _baseZoom = _currentZoom;
    if (d.pointerCount >= 2) setState(() => _hideTextForZoom = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_cam == null || d.pointerCount < 2) return;
    final zoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    setState(() => _currentZoom = zoom);
    await _cam!.setZoomLevel(zoom);
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (mounted) setState(() => _hideTextForZoom = false);
  }

  Future<void> _setExposure(double v) async {
    setState(() => _currentExp = v);
    await _cam?.setExposureOffset(v);
  }

  // ── Compte à rebours ─────────────────────────────────────────────────────

  void _startCountdown() {
    final secs = _provider.settings.countdownSeconds;
    if (secs == 0) { _startScrolling(); return; }
    setState(() { _isCountingDown = true; _countdownValue = secs; });
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

  // ── Défilement ───────────────────────────────────────────────────────────

  void _startScrolling() {
    if (!mounted) return;
    _lastTickUs = -1;
    setState(() => _isPlaying = true);
    _ticker?.dispose();
    _ticker = createTicker((elapsed) {
      if (!_scroll.hasClients) return;
      final now = elapsed.inMicroseconds.toDouble();
      if (_lastTickUs < 0) { _lastTickUs = now; return; }
      final delta = (now - _lastTickUs) / 1000000.0;
      _lastTickUs = now;
      final next = _scroll.offset + _provider.settings.scrollSpeed * delta;
      if (next >= _scroll.position.maxScrollExtent) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _ticker?.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        _scroll.jumpTo(next);
      }
    })..start();
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
    final s = (_provider.settings.scrollSpeed + delta).clamp(20.0, 300.0);
    _provider.updateScrollSpeed(s);
    _broadcastStatus();
  }

  void _rewind(double seconds) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset - _provider.settings.scrollSpeed * seconds)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
    _broadcastStatus();
  }

  // ── Enregistrement ───────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    _isRecording ? await _stopRecording() : await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    try {
      await _stopImageStream();
      await _cam!.startVideoRecording();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recDuration += const Duration(seconds: 1));
        _broadcastStatus();
      });
      if (mounted) setState(() { _isRecording = true; _recDuration = Duration.zero; });
      _broadcastStatus();
    } catch (e) {
      _startImageStream();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
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
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
      _startImageStream();
    }
  }

  Future<void> _saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putVideo(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Vidéo sauvegardée dans la Galerie ✓'),
              backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sauvegarde: $e'),
              backgroundColor: Colors.orange));
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Serveur WiFi ─────────────────────────────────────────────────────────

  Future<void> _startWifiServer() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _serverIp = addr.address);
            break;
          }
        }
        if (_serverIp.isNotEmpty) break;
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server!.listen((req) async {
        // WebSocket
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          _wsClients.add(ws);
          _broadcastStatus();
          ws.listen(
            (data) => _handleWsCommand(data.toString()),
            onDone: () => _wsClients.remove(ws),
            onError: (_) => _wsClients.remove(ws),
            cancelOnError: true,
          );
          return;
        }

        // Stream MJPEG
        if (req.uri.path == '/stream') {
          final resp = req.response;
          resp.headers.set(HttpHeaders.contentTypeHeader,
              'multipart/x-mixed-replace; boundary=mjpeg');
          resp.headers.set('Cache-Control', 'no-cache');
          resp.headers.set('Connection', 'keep-alive');
          resp.statusCode = 200;
          _mjpegClients.add(resp);
          resp.done.catchError((_) => _mjpegClients.remove(resp));
          return; // ne pas fermer la réponse
        }

        // Page de contrôle HTML
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_controlPageHtml())
          ..close();
      });
    } catch (_) {}
  }

  void _handleWsCommand(String cmd) {
    switch (cmd) {
      case 'toggle': _togglePlay(); break;
      case 'pause': _pauseScrolling(); break;
      case 'play': if (!_isCountingDown) _startScrolling(); break;
      case 'rewind2': _rewind(2.0); break;
      case 'home':
        _pauseScrolling();
        if (_scroll.hasClients) _scroll.jumpTo(0);
        break;
      case 'speed+': _adjustSpeed(10); break;
      case 'speed-': _adjustSpeed(-10); break;
      case 'rec': _toggleRecording(); break;
    }
    _broadcastStatus();
  }

  void _broadcastStatus() {
    if (_wsClients.isEmpty) return;
    double progress = 0;
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      progress = _scroll.offset / _scroll.position.maxScrollExtent;
    }
    final msg = jsonEncode({
      'playing': _isPlaying,
      'speed': _provider.settings.scrollSpeed.round(),
      'progress': (progress * 100).round(),
      'recording': _isRecording,
      'duration': _fmtDuration(_recDuration),
    });
    for (final ws in List.of(_wsClients)) {
      try { ws.add(msg); } catch (_) { _wsClients.remove(ws); }
    }
  }

  String _controlPageHtml() => '''<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Prompteur - Telecommande</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#1A1A2E;color:#fff;font-family:-apple-system,sans-serif;
  min-height:100vh;display:flex;flex-direction:column;align-items:center;
  padding:16px;gap:12px;-webkit-tap-highlight-color:transparent}
h1{font-size:18px;color:#6C63FF}
#st{font-size:12px;color:#666}
.preview-wrap{position:relative;width:180px;height:320px;
  background:#0a0a14;border-radius:10px;overflow:hidden;
  border:1px solid #2a2a4a;flex-shrink:0}
#stream-img{width:100%;height:100%;object-fit:cover;display:block}
#rec-overlay{position:absolute;inset:0;background:rgba(0,0,0,.75);
  display:none;align-items:center;justify-content:center;
  color:#ff4444;font-weight:bold;font-size:14px;text-align:center;padding:10px}
.info{display:flex;justify-content:space-between;width:100%;max-width:440px;
  font-size:13px;color:#888}
.info b{color:#fff}
.pb{width:100%;max-width:440px;background:#16213E;border-radius:99px;height:6px}
.pf{height:6px;background:#6C63FF;border-radius:99px;width:0%;transition:width .5s}
.g{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;width:100%;max-width:440px}
.b{background:#16213E;border:1.5px solid #2a2a4a;border-radius:12px;
  color:#fff;padding:16px 8px;font-size:13px;cursor:pointer;
  display:flex;flex-direction:column;align-items:center;gap:5px;
  transition:background .1s,transform .1s;user-select:none}
.b:hover{background:#6C63FF;border-color:#6C63FF}
.b:active{transform:scale(.94)}
.b .i{font-size:24px}
.full{grid-column:1/-1}
.rec{border-color:#ff4444}
.rec:hover,.rec.on{background:#cc0000;border-color:#ff4444}
.kbd{color:#444;font-size:11px;text-align:center;line-height:2.2;max-width:440px}
kbd{background:#16213E;padding:2px 7px;border-radius:5px;
  color:#888;border:1px solid #333;font-size:11px}
</style>
</head>
<body>
<h1>Prompteur - Telecommande</h1>
<div id="st">Connexion...</div>
<div class="preview-wrap">
  <img id="stream-img" src="/stream" alt="Apercu camera">
  <div id="rec-overlay">&#9210; Enregistrement<br>en cours</div>
</div>
<div class="info">
  <span>Progression: <b id="pct">0%</b></span>
  <span>Vitesse: <b id="spd">-</b></span>
  <span id="dur"></span>
</div>
<div class="pb"><div class="pf" id="prog"></div></div>
<div class="g">
  <button class="b" onclick="s('rewind2')"><span class="i">&#8249;&#8249;</span>-2s</button>
  <button class="b" id="bp" onclick="s('toggle')"><span class="i" id="ip">&#9646;&#9646;</span><span id="lp">PAUSE</span></button>
  <button class="b" onclick="s('home')"><span class="i">&#9198;</span>DEBUT</button>
  <button class="b" onclick="s('speed-')"><span class="i">&#128022;</span>LENT</button>
  <button class="b" onclick="s('speed+')"><span class="i">&#128007;</span>VITE</button>
  <button class="b" onclick="s('rewind2')"><span class="i">&#8617;</span>RETOUR</button>
  <button class="b rec full" id="br" onclick="s('rec')">
    <span class="i" id="ir">&#9210;</span>
    <span id="lr">DEMARRER ENREGISTREMENT</span>
  </button>
</div>
<div class="kbd">
  <kbd>Espace</kbd> Pause/Play &nbsp;
  <kbd>&larr;</kbd> -2s &nbsp;
  <kbd>&uarr;</kbd> + Vite &nbsp;
  <kbd>&darr;</kbd> - Lent &nbsp;
  <kbd>Home</kbd> Debut &nbsp;
  <kbd>R</kbd> Enregistrement
</div>
<script>
var ws=new WebSocket('ws://'+location.host+'/ws');
ws.onopen=function(){document.getElementById('st').innerHTML='<span style="color:#4CAF50">&#9679;</span> Connecte';};
ws.onclose=function(){document.getElementById('st').innerHTML='<span style="color:#f44">&#9679;</span> Deconnecte';};
ws.onmessage=function(e){
  var d=JSON.parse(e.data);
  document.getElementById('ip').innerHTML=d.playing?'&#9646;&#9646;':'&#9654;';
  document.getElementById('lp').textContent=d.playing?'PAUSE':'REPRENDRE';
  document.getElementById('spd').textContent=d.speed;
  document.getElementById('pct').textContent=d.progress+'%';
  document.getElementById('prog').style.width=d.progress+'%';
  document.getElementById('ir').innerHTML=d.recording?'&#9209;':'&#9210;';
  document.getElementById('lr').textContent=d.recording?'STOP - '+d.duration:'DEMARRER ENREGISTREMENT';
  var ro=document.getElementById('rec-overlay');
  var si=document.getElementById('stream-img');
  if(d.recording){
    ro.style.display='flex';
  } else {
    if(ro.style.display==='flex'){
      si.src='/stream?t='+Date.now();
    }
    ro.style.display='none';
  }
  if(d.recording){document.getElementById('br').classList.add('on');}
  else{document.getElementById('br').classList.remove('on');}
};
function s(cmd){if(ws.readyState===1)ws.send(cmd);}
document.addEventListener('keydown',function(e){
  switch(e.code){
    case 'Space':e.preventDefault();s('toggle');break;
    case 'ArrowLeft':e.preventDefault();s('rewind2');break;
    case 'ArrowUp':e.preventDefault();s('speed+');break;
    case 'ArrowDown':e.preventDefault();s('speed-');break;
    case 'Home':e.preventDefault();s('home');break;
    case 'KeyR':s('rec');break;
  }
});
</script>
</body>
</html>''';

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final script = context.watch<SettingsProvider>().script;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(children: [
          // ── Fond caméra (sans distorsion) ─────────────────────
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
                      // Les dimensions du capteur sont en paysage → on les inverse
                      // pour afficher en portrait sans distorsion
                      width: _cam!.value.previewSize?.height ?? 1920,
                      height: _cam!.value.previewSize?.width ?? 1080,
                      child: CameraPreview(_cam!),
                    ),
                  ),
                ),
              ),
            ),

          // ── Texte défilant ────────────────────────────────────
          if (_cameraReady && !_hideTextForZoom)
            _buildTextOverlay(settings, script),

          // ── Chargement ────────────────────────────────────────
          if (!_cameraReady)
            const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C63FF))),

          // ── Indicateur zoom ───────────────────────────────────
          if (_hideTextForZoom)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

          // ── Indicateur REC (toujours visible) ─────────────────
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

          // ── Compte à rebours ──────────────────────────────────
          if (_isCountingDown)
            Center(
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    shape: BoxShape.circle),
                child: Center(
                    child: Text('$_countdownValue',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.bold))),
              ),
            ),

          // ── Contrôles ─────────────────────────────────────────
          if (_showControls && !_isCountingDown) _buildControls(settings),
        ]),
      ),
    );
  }

  Widget _buildTextOverlay(PrompterSettings settings, String script) {
    final screenH = MediaQuery.of(context).size.height;
    return Positioned.fill(
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: settings.marginHorizontal,
          vertical: screenH * 0.45,
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
            child: Text(
              script,
              textAlign: settings.textAlign,
              style: TextStyle(
                color: settings.textColor,
                fontSize: settings.fontSize,
                height: settings.lineSpacing,
                fontFamily: settings.fontFamily == 'Default'
                    ? null
                    : settings.fontFamily,
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

    return Stack(children: [
      // ── Barre haute ───────────────────────────────────────────
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
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            if (_serverIp.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: 'http://$_serverIp:$_port'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Adresse copiée !'),
                      duration: Duration(seconds: 1)));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi, color: Color(0xFF6C63FF), size: 13),
                    const SizedBox(width: 4),
                    Text('$_serverIp:$_port',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.flip,
                  color: settings.mirrorMode
                      ? const Color(0xFF6C63FF)
                      : Colors.white),
              onPressed: () =>
                  context.read<SettingsProvider>().toggleMirror(),
            ),
            if (_cameras.length >= 2)
              IconButton(
                icon: const Icon(Icons.flip_camera_android,
                    color: Colors.white),
                onPressed: _switchCamera,
              ),
            IconButton(
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

      // ── Slider exposition (droite) ────────────────────────────
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

      // ── Barre basse ───────────────────────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0,
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
                width: 62, height: 62,
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
              onTap: () {
                _pauseScrolling();
                if (_scroll.hasClients) _scroll.jumpTo(0);
                _broadcastStatus();
              },
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Colors.red
                      : Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.red, width: _isRecording ? 0 : 2),
                ),
                child: Icon(
                    _isRecording
                        ? Icons.stop
                        : Icons.fiber_manual_record,
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

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CtrlBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44, height: 44,
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

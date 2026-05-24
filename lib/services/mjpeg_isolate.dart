import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'logger.dart';

/// Requête de conversion d'une frame YUV → JPEG.
class FrameRequest {
  final int width, height, yStride, uvStride, uvPixelStride, rotation;
  final Uint8List y, u, v;
  final int step;     // 1 = full res, 2 = half, 4 = quarter
  final int quality;  // 1-100

  const FrameRequest({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yStride,
    required this.uvStride,
    required this.uvPixelStride,
    required this.rotation,
    this.step = 2,
    this.quality = 78,
  });
}

class _IsolateError {
  final String message;
  _IsolateError(this.message);
}

/// Isolate persistant qui convertit YUV420 → JPEG sans recréer
/// d'isolate à chaque frame (gain ~30-50ms par frame vs compute()).
class MjpegIsolate {
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _receive;
  StreamSubscription? _sub;
  Completer<Uint8List>? _pending;
  bool _ready = false;

  bool get ready => _ready;
  bool get busy => _pending != null && !_pending!.isCompleted;

  Future<void> start() async {
    if (_isolate != null) return;
    _receive = ReceivePort();
    _isolate = await Isolate.spawn<SendPort>(_entry, _receive!.sendPort);
    final completer = Completer<void>();
    _sub = _receive!.listen((msg) {
      if (msg is SendPort) {
        _send = msg;
        _ready = true;
        if (!completer.isCompleted) completer.complete();
      } else if (msg is Uint8List) {
        if (_pending != null && !_pending!.isCompleted) {
          _pending!.complete(msg);
        }
        _pending = null;
      } else if (msg is _IsolateError) {
        Log.w('MjpegIsolate', 'frame error: ${msg.message}');
        if (_pending != null && !_pending!.isCompleted) {
          _pending!.complete(Uint8List(0));
        }
        _pending = null;
      }
    });
    await completer.future;
    Log.i('MjpegIsolate', 'started');
  }

  /// Convertit une frame. Retourne Uint8List vide si occupé (frame droppée)
  /// ou en cas d'erreur.
  Future<Uint8List> convert(FrameRequest req) async {
    if (!_ready || _send == null) return Uint8List(0);
    if (busy) return Uint8List(0);
    final c = Completer<Uint8List>();
    _pending = c;
    _send!.send(req);
    return c.future;
  }

  void dispose() {
    try { _send?.send('stop'); } catch (_) {}
    _sub?.cancel();
    _receive?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _send = null;
    _receive = null;
    _ready = false;
    _pending = null;
  }

  static void _entry(SendPort mainPort) {
    final port = ReceivePort();
    mainPort.send(port.sendPort);
    port.listen((msg) {
      if (msg is FrameRequest) {
        try {
          final jpeg = _convertYuvToJpeg(msg);
          mainPort.send(jpeg);
        } catch (e) {
          mainPort.send(_IsolateError(e.toString()));
        }
      } else if (msg == 'stop') {
        port.close();
      }
    });
  }
}

Uint8List _convertYuvToJpeg(FrameRequest p) {
  final step = p.step;
  final outW = p.width ~/ step;
  final outH = p.height ~/ step;
  final base = img.Image(width: outW, height: outH);

  for (int row = 0; row < outH; row++) {
    final srcRow = row * step;
    final yRowBase = srcRow * p.yStride;
    final uvRowBase = (srcRow >> 1) * p.uvStride;
    for (int col = 0; col < outW; col++) {
      final srcCol = col * step;
      final yIdx = yRowBase + srcCol;
      final uvIdx = uvRowBase + (srcCol >> 1) * p.uvPixelStride;
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
  return img.encodeJpg(rotated, quality: p.quality);
}

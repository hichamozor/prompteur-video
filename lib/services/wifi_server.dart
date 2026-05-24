import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'logger.dart';

/// Serveur HTTP/WS local sur le port 8080.
class WifiServer {
  static const int port = 8080;

  HttpServer? _server;
  String _ip = '';
  String _controlPageHtml = '';
  String _authToken = '';

  String get ip => _ip;
  String get authToken => _authToken;
  bool get running => _server != null;

  final Set<WebSocket> _wsClients = {};
  final Set<WebSocket> _authedClients = {};
  final List<HttpResponse> _mjpegClients = [];
  final _wsMessageController = StreamController<String>.broadcast();

  /// Stream des messages reçus de clients authentifiés uniquement.
  Stream<String> get onAuthedMessage => _wsMessageController.stream;
  int get clientCount => _wsClients.length;
  bool get hasMjpegClients => _mjpegClients.isNotEmpty;

  String Function()? scriptProvider;

  Future<void> start({required String authToken}) async {
    if (_server != null) return;
    _authToken = authToken;
    try {
      try {
        _controlPageHtml = await rootBundle.loadString('assets/control.html');
      } catch (e, st) {
        Log.e('WifiServer', 'failed to load control.html', e, st);
        _controlPageHtml = '<html><body><h1>Erreur</h1></body></html>';
      }

      try {
        final interfaces =
            await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              _ip = addr.address;
              break;
            }
          }
          if (_ip.isNotEmpty) break;
        }
      } catch (e) {
        Log.w('WifiServer', 'unable to detect IP: $e');
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      Log.i('WifiServer', 'listening on $_ip:$port (token $_authToken)');
      _server!.listen(_handleRequest, onError: (e, st) {
        Log.e('WifiServer', 'listen error', e, st);
      });
    } catch (e, st) {
      Log.e('WifiServer', 'start failed', e, st);
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _wsClients.add(ws);
        Log.i('WifiServer', 'ws connected (${_wsClients.length} clients)');
        // Demande l'auth
        try { ws.add('auth_required'); } catch (_) {}
        ws.listen(
          (data) => _onWsData(ws, data.toString()),
          onDone: () { _wsClients.remove(ws); _authedClients.remove(ws); },
          onError: (e) { _wsClients.remove(ws); _authedClients.remove(ws); Log.w('WifiServer', 'ws error: $e'); },
          cancelOnError: true,
        );
        return;
      }

      if (req.uri.path == '/stream') {
        final resp = req.response;
        resp.headers.set(HttpHeaders.contentTypeHeader,
            'multipart/x-mixed-replace; boundary=mjpeg');
        resp.headers.set('Cache-Control', 'no-cache');
        resp.headers.set('Connection', 'keep-alive');
        resp.statusCode = 200;
        _mjpegClients.add(resp);
        resp.done.catchError((_) {}).whenComplete(() {
          _mjpegClients.remove(resp);
        });
        return;
      }

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_controlPageHtml)
        ..close();
    } catch (e, st) {
      Log.e('WifiServer', 'request handler error', e, st);
      try { req.response.close(); } catch (_) {}
    }
  }

  void _onWsData(WebSocket ws, String raw) {
    if (raw.startsWith('auth:')) {
      final t = raw.substring(5).trim();
      if (t == _authToken) {
        _authedClients.add(ws);
        try { ws.add('auth_ok'); } catch (_) {}
        try { ws.add('script:${scriptProvider?.call() ?? ""}'); } catch (_) {}
        Log.i('WifiServer', 'client authenticated');
      } else {
        try { ws.add('auth_fail'); } catch (_) {}
        Log.w('WifiServer', 'auth failed (got "$t")');
      }
      return;
    }
    if (raw == 'ping') {
      try { ws.add('pong'); } catch (_) {}
      return;
    }
    if (!_authedClients.contains(ws)) {
      try { ws.add('auth_required'); } catch (_) {}
      return;
    }
    _wsMessageController.add(raw);
  }

  Future<void> stop() async {
    for (final ws in List.of(_wsClients)) {
      try { await ws.close(); } catch (_) {}
    }
    _wsClients.clear();
    _authedClients.clear();
    for (final r in List.of(_mjpegClients)) {
      try { await r.close(); } catch (_) {}
    }
    _mjpegClients.clear();
    try { await _server?.close(force: true); } catch (e) {
      Log.w('WifiServer', 'close error: $e');
    }
    _server = null;
    Log.i('WifiServer', 'stopped');
  }

  void dispose() {
    stop();
    _wsMessageController.close();
  }

  /// Envoie un message à tous les clients **authentifiés**.
  void broadcastWs(String message) {
    for (final ws in List.of(_authedClients)) {
      try { ws.add(message); } catch (_) {
        _authedClients.remove(ws);
        _wsClients.remove(ws);
      }
    }
  }

  void broadcastScript(String script) {
    broadcastWs('script:$script');
  }

  void broadcastStatus(Map<String, dynamic> status) {
    broadcastWs(jsonEncode(status));
  }

  void sendMjpegFrame(Uint8List jpeg) {
    if (_mjpegClients.isEmpty || jpeg.isEmpty) return;
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
}


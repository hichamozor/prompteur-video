import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'logger.dart';

/// Serveur HTTP/WS local sur le port 8080 :
///  - GET /        → page de télécommande HTML
///  - GET /stream  → flux MJPEG live
///  - WS /…        → contrôles + sync script bidirectionnelle
class WifiServer {
  static const int port = 8080;

  HttpServer? _server;
  String _ip = '';
  String _controlPageHtml = '';

  String get ip => _ip;
  bool get running => _server != null;

  final Set<WebSocket> _wsClients = {};
  final List<HttpResponse> _mjpegClients = [];
  final _wsMessageController = StreamController<String>.broadcast();

  Stream<String> get onWsMessage => _wsMessageController.stream;
  int get clientCount => _wsClients.length;
  bool get hasMjpegClients => _mjpegClients.isNotEmpty;

  /// Fournit le contenu courant du script aux nouveaux clients WS.
  String Function()? scriptProvider;

  Future<void> start() async {
    if (_server != null) return;
    try {
      // Charger la page de télécommande depuis l'asset
      try {
        _controlPageHtml = await rootBundle.loadString('assets/control.html');
      } catch (e, st) {
        Log.e('WifiServer', 'failed to load control.html asset', e, st);
        _controlPageHtml = '<html><body><h1>Erreur: page de contrôle introuvable</h1></body></html>';
      }

      // Récupérer l'IP locale
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              _ip = addr.address;
              break;
            }
          }
          if (_ip.isNotEmpty) break;
        }
      } catch (e, st) {
        Log.w('WifiServer', 'unable to detect IP: $e');
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      Log.i('WifiServer', 'listening on $_ip:$port');
      _server!.listen(_handleRequest, onError: (e, st) {
        Log.e('WifiServer', 'listen error', e, st);
      });
    } catch (e, st) {
      Log.e('WifiServer', 'start failed', e, st);
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // WebSocket upgrade
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _wsClients.add(ws);
        Log.i('WifiServer', 'ws client connected (${_wsClients.length} total)');
        // Envoyer le script courant immédiatement
        try {
          final s = scriptProvider?.call() ?? '';
          ws.add('script:$s');
        } catch (_) {}
        ws.listen(
          (data) => _wsMessageController.add(data.toString()),
          onDone: () { _wsClients.remove(ws); Log.i('WifiServer', 'ws client gone'); },
          onError: (e) { _wsClients.remove(ws); Log.w('WifiServer', 'ws error: $e'); },
          cancelOnError: true,
        );
        return;
      }

      // MJPEG stream
      if (req.uri.path == '/stream') {
        final resp = req.response;
        resp.headers.set(HttpHeaders.contentTypeHeader, 'multipart/x-mixed-replace; boundary=mjpeg');
        resp.headers.set('Cache-Control', 'no-cache');
        resp.headers.set('Connection', 'keep-alive');
        resp.statusCode = 200;
        _mjpegClients.add(resp);
        resp.done.catchError((_) => _mjpegClients.remove(resp)).whenComplete(() {
          _mjpegClients.remove(resp);
        });
        return;
      }

      // Page de télécommande
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

  Future<void> stop() async {
    for (final ws in List.of(_wsClients)) {
      try { await ws.close(); } catch (_) {}
    }
    _wsClients.clear();
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

  /// Envoie un message JSON ou texte à tous les clients WebSocket.
  void broadcastWs(String message) {
    for (final ws in List.of(_wsClients)) {
      try { ws.add(message); } catch (_) { _wsClients.remove(ws); }
    }
  }

  /// Envoie le script à tous les clients WebSocket (resync).
  void broadcastScript(String script) {
    broadcastWs('script:$script');
  }

  /// Envoie le statut JSON aux clients WebSocket.
  void broadcastStatus(Map<String, dynamic> status) {
    broadcastWs(jsonEncode(status));
  }

  /// Envoie une frame JPEG au flux MJPEG.
  void sendMjpegFrame(Uint8List jpeg) {
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
}

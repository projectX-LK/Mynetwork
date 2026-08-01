import 'dart:io';
import 'secure_client.dart';

/// Native platform media players (ExoPlayer on Android, AVPlayer on iOS)
/// manage their own TLS trust and don't consult Dart's `badCertificateCallback`,
/// so they can't be pointed directly at a self-signed remote HTTPS URL the
/// way our own Dart HTTP calls can.
///
/// The fix: this tiny server listens on 127.0.0.1 only (unreachable from
/// other devices on the WiFi network), receives the plain-HTTP request the
/// native player makes -- including Range headers for seeking -- forwards
/// it over the *pinned, authenticated* HTTPS connection via [SecureClient],
/// and streams the bytes back. The player only ever sees a local,
/// unencrypted loopback connection; the real network hop stays behind our
/// own certificate pinning and PIN auth the whole time.
class RelayServer {
  final SecureClient secureClient;
  HttpServer? _server;

  RelayServer(this.secureClient);

  int get port => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// The URL to hand to video_player / just_audio for a given remote file.
  String urlFor(String relPath) =>
      'http://127.0.0.1:$port/proxy?path=${Uri.encodeQueryComponent(relPath)}';

  Future<void> _handle(HttpRequest request) async {
    final relPath = request.uri.queryParameters['path'] ?? '';
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    try {
      final remote = await secureClient.openStream(relPath, rangeHeader: rangeHeader);

      request.response.statusCode = remote.statusCode;
      if (remote.headers.contentType != null) {
        request.response.headers.contentType = remote.headers.contentType;
      }
      final contentRange = remote.headers.value('content-range');
      if (contentRange != null) {
        request.response.headers.set('Content-Range', contentRange);
      }
      final contentLength = remote.headers.value(HttpHeaders.contentLengthHeader);
      if (contentLength != null) {
        request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
      }
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      await request.response.addStream(remote);
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }
}

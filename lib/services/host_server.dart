import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import 'cert_service.dart';
import 'auth_service.dart';
import 'media_scanner.dart';

/// Runs the HTTPS server that other LocalCast devices connect to. Every
/// route except none (all routes) requires a valid `Authorization: Bearer
/// <pin>` header -- there is no unauthenticated endpoint, deliberately,
/// since even folder listings and the LAN address list are meaningful
/// information to keep behind the PIN.
class HostServer {
  final CertService certService;
  final AuthService authService;
  MediaScanner scanner;
  HttpServer? _server;

  HostServer({required this.certService, required this.authService, required this.scanner});

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start({int port = 8443}) async {
    if (_server != null) return;
    final context = certService.buildSecurityContext();
    _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, port, context);
    _server!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void setMediaRoot(Directory dir) {
    scanner = MediaScanner(dir);
  }

  Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addrs = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) addrs.add(addr.address);
      }
    }
    return addrs;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
      final token = authHeader?.replaceFirst('Bearer ', '').trim();
      if (!authService.verify(token)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid or missing PIN'}));
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      if (path == '/api/browse') {
        await _handleBrowse(request);
      } else if (path == '/api/stream') {
        await _handleStream(request);
      } else if (path == '/api/info') {
        await _handleInfo(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleBrowse(HttpRequest request) async {
    final relPath = request.uri.queryParameters['path'] ?? '';
    final entries = scanner.list(relPath);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'path': relPath,
      'entries': entries.map((e) => e.toJson()).toList(),
    }));
    await request.response.close();
  }

  Future<void> _handleStream(HttpRequest request) async {
    final relPath = request.uri.queryParameters['path'] ?? '';
    final resolved = scanner.safeResolve(relPath);
    if (resolved == null || resolved is! File || !await resolved.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = resolved;
    final length = await file.length();
    final ext = _extensionOf(file.path);
    final contentType = MediaScanner.mimeForExtension(ext);
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      int start = 0;
      int end = length - 1;
      if (match != null) {
        if (match.group(1)!.isNotEmpty) start = int.parse(match.group(1)!);
        if (match.group(2)!.isNotEmpty) end = int.parse(match.group(2)!);
      }
      if (end >= length) end = length - 1;
      if (start > end || start >= length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set('Content-Range', 'bytes */$length');
        await request.response.close();
        return;
      }

      final chunkSize = end - start + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set('Content-Range', 'bytes $start-$end/$length');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentLength = chunkSize;
      request.response.headers.contentType = ContentType.parse(contentType);

      final stream = file.openRead(start, end + 1);
      await request.response.addStream(stream);
      await request.response.close();
    } else {
      request.response.headers.contentLength = length;
      request.response.headers.contentType = ContentType.parse(contentType);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      await request.response.addStream(file.openRead());
      await request.response.close();
    }
  }

  Future<void> _handleInfo(HttpRequest request) async {
    final addrs = await localAddresses();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'port': port,
      'addresses': addrs,
      'mediaRoot': scanner.mediaRoot.path,
      'fingerprint': certService.fingerprint,
    }));
    await request.response.close();
  }

  String _extensionOf(String path) {
    final idx = path.lastIndexOf('.');
    if (idx == -1) return '';
    return path.substring(idx);
  }

  static Future<Directory> defaultMediaRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${dir.path}${Platform.pathSeparator}LocalCast Media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }
}

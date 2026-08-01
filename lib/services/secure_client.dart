import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../models/connection_info.dart';

/// An HttpClient that only trusts the exact certificate fingerprint that
/// was pinned during pairing (via QR scan or manual PIN entry) -- it does
/// NOT trust any certificate authority. This is what makes a self-signed,
/// device-generated certificate safe to use here: we're not asking "is
/// this cert signed by someone we trust", we're asking "is this literally
/// the same cert we saw when we paired", which an on-path attacker on the
/// same WiFi cannot forge without the host's private key.
class SecureClient {
  final ConnectionInfo connection;
  late final HttpClient _client;

  SecureClient(this.connection) {
    _client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        final digest = sha256.convert(cert.der).bytes;
        final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        return hex == connection.fingerprint.toLowerCase();
      };
  }

  Map<String, String> get _authHeaders => {
        HttpHeaders.authorizationHeader: 'Bearer ${connection.pin}',
      };

  Future<Map<String, dynamic>> browse(String relPath) async {
    final uri = Uri.parse('${connection.baseUrl}/api/browse')
        .replace(queryParameters: {'path': relPath});
    final request = await _client.getUrl(uri);
    _authHeaders.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw SecureClientException(response.statusCode, body);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> info() async {
    final uri = Uri.parse('${connection.baseUrl}/api/info');
    final request = await _client.getUrl(uri);
    _authHeaders.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw SecureClientException(response.statusCode, body);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Opens a streaming GET to /api/stream, forwarding an optional Range
  /// header, and returns the raw response so callers (e.g. the local relay
  /// server) can pipe bytes through without buffering the whole file.
  Future<HttpClientResponse> openStream(String relPath, {String? rangeHeader}) async {
    final uri = Uri.parse('${connection.baseUrl}/api/stream')
        .replace(queryParameters: {'path': relPath});
    final request = await _client.getUrl(uri);
    _authHeaders.forEach(request.headers.set);
    if (rangeHeader != null) {
      request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }
    return request.close();
  }

  void close() => _client.close(force: true);
}

class SecureClientException implements Exception {
  final int statusCode;
  final String body;
  SecureClientException(this.statusCode, this.body);

  @override
  String toString() => 'SecureClientException($statusCode): $body';
}

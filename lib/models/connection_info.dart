import 'dart:convert';

/// Everything a client needs to securely reach a host device: where it is,
/// the TLS certificate fingerprint to pin against (so we don't need a real
/// CA on a local network), and the shared secret used to authenticate API
/// calls.
class ConnectionInfo {
  final String host; // IP address, e.g. 192.168.1.42
  final int port;
  final String fingerprint; // sha256 fingerprint of the host's cert, hex, lowercase
  final String pin; // 6-digit pairing PIN, doubles as bearer token
  final String label; // friendly name shown in the UI

  ConnectionInfo({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.pin,
    this.label = '',
  });

  String get baseUrl => 'https://$host:$port';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'fingerprint': fingerprint,
        'pin': pin,
        'label': label,
      };

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
        host: json['host'] as String,
        port: json['port'] as int,
        fingerprint: (json['fingerprint'] as String).toLowerCase(),
        pin: json['pin'] as String,
        label: json['label'] as String? ?? '',
      );

  /// Compact JSON used inside the QR code payload. Keys are kept short
  /// since QR payload size affects scan reliability at small sizes.
  factory ConnectionInfo.fromQrPayload(String payload) {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return ConnectionInfo(
      host: json['h'] as String,
      port: json['p'] as int,
      fingerprint: (json['f'] as String).toLowerCase(),
      pin: json['k'] as String,
    );
  }

  String toQrPayload() {
    return jsonEncode({
      'h': host,
      'p': port,
      'f': fingerprint,
      'k': pin,
    });
  }
}

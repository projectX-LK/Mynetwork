import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart';

/// Generates (once) and reuses a self-signed TLS certificate + private key
/// for this device install. Because every device generates its own unique
/// key pair, the certificate fingerprint shown in a host's QR code/PIN
/// screen uniquely identifies *that* device's server, and a client pinning
/// against it is protected from impersonation on the local network -- an
/// attacker without that private key cannot present a matching cert even
/// if they know it's "the LocalCast app" too.
///
/// NOTE: this file leans on `basic_utils` for X.509 generation, which wraps
/// `pointycastle`. This is the one part of the project I have not been able
/// to compile-check in the sandbox this was written in (no network access
/// to fetch packages, no Flutter/Dart runtime installed). If
/// `X509Utils.generateSelfSignedCertificate` differs slightly between
/// package versions, this is the first place to look -- see the README for
/// how to sanity-check it in isolation.
class CertService {
  static const _certFileName = 'localcast_cert.pem';
  static const _keyFileName = 'localcast_key.pem';

  String? _certPem;
  String? _keyPem;
  String? _fingerprint;

  String get certPem => _certPem!;
  String get keyPem => _keyPem!;

  /// Lowercase hex SHA-256 fingerprint of the DER-encoded certificate.
  /// This is what gets shown in the PIN/QR screen and pinned by clients.
  String get fingerprint => _fingerprint!;

  Future<void> loadOrCreate() async {
    final dir = await getApplicationSupportDirectory();
    final certFile = File('${dir.path}/$_certFileName');
    final keyFile = File('${dir.path}/$_keyFileName');

    if (await certFile.exists() && await keyFile.exists()) {
      _certPem = await certFile.readAsString();
      _keyPem = await keyFile.readAsString();
    } else {
      final generated = _generateSelfSigned();
      _certPem = generated.certPem;
      _keyPem = generated.keyPem;
      await certFile.writeAsString(_certPem!);
      await keyFile.writeAsString(_keyPem!);
    }

    _fingerprint = _computeFingerprint(_certPem!);
  }

  /// Wipes and regenerates the certificate. Any device that had this host
  /// pinned will need to re-pair (scan a fresh QR / re-enter the new PIN).
  Future<void> regenerate() async {
    final dir = await getApplicationSupportDirectory();
    final certFile = File('${dir.path}/$_certFileName');
    final keyFile = File('${dir.path}/$_keyFileName');
    if (await certFile.exists()) await certFile.delete();
    if (await keyFile.exists()) await keyFile.delete();
    await loadOrCreate();
  }

  SecurityContext buildSecurityContext() {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certPem));
    context.usePrivateKeyBytes(utf8.encode(keyPem));
    return context;
  }

  _GeneratedCert _generateSelfSigned() {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;

    final dn = {
      'CN': 'localcast-${DateTime.now().millisecondsSinceEpoch}',
      'O': 'LocalCast',
    };

    final csr = X509Utils.generateRsaCsrPem(dn, privateKey, publicKey);

    // 10-year validity: this is a local-pairing cert, not a publicly
    // trusted one, so a long lifetime just avoids nagging re-pairing.
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
    );

    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    return _GeneratedCert(certPem: certPem, keyPem: keyPem);
  }

  String _computeFingerprint(String certPem) {
    final der = X509Utils.getBytesFromPEMString(certPem);
    final digest = sha256.convert(der);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _GeneratedCert {
  final String certPem;
  final String keyPem;
  _GeneratedCert({required this.certPem, required this.keyPem});
}

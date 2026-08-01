import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import '../models/connection_info.dart';
import '../services/connections_store.dart';
import '../services/secure_client.dart';
import 'browse_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({Key? key}) : super(key: key);

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _store = ConnectionsStore();
  List<ConnectionInfo> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _store.loadAll();
    setState(() => _saved = saved);
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result == null) return;
    try {
      final info = ConnectionInfo.fromQrPayload(result);
      await _verifyAndOpen(info);
    } catch (e) {
      _showError('That QR code doesn\'t look like a LocalCast pairing code.');
    }
  }

  Future<void> _manualEntry() async {
    final result = await showDialog<_ManualEntryResult>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    if (result == null) return;

    // Trust-on-first-use: connect without pinning yet, just to retrieve the
    // host's certificate fingerprint (the PIN is still checked by the
    // server regardless), then ask the user to visually confirm the safety
    // code before we pin it for real.
    final probe = ConnectionInfo(
      host: result.host,
      port: result.port,
      fingerprint: '', // unknown yet
      pin: result.pin,
    );

    try {
      final tofuClient = _TofuProbeClient(probe);
      final info = await tofuClient.fetchInfo();
      tofuClient.close();

      final fingerprint = (info['fingerprint'] as String).toLowerCase();
      final safetyCode = fingerprint.substring(0, 8).toUpperCase();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm this is the right device'),
          content: Text(
            'Safety code:\n\n$safetyCode\n\n'
            'Check this matches the safety code shown on the host\'s '
            'screen before continuing.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Matches, connect')),
          ],
        ),
      );

      if (confirmed != true) return;

      final finalInfo = ConnectionInfo(
        host: result.host,
        port: result.port,
        fingerprint: fingerprint,
        pin: result.pin,
      );
      await _verifyAndOpen(finalInfo);
    } catch (e) {
      _showError('Could not reach that device. Check the address and PIN.');
    }
  }

  Future<void> _verifyAndOpen(ConnectionInfo info) async {
    try {
      final client = SecureClient(info);
      await client.info(); // confirms PIN + pinned fingerprint both work
      client.close();
      await _store.save(info);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BrowseScreen(connection: info)),
      );
    } catch (e) {
      _showError('Could not verify this connection. Check the PIN and try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to a device')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Scan QR code'),
            ),
            onPressed: _scanQr,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.keyboard),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Enter address and PIN manually'),
            ),
            onPressed: _manualEntry,
          ),
          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text('Previously paired', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._saved.map((c) => Card(
                  child: ListTile(
                    title: Text('${c.host}:${c.port}'),
                    subtitle: Text('PIN ${c.pin}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _store.remove(c);
                        _loadSaved();
                      },
                    ),
                    onTap: () => _verifyAndOpen(c),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _ManualEntryResult {
  final String host;
  final int port;
  final String pin;
  _ManualEntryResult(this.host, this.port, this.pin);
}

class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8443');
  final _pinController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect manually'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(labelText: 'Host address (e.g. 192.168.1.42)'),
          ),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Port'),
          ),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '6-digit PIN'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final host = _hostController.text.trim();
            final port = int.tryParse(_portController.text.trim()) ?? 8443;
            final pin = _pinController.text.trim();
            if (host.isEmpty || pin.length != 6) return;
            Navigator.pop(context, _ManualEntryResult(host, port, pin));
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// Used only during manual trust-on-first-use pairing, before we have a
/// fingerprint to pin against. Accepts any certificate for this one
/// bootstrap call -- the PIN check on the server side still applies, and
/// the user must visually confirm the resulting safety code before this
/// connection is ever saved or reused.
class _TofuProbeClient {
  final ConnectionInfo probe;
  late final HttpClient _client;

  _TofuProbeClient(this.probe) {
    _client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
  }

  Future<Map<String, dynamic>> fetchInfo() async {
    final uri = Uri.parse('${probe.baseUrl}/api/info');
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${probe.pin}');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('Server responded ${response.statusCode}');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void close() => _client.close(force: true);
}

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'qr_view');
  QRViewController? _controller;
  bool _handled = false;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }

  void _onQrViewCreated(QRViewController controller) {
    _controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (_handled) return;
      final value = scanData.code;
      if (value == null) return;
      _handled = true;
      Navigator.of(context).pop(value);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR code')),
      body: QRView(
        key: _qrKey,
        onQRViewCreated: _onQrViewCreated,
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../models/connection_info.dart';
import '../services/cert_service.dart';
import '../services/auth_service.dart';
import '../services/host_server.dart';
import '../services/media_scanner.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({Key? key}) : super(key: key);

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final _certService = CertService();
  final _authService = AuthService();
  HostServer? _server;

  bool _initializing = true;
  bool _running = false;
  List<String> _addresses = [];
  String _mediaRootPath = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _certService.loadOrCreate();
      _authService.generatePin();

      final mediaRoot = await HostServer.defaultMediaRoot();
      final server = HostServer(
        certService: _certService,
        authService: _authService,
        scanner: MediaScanner(mediaRoot),
      );
      await server.start();
      final addrs = await server.localAddresses();

      setState(() {
        _server = server;
        _running = true;
        _addresses = addrs;
        _mediaRootPath = mediaRoot.path;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not start the server: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _toggleServer() async {
    if (_server == null) return;
    if (_running) {
      await _server!.stop();
    } else {
      await _server!.start();
    }
    setState(() => _running = _server!.isRunning);
  }

  Future<void> _newPin() async {
    setState(() => _authService.generatePin());
  }

  Future<void> _changeFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder to share',
    );
    if (path == null || _server == null) return;
    final dir = Directory(path);
    if (!await dir.exists()) return;
    _server!.setMediaRoot(dir);
    setState(() => _mediaRootPath = path);
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing this device')),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final primaryAddress = _addresses.isNotEmpty ? _addresses.first : null;
    final qrPayload = primaryAddress == null
        ? null
        : ConnectionInfo(
            host: primaryAddress,
            port: _server!.port!,
            fingerprint: _certService.fingerprint,
            pin: _authService.pin,
          ).toQrPayload();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(_running ? Icons.wifi_tethering : Icons.power_settings_new,
                color: _running ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 8),
            Text(_running ? 'Running' : 'Stopped', style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Switch(value: _running, onChanged: (_) => _toggleServer()),
          ],
        ),
        const SizedBox(height: 24),
        if (qrPayload != null) ...[
          const Text('Scan to pair a phone or tablet', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: QrImage(data: qrPayload, size: 220),
            ),
          ),
          const SizedBox(height: 28),
        ],
        const Text('Or enter this PIN manually', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _authService.pin.replaceAllMapped(
                RegExp(r'.{1,3}'), (m) => '${m.group(0)} '),
            style: const TextStyle(fontSize: 34, letterSpacing: 4, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('New PIN'),
            onPressed: _newPin,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Safety code: ${_certService.fingerprint.substring(0, 8).toUpperCase()}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white54),
          ),
        ),
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'When someone connects manually (not via QR), check this code matches '
              'what their app shows before they confirm.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        const Text('Network addresses', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_addresses.isEmpty)
          const Text('No LAN address detected. Check your WiFi connection.')
        else
          ..._addresses.map((a) => Text('$a:${_server!.port}',
              style: const TextStyle(fontFamily: 'monospace'))),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        const Text('Shared folder', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_mediaRootPath, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Change folder'),
          onPressed: _changeFolder,
        ),
        const SizedBox(height: 16),
        const Text(
          'Anyone with the PIN or QR code can browse and stream this folder '
          'while the server is running. Turn it off when you\'re done sharing.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

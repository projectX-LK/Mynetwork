import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../services/secure_client.dart';
import 'player_screen.dart';

class BrowseScreen extends StatefulWidget {
  final ConnectionInfo connection;
  const BrowseScreen({Key? key, required this.connection}) : super(key: key);

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final SecureClient _client;
  String _path = '';
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = SecureClient(widget.connection);
    _load('');
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _client.browse(path);
      setState(() {
        _path = path;
        _entries = List<Map<String, dynamic>>.from(result['entries'] as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this folder.';
        _loading = false;
      });
    }
  }

  List<String> get _crumbs => _path.isEmpty ? [] : _path.split('/');

  void _goTo(int crumbIndex) {
    if (crumbIndex < 0) {
      _load('');
    } else {
      _load(_crumbs.sublist(0, crumbIndex + 1).join('/'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.connection.host}'),
      ),
      body: Column(
        children: [
          _buildCrumbs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildCrumbs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          TextButton(onPressed: () => _goTo(-1), child: const Text('Library')),
          for (var i = 0; i < _crumbs.length; i++) ...[
            const Text(' / '),
            TextButton(onPressed: () => _goTo(i), child: Text(_crumbs[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_entries.isEmpty) {
      return const Center(child: Text('This folder is empty.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isFolder = entry['kind'] == null;
        return _EntryCard(
          name: entry['name'] as String,
          isFolder: isFolder,
          kind: entry['kind'] as String?,
          size: entry['size'] as int? ?? 0,
          onTap: () {
            if (isFolder) {
              _load(entry['path'] as String);
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  connection: widget.connection,
                  relPath: entry['path'] as String,
                  name: entry['name'] as String,
                  isVideo: entry['kind'] == 'video',
                ),
              ));
            }
          },
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  final String name;
  final bool isFolder;
  final String? kind;
  final int size;
  final VoidCallback onTap;

  const _EntryCard({
    required this.name,
    required this.isFolder,
    required this.kind,
    required this.size,
    required this.onTap,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var n = bytes.toDouble();
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final icon = isFolder
        ? Icons.folder
        : (kind == 'video' ? Icons.movie : Icons.audiotrack);
    final color = isFolder
        ? Colors.amber
        : (kind == 'video' ? Colors.lightBlueAccent : Colors.pinkAccent);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(child: Icon(icon, size: 40, color: color)),
            ),
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            if (!isFolder)
              Text(_formatSize(size), style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

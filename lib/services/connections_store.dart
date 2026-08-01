import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_info.dart';

class ConnectionsStore {
  static const _key = 'localcast_saved_connections';

  Future<List<ConnectionInfo>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => ConnectionInfo.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(ConnectionInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll();
    existing.removeWhere((c) => c.host == info.host && c.port == info.port);
    existing.add(info);
    await prefs.setStringList(
      _key,
      existing.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<void> remove(ConnectionInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll();
    existing.removeWhere((c) => c.host == info.host && c.port == info.port);
    await prefs.setStringList(
      _key,
      existing.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}

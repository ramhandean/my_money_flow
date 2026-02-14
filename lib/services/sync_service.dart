import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncService {
  static final _supabase = Supabase.instance.client;
  static const String _queueKey = 'sync_queue';
  static bool _isSyncing = false; // Satpam baru

  static Future<void> processQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? localQueue = prefs.getString(_queueKey);
      if (localQueue == null) return;

      List<dynamic> queue = jsonDecode(localQueue);
      if (queue.isEmpty) return;

      List<dynamic> remainingQueue = List.from(queue);

      for (var item in queue) {
        try {
          await _supabase.from(item['table']).insert(item['data']).timeout(const Duration(seconds: 5));

          // Hapus per item yang sukses
          remainingQueue.removeAt(0);
          await prefs.setString(_queueKey, jsonEncode(remainingQueue));
        } catch (e) {
          break; // Stop kalau koneksi bapuk
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
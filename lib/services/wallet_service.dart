import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/wallet_model.dart';

class WalletService {
  final _supabase = Supabase.instance.client;
  final String _cacheKey = 'local_db_wallets';
  final String _queueKey = 'wallet_sync_queue';

  // KUNCI UTAMA: Biar proses sync gak tabrakan (singleton-ish flag)
  bool _isProcessing = false;

  Future<List<Wallet>> getWallets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    List<dynamic> queue = queueData != null ? jsonDecode(queueData) : [];

    // 1. Trigger sync di background kalau ada antrean
    if (queue.isNotEmpty && !_isProcessing) {
      _processQueue();
    }

    try {
      // 2. Coba ambil data terbaru dari Supabase
      final response = await _supabase
          .from('wallets')
          .select()
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 4));

      await prefs.setString(_cacheKey, jsonEncode(response));
      return response.map((data) => Wallet.fromMap(data)).toList();

    } catch (e) {
      print("DEBUG: [Wallet] Ambil data dari cache lokal (Offline/Timeout).");
    }

    // 3. Fallback ke data lokal (The Source of Truth)
    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      final List<dynamic> decoded = jsonDecode(localData);
      return decoded.map((data) => Wallet.fromMap(data)).toList();
    }
    return [];
  }

  Future<void> addWallet(String name, double balance, String type) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final String tempId = const Uuid().v4();

    final newWalletData = {
      'id': tempId,
      'user_id': user.id,
      'name': name,
      'balance': balance,
      'type': type,
    };

    // A. UPDATE LOKAL
    final String? localData = prefs.getString(_cacheKey);
    List<dynamic> currentList = localData != null ? jsonDecode(localData) : [];
    currentList.add(newWalletData);
    await prefs.setString(_cacheKey, jsonEncode(currentList));

    // B. MASUKKAN KE ANTREAN
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    queue.add(newWalletData);
    await prefs.setString(_queueKey, jsonEncode(queue));

    if (!_isProcessing) _processQueue();
  }

  Future<void> updateWallet(String walletId, String name, double balance) async {
    final prefs = await SharedPreferences.getInstance();

    // A. UPDATE LOKAL
    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      List<dynamic> currentList = jsonDecode(localData);
      final index = currentList.indexWhere((w) => w['id'] == walletId);
      if (index != -1) {
        currentList[index]['name'] = name;
        currentList[index]['balance'] = balance;
        await prefs.setString(_cacheKey, jsonEncode(currentList));
      }
    }

    // B. MASUKKAN KE ANTREAN (dengan operasi UPDATE)
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    
    queue.add({
      'id': walletId,
      'name': name,
      'balance': balance,
      'operation': 'update',
    });
    await prefs.setString(_queueKey, jsonEncode(queue));

    if (!_isProcessing) _processQueue();
  }

  Future<void> deleteWallet(String walletId) async {
    final prefs = await SharedPreferences.getInstance();

    // A. HAPUS DARI LOKAL
    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      List<dynamic> currentList = jsonDecode(localData);
      currentList.removeWhere((w) => w['id'] == walletId);
      await prefs.setString(_cacheKey, jsonEncode(currentList));
    }

    // B. MASUKKAN KE ANTREAN (dengan operasi DELETE)
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    
    queue.add({
      'id': walletId,
      'operation': 'delete',
    });
    await prefs.setString(_queueKey, jsonEncode(queue));

    if (!_isProcessing) _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return; // Satpam: Kalau lagi ada yang kerja, jangan masuk.
    _isProcessing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      String? queueData = prefs.getString(_queueKey);
      if (queueData == null) {
        _isProcessing = false;
        return;
      }

      List<dynamic> queue = jsonDecode(queueData);
      List<dynamic> remainingQueue = List.from(queue);

      for (var item in queue) {
        try {
          final operation = item['operation'] ?? 'create';
          
          if (operation == 'create') {
            // Kirim ke Supabase
            await _supabase.from('wallets').insert({
              'name': item['name'],
              'balance': item['balance'],
              'type': item['type'],
              'user_id': item['user_id'],
            }).timeout(const Duration(seconds: 5));
          } else if (operation == 'update') {
            // Update di Supabase
            await _supabase.from('wallets').update({
              'name': item['name'],
              'balance': item['balance'],
            }).eq('id', item['id']).timeout(const Duration(seconds: 5));
          } else if (operation == 'delete') {
            // Delete di Supabase
            await _supabase.from('wallets').delete().eq('id', item['id']).timeout(const Duration(seconds: 5));
          }

          // Hapus dari antrean lokal
          remainingQueue.removeWhere((q) => q['id'] == item['id']);

          // Hapus dari cache list lokal biar gak duplikat pas Pull nanti (hanya untuk CREATE)
          if (operation == 'create') {
            final String? localData = prefs.getString(_cacheKey);
            if (localData != null) {
              List<dynamic> localList = jsonDecode(localData);
              localList.removeWhere((l) => l['id'] == item['id']);
              await prefs.setString(_cacheKey, jsonEncode(localList));
            }
          }

          // Simpan status antrean terbaru setiap satu item sukses
          await prefs.setString(_queueKey, jsonEncode(remainingQueue));
        } catch (e) {
          // Berhenti kalau koneksi putus tengah jalan
          break;
        }
      }

      if (remainingQueue.isEmpty) {
        await _syncFreshFromServer();
      }
    } finally {
      _isProcessing = false; // Kerja bakti selesai
    }
  }

  Future<void> _syncFreshFromServer() async {
    try {
      final response = await _supabase.from('wallets').select().order('name', ascending: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(response));
    } catch (_) {}
  }

  // --- Fungsi Lain Tetap Sama ---
  Future<double> getTotalBalance() async {
    final wallets = await getWallets();
    return wallets.fold<double>(0.0, (sum, item) => sum + item.balance);
  }

  Future<Map<String, double>> getFinancialHealth() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Ambil Saldo + Pending (Aset Riil saat ini)
    final double balance = await getTotalBalance();

    double totalHutang = 0;
    double totalPiutang = 0;

    try {
      final response = await _supabase
          .from('debts')
          .select('*')
          .eq('is_settled', false)
          .timeout(const Duration(seconds: 3));

      for (var item in response) {
        double amount = (item['remaining_amount'] ?? 0).toDouble();
        if (item['is_debt'] == true) {
          totalHutang += amount;
        } else {
          totalPiutang += amount;
        }
      }

      await prefs.setString('local_db_debts', jsonEncode(response));

    } catch (e) {
      print("DEBUG: [Health] Offline/Timeout, ambil dari cache...");
      final String? localData = prefs.getString('local_db_debts');
      if (localData != null) {
        final List<dynamic> decoded = jsonDecode(localData);
        for (var item in decoded) {
          double amount = (item['remaining_amount'] ?? 0).toDouble();
          if (item['is_debt'] == true) totalHutang += amount; else totalPiutang += amount;
        }
      }
    }

    // 2. Kalkulasi buat UI
    // Total Aset = Saldo di kantong + Piutang (duit lu yang ada di orang lain)
    double totalAssets = balance + totalPiutang;

    return {
      'total_assets': totalAssets, // Balikin ini buat dibandingin
      'total_debts': totalHutang,   // Balikin ini buat dibandingin
      'balance': balance,
      'hutang': totalHutang,
      'piutang': totalPiutang,
      'net_worth': totalAssets - totalHutang,
    };
  }
}
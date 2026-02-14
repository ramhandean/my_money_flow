import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/debt_model.dart';

class DebtService {
  final _supabase = Supabase.instance.client;
  final String _cacheKey = 'local_db_debts';
  final String _queueKey = 'debt_sync_queue';

  bool _isProcessing = false;

  // --- 0. FUNGSI SAKTI BUAT STATS PAGE ---
  // Memastikan nominal hutang/piutang yang belum sinkron tetap terhitung di UI
  Future<Map<String, double>> getPendingDebts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    if (queueData == null || queueData == '[]') return {'hutang': 0, 'piutang': 0};

    List<dynamic> queue = jsonDecode(queueData);
    double p_hutang = 0;
    double p_piutang = 0;

    for (var item in queue) {
      final data = item['data'];
      final double amount = (data['amount'] ?? 0).toDouble();
      final bool isDebt = data['is_debt'] ?? true;

      if (item['action'] == 'INSERT') {
        if (isDebt) p_hutang += amount; else p_piutang += amount;
      } else if (item['action'] == 'SETTLE') {
        // Jika pelunasan sedang antre, kurangi nominal dari total
        if (isDebt) p_hutang -= amount; else p_piutang -= amount;
      }
    }
    return {'hutang': p_hutang, 'piutang': p_piutang};
  }

  // --- 1. AMBIL HUTANG (SAFE SYNC) ---
  Future<List<Debt>> getActiveDebts() async {
    final prefs = await SharedPreferences.getInstance();

    // TRIGGER SYNC OTOMATIS: Biar piutang lama yang "nyangkut" langsung kekirim pas ada sinyal
    _processQueue();

    final String? queueData = prefs.getString(_queueKey);
    List<dynamic> queue = queueData != null ? jsonDecode(queueData) : [];

    // 1. Data dari antrean (INSERT) agar UI instan update
    List<Debt> pendingDebts = queue
        .where((item) => item['action'] == 'INSERT')
        .map((item) => Debt.fromMap(item['data']))
        .toList();

    List<dynamic> rawDataFromSource = [];

    try {
      // Ambil data resmi dari Supabase
      final response = await _supabase
          .from('debts')
          .select('*')
          .eq('is_settled', false)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));

      rawDataFromSource = response;

      // Update cache hanya jika antrean kosong untuk menjaga integritas data lokal
      if (queue.isEmpty) {
        await prefs.setString(_cacheKey, jsonEncode(rawDataFromSource));
      }

    } catch (e) {
      print("DEBUG: [Debt] Offline/Error, ambil dari cache.");
      final String? cachedString = prefs.getString(_cacheKey);
      if (cachedString != null) {
        rawDataFromSource = jsonDecode(cachedString);
      }
    }

    final List<Debt> finalDebts = rawDataFromSource.map((data) => Debt.fromMap(data)).toList();

    // --- SOLUSI ANTI-DOUBLE: FILTER ID YANG SUDAH ADA DI QUEUE ---
    // Ambil semua ID yang lagi antre
    final pendingIds = pendingDebts.map((pd) => pd.id).toSet();

    // Filter data dari server/cache: Hapus yang ID-nya sudah ada di pending
    final uniqueStoredDebts = finalDebts.where((d) => !pendingIds.contains(d.id)).toList();

    // Gabungkan: Pending (yang paling baru) + Data Tersimpan (yang unik)
    return [...pendingDebts, ...uniqueStoredDebts];
  }

  // --- 2. TAMBAH HUTANG ---
  Future<void> addDebt({
    required String personName,
    required double amount,
    required bool isDebt,
    required String? walletId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final String tempId = const Uuid().v4();

    final newDebtMap = {
      'id': tempId,
      'user_id': user.id,
      'person_name': personName,
      'amount': amount,
      'remaining_amount': amount,
      'is_debt': isDebt,
      'is_settled': false,
      'created_at': DateTime.now().toIso8601String(),
      'wallet_id': walletId, // Simpan ID wallet untuk potong saldo nanti
    };

    // A. UPDATE LOKAL (Biar langsung muncul di list)
    final String? localData = prefs.getString(_cacheKey);
    List<dynamic> currentList = localData != null ? jsonDecode(localData) : [];
    currentList.insert(0, newDebtMap);
    await prefs.setString(_cacheKey, jsonEncode(currentList));

    // B. MASUKKAN KE ANTREAN
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    queue.add({'action': 'INSERT', 'data': newDebtMap});
    await prefs.setString(_queueKey, jsonEncode(queue));

    _processQueue();
  }

  // --- 3. PELUNASAN ---
  Future<void> settleDebt(String debtId, {String? walletId, double? amount, bool isDebt = true}) async {
    final prefs = await SharedPreferences.getInstance();

    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      List<dynamic> currentList = jsonDecode(localData);
      currentList.removeWhere((item) => item['id'] == debtId);
      await prefs.setString(_cacheKey, jsonEncode(currentList));
    }

    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    queue.add({
      'action': 'SETTLE',
      'data': {
        'id': debtId,
        'wallet_id': walletId,
        'amount': amount ?? 0,
        'is_debt': isDebt
      }
    });
    await prefs.setString(_queueKey, jsonEncode(queue));

    _processQueue();
  }

  // --- 4. TUKANG PROSES (LOCKING) ---
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      while (true) {
        String? queueData = prefs.getString(_queueKey);
        if (queueData == null || queueData == '[]') break;

        List<dynamic> queue = jsonDecode(queueData);
        if (queue.isEmpty) break;

        final item = queue[0];
        final action = item['action'];
        final data = item['data'];

        try {
          if (action == 'INSERT') {
            // Gunakan upsert agar ID UUID dari Flutter tetap konsisten
            await _supabase.from('debts').upsert({
              'id': data['id'],
              'user_id': data['user_id'],
              'person_name': data['person_name'],
              'amount': data['amount'],
              'remaining_amount': data['remaining_amount'],
              'is_debt': data['is_debt'],
              'is_settled': false,
              'created_at': data['created_at'],
            }).timeout(const Duration(seconds: 10));

            // Jika Piutang (is_debt = false), otomatis potong saldo wallet
            if (data['is_debt'] == false && data['wallet_id'] != null) {
              await _supabase.rpc('update_wallet_balance', params: {
                'w_id': data['wallet_id'],
                'amount_change': -data['amount'],
              });
            }
          }
          else if (action == 'SETTLE') {
            await _supabase.from('debts').update({
              'is_settled': true,
              'remaining_amount': 0,
            }).eq('id', data['id']).timeout(const Duration(seconds: 10));

            // Jika Piutang lunas, saldo wallet bertambah kembali
            if (data['is_debt'] == false && data['wallet_id'] != null) {
              await _supabase.rpc('update_wallet_balance', params: {
                'w_id': data['wallet_id'],
                'amount_change': data['amount'],
              });
            }
          }

          // Hapus dari antrean hanya jika request ke server SUKSES
          queue.removeAt(0);
          await prefs.setString(_queueKey, jsonEncode(queue));

        } catch (e) {
          print("DEBUG: [Debt Sync] Koneksi gagal/timeout, berhenti sejenak: $e");
          break; // Keluar loop jika offline
        }
      }

      // Jika semua antrean beres, sinkronkan data bersih dari server ke cache
      if (prefs.getString(_queueKey) == '[]') {
        await _syncDebtsFromOnline();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _syncDebtsFromOnline() async {
    try {
      final response = await _supabase
          .from('debts')
          .select('*')
          .eq('is_settled', false)
          .order('created_at', ascending: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(response));
    } catch (_) {}
  }
}
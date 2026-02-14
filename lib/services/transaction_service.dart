import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction_model.dart';

class TransactionService {
  final _supabase = Supabase.instance.client;
  final String _cacheKey = 'local_db_transactions';
  final String _queueKey = 'transaction_sync_queue';
  final String _cacheKeyMonthTotal = 'local_db_month_total';

  // --- SATPAM LOCK SYSTEM ---
  bool _isProcessing = false;
  Future<void>? _activeProcess;

  // --- 1. AMBIL RIWAYAT (SAFE SYNC) ---
  Future<List<Transaction>> getRecentTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    List<dynamic> queue = queueData != null ? jsonDecode(queueData) : [];

    if (queue.isNotEmpty) {
      // Tungguin sampe proses sync yang lagi jalan (kalau ada) beneran kelar
      await _processQueue();
    }

    try {
      final String? freshQueue = prefs.getString(_queueKey);
      if (freshQueue == null || jsonDecode(freshQueue).isEmpty) {
        final response = await _supabase
            .from('transactions')
            .select()
            .order('created_at', ascending: false)
            .limit(20)
            .timeout(const Duration(seconds: 4));

        await prefs.setString(_cacheKey, jsonEncode(response));
        return response.map((data) => Transaction.fromMap(data)).toList();
      }
    } catch (e) {
      print("DEBUG: [Transaction] Offline fallback.");
    }

    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      final List<dynamic> decoded = jsonDecode(localData);
      return decoded.map((data) => Transaction.fromMap(data)).toList();
    }
    return [];
  }

  // --- 2. TAMBAH TRANSAKSI ---
  Future<void> addTransaction({
    required String walletId,
    required double amount,
    required String description,
    required String category,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      print("❌ [TX SERVICE] Gagal: User tidak ditemukan.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String tempId = const Uuid().v4();

    // LOG: Cek input mentah dari UI
    print("📝 [TX SERVICE] Menyiapkan transaksi baru:");
    print("   - Tipe: ${amount < 0 ? 'PENGELUARAN' : 'PEMASUKAN'}");
    print("   - Nominal: $amount");
    print("   - Deskripsi: $description");

    final newTxMap = {
      'id': tempId,
      'user_id': user.id,
      'wallet_id': walletId,
      'amount': amount, // Di sini krusial: harus negatif jika pengeluaran
      'description': description,
      'category': category,
      'created_at': DateTime.now().toIso8601String(),
    };

    // A. UPDATE LOKAL (INSTANT UI)
    final String? localData = prefs.getString(_cacheKey);
    List<dynamic> currentList = localData != null ? jsonDecode(localData) : [];
    currentList.insert(0, newTxMap);
    await prefs.setString(_cacheKey, jsonEncode(currentList.take(25).toList()));
    print("✅ [TX SERVICE] Data berhasil disimpan ke Cache Lokal.");

    // B. MASUKKAN KE ANTREAN
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    queue.add({'action': 'INSERT', 'data': newTxMap});
    await prefs.setString(_queueKey, jsonEncode(queue));
    print("📥 [TX SERVICE] Transaksi masuk antrean sync (Total antrean: ${queue.length}).");
    print("📥 Queue entry: action=INSERT, amount=$amount, desc=$description");

    // C. TRIGGER SYNC (Background)
    print("🔄 [TX SERVICE] Memulai proses sinkronisasi ke Supabase...");
    _processQueue();
  }

  // --- 3. TUKANG PROSES (LOCKING LEVEL DEWA) ---
  Future<void> _processQueue() async {
    if (_isProcessing) {
      return _activeProcess; // Antre di proses yang lagi jalan
    }

    _isProcessing = true;
    _activeProcess = _executeSync();

    try {
      await _activeProcess;
    } finally {
      _isProcessing = false;
      _activeProcess = null;
    }
  }

  Future<void> _executeSync() async {
    print("DEBUG: [Transaction] Lock dipasang. Memulai...");

    try {
      final prefs = await SharedPreferences.getInstance();

      while (true) {
        final String? queueData = prefs.getString(_queueKey);
        if (queueData == null || queueData == '[]') break;

        List<dynamic> queue = jsonDecode(queueData);
        if (queue.isEmpty) break;

        final item = queue[0];
        final action = item['action'];
        final data = item['data'];

        try {
          if (action == 'INSERT') {
            // 1. UPSERT DATA (Primary Key ID UUID dari Flutter)
            await _supabase.from('transactions').upsert({
              'id': data['id'],
              'wallet_id': data['wallet_id'],
              'amount': data['amount'],
              'description': data['description'],
              'category': data['category'],
              'user_id': data['user_id'],
              'created_at': data['created_at'],
            }).timeout(const Duration(seconds: 10));

            // 2. ATOMIC CHECK & REMOVE
            // Kita baca ulang antrean sebelum RPC biar gak dobel potong saldo
            final String? latestQueueData = prefs.getString(_queueKey);
            List<dynamic> latestQueue = jsonDecode(latestQueueData!);

            if (latestQueue.isNotEmpty && latestQueue[0]['data']['id'] == data['id']) {
              // Hapus dari antrean DULUAN
              latestQueue.removeAt(0);
              await prefs.setString(_queueKey, jsonEncode(latestQueue));

              // 3. BARU UPDATE SALDO VIA RPC
              await _supabase.rpc('update_wallet_balance', params: {
                'w_id': data['wallet_id'],
                'amount_change': data['amount'], // HAPUS TANDA MINUSNYA!
              });
              print("DEBUG: [Transaction] Sukses Sync & Update Saldo.");
            } else {
              print("DEBUG: [Transaction] Skip RPC karena sudah diproses.");
            }
          }
          else if (action == 'DELETE') {
            await _supabase.from('transactions').delete().eq('id', data['id']);

            // Hapus dari antrean dulu baru RPC balikin saldo
            final String? latestQueueData = prefs.getString(_queueKey);
            List<dynamic> latestQueue = jsonDecode(latestQueueData!);
            if (latestQueue.isNotEmpty && latestQueue[0]['data']['id'] == data['id']) {
              latestQueue.removeAt(0);
              await prefs.setString(_queueKey, jsonEncode(latestQueue));

              await _supabase.rpc('update_wallet_balance', params: {
                'w_id': data['wallet_id'],
                'amount_change': -data['amount'],
              });
            }
          }

          // Bersihkan cache riwayat lokal
          final String? localData = prefs.getString(_cacheKey);
          if (localData != null) {
            List<dynamic> localList = jsonDecode(localData);
            localList.removeWhere((l) => l['id'] == data['id']);
            await prefs.setString(_cacheKey, jsonEncode(localList));
          }

        } catch (e) {
          if (e.toString().contains("duplicate") || e.toString().contains("PGRST116")) {
            // Kalau data udah masuk di DB, hapus aja antreannya biar gak nyangkut
            queue.removeAt(0);
            await prefs.setString(_queueKey, jsonEncode(queue));
            continue;
          }
          print("DEBUG: [Transaction] Error: $e");
          break; // Stop loop jika offline
        }
      }

      if (prefs.getString(_queueKey) == '[]') {
        await _syncTransactionsFromOnline();
        await _syncMonthTotal();
      }
    } catch (e) {
      print("DEBUG: [Transaction] Fatal Error: $e");
    }
    print("DEBUG: [Transaction] Lock dilepas.");
  }

  // --- 4. FUNGSI LAINNYA ---
  Future<void> deleteTransaction(Transaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final String? localData = prefs.getString(_cacheKey);
    if (localData != null) {
      List<dynamic> currentList = jsonDecode(localData);
      currentList.removeWhere((item) => item['id'] == tx.id);
      await prefs.setString(_cacheKey, jsonEncode(currentList));
    }
    final String? currentQueue = prefs.getString(_queueKey);
    List<dynamic> queue = currentQueue != null ? jsonDecode(currentQueue) : [];
    queue.add({'action': 'DELETE', 'data': {'id': tx.id, 'wallet_id': tx.walletId, 'amount': tx.amount}});
    await prefs.setString(_queueKey, jsonEncode(queue));
    _processQueue();
  }

  // 1. KHUSUS PENGELUARAN HARI INI
  Future<double> getTodayExpense() async {
    final transactions = await getRecentTransactions();
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    return transactions
        .where((tx) =>
    tx.createdAt.toString().contains(todayStr) &&
        tx.amount < 0) // <--- KUNCINYA: Cuma ambil yang MINUS
        .fold<double>(0.0, (sum, item) => sum + item.amount);
  }

// 2. KHUSUS PEMASUKAN HARI INI
  Future<double> getTodayIncome() async {
    final transactions = await getRecentTransactions();
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    return transactions
        .where((tx) =>
    tx.createdAt.toString().contains(todayStr) &&
        tx.amount > 0) // <--- KUNCINYA: Cuma ambil yang POSITIF
        .fold<double>(0.0, (sum, item) => sum + item.amount);
  }

  Future<double> getTotalMonthExpense() async {
    final prefs = await SharedPreferences.getInstance();
    _syncMonthTotal();
    return prefs.getDouble(_cacheKeyMonthTotal) ?? 0.0;
  }

  Future<Map<String, double>> getCategoryReport() async {
    final transactions = await getRecentTransactions();
    Map<String, double> report = {};
    for (var tx in transactions) {
      report[tx.category] = (report[tx.category] ?? 0) + tx.amount;
    }
    return report;
  }

  Future<void> _syncTransactionsFromOnline() async {
    try {
      final response = await _supabase.from('transactions').select().order('created_at', ascending: false).limit(25);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(response));
    } catch (_) {}
  }

  Future<void> _syncMonthTotal() async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final response = await _supabase.from('transactions').select('amount').gte('created_at', monthStart);
      double total = response.fold<double>(0.0, (sum, item) => sum + (item['amount'] ?? 0).toDouble());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cacheKeyMonthTotal, total);
    } catch (_) {}
  }

  // Tambahkan di dalam class TransactionService
  Future<double> getPendingAmount() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    if (queueData == null || queueData == '[]') return 0.0;

    List<dynamic> queue = jsonDecode(queueData);
    double pending = 0.0;

    for (var item in queue) {
      final double amount = (item['data']['amount'] ?? 0).toDouble();

      if (item['action'] == 'INSERT') {
        // Kalau jajan (-1000), maka pending jadi -1000.
        // Nanti di UI: Saldo + (-1000) = Berkurang. (BENER)
        pending += amount;
      } else if (item['action'] == 'DELETE') {
        // Kalau hapus jajan (-1000), maka pending jadi - (-1000) = +1000.
        // Nanti di UI: Saldo + 1000 = Bertambah. (BENER)
        pending -= amount;
      }
    }
    return pending;
  }

  Future<Map<String, double>> getPendingAmountByWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    if (queueData == null || queueData == '[]') return {};

    List<dynamic> queue = jsonDecode(queueData);
    Map<String, double> pendingMap = {};

    print("\n=== DEBUG PENDING AMOUNT BY WALLET ===");
    print("Queue size: ${queue.length}");

    for (var item in queue) {
      try {
        final String wId = item['data']['wallet_id'];
        final double amount = (item['data']['amount'] ?? 0).toDouble();
        final String action = item['action'] ?? 'UNKNOWN';
        final String desc = item['data']['description'] ?? 'N/A';

        print("Item - Action: $action, Amount: $amount, Desc: $desc");

        if (action == 'INSERT') {
          pendingMap[wId] = (pendingMap[wId] ?? 0) + amount;
          print("  ➜ Added $amount to wallet $wId. Running total: ${pendingMap[wId]}");
        } else if (action == 'DELETE') {
          pendingMap[wId] = (pendingMap[wId] ?? 0) - amount;
          print("  ➜ Removed $amount from wallet $wId. Running total: ${pendingMap[wId]}");
        }
      } catch (e) {
        print("  ❌ Error parsing item: $e");
      }
    }

    print("Final pendingMap: $pendingMap");
    print("=====================================\n");
    
    return pendingMap;
  }

  // --- RECOVERY FUNCTION: CEK & BERSIHKAN QUEUE CORRUPTED ---
  Future<Map<String, dynamic>> diagnoseAndRepair() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueData = prefs.getString(_queueKey);
    
    List<dynamic> queue = queueData != null ? jsonDecode(queueData) : [];
    List<String> issues = [];
    int invalidCount = 0;

    print("\n=== TRANSACTION QUEUE DIAGNOSIS ===");
    print("Total items in queue: ${queue.length}");

    // CEK SETIAP ITEM DI QUEUE
    for (int i = 0; i < queue.length; i++) {
      try {
        final item = queue[i];
        final data = item['data'] ?? {};
        final amount = (data['amount'] ?? 0).toDouble();
        final action = item['action'] ?? 'UNKNOWN';

        print("\n[Item $i] Action: $action");
        print("  Amount: $amount");
        print("  Description: ${data['description'] ?? 'N/A'}");

        // Flag jika ada yang aneh
        if (action != 'INSERT' && action != 'DELETE') {
          issues.add("Item $i: Invalid action '$action'");
          invalidCount++;
        }
        if (amount == 0) {
          issues.add("Item $i: Amount is 0 (possibly corrupted)");
        }
      } catch (e) {
        issues.add("Item $i: Parse error - $e");
        invalidCount++;
      }
    }

    print("\n=== DIAGNOSIS RESULT ===");
    if (issues.isEmpty) {
      print("✅ Queue looks clean!");
      return {'status': 'OK', 'queue_size': queue.length};
    } else {
      print("⚠️  Found ${issues.length} issues:");
      for (var issue in issues) {
        print("  - $issue");
      }
    }

    // JIKA ADA YANG CORRUPT, BERSIHKAN & RETURN
    if (invalidCount > 0) {
      print("\n🧹 Cleaning corrupted transactions...");
      
      // Filter hanya yang valid
      List<dynamic> cleanedQueue = [];
      for (var item in queue) {
        try {
          final action = item['action'];
          final amount = (item['data']['amount'] ?? 0).toDouble();
          
          if ((action == 'INSERT' || action == 'DELETE') && amount != 0) {
            cleanedQueue.add(item);
          }
        } catch (_) {}
      }

      await prefs.setString(_queueKey, jsonEncode(cleanedQueue));
      print("✅ Cleaned! Removed ${queue.length - cleanedQueue.length} items");
      print("   New queue size: ${cleanedQueue.length}");

      return {
        'status': 'CLEANED',
        'removed': queue.length - cleanedQueue.length,
        'remaining': cleanedQueue.length
      };
    }

    return {'status': 'ISSUES_FOUND', 'issue_count': issues.length};
  }

  // --- FORCE RESET QUEUE & CACHE (NUCLEAR OPTION) ---
  Future<void> forceResetAndResync() async {
    final prefs = await SharedPreferences.getInstance();
    
    print("\n⚠️  FORCE RESET: Clearing all transaction cache & queue...");
    
    await prefs.remove(_cacheKey);
    await prefs.remove(_queueKey);
    await prefs.remove(_cacheKeyMonthTotal);
    
    print("✅ Cache cleared. Syncing fresh data from server...");
    
    try {
      await _syncTransactionsFromOnline();
      await _syncMonthTotal();
      print("✅ Fresh data synced successfully");
    } catch (e) {
      print("❌ Sync error: $e");
    }
  }
}
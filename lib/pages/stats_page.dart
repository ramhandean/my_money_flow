import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/transaction_service.dart';
import '../services/wallet_service.dart';
import '../utils/formatters.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final TransactionService _txService = TransactionService();
  final WalletService _walletService = WalletService();

  // Hapus 'late', jadikan nullable biar aman pas build pertama
  Future<Map<String, double>>? _healthFuture;
  Future<Map<String, double>>? _reportFuture;

  // Live update tracking
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _autoRefreshTimer;
  Timer? _syncQueueCheckTimer;
  bool _hadQueueBefore = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _setupConnectivityListener();
    _setupSyncQueueListener();
    _setupAutoRefresh();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _autoRefreshTimer?.cancel();
    _syncQueueCheckTimer?.cancel();
    super.dispose();
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      final isOnline = !result.contains(ConnectivityResult.none);
      if (isOnline && mounted && !_isRefreshing) {
        print("✅ [Stats] Kembali Online - Refresh data...");
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) _handleRefresh();
      }
    });
  }

  void _setupSyncQueueListener() {
    _syncQueueCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _isRefreshing) return;
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final txQueue = prefs.getString('transaction_sync_queue');
        final walletQueue = prefs.getString('wallet_sync_queue');
        final debtQueue = prefs.getString('debt_sync_queue');
        
        final hasTxQueue = txQueue != null && jsonDecode(txQueue).isNotEmpty;
        final hasWalletQueue = walletQueue != null && jsonDecode(walletQueue).isNotEmpty;
        final hasDebtQueue = debtQueue != null && jsonDecode(debtQueue).isNotEmpty;
        
        final hasQueue = hasTxQueue || hasWalletQueue || hasDebtQueue;
        
        if (_hadQueueBefore && !hasQueue) {
          print("✅ [Stats] Sync Queue selesai - Refresh data...");
          _handleRefresh();
        }
        
        _hadQueueBefore = hasQueue;
      } catch (e) {
        print("⚠️ [Stats] Error checking queue: $e");
      }
    });
  }

  void _setupAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (mounted && !_isRefreshing) {
        _handleRefresh();
      }
    });
  }

  // Fungsi buat trigger ambil data baru
  void _refreshData() {
    _healthFuture = _walletService.getFinancialHealth();
    _reportFuture = _txService.getCategoryReport();
  }

  // Handle Pull to Refresh manual
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    
    try {
      setState(() {
        _refreshData();
      });
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF4DB6AC);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Statistik Keuangan"),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- KARTU RINGKASAN (ASET vs HUTANG) ---
              FutureBuilder<Map<String, double>>(
                future: _healthFuture,
                builder: (context, snapshot) {
                  return _buildQuickSummary(snapshot);
                },
              ),

              const SizedBox(height: 32),
              const Text(
                "Analisis Pengeluaran",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // --- PROGRESS BARS KATEGORI ---
              FutureBuilder<Map<String, double>>(
                future: _reportFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(color: primaryColor)),
                    );
                  }

                  if (snapshot.hasError) return _buildErrorState();

                  final data = snapshot.data ?? {};
                  if (data.isEmpty) return _buildEmptyState();

                  final sortedEntries = data.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));

                  double totalExpense = data.values.fold(0, (sum, item) => sum + item);

                  return Column(
                    children: sortedEntries.map((entry) {
                      double percent = totalExpense > 0 ? entry.value / totalExpense : 0;
                      return _buildCategoryProgress(entry.key, entry.value, percent, primaryColor);
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 32),
              _buildSavingsAdvice(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS (LOGIC TETAP SAMA) ---

  Widget _buildQuickSummary(AsyncSnapshot<Map<String, double>> snapshot) {
    final balance = snapshot.data?['balance'] ?? 0;
    final debt = snapshot.data?['hutang'] ?? 0;
    final credit = snapshot.data?['piutang'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF4DB6AC).withOpacity(0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          _buildSummaryRow("Aset (Saldo + Piutang)", balance + credit, const Color(0xFF4DB6AC)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          _buildSummaryRow("Total Hutang Lu", debt, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        Text(
          CurrencyFormat.convertToIdr(amount, 0),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildCategoryProgress(String name, double amount, double percent, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("${(percent * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              backgroundColor: primary.withOpacity(0.1),
              color: percent > 0.4 ? Colors.orangeAccent : primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormat.convertToIdr(amount, 0),
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text("Belum ada data bulan ini.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.orangeAccent),
          const SizedBox(height: 12),
          const Text("Gagal hitung statistik."),
          TextButton(onPressed: () => setState(() => _refreshData()), child: const Text("Coba Lagi")),
        ],
      ),
    );
  }

  Widget _buildSavingsAdvice() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: Colors.blueAccent, size: 28),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              "Tips: Kurangi jajan yang nggak perlu biar aset lu makin nambah pas lebaran nanti!",
              style: TextStyle(fontSize: 12, height: 1.5, color: Colors.blueAccent, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
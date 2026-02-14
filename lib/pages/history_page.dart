import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/transaction_service.dart';
import '../services/debt_service.dart';
import '../models/transaction_model.dart';
import '../models/debt_model.dart';
import '../utils/formatters.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TransactionService _txService = TransactionService();
  final DebtService _debtService = DebtService();

  String _searchQuery = "";
  String _selectedFilter = "Semua";

  // Live update tracking
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _autoRefreshTimer;
  Timer? _syncQueueCheckTimer;
  bool _hadQueueBefore = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
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
        print("✅ [History] Kembali Online - Refresh data...");
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
          print("✅ [History] Sync Queue selesai - Refresh data...");
          _handleRefresh();
        }
        
        _hadQueueBefore = hasQueue;
      } catch (e) {
        print("⚠️ [History] Error checking queue: $e");
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

  // Fungsi refresh ditaruh di setState supaya FutureBuilder ke-trigger ambil data baru
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    
    try {
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Aktivitas", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  _txService.getRecentTransactions(),
                  _debtService.getActiveDebts(),
                ]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) return _buildErrorState();

                  final List<Transaction> txData = (snapshot.data?[0] as List<Transaction>?) ?? [];
                  final List<Debt> debtData = (snapshot.data?[1] as List<Debt>?) ?? [];

                  List<dynamic> allCombined = [...txData, ...debtData];

                  // LOGIKA FILTERING
                  final filteredData = allCombined.where((item) {
                    String title = "";
                    String category = "";
                    bool matchesType = false;

                    if (item is Transaction) {
                      title = item.description.toLowerCase();
                      category = item.category.toLowerCase();
                      if (_selectedFilter == "Semua") matchesType = true;
                      else if (_selectedFilter == "Pemasukan") matchesType = item.amount > 0;
                      else if (_selectedFilter == "Pengeluaran") matchesType = item.amount < 0;
                    } else if (item is Debt) {
                      title = item.personName.toLowerCase();
                      category = item.isDebt ? "hutang" : "piutang";
                      if (_selectedFilter == "Semua") matchesType = true;
                      else if (_selectedFilter == "Hutang") matchesType = item.isDebt;
                      else if (_selectedFilter == "Piutang") matchesType = !item.isDebt;
                    }

                    return (title.contains(_searchQuery.toLowerCase()) ||
                        category.contains(_searchQuery.toLowerCase())) && matchesType;
                  }).toList();

                  if (filteredData.isEmpty) return _buildEmptyState();

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: filteredData.length,
                    itemBuilder: (context, index) {
                      final item = filteredData[index];
                      final String uniqueKey = item is Transaction ? item.id! : item.id;

                      // Ganti bagian Dismissible di ListView.builder lu jadi kayak gini:

                      return Dismissible(
                        key: Key(uniqueKey),
                        direction: DismissDirection.endToStart,
                        // --- FIX DISINI ---
                        onDismissed: (direction) async {
                          // 1. Simpan salinan item buat di-delete di service
                          final itemToDelete = item;

                          // 2. Kasih feedback getar
                          HapticFeedback.mediumImpact();

                          // 3. Eksekusi hapus di Service (DB/Cache)
                          if (itemToDelete is Transaction) {
                            await _txService.deleteTransaction(itemToDelete);
                          } else if (itemToDelete is Debt) {
                            await _debtService.settleDebt(
                              itemToDelete.id,           // ID hutangnya
                              isDebt: itemToDelete.isDebt,
                              walletId: null,            // Null kalau mau potong kantong default
                              amount: itemToDelete.remainingAmount,
                            );
                          }

                          // 4. Update UI secara instan
                          setState(() {
                            // Kita panggil setState kosong aja udah cukup buat
                            // nge-trigger FutureBuilder ngebaca ulang data yang udah dihapus tadi.
                          });

                          // 5. Snack bar buat feedback
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("${itemToDelete is Transaction ? 'Transaksi' : 'Catatan'} berhasil dihapus"),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2), // Gue cerahin dikit biar jelas
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                              Text("Hapus", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        child: item is Transaction
                            ? _buildTransactionCard(item)
                            : _buildDebtCard(item),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET HELPER (Ditaruh diluar Builder biar Clean) ---

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: "Cari riwayat...",
          prefixIcon: const Icon(Icons.search, color: Color(0xFF4DB6AC)),
          filled: true,
          fillColor: Colors.grey.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchQuery = ""))
              : null,
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ["Semua", "Pemasukan", "Pengeluaran", "Hutang", "Piutang"];
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 12)),
              selected: isSelected,
              selectedColor: const Color(0xFF4DB6AC),
              onSelected: (_) => setState(() => _selectedFilter = filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionCard(Transaction tx) {
    final bool isExpense = tx.amount < 0;
    final Color statusColor = isExpense ? Colors.redAccent : const Color(0xFF4DB6AC);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(
            isExpense ? _getIcon(tx.category) : Icons.add_chart_rounded,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(tx.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("${isExpense ? 'Keluar' : 'Masuk'} • ${tx.category}", style: const TextStyle(fontSize: 11)),
        trailing: Text(
          "${isExpense ? '-' : '+'} ${CurrencyFormat.convertToIdr(tx.amount.abs(), 0)}",
          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDebtCard(Debt d) {
    final Color debtColor = d.isDebt ? Colors.orangeAccent : Colors.blueAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: debtColor.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: debtColor.withOpacity(0.1),
          child: Icon(d.isDebt ? Icons.arrow_downward : Icons.arrow_upward, color: debtColor, size: 20),
        ),
        title: Text(d.personName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(d.isDebt ? "Hutang Belum Lunas" : "Piutang Belum Lunas", style: const TextStyle(fontSize: 11)),
        trailing: Text(
          CurrencyFormat.convertToIdr(d.remainingAmount, 0),
          style: TextStyle(color: debtColor, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text("Gak ada riwayatnya, Bro.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildErrorState() => const Center(child: Text("Waduh, gagal ambil data!"));

  IconData _getIcon(String category) {
    switch (category) {
      case 'Makan': return Icons.fastfood_rounded;
      case 'Transport': return Icons.directions_bus_rounded;
      case 'Bensin': return Icons.local_gas_station_rounded;
      case 'Laundry': return Icons.local_laundry_service_rounded;
      default: return Icons.receipt_long_rounded;
    }
  }
}
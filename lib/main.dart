import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:my_money_flow/pages/add_debt_page.dart';
import 'package:shimmer/shimmer.dart'; // Tambahkan ini
import 'package:my_money_flow/models/wallet_model.dart';
import 'package:my_money_flow/pages/add_transaction_page.dart';
import 'package:my_money_flow/pages/auth_page.dart';
import 'package:my_money_flow/pages/history_page.dart';
import 'package:my_money_flow/pages/profile_page.dart';
import 'package:my_money_flow/pages/stats_page.dart';
import 'package:my_money_flow/services/debt_service.dart';
import 'package:my_money_flow/services/transaction_service.dart';
import 'package:my_money_flow/services/wallet_service.dart';
import 'package:my_money_flow/utils/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/debt_model.dart';
import 'models/transaction_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyMoneyFlow',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF4DB6AC),
        scaffoldBackgroundColor: const Color(0xFFF5F7F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4DB6AC),
        scaffoldBackgroundColor: const Color(0xFF111315),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E2023),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: Supabase.instance.client.auth.currentSession == null
          ? const AuthPage()
          : const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  final GlobalKey<_DashboardTabState> _dashboardKey = GlobalKey<_DashboardTabState>();

  @override
  void initState() {
    super.initState();
    _pages = [
      DashboardTab(
          key: _dashboardKey,
          onSeeAll: () => setState(() => _currentIndex = 1)
      ),
      const HistoryPage(),
      const StatsPage(),
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });

          // TAMBAHKAN LOGIC INI:
          // Kalau user ngetap ikon Home (index 0), paksa Dashboard buat refresh data
          if (index == 0) {
            _dashboardKey.currentState?._refreshAllData();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: 'Riwayat'),
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), selectedIcon: Icon(Icons.bar_chart), label: 'Statistik'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class DashboardTab extends StatefulWidget {
  final VoidCallback onSeeAll;
  const DashboardTab({super.key, required this.onSeeAll});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final WalletService _walletService = WalletService();
  final TransactionService _transactionService = TransactionService();

  late Future<double> _totalBalanceFuture;
  late Future<double> _todayExpenseFuture;
  late Future<double> _todayIncomeFuture;
  late Future<double> _monthExpenseFuture;
  late Future<List<Wallet>> _walletsFuture;
  late Future<List<Transaction>> _recentTransactionsFuture;
  late Future<List<Debt>> _activeDebtsFuture;

  bool _isBalanceVisible = true;
  
  // Untuk tracking konektivitas dan sync queue
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _syncQueueCheckTimer;
  bool _hadQueueBefore = false; // Track previous queue state
  bool _isRefreshing = false; // Prevent multiple simultaneous refreshes

  @override
  void initState() {
    super.initState();

    _totalBalanceFuture = Future.value(0.0);
    _todayExpenseFuture = Future.value(0.0);
    _todayIncomeFuture = Future.value(0.0);
    _monthExpenseFuture = Future.value(0.0);
    _walletsFuture = Future.value([]);
    _recentTransactionsFuture = Future.value([]);
    _activeDebtsFuture = Future.value([]);

    _refreshAllData();
    _setupConnectivityListener();
    _setupSyncQueueListener();
  }
  
  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _syncQueueCheckTimer?.cancel();
    super.dispose();
  }
  
  // --- LISTENER KONEKTIVITAS ---
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      // Jika baru terhubung online, refresh data
      final isOnline = !result.contains(ConnectivityResult.none);
      if (isOnline && mounted && !_isRefreshing) {
        print("✅ [Dashboard] Kembali Online - Refresh data...");
        await Future.delayed(const Duration(milliseconds: 800)); // Tunggu koneksi stabil
        if (mounted) _refreshAllData();
      }
    });
  }
  
  // --- LISTENER SYNC QUEUE (IMPROVED) ---
  void _setupSyncQueueListener() {
    _syncQueueCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _isRefreshing) return;
      
      try {
        final prefs = await SharedPreferences.getInstance();
        
        // Cek semua queue
        final txQueue = prefs.getString('transaction_sync_queue');
        final walletQueue = prefs.getString('wallet_sync_queue');
        final debtQueue = prefs.getString('debt_sync_queue');
        
        final hasTxQueue = txQueue != null && jsonDecode(txQueue).isNotEmpty;
        final hasWalletQueue = walletQueue != null && jsonDecode(walletQueue).isNotEmpty;
        final hasDebtQueue = debtQueue != null && jsonDecode(debtQueue).isNotEmpty;
        
        final hasQueue = hasTxQueue || hasWalletQueue || hasDebtQueue;
        
        // HANYA refresh jika queue berubah dari ADA → KOSONG
        // (Ini berarti sync baru selesai)
        if (_hadQueueBefore && !hasQueue) {
          print("✅ [Dashboard] Sync Queue selesai - Refresh data...");
          _refreshAllData();
        }
        
        _hadQueueBefore = hasQueue;
      } catch (e) {
        print("⚠️ [Dashboard] Error checking queue: $e");
      }
    });
  }

  // GANTI VOID JADI FUTURE<VOID>
  Future<void> _refreshAllData() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      // 1. KASIH JEDA DIKIT (Opsi)
      // Supaya SharedPreferences kelar nulis data baru dari addWallet
      await Future.delayed(const Duration(milliseconds: 100));

      // 2. AMBIL DATA (Satu sumber kebenaran)
      final results = await Future.wait([
        _walletService.getWallets(),
        _transactionService.getPendingAmountByWallet(),
        _transactionService.getTodayExpense(),
        _transactionService.getTodayIncome(),
        _transactionService.getTotalMonthExpense(),
        _transactionService.getRecentTransactions(),
        DebtService().getActiveDebts(),
      ]);

      final List<Wallet> baseWallets = results[0] as List<Wallet>;
      final Map<String, double> pendingMap = results[1] as Map<String, double>;

      // 3. KALKULASI SALDO + PENDING (Untuk Dashboard)
      final List<Wallet> walletsWithPending = baseWallets.map((w) {
        double pending = pendingMap[w.id] ?? 0.0;
        return w.copyWith(balance: w.balance + pending);
      }).toList();

      final double totalBalance = walletsWithPending.fold<double>(
          0.0, (sum, item) => sum + item.balance
      );

      // 4. UPDATE FUTURES (Semua serentak)
      if (mounted) {
        setState(() {
          _totalBalanceFuture = Future.value(totalBalance);
          _walletsFuture = Future.value(walletsWithPending);
          _todayExpenseFuture = Future.value(results[2] as double);
          _todayIncomeFuture = Future.value(results[3] as double);
          _monthExpenseFuture = Future.value(results[4] as double);
          _recentTransactionsFuture = Future.value(results[5] as List<Transaction>);
          _activeDebtsFuture = Future.value(results[6] as List<Debt>);
        });
      }

      // Delay visual kecil buat transisi Shimmer
      await Future.delayed(const Duration(milliseconds: 200));

    } catch (e) {
      print("⚠️ [Dashboard] Error Refresh: $e");
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MyMoneyFlow', style: TextStyle(fontSize: 12, color: Colors.grey)),
            StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final user = snapshot.data?.session?.user ?? Supabase.instance.client.auth.currentUser;
                final String name = user?.userMetadata?['display_name'] ?? user?.email?.split('@')[0] ?? "Bro";
                return Text('Halo, $name!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
              },
            ),
          ],
        ),
        actions: [
          FutureBuilder<bool>(
            future: _hasAnyQueue(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return IconButton(
                  icon: const Icon(Icons.cleaning_services_rounded, color: Colors.orangeAccent, size: 20),
                  onPressed: () => _showClearQueueDialog(),
                );
              }
              return const SizedBox();
            },
          ),
          StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snapshot) {
              final connectivity = snapshot.data;
              bool isOnline = connectivity != null && !connectivity.contains(ConnectivityResult.none);
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: isOnline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  side: BorderSide.none,
                  label: Text(isOnline ? "Online" : "Offline", style: TextStyle(fontSize: 10, color: isOnline ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                  avatar: CircleAvatar(radius: 4, backgroundColor: isOnline ? Colors.green : Colors.grey),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAllData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), // Padding atas dikit aja
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSmartInsight(),

              // --- SECTION SALDO ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Saldo Kamu", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  IconButton(
                    onPressed: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                    icon: Icon(_isBalanceVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  ),
                ],
              ),
              FutureBuilder<double>(
                future: _totalBalanceFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return _buildShimmerText(200, 32);

                  final saldo = snapshot.data ?? 0;
                  final isNegative = saldo < 0;

                  // --- PERBAIKAN DI SINI ---
                  // Kalau negatif tetep merah, kalau nggak, ikutin warna tema sistem
                  final displayColor = isNegative
                      ? Colors.redAccent
                      : Theme.of(context).colorScheme.onSurface;

                  return Row(
                    children: [
                      if (isNegative)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.warning_rounded, color: Colors.redAccent, size: 24),
                        ),
                      Expanded(
                        child: Text(
                          _isBalanceVisible ? CurrencyFormat.convertToIdr(saldo, 0) : "••••••••",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -1,
                            color: displayColor, // Sudah otomatis adaptif
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // --- BARIS 1: SUMMARY (MASUK & KELUAR) ---
              Row(
                children: [
                  // Pemasukan (Gue asumsikan lu ada _todayIncomeFuture, kalau belum pake 0 dulu)
                  _buildSummaryCard("Masuk Hari Ini", _todayIncomeFuture, const Color(0xFF4DB6AC), Icons.arrow_upward),
                  const SizedBox(width: 12),
                  _buildSummaryCard("Keluar Hari Ini", _todayExpenseFuture, Colors.redAccent, Icons.arrow_downward),
                ],
              ),

              const SizedBox(height: 12),

              // --- BARIS 2: KESEHATAN (FULL WIDTH) ---
              // Kita bungkus HealthCard biar lebarnya penuh, lebih enak dilihat
              SizedBox(
                width: double.infinity,
                child: _buildHealthCard(),
              ),

              const SizedBox(height: 32),

              // --- SECTION KANTONG ---
              _buildSectionHeader("Kantong Saya", onAction: () => _showAddWalletDialog()),
              _buildWalletList(),

              const SizedBox(height: 32),

              // --- SECTION TRANSAKSI ---
              _buildSectionHeader(
                  "Transaksi Terakhir",
                  onAction: widget.onSeeAll,
                  actionLabel: "Lihat Semua"
              ),
              _buildRecentTransactions(),

              const SizedBox(height: 32),

              // --- SECTION HUTANG ---
              _buildSectionHeader(
                  "Hutang & Piutang",
                  onAction: widget.onSeeAll,
                  actionLabel: "Lihat Semua"
              ),
              _buildDebtList(),
            ],
          ),
        ),
      ),
      // Diubah jadi FAB standar agar lebih ramping
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddOptions(); // Fungsi buat milih mau nambah apa
        },
        backgroundColor: const Color(0xFF4DB6AC),
        child: const Icon(Icons.add_rounded, size: 32, color: Colors.white),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle bar kecil di atas modal biar makin pro
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Opsi 1: Transaksi (Bisa Pengeluaran / Pemasukan)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF4DB6AC),
              child: Icon(Icons.swap_horiz_rounded, color: Colors.white),
            ),
            title: const Text("Catat Transaksi", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("Pengeluaran atau Pemasukan harian"),
            onTap: () async {
              Navigator.pop(context);
              final res = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddTransactionPage())
              );
              if (res == true) _refreshAllData();
            },
          ),

          const Divider(indent: 70, endIndent: 20),

          // Opsi 2: Hutang / Piutang
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent.withOpacity(0.1),
              child: const Icon(Icons.handshake_outlined, color: Colors.blueAccent),
            ),
            title: const Text("Hutang & Piutang", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("Catat pinjaman atau tagihan"),
            onTap: () async {
              Navigator.pop(context);
              final res = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddDebtPage())
              );
              if (res == true) _refreshAllData();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS & SHIMMERS ---

  Widget _buildShimmerText(double width, double height) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.withOpacity(0.1),
      highlightColor: Colors.grey.withOpacity(0.05),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.withOpacity(0.1),
      highlightColor: Colors.grey.withOpacity(0.05),
      child: Card(
        margin: const EdgeInsets.only(top: 12),
        child: Container(height: 70, width: double.infinity),
      ),
    );
  }

  Widget _buildSmartInsight() {
    return FutureBuilder<List<dynamic>>(
      // Ambil balance dan expenses dari sumber yang SAMA
      future: Future.wait([
        _totalBalanceFuture,
        _monthExpenseFuture,
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        double currentBalance = snapshot.data![0] as double;
        double monthExpense = snapshot.data![1] as double;

        // Jika saldo negatif, PASTI critical
        if (currentBalance < 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.redAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Waduh, Saldo Negatif!",
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Saldo lu ${CurrencyFormat.convertToIdr(currentBalance, 0)}. Segera topup atau kurangi pengeluaran!",
                        style: TextStyle(fontSize: 12, color: Colors.redAccent.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Hitung rasio pengeluaran bulan ini vs saldo saat ini
        double totalBudget = currentBalance + monthExpense;
        double burnRate = totalBudget > 0 ? (monthExpense / totalBudget) : 0;

        // Logika Status berdasarkan burn rate dan saldo
        bool isCritical = burnRate >= 0.7 || (currentBalance > 0 && currentBalance < monthExpense);
        bool isWarning = burnRate >= 0.4;

        // Jika pengeluaran masih kecil, gak usah munculin insight
        if (burnRate < 0.1) return const SizedBox();

        final Color themeColor = isCritical ? Colors.redAccent : Colors.orangeAccent;

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: themeColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                  isCritical ? Icons.warning_rounded : Icons.insights_rounded,
                  color: themeColor
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCritical
                          ? "Waduh, Gawat Bro!"
                          : "Update Keuangan Bulan Ini",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: themeColor
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Lu udah pake ${(burnRate * 100).toStringAsFixed(1)}% dari total aset lu bulan ini. ${isCritical ? 'Rem dulu, jangan boros!' : 'Masih aman, tapi tetep dijaga ya.'}",
                      style: TextStyle(fontSize: 12, color: themeColor.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(String title, Future<double> future, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2))
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 4),
                  Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))
                ]
            ),
            const SizedBox(height: 12),
            FutureBuilder<double>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerText(100, 20);
                }

                // --- FIX DISINI ---
                // Pake .abs() supaya pengeluaran (-1000) tampil jadi 1000
                // Karena judulnya udah "Keluar Hari Ini", gak perlu minus lagi
                double displayValue = (snapshot.data ?? 0).abs();

                return Text(
                  CurrencyFormat.convertToIdr(displayValue, 0),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard() {
    return FutureBuilder<List<dynamic>>(
      // Ambil balance dan financial health sekaligus dari sumber yang SAMA
      future: Future.wait([
        _totalBalanceFuture,
        _walletService.getFinancialHealth(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
              height: 80,
              decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20)
              )
          );
        }

        final double totalBalance = snapshot.data?[0] as double? ?? 0;
        final Map<String, double> health = snapshot.data?[1] as Map<String, double>? ?? {};
        
        double totalAssets = health['total_assets'] ?? 0;
        double totalDebts = health['total_debts'] ?? 0;

        // --- LOGIC KESEHATAN YANG AKURAT (KUNCI!) ---
        bool isCritical = false;
        bool isWarning = false;
        String statusText = "Dompet Aman!";
        IconData statusIcon = Icons.health_and_safety_outlined;

        // 1. CRITICAL: Saldo negatif (TERBURUK!)
        if (totalBalance < 0) {
          isCritical = true;
          statusText = "Waduh, Defisit!";
          statusIcon = Icons.warning_rounded;
        }
        // 2. CRITICAL: Saldo positif tapi < totalDebts (gak bisa cover hutang)
        else if (totalBalance > 0 && totalBalance < totalDebts) {
          isCritical = true;
          statusText = "Saldo < Hutang!";
          statusIcon = Icons.warning_rounded;
        }
        // 3. CRITICAL: Debt Ratio > 80% (hutang terlalu banyak)
        else if (totalAssets > 0 && (totalDebts / totalAssets) > 0.8) {
          isCritical = true;
          statusText = "Hutang Berat";
          statusIcon = Icons.warning_rounded;
        }
        // 4. WARNING: Saldo 0 atau sangat rendah (< 10% dari aset total)
        else if (totalBalance == 0 || (totalAssets > 0 && totalBalance > 0 && totalBalance < (totalAssets * 0.1))) {
          isWarning = true;
          statusText = totalBalance == 0 ? "Saldo Kosong!" : "Saldo Rendah";
          statusIcon = Icons.trending_down_rounded;
        }
        // 5. WARNING: Debt Ratio moderate (50-80%)
        else if (totalAssets > 0 && (totalDebts / totalAssets) > 0.5) {
          isWarning = true;
          statusText = "Rem Dulu, Bro";
          statusIcon = Icons.trending_down_rounded;
        }
        // 6. SAFE: Semuanya baik
        else {
          statusText = "Dompet Aman!";
          statusIcon = Icons.check_circle_rounded;
        }

        final Color statusColor = isCritical 
            ? Colors.redAccent 
            : (isWarning ? Colors.orangeAccent : const Color(0xFF4DB6AC));

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.2))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.health_and_safety_outlined, color: statusColor, size: 16),
                      const SizedBox(width: 4),
                      const Text("Kesehatan", style: TextStyle(color: Colors.grey, fontSize: 12))
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor)
                  ),
                ],
              ),
              Icon(statusIcon, color: statusColor, size: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWalletList() {
    return FutureBuilder<List<Wallet>>(
      future: _walletsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(children: List.generate(2, (i) => _buildLoadingCard()));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  "Belum ada kantong.",
                  style: TextStyle(color: Colors.grey, fontSize: 13)
              ),
            ),
          );
        }

        final List<Wallet> wallets = snapshot.data!;

        return Column(
          children: wallets.map((wallet) {
            final isCash = wallet.type == 'cash';

            return Dismissible(
              key: Key(wallet.id),
              direction: DismissDirection.endToStart,
              // Konfirmasi sebelum hapus biar nggak sengaja kegeser
              confirmDismiss: (direction) async {
                _showDeleteWalletDialog(wallet);
                return false; // Kita return false karena hapus benerannya di dalam dialog
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              ),
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ListTile(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    _showEditWalletDialog(wallet);
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DB6AC).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCash ? Icons.payments_rounded : Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF4DB6AC),
                      size: 24,
                    ),
                  ),
                  title: Text(wallet.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(
                      "Tahan untuk edit • ${isCash ? "Tunai" : "Digital"}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey)
                  ),
                  trailing: Text(
                    CurrencyFormat.convertToIdr(wallet.balance, 0),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: wallet.balance < 0 ? Colors.redAccent : const Color(0xFF4DB6AC),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildRecentTransactions() {
    return FutureBuilder<List<Transaction>>(
      future: _recentTransactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(children: List.generate(3, (i) => _buildLoadingCard()));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  "Belum ada transaksi.",
                  style: TextStyle(color: Colors.grey, fontSize: 13)
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.take(5).map((tx) {
            // --- LOGIKA PINTAR ---
            // Kita cek apakah ini pengeluaran (angka negatif)
            final bool isExpense = tx.amount < 0;
            final Color statusColor = isExpense ? Colors.redAccent : const Color(0xFF4DB6AC);
            final IconData statusIcon = isExpense ? Icons.south_west_rounded : Icons.north_east_rounded;

            // ... di dalam map transaksi ...
            return Dismissible(
              key: Key(tx.id!),
              direction: DismissDirection.endToStart,
              // TAMBAHKAN INI
              confirmDismiss: (direction) async {
                return await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Hapus Transaksi?"),
                    content: Text("Yakin mau hapus '${tx.description}'?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("BATAL")),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("HAPUS", style: TextStyle(color: Colors.redAccent))
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) async {
                HapticFeedback.mediumImpact();
                await _transactionService.deleteTransaction(tx);
                _refreshAllData();
              },
              // ... rest of code
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.withOpacity(0.05)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.1),
                    child: Icon(statusIcon, size: 18, color: statusColor),
                  ),
                  title: Text(
                    tx.description,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(tx.category, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Text(
                    // Pake .abs() biar tanda minus aslinya ilang, kita ganti tanda manual
                    "${isExpense ? '-' : '+'} ${CurrencyFormat.convertToIdr(tx.amount.abs(), 0)}",
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDebtList() {
    return FutureBuilder<List<Debt>>(
      future: _activeDebtsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingCard();

        if (snapshot.hasError) return const Text("Gagal muat data.");

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  "Semua hutang lunas! 🎉",
                  style: TextStyle(color: Colors.grey, fontSize: 13)
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.take(3).map((d) {
            final Color statusColor = d.isDebt ? Colors.orangeAccent : Colors.blueAccent;

            // ... di dalam map hutang ...
            return Dismissible(
              key: Key(d.id),
              direction: DismissDirection.endToStart,
              // TAMBAHKAN INI
              confirmDismiss: (direction) async {
                return await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Konfirmasi Lunas"),
                    content: Text("Yakin ${d.personName} sudah lunas?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("BELUM")),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("YA, LUNAS!", style: TextStyle(color: Color(0xFF4DB6AC)))
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) async {
                HapticFeedback.mediumImpact();
                await DebtService().settleDebt(
                  d.id,
                  isDebt: d.isDebt,
                  walletId: null,
                  amount: d.remainingAmount,
                );
                _refreshAllData();
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, color: statusColor),
                    Text("LUNAS", style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.1)),
                ),
                child: ListTile(
                  onTap: () => _showSettleConfirmation(d), // Klik biasa tetep muncul dialog kalau mau
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.1),
                    child: Icon(d.isDebt ? Icons.upload_rounded : Icons.download_rounded, color: statusColor, size: 20),
                  ),
                  title: Text(d.personName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(d.isDebt ? "Hutang" : "Piutang", style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    CurrencyFormat.convertToIdr(d.remainingAmount, 0),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onAction, String actionLabel = "Tambah"}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  // --- LOGIC HELPERS & DIALOGS ---

  Future<bool> _hasAnyQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final txQueue = prefs.getString('transaction_sync_queue');
    return txQueue != null && jsonDecode(txQueue).isNotEmpty;
  }

  void _showClearQueueDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Antrean?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          TextButton(onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('transaction_sync_queue');
            Navigator.pop(context);
            _refreshAllData();
          }, child: const Text("HAPUS")),
        ],
      ),
    );
  }

  void _showAddWalletDialog() {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    const Color primaryColor = Color(0xFF4DB6AC);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 12
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar di atas
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Buat Kantong Baru",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Pisahkan dana lu biar nggak kecampur-campur.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Input Nama Kantong
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nama Kantong',
                hintText: 'Misal: Tabungan Mudik, Dana Darurat',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Input Saldo Awal
            TextField(
              controller: balanceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Saldo Awal (Rp)',
                prefixIcon: const Icon(Icons.money, color: primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Tombol Simpan (WARNA PUTIH BIAR SAMA)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white, // INI DIA KUNCINYA
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    // A. Simpan data
                    await _walletService.addWallet(
                        nameController.text,
                        double.tryParse(balanceController.text) ?? 0,
                        'cash'
                    );

                    if (context.mounted) {
                      Navigator.pop(context); // Tutup modal dulu

                      // B. AWAIT REFRESH (Nunggu sampe Future.wait di atas kelar)
                      await _refreshAllData();

                      // C. NOTIFIKASI
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Kantong berhasil dibuat!"))
                      );
                    }
                  }
                },
                child: const Text(
                  "SIMPAN KANTONG",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDebtDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    bool isDebt = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Expanded(child: GestureDetector(
                      onTap: () => setModalState(() => isDebt = true),
                      child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: isDebt ? Colors.redAccent.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text("HUTANG SAYA", style: TextStyle(color: isDebt ? Colors.redAccent : Colors.grey, fontWeight: FontWeight.bold)))
                      ))),
                  Expanded(child: GestureDetector(
                      onTap: () => setModalState(() => isDebt = false),
                      child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: !isDebt ? Colors.blueAccent.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text("PIUTANG", style: TextStyle(color: !isDebt ? Colors.blueAccent : Colors.grey, fontWeight: FontWeight.bold)))
                      ))),
                ]),
              ),
              const SizedBox(height: 24),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Orang/Instansi', prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 16),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp)', prefixIcon: Icon(Icons.money))),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDebt ? Colors.redAccent : Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (nameController.text.isNotEmpty && amountController.text.isNotEmpty) {
                      await DebtService().addDebt(personName: nameController.text, amount: double.parse(amountController.text), isDebt: isDebt, walletId: null);
                      if (mounted) {
                        Navigator.pop(context);
                        _refreshAllData();
                      }
                    }
                  },
                  child: Text(isDebt ? "SIMPAN HUTANG" : "SIMPAN PIUTANG", style: const TextStyle(fontWeight: FontWeight.bold))
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettleConfirmation(Debt debt) {
    // Tentukan warna tema dialog berdasarkan jenis hutang/piutang
    final Color themeColor = debt.isDebt ? Colors.redAccent : const Color(0xFF4DB6AC);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: themeColor),
            const SizedBox(width: 10),
            const Text("Konfirmasi Lunas"),
          ],
        ),
        content: Text(
          "Yakin ${debt.isDebt ? 'hutang ke' : 'piutang dari'} ${debt.personName} sebesar ${CurrencyFormat.convertToIdr(debt.remainingAmount, 0)} sudah lunas?",
          style: const TextStyle(fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("BELUM", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white, // WARNA TEXT PUTIH BIAR CAKEP
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              await DebtService().settleDebt(
                debt.id,
                isDebt: debt.isDebt,
                walletId: null,
                amount: debt.remainingAmount,
              );
              if (context.mounted) {
                Navigator.pop(context);
                _refreshAllData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Berhasil! ${debt.personName} sudah lunas."),
                    backgroundColor: themeColor,
                  ),
                );
              }
            },
            child: const Text("YA, LUNAS!", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditWalletDialog(Wallet wallet) {
    final nameController = TextEditingController(text: wallet.name);
    final balanceController = TextEditingController(text: wallet.balance.toString());
    const Color primaryColor = Color(0xFF4DB6AC);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 12
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar di atas
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Edit Kantong",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Ubah nama atau saldo kantong kamu.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Input Nama Kantong
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Nama Kantong',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Input Saldo
            TextField(
              controller: balanceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Saldo (Rp)',
                prefixIcon: const Icon(Icons.money, color: primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Tombol Simpan & Hapus
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteWalletDialog(wallet);
                    },
                    child: const Text("HAPUS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (nameController.text.isNotEmpty && balanceController.text.isNotEmpty) {
                        await _walletService.updateWallet(
                          wallet.id,
                          nameController.text,
                          double.tryParse(balanceController.text) ?? 0,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          _refreshAllData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Kantong berhasil diupdate!"),
                              backgroundColor: primaryColor,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text("SIMPAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteWalletDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            const Text("Hapus Kantong?"),
          ],
        ),
        content: Text(
          "Yakin mau hapus kantong '${wallet.name}'? Data ini gak bisa dikembaliin.",
          style: const TextStyle(fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("BATAL", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              await _walletService.deleteWallet(wallet.id);
              if (context.mounted) {
                Navigator.pop(context);
                _refreshAllData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Kantong berhasil dihapus!"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text("HAPUS", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
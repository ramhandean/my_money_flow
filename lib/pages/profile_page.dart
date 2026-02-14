import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wallet_service.dart';
import '../utils/formatters.dart';
import 'account_settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final walletService = WalletService();

    return Scaffold(
      appBar: AppBar(title: const Text("Profil Saya")),
      body: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            // Ambil user paling fresh dari stream
            final user = snapshot.data?.session?.user ?? Supabase.instance.client.auth.currentUser;

            final String displayName = user?.userMetadata?['display_name'] ??
                user?.email?.split('@')[0].toUpperCase() ??
                "USER";
            final String? photoUrl = user?.userMetadata?['photo_url'];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // --- AVATAR DINAMIS (Sekarang Otomatis Refresh) ---
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF4DB6AC),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(Icons.person, size: 50, color: Colors.black)
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // --- NAMA DINAMIS ---
                  Text(
                      displayName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                  ),
                  Text(user?.email ?? "", style: const TextStyle(color: Colors.grey)),

                  const SizedBox(height: 32),

                  // --- KARTU RINGKASAN ASET ---
                  FutureBuilder<Map<String, double>>(
                    future: walletService.getFinancialHealth(),
                    builder: (context, healthSnapshot) {
                      double netWorth = healthSnapshot.data?['net_worth'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total Kekayaan Bersih", style: TextStyle(fontWeight: FontWeight.w500)),
                            Text(
                              CurrencyFormat.convertToIdr(netWorth, 0),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4DB6AC)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // --- MENU LAINNYA ---
                  _buildProfileMenu(
                      Icons.settings_outlined, "Pengaturan Akun", () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AccountSettingsPage())
                    );
                  }),
                  _buildProfileMenu(
                      Icons.info_outline,
                      "Tentang MyMoneyFlow",
                          () => _showAboutDialog(context)
                  ),

                  const Divider(height: 40),

                  _buildProfileMenu(
                      Icons.logout,
                      "Keluar Aplikasi",
                          () => _showLogoutConfirmation(context),
                      isLogout: true
                  ),
                ],
              ),
            );
          }
      ),
    );
  }

  // ... (Widget _buildProfileMenu, _showAboutDialog, dan _showLogoutConfirmation tetep sama kayak kode lu)

  Widget _buildProfileMenu(IconData icon, String title, VoidCallback onTap, {bool isLogout = false}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.redAccent : null),
      title: Text(title, style: TextStyle(color: isLogout ? Colors.redAccent : null)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: "MyMoneyFlow",
      applicationVersion: "v1.1.0",
      applicationIcon: const CircleAvatar(
        backgroundColor: Color(0xFF4DB6AC),
        child: Icon(Icons.auto_graph, color: Colors.black),
      ),
      children: [
        const Text("Aplikasi pengelola keuangan pribadi untuk memantau saldo, transaksi, dan hutang secara real-time."),
        const SizedBox(height: 12),
        const Text("Developer: Dean Ramhan"),
        const Text("Website: engineroom.my.id"),
      ],
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Konfirmasi Keluar"),
        content: const Text("Yakin mau keluar? Catatan keuangan lu tetep aman kok di database."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              }
            },
            child: const Text("KELUAR"),
          ),
        ],
      ),
    );
  }
}
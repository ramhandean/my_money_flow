import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/transaction_service.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _isLoading = false;

  User? get user => Supabase.instance.client.auth.currentUser;

  // --- HELPER CEK KONEKSI (SAT-SET) ---
  Future<bool> _isOnline() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  // --- WRAPPER UNTUK FITUR YANG WAJIB ONLINE ---
  void _runOnlineAction(Function action) async {
    if (await _isOnline()) {
      action();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Fitur ini wajib online, Bro. Cari sinyal dulu!"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = user?.userMetadata?['display_name'] ?? user?.email?.split('@')[0] ?? "User";
    final String? photoUrl = user?.userMetadata?['photo_url'];

    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan Akun")),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text("Profil", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4DB6AC))),
              const SizedBox(height: 8),

              // Username (Bisa dilihat offline, tapi edit wajib online)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text("Username"),
                subtitle: Text(displayName),
                trailing: const Icon(Icons.edit, size: 18),
                onTap: () => _runOnlineAction(() => _showEditNameDialog(context, displayName)),
              ),

              // Foto Profil (Wajib online untuk upload)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text("Foto Profil"),
                subtitle: Text(photoUrl != null && photoUrl.isNotEmpty ? "Sudah ada foto" : "Belum ada foto"),
                trailing: const Icon(Icons.upload_rounded, size: 18),
                onTap: _isLoading ? null : () => _runOnlineAction(_uploadAndSavePhoto),
              ),

              const Divider(),
              const SizedBox(height: 16),
              const Text("Informasi Akun", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4DB6AC))),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text("Email"),
                subtitle: Text(user?.email ?? "-"),
              ),

              const Divider(),
              const SizedBox(height: 16),
              const Text("Keamanan", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4DB6AC))),

              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text("Ganti Password"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _runOnlineAction(() => _showChangePasswordDialog(context)),
              ),

              const Divider(),
              const SizedBox(height: 16),
              const Text("Perbaikan Data", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4DB6AC))),

              ListTile(
                leading: const Icon(Icons.health_and_safety_outlined, color: Color(0xFF4DB6AC)),
                title: const Text("Diagnosa Transaksi"),
                subtitle: const Text("Cek apakah ada transaksi yang corrupt"),
                trailing: const Icon(Icons.info_outline),
                onTap: () => _showDiagnoseDialog(context),
              ),

              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined, color: Colors.blueAccent),
                title: const Text("Reset & Sinkron Ulang"),
                subtitle: const Text("Bersihkan cache & ambil data terbaru"),
                trailing: const Icon(Icons.refresh_rounded),
                onTap: _isLoading ? null : () => _showResetConfirmDialog(context),
              ),

              const SizedBox(height: 32),

              const Text("Lainnya", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),

              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text("Hapus Akun & Data", style: TextStyle(color: Colors.redAccent)),
                onTap: () => _runOnlineAction(() => _showDeleteAccountConfirm(context)),
              ),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // Sisanya (Dialog Edit Name, Upload Photo, dll) tetap sama,
  // Tapi panggilannya sudah dijaga oleh _runOnlineAction.

  void _showEditNameDialog(BuildContext context, String currentName) {
    final nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ubah Username"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Username Baru"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(data: {'display_name': nameController.text}),
                );
                if (mounted) {
                  setState(() {});
                  Navigator.pop(context);
                }
              } catch (e) {
                print(e);
              }
            },
            child: const Text("SIMPAN"),
          ),
        ],
      ),
    );
  }

  // --- FUNGSI UPLOAD TETAP SAMA SEPERTI KODE LU ---
  Future<void> _uploadAndSavePhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    try {
      setState(() => _isLoading = true);
      final file = File(image.path);
      final String filePath = '${user!.id}/profile.${image.path.split('.').last}';

      await Supabase.instance.client.storage.from('avatars').upload(filePath, file, fileOptions: const FileOptions(upsert: true));
      final String publicUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(filePath);

      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'photo_url': publicUrl}));
      if (mounted) setState(() {});
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FUNGSI GANTI PASSWORD ---
  void _showChangePasswordDialog(BuildContext context) {
    final passController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ganti Password Baru"),
        content: TextField(
          controller: passController,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Minimal 6 Karakter"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () async {
              if (passController.text.length < 6) return;
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(password: passController.text),
              );
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password diganti!")));
              }
            },
            child: const Text("SIMPAN"),
          ),
        ],
      ),
    );
  }

  // --- DIAGNOSE TRANSACTIONS ---
  void _showDiagnoseDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Diagnosa Transaksi"),
        content: const Text("Scanning transaction queue untuk mencari anomali..."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("BATAL"),
          ),
        ],
      ),
    );

    try {
      final txService = TransactionService();
      final result = await txService.diagnoseAndRepair();

      if (context.mounted) {
        Navigator.pop(context);
        
        String message = "";
        if (result['status'] == 'OK') {
          message = "✅ Queue terlihat bersih!\nTotal items: ${result['queue_size']}";
        } else if (result['status'] == 'CLEANED') {
          message = "🧹 Berhasil dibersihkan!\nDihapus: ${result['removed']} items\nSisa: ${result['remaining']} items";
        } else {
          message = "⚠️ Ditemukan ${result['issue_count']} masalah di queue.\nSilakan gunakan 'Reset & Sinkron Ulang'.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  // --- RESET & RESYNC ---
  void _showResetConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset & Sinkron Ulang?"),
        content: const Text(
          "Ini akan:\n"
          "• Hapus cache transaksi lokal\n"
          "• Bersihkan queue yang pending\n"
          "• Ambil data terbaru dari server\n\n"
          "⚠️ Pastikan kamu online!"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("BATAL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              Navigator.pop(context);
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text("Sedang memproses..."),
                  content: const LinearProgressIndicator(),
                ),
              );

              try {
                final txService = TransactionService();
                await txService.forceResetAndResync();

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Reset berhasil! Data sudah segar. Silakan buka ulang dashboard."),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("❌ Error: $e")),
                  );
                }
              }
            },
            child: const Text("RESET SEKARANG"),
          ),
        ],
      ),
    );
  }

  // --- KONFIRMASI HAPUS AKUN ---
  void _showDeleteAccountConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Semua Data?"),
        content: const Text("Aksi ini tidak bisa dibatalkan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur hapus akun butuh konfirmasi admin.")));
                Navigator.pop(context);
              },
              child: const Text("IYA, HAPUS", style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }
}
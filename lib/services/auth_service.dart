import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // Login pake email
  Future<void> signIn(String email, String password) async {
    try {
      await _supabase.auth.signInWithPassword(
          email: email,
          password: password
      ).timeout(const Duration(seconds: 10)); // Kasih timeout biar gak nungguin selamanya
    } catch (e) {
      // Kalau offline, errornya biasanya SocketException atau Timeout
      throw _handleAuthError(e);
    }
  }

  // Daftar akun baru
  Future<void> signUp(String email, String password, String name) async {
    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': name},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Logout
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // Pas offline logout kadang gagal di server, tapi di lokal harus tetep bersih
      print("Logout lokal dibersihkan: $e");
    }
  }

  // Cek apakah user lagi login (Ini ambil dari LocalStorage otomatis)
  User? get currentUser => _supabase.auth.currentUser;

  // Helper buat nerjemahin error biar user gak bingung liat kode dewa
  String _handleAuthError(dynamic e) {
    if (e.toString().contains('SocketException') || e.toString().contains('host lookup')) {
      return "Gak ada koneksi internet, Bro. Cek sinyal lu!";
    }
    if (e.toString().contains('Invalid login credentials')) {
      return "Email atau password lu salah, coba cek lagi.";
    }
    return "Ada masalah: $e";
  }
}
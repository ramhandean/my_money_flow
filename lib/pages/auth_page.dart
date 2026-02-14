import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

// ... import tetap sama ...

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLoginMode = true;
  bool _obscureText = true; // Tambahan buat toggle password

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email dan password gak boleh kosong, Bro!"))
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await Supabase.instance.client.auth.signInWithPassword(
            email: email, password: password);
      } else {
        String autoUsername = email.split('@')[0];
        await Supabase.instance.client.auth.signUp(
            email: email,
            password: password,
            data: {
              'display_name': autoUsername,
              'photo_url': null,
            }
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cek email buat konfirmasi ya! (Kalau aktif)"))
          );
        }
      }

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } on AuthException catch (e) {
      // Error khusus Supabase
      String message = "Ada masalah nih: ${e.message}";
      if (e.message.contains("Invalid login credentials")) message = "Email atau password salah, coba cek lagi.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Waduh: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gunakan onPrimary atau putih biar teks tombol kelihatan jelas
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ikon yang menyesuaikan mode
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    _isLoginMode ? Icons.lock_open_rounded : Icons.person_add_alt_1_rounded,
                    size: 64,
                    color: primaryColor
                ),
              ),
              const SizedBox(height: 24),
              Text(
                  _isLoginMode ? "Halo Lagi!" : "Mulai Kelola Cuan",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 8),
              Text(
                _isLoginMode ? "Masuk buat lanjut catat transaksi." : "Daftar dulu biar datanya aman di cloud.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),
              TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                  )
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: _passwordController,
                  obscureText: _obscureText,
                  decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureText = !_obscureText),
                      )
                  )
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white, // Ganti ke putih biar pro
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isLoginMode ? "MASUK" : "DAFTAR SEKARANG", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => setState(() {
                    _isLoginMode = !_isLoginMode;
                    _emailController.clear();
                    _passwordController.clear();
                  }),
                  child: Text(_isLoginMode ? "Belum punya akun? Daftar" : "Udah punya akun? Masuk")
              ),
            ],
          ),
        ),
      ),
    );
  }
}
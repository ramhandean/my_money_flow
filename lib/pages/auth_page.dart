import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLoginMode = true;

  Future<void> _handleAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await Supabase.instance.client.auth.signInWithPassword(
            email: _emailController.text, password: _passwordController.text);
      } else {
        // LOGIKA BARU: Ambil username awal dari email
        // Contoh: dean@gmail.com jadi 'dean'
        String autoUsername = _emailController.text.split('@')[0];

        await Supabase.instance.client.auth.signUp(
            email: _emailController.text,
            password: _passwordController.text,
            // Simpan ke metadata user
            data: {
              'display_name': autoUsername,
              'photo_url': null, // Default kosong
            }
        );
      }

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(_isLoginMode ? Icons.lock_person_rounded : Icons.person_add_rounded, size: 64, color: primaryColor),
              const SizedBox(height: 24),
              Text(_isLoginMode ? "Selamat Datang" : "Buat Akun", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TextField(controller: _emailController, decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.email))),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock))),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAuth,
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.black),
                  child: _isLoading ? const CircularProgressIndicator() : Text(_isLoginMode ? "LOGIN" : "DAFTAR"),
                ),
              ),
              TextButton(onPressed: () => setState(() => _isLoginMode = !_isLoginMode), child: Text(_isLoginMode ? "Daftar" : "Login")),
            ],
          ),
        ),
      ),
    );
  }
}
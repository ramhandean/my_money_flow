import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debt_service.dart';

class AddDebtPage extends StatefulWidget {
  const AddDebtPage({super.key});

  @override
  State<AddDebtPage> createState() => _AddDebtPageState();
}

class _AddDebtPageState extends State<AddDebtPage> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isDebt = true; // True = Hutang, False = Piutang
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveDebt() async {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Isi dulu semua datanya, Bro!")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await DebtService().addDebt(
        personName: _nameController.text,
        amount: double.parse(_amountController.text),
        isDebt: _isDebt,
        walletId: null, // Bisa dikembangkan kalau mau pilih wallet
      );

      if (mounted) {
        Navigator.pop(context, true); // Balikin true biar Dashboard tau harus refresh
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal simpan: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Warna tema menyesuaikan tipe (Hutang = Merah, Piutang = Biru/Teal)
    final Color themeColor = _isDebt ? Colors.redAccent : const Color(0xFF4DB6AC);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDebt ? "Tambah Hutang" : "Tambah Piutang"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOGGLE TYPE ---
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildTypeTab("HUTANG SAYA", true, Colors.redAccent),
                  _buildTypeTab("PIUTANG", false, const Color(0xFF4DB6AC)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- INPUT NAMA ---
            const Text("Nama Orang / Instansi", style: TextStyle(color: Colors.grey, fontSize: 13)),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "Siapa nih?",
                prefixIcon: Icon(Icons.person_pin_rounded, color: themeColor),
                border: UnderlineInputBorder(borderSide: BorderSide(color: themeColor.withOpacity(0.2))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: themeColor, width: 2)),
              ),
            ),
            const SizedBox(height: 32),

            // --- INPUT NOMINAL ---
            const Text("Nominal Pinjaman", style: TextStyle(color: Colors.grey, fontSize: 13)),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeColor),
              decoration: InputDecoration(
                prefixText: "Rp ",
                prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeColor),
                hintText: "0",
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: themeColor, width: 2)),
              ),
            ),
            const SizedBox(height: 48),

            // --- BUTTON SIMPAN ---
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _saveDebt,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  _isDebt ? "CATAT SEBAGAI HUTANG" : "CATAT SEBAGAI PIUTANG",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTab(String label, bool value, Color activeColor) {
    bool isSelected = _isDebt == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _isDebt = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
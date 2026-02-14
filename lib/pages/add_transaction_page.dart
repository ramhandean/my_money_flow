import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/transaction_service.dart';
import '../services/wallet_service.dart';
import '../models/wallet_model.dart';

class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _transactionService = TransactionService();
  final _walletService = WalletService();

  String? _selectedWalletId;
  String _selectedCategory = 'Lainnya';
  bool _isSaving = false;
  bool _isExpense = true; // True = Pengeluaran, False = Pemasukan

  final List<String> _expenseCategories = [
    'Makan', 'Transport', 'Laundry', 'Jajan', 'Hiburan', 'Bensin', 'Tol', 'Lainnya'
  ];

  final List<String> _incomeCategories = [
    'Gaji', 'Transfer', 'Bonus', 'Bonus Project', 'Lainnya'
  ];

  Future<void> _handleSave() async {
    if (_selectedWalletId == null || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nominal & Kantong wajib diisi, Bro!"), backgroundColor: Colors.orange),
      );
      return;
    }

    continue_saving:
    setState(() => _isSaving = true);

    try {
      final double amount = double.tryParse(_amountController.text) ?? 0;

      // --- CEK SALDO CUKUP UNTUK PENGELUARAN ---
      if (_isExpense) {
        final wallets = await _walletService.getWallets();
        final selectedWallet = wallets.firstWhere((w) => w.id == _selectedWalletId);
        final pendingAmount = await _transactionService.getPendingAmountByWallet();
        final finalBalance = selectedWallet.balance + (pendingAmount[selectedWallet.id] ?? 0.0);

        if (finalBalance < amount) {
          setState(() => _isSaving = false);
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                title: const Row(
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text("Saldo Tidak Cukup!"),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Saldo kantong \"${selectedWallet.name}\" hanya ${_formatCurrency(finalBalance)}, tapi lu mau keluar ${_formatCurrency(amount)}.",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Gaada minus bro! Topup dulu kantong kamu.",
                              style: TextStyle(color: Colors.redAccent.withOpacity(0.9), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("OKE", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      // --- PERBAIKAN DI SINI ---
      await _transactionService.addTransaction(
        walletId: _selectedWalletId!,
        // Kalau Pengeluaran, kasih MINUS. Kalau Pemasukan, biarkan POSITIF.
        amount: _isExpense ? -amount : amount,
        description: _descController.text.trim().isEmpty ? "Tanpa Deskripsi" : _descController.text.trim(),
        category: _selectedCategory,
      );
      // -------------------------

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("${_isExpense ? 'Pengeluaran' : 'Pemasukan'} berhasil dicatat!"),
              backgroundColor: _isExpense ? Colors.redAccent : const Color(0xFF4DB6AC)
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal simpan: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(1)}jt';
    } else if (value >= 1000) {
      return 'Rp ${(value / 1000).toStringAsFixed(0)}rb';
    } else {
      return 'Rp ${value.toStringAsFixed(0)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = _isExpense ? Colors.redAccent : const Color(0xFF4DB6AC);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isExpense ? "Catat Pengeluaran" : "Catat Pemasukan"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOGGLE PEMASUKAN / PENGELUARAN ---
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildTypeTab("PENGELUARAN", true, Colors.redAccent),
                  _buildTypeTab("PEMASUKAN", false, const Color(0xFF4DB6AC)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- INPUT NOMINAL ---
            Text("Nominal ${_isExpense ? 'Pengeluaran' : 'Pemasukan'}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: activeColor),
              decoration: InputDecoration(
                hintText: "0",
                border: InputBorder.none,
                prefixText: "Rp ",
                prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: activeColor),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            Divider(thickness: 1, color: activeColor.withOpacity(0.2)),
            const SizedBox(height: 32),

            // --- PILIH KANTONG ---
            const Text("Ke / Dari Kantong Mana?", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            FutureBuilder<List<Wallet>>(
              future: _walletService.getWallets(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return LinearProgressIndicator(color: activeColor);
                }
                final wallets = snapshot.data ?? [];
                if (_selectedWalletId == null && wallets.length == 1) {
                  _selectedWalletId = wallets[0].id;
                }

                return DropdownButtonFormField<String>(
                  value: _selectedWalletId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: activeColor),
                  ),
                  hint: const Text("Pilih Kantong"),
                  items: wallets.map((w) => DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold))
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedWalletId = val),
                );
              },
            ),
            const SizedBox(height: 32),

            // --- DESKRIPSI ---
            const Text("Keterangan", style: TextStyle(color: Colors.grey, fontSize: 13)),
            TextField(
              controller: _descController,
              onChanged: _autoSuggestCategory,
              style: const TextStyle(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: _isExpense ? "Contoh: Bensin Pertamax" : "Contoh: Gaji Bulan Februari",
                prefixIcon: Icon(Icons.edit_note, color: activeColor),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: activeColor, width: 2)),
              ),
            ),
            const SizedBox(height: 32),

            // --- KATEGORI ---
            const Text("Kategori", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_isExpense ? _expenseCategories : _incomeCategories).map((cat) {
                final bool isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: activeColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isSelected ? activeColor : Colors.grey.shade300),
                  onSelected: (selected) {
                    if (selected) {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedCategory = cat);
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 48),

            // --- TOMBOL SIMPAN ---
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: activeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text("SIMPAN ${_isExpense ? 'PENGELUARAN' : 'PEMASUKAN'}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTab(String label, bool value, Color color) {
    final bool isSelected = _isExpense == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _isExpense = value;
            _selectedCategory = 'Lainnya'; // Reset kategori pas ganti tipe
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
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

  void _autoSuggestCategory(String query) {
    if (query.isEmpty) return;

    if (_isExpense) {
      final Map<String, List<String>> keywordMap = {
        'Makan': ['makan', 'nasi', 'bakso', 'mie', 'kopi', 'haus', 'warung'],
        'Transport': ['gojek', 'grab', 'bus', 'tiket'],
        'Bensin': ['bensin', 'pertamax', 'pertalite', 'spbu'],
        'Tol': ['tol', 'e-toll'],
        'Laundry': ['laundry', 'cuci'],
      };
      for (var entry in keywordMap.entries) {
        if (entry.value.any((keyword) => query.toLowerCase().contains(keyword))) {
          setState(() => _selectedCategory = entry.key);
          break;
        }
      }
    } else {
      // Suggestion buat Pemasukan
      if (query.toLowerCase().contains('gaji')) setState(() => _selectedCategory = 'Gaji');
      else if (query.toLowerCase().contains('transfer')) setState(() => _selectedCategory = 'Transfer');
      else if (query.toLowerCase().contains('bonus')) setState(() => _selectedCategory = 'Bonus');
    }
  }
}
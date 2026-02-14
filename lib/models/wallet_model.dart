class Wallet {
  final String id;
  final String name;
  final double balance;
  final String type; // cash atau cashless

  Wallet({
    required this.id,
    required this.name,
    required this.balance,
    required this.type,
  });

  // --- 1. CLONE OBJECT (Biar bisa update balance lokal tanpa nunggu sync) ---
  Wallet copyWith({
    String? id,
    String? name,
    double? balance,
    String? type,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      type: type ?? this.type,
    );
  }

  // --- 2. FROM MAP (Buat baca dari Supabase atau Cache Lokal) ---
  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      // Pastiin handle null dan tipe data double dengan aman
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Tanpa Nama',
      balance: (map['balance'] ?? 0).toDouble(),
      type: map['type']?.toString() ?? 'cash',
    );
  }

  // --- 3. TO MAP (Buat simpan ke Supabase atau Cache Lokal) ---
  Map<String, dynamic> toMap() {
    return {
      'id': id, // ID biasanya dibutuhin buat upsert/sync
      'name': name,
      'balance': balance,
      'type': type,
    };
  }
}
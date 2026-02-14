class Transaction {
  final String? id;
  final String walletId;
  final double amount;
  final String description;
  final String category;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.walletId,
    required this.amount,
    required this.description,
    required this.category,
    required this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      walletId: map['wallet_id'],
      amount: (map['amount'] ?? 0).toDouble(),
      description: map['description'] ?? '',
      category: map['category'] ?? 'Lainnya',
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
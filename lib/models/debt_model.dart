class Debt {
  final String id;
  final String personName;
  final double amount;
  final double remainingAmount;
  final bool isDebt; // true = Hutang kita, false = Piutang (duit di orang)
  final DateTime? dueDate;
  final bool isSettled;

  Debt({
    required this.id,
    required this.personName,
    required this.amount,
    required this.remainingAmount,
    required this.isDebt,
    this.dueDate,
    required this.isSettled,
  });

  factory Debt.fromMap(Map<String, dynamic> map) {
    return Debt(
      id: map['id'],
      personName: map['person_name'],
      amount: (map['amount'] ?? 0).toDouble(),
      remainingAmount: (map['remaining_amount'] ?? 0).toDouble(),
      isDebt: map['is_debt'],
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      isSettled: map['is_settled'],
    );
  }
}
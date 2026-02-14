import 'package:intl/intl.dart';

class CurrencyFormat {
  static String convertToIdr(dynamic number, int decimalDigit) {
    num value = number is num ? number : (num.tryParse(number.toString()) ?? 0);

    // PENTING: Jangan pakai .abs() di sini! Kita perlu preserve sign.
    // Track apakah nilai negatif
    bool isNegative = value < 0;
    num absValue = value.abs();

    NumberFormat currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: decimalDigit,
    );
    
    String formatted = currencyFormatter.format(absValue);
    
    // Tambahkan tanda minus di depan kalau negatif
    return isNegative ? '-$formatted' : formatted;
  }
}
import '../transaction_draft.dart';
import 'parse_span.dart';

final class TypeDetection {
  const TypeDetection(this.type, this.matched);
  final TransactionType type;
  final bool matched;
}

final class TypeDetector {
  const TypeDetector();
  static const incomeKeywords = [
    'gaji',
    'gajian',
    'bonus',
    'thr',
    'terima',
    'dapat',
    'masuk',
    'refund',
    'cashback',
  ];
  static const transferKeywords = [
    'transfer',
    'pindah',
    'tarik tunai',
    'setor',
  ];
  static const expenseKeywords = [
    'beli',
    'bayar',
    'makan',
    'jajan',
    'isi',
    'langganan',
  ];
  bool isTransfer(String text) =>
      transferKeywords.any((k) => containsPhrase(text, k));

  TypeDetection detect(String text, {bool hasOtherAccount = false}) {
    if (isTransfer(text) ||
        (containsPhrase(text, 'top up') && hasOtherAccount)) {
      return const TypeDetection(TransactionType.transfer, true);
    }
    if (incomeKeywords.any((k) => containsPhrase(text, k))) {
      return const TypeDetection(TransactionType.income, true);
    }
    if (expenseKeywords.any((k) => containsPhrase(text, k))) {
      return const TypeDetection(TransactionType.expense, true);
    }
    return const TypeDetection(TransactionType.expense, false);
  }
}

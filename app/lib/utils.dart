import 'models.dart';

String formatMoney(double amount, [String currency = '¥']) {
  return '$currency${amount.toStringAsFixed(2)}';
}

String txnDisplay(Txn t, [String currency = '¥']) =>
    '${t.type.isExpense ? '-' : '+'}${formatMoney(t.amount, currency)}';

Account? findAccount(List<Account> list, String id) {
  for (final a in list) {
    if (a.id == id) return a;
  }
  return null;
}

Category? findCategory(List<Category> list, String id) {
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
}

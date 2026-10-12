import 'models.dart';

String formatMoney(double amount, [String currency = '¥']) {
  return '$currency${amount.toStringAsFixed(2)}';
}

/// 金额短格式:先固定两位小数**消除浮点噪声**(杜绝 120.4500000000001),
/// 再去掉多余的 0 —— 例:120.45 / 120.5 / 120
String shortMoney(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
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

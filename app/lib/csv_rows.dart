import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// 生成账单 CSV 的数据行（仅数据,不含汇总行,便于在 Excel 里直接做二次统计）。
List<List<dynamic>> buildTxnRows(AppData data, List<Txn> txns) {
  final rows = <List<dynamic>>[
    ['日期', '类型', '分类', '账户', '金额', '备注'],
  ];
  final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
  for (final t in sorted) {
    final cat = findCategory(data.categories, t.categoryId);
    final acc = findAccount(data.accounts, t.accountId);
    rows.add([
      dateOnly(t.date),
      t.type.label,
      cat?.name ?? '',
      acc?.name ?? '',
      t.amount.toStringAsFixed(2),
      t.note ?? '',
    ]);
  }
  return rows;
}

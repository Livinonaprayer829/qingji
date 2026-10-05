import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// 汇总结果：收入 / 支出 / 笔数
typedef TxnSummary = ({double income, double expense, int count});

TxnSummary summarizeTxns(List<Txn> txns) {
  double inc = 0, exp = 0;
  for (final t in txns) {
    if (t.type.isExpense) {
      exp += t.amount;
    } else {
      inc += t.amount;
    }
  }
  return (income: inc, expense: exp, count: txns.length);
}

/// 生成账单 CSV 的数据行。
/// [withSummary] 为 true 时，末尾追加一段汇总（收入 / 支出 / 结余 / 笔数），
/// 用一整行空列与数据分隔，方便在 Excel 里识别或删除。
List<List<dynamic>> buildTxnRows(AppData data, List<Txn> txns,
    {bool withSummary = true}) {
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

  if (withSummary) {
    final s = summarizeTxns(sorted);
    rows.add(['', '', '', '', '', '']); // 分隔行
    rows.add(['合计', '', '', '', '', '']);
    rows.add(['收入合计', '', '', '', s.income.toStringAsFixed(2), '']);
    rows.add(['支出合计', '', '', '', s.expense.toStringAsFixed(2), '']);
    rows.add(['结余', '', '', '', (s.income - s.expense).toStringAsFixed(2), '']);
    rows.add(['笔数', '', '', '', '${s.count}', '']);
  }
  return rows;
}

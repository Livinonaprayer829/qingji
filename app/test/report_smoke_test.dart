import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daka/models.dart';
import 'package:daka/report_html.dart';
import 'package:daka/repository.dart';

/// 冒烟测试：验证账单报告 HTML 能正常生成（含汇总与饼图 SVG），
/// 并把样例输出到 tool/report-sample.html 供人工查看。
void main() {
  test('buildReportHtml 生成汇总与饼图', () {
    final cats = [
      Category(id: 'c1', name: '餐饮', icon: '🍜', type: TxType.expense),
      Category(id: 'c2', name: '交通', icon: '🚌', type: TxType.expense),
      Category(id: 'c3', name: '购物', icon: '🛍', type: TxType.expense),
      Category(id: 'c4', name: '工资', icon: '💰', type: TxType.income),
    ];
    final acc = Account(id: 'a1', name: '微信');
    final txns = [
      Txn(
          amount: 35.5,
          type: TxType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          date: DateTime(2026, 9, 28),
          note: '晚餐'),
      Txn(
          amount: 128,
          type: TxType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          date: DateTime(2026, 9, 29),
          note: '聚餐'),
      Txn(
          amount: 12,
          type: TxType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          date: DateTime(2026, 9, 29)),
      Txn(
          amount: 260,
          type: TxType.expense,
          categoryId: 'c3',
          accountId: 'a1',
          date: DateTime(2026, 9, 30),
          note: '衣服'),
      Txn(
          amount: 8000,
          type: TxType.income,
          categoryId: 'c4',
          accountId: 'a1',
          date: DateTime(2026, 9, 30),
          note: '9月工资'),
    ];
    final data = AppData(
        accounts: [acc], categories: cats, transactions: txns, loans: []);

    final html = buildReportHtml(
        data: data, txns: txns, rangeText: '9.28～9.30', selectedDays: 3);

    expect(html.contains('<svg'), true, reason: '应包含饼图 SVG');
    expect(html.contains('</svg>'), true);
    expect(html.contains('结余'), true);
    expect(html.contains('餐饮'), true);
    // 收入 8000,支出 435.5 → 结余 7564.50
    expect(html.contains('7564.50'), true, reason: '结余应为 8000 - 435.5 = 7564.50');
    expect(html.contains('435.50'), true, reason: '支出合计应为 435.50');

    File(r'D:\Agent project\daka\app\tool\report-sample.html')
        .writeAsStringSync(html);
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// Web 端 CSV 导出:用 universal_html 生成 Blob 并触发浏览器下载。
Future<void> exportCsv(BuildContext context, AppData data) async {
  final rows = [
    ['日期', '类型', '分类', '账户', '金额', '备注']
  ];
  final sorted = [...data.transactions]..sort((a, b) => a.date.compareTo(b.date));
  for (final t in sorted) {
    final cat = findCategory(data.categories, t.categoryId);
    final acc = findAccount(data.accounts, t.accountId);
    rows.add([
      '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}',
      t.type.label,
      cat?.name ?? '',
      acc?.name ?? '',
      t.amount.toStringAsFixed(2),
      t.note ?? '',
    ]);
  }
  final csv = const ListToCsvConverter().convert(rows);
  final bytes = utf8.encode(csv);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.document.createElement('a') as html.AnchorElement)
    ..href = url
    ..download = 'qingji_${DateTime.now().millisecondsSinceEpoch}.csv'
    ..click();
  html.Url.revokeObjectUrl(url);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已导出 CSV')));
  }
}

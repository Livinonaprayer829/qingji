import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import 'models.dart';
import 'repository.dart';
import 'csv_rows.dart';

/// Web 端 CSV 导出:用 universal_html 生成 Blob 并触发浏览器下载。
///
/// [txns] 为本次要导出的记录(由导出页按所选日期筛好)。
/// [fileStem] 文件名前缀(不含 .csv)。
Future<void> exportCsv(BuildContext context, AppData data, List<Txn> txns,
    {String? fileStem}) async {
  final rows = buildTxnRows(data, txns);
  final csv = const ListToCsvConverter().convert(rows);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  final bytes = utf8.encode(csv);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.document.createElement('a') as html.AnchorElement)
    ..href = url
    ..download = '$stem.csv'
    ..click();
  html.Url.revokeObjectUrl(url);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${txns.length} 笔账单')));
  }
}

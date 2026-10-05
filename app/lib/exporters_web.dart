import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;

import 'csv_rows.dart';
import 'models.dart';
import 'report_html.dart';
import 'repository.dart';

/// Web 端:生成 Blob 触发浏览器下载。
/// [bom] 为 true 时在开头写入 UTF-8 BOM,避免 Excel/WPS 打开中文 CSV 乱码。
void _download(String content, String fileName, String mime,
    {bool bom = false}) {
  final bytes = utf8.encode(bom ? '\uFEFF$content' : content);
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  (html.document.createElement('a') as html.AnchorElement)
    ..href = url
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// 导出 CSV(纯数据表 + 末尾汇总),便于在 Excel 里二次统计。
Future<void> exportCsv(BuildContext context, AppData data, List<Txn> txns,
    {String? fileStem}) async {
  final rows = buildTxnRows(data, txns);
  final csv = const ListToCsvConverter().convert(rows);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  _download(csv, '$stem.csv', 'text/csv;charset=utf-8', bom: true);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${txns.length} 笔账单 · CSV')));
  }
}

/// 导出 HTML 账单报告(汇总 + 支出饼图 + 明细),浏览器打开即可,可另存为 PDF。
Future<void> exportHtmlReport(BuildContext context, AppData data,
    List<Txn> txns,
    {required String rangeText, required int selectedDays, String? fileStem}) async {
  final htmlStr = buildReportHtml(
      data: data, txns: txns, rangeText: rangeText, selectedDays: selectedDays);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  _download(htmlStr, '$stem.html', 'text/html;charset=utf-8');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已导出账单报告 · HTML（含饼图）')));
  }
}

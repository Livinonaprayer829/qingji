import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'csv_rows.dart';
import 'models.dart';
import 'report_html.dart';
import 'repository.dart';

/// 移动端(安卓/iOS):写临时文件 → 调起系统分享面板选择保存位置/发送。
/// [bom] 为 true 时在开头写入 UTF-8 BOM,避免 Excel/WPS 打开中文 CSV 乱码。
Future<void> _saveAndShare(String content, String fileName, String shareText,
    {bool bom = false}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(bom ? '\uFEFF$content' : content, encoding: utf8);
  await Share.shareXFiles([XFile(file.path)], text: shareText);
}

/// 导出 CSV(纯数据表 + 末尾汇总),便于在 Excel 里二次统计。
Future<void> exportCsv(BuildContext context, AppData data, List<Txn> txns,
    {String? fileStem}) async {
  final rows = buildTxnRows(data, txns);
  final csv = const ListToCsvConverter().convert(rows);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  await _saveAndShare(csv, '$stem.csv', '青记账单导出', bom: true);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${txns.length} 笔账单 · CSV')));
  }
}

/// 导出 HTML 账单报告(汇总 + 支出饼图 + 明细),浏览器打开即可,可另存为 PDF。
Future<void> exportHtmlReport(BuildContext context, AppData data,
    List<Txn> txns,
    {required String rangeText, required int selectedDays, String? fileStem}) async {
  final html = buildReportHtml(
      data: data, txns: txns, rangeText: rangeText, selectedDays: selectedDays);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  await _saveAndShare(html, '$stem.html', '青记账单报告');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已导出账单报告 · HTML（含饼图）')));
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'repository.dart';
import 'csv_rows.dart';

/// 移动端(安卓/iOS)CSV 导出:写入临时文件,再用系统分享面板让用户
/// 选择保存位置(文件管理/微信/邮件等)。不依赖任何外部存储权限。
///
/// [txns] 为本次要导出的记录(由导出页按所选日期筛好)。
/// [fileStem] 文件名前缀(不含 .csv)。
Future<void> exportCsv(BuildContext context, AppData data, List<Txn> txns,
    {String? fileStem}) async {
  final rows = buildTxnRows(data, txns);
  final csv = const ListToCsvConverter().convert(rows);
  final stem = fileStem ?? 'qingji_${DateTime.now().millisecondsSinceEpoch}';
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$stem.csv');
  await file.writeAsString(csv, encoding: utf8);
  await Share.shareXFiles([XFile(file.path)], text: '青记账单导出');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${txns.length} 笔账单')));
  }
}

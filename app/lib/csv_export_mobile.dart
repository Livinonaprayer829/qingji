import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// 移动端(安卓/iOS)CSV 导出:写入临时文件,再用系统分享面板让用户
/// 选择保存位置(文件管理/微信/邮件等)。不依赖任何外部存储权限。
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
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/qingji_${DateTime.now().millisecondsSinceEpoch}.csv');
  await file.writeAsString(csv, encoding: utf8);
  await Share.shareXFiles([XFile(file.path)], text: '青记账单导出');
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已导出 CSV')));
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import '../models.dart';
import '../providers.dart';
import '../repository.dart';
import '../utils.dart';
import 'sync_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('账户', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: data.accounts
                .map((a) => ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: Text(a.name),
                      subtitle: Text(a.currency),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('分类', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.categories
                  .map((c) => Chip(
                        avatar: Text(c.icon),
                        label: Text(c.name),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('数据',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('数据同步'),
            subtitle: const Text('登录、离线模式、多设备云端同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SyncScreen()),
                ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _exportCsv(context, data),
          icon: const Icon(Icons.download),
          label: const Text('导出 CSV'),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Daka 记账 · 简约清爽',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  void _exportCsv(BuildContext context, AppData data) {
    final rows = [
      ['日期', '类型', '分类', '账户', '金额', '备注']
    ];
    final sorted = [...data.transactions]
      ..sort((a, b) => a.date.compareTo(b.date));
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
      ..download = 'daka_${DateTime.now().millisecondsSinceEpoch}.csv'
      ..click();
    html.Url.revokeObjectUrl(url);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已导出 CSV')));
  }
}

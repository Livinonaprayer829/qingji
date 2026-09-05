import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'sync_screen.dart';
import '../csv_export.dart';
import '../widgets/update_check_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('账户',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
        const Text('分类',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
        const Text('关于',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        const UpdateCheckTile(),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => exportCsv(context, data),
          icon: const Icon(Icons.download),
          label: const Text('导出 CSV'),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('青记 · 简约清爽',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }
}

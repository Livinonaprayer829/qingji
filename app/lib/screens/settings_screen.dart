import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../utils.dart';
import 'account_detail_screen.dart';
import 'sync_screen.dart';
import 'export_screen.dart';
import '../widgets/update_check_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('我的账户',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < data.accounts.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _AccountTile(account: data.accounts[i]),
              ],
            ],
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
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExportScreen()),
          ),
          icon: const Icon(Icons.download),
          label: const Text('导出账单'),
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

/// 账户列表项：显示结余、默认标识，点击进入账户详情页
class _AccountTile extends ConsumerWidget {
  final Account account;
  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final isDefault = ref.watch(defaultAccountProvider) == account.id;

    double inc = 0, exp = 0;
    for (final t in data.transactions) {
      if (t.accountId != account.id) continue;
      if (t.type.isExpense) {
        exp += t.amount;
      } else {
        inc += t.amount;
      }
    }
    final balance = inc - exp;
    final primary = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: Row(
        children: [
          Flexible(
            child: Text(account.name, overflow: TextOverflow.ellipsis),
          ),
          if (isDefault) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('默认',
                  style: TextStyle(fontSize: 11, color: primary)),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '结余 ${formatMoney(balance, account.currency)}',
        style: TextStyle(
            color: balance >= 0 ? Colors.grey.shade700 : Colors.redAccent,
            fontSize: 12.5),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: account.id)),
      ),
    );
  }
}

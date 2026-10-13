import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../utils.dart';
import '../widgets/swipe_delete.dart';
import '../widgets/txn_tile.dart';
import '../widgets/transaction_form.dart';

/// 账户详情页：
/// - 只展示该账户的收支流水（可左滑删除、点按编辑）
/// - 结余 = 收入 − 支出
/// - 可把该账户设为全局默认记账账户
class AccountDetailScreen extends ConsumerWidget {
  final String accountId;
  const AccountDetailScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    Account? account;
    for (final a in data.accounts) {
      if (a.id == accountId) {
        account = a;
        break;
      }
    }

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('账户详情')),
        body: const Center(child: Text('该账户已不存在')),
      );
    }

    final txns = data.transactions
        .where((t) => t.accountId == account!.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    double inc = 0, exp = 0;
    for (final t in txns) {
      if (t.type.isExpense) {
        exp += t.amount;
      } else {
        inc += t.amount;
      }
    }
    final balance = inc - exp;
    final isDefault = ref.watch(defaultAccountProvider) == account.id;

    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 结余 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('结余',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Text(
                    formatMoney(balance, account.currency),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: balance >= 0
                          ? const Color(0xFF0E9E8E)
                          : const Color(0xFFD9534F),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _miniStat('收入', formatMoney(inc, account.currency),
                          Colors.green.shade600),
                      const SizedBox(width: 24),
                      _miniStat('支出', formatMoney(exp, account.currency),
                          Colors.redAccent),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- 设为默认 ----
          isDefault
              ? OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(defaultAccountProvider.notifier)
                        .setAccount(null);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已取消默认账户')));
                    }
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('默认账户（点按取消）'),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(defaultAccountProvider.notifier)
                        .setAccount(account!.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('已把「${account!.name}」设为默认记账账户')));
                    }
                  },
                  icon: const Icon(Icons.star_border),
                  label: const Text('设为默认账户'),
                ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              isDefault ? '记一笔时会自动选中该账户' : '设为默认后,记一笔时会自动选中它',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 20),

          // ---- 流水 ----
          Row(
            children: [
              const Text('收支流水',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('共 ${txns.length} 笔',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          if (txns.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text('该账户还没有记录',
                      style: TextStyle(color: Colors.grey.shade600)),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < txns.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    SwipeDelete(
                      key: ValueKey('acc_${txns[i].id}'),
                      message: '删除这笔记录？',
                      onDelete: () => ref
                          .read(appDataProvider.notifier)
                          .deleteTx(txns[i].id),
                      child: TxnTile(
                        txn: txns[i],
                        onTap: () => showTxnForm(context, editing: txns[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: Text('左滑删除 · 点按编辑',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

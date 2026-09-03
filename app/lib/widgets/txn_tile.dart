import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../utils.dart';

class TxnTile extends ConsumerWidget {
  final Txn txn;
  final VoidCallback? onTap;
  const TxnTile({super.key, required this.txn, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final cat = findCategory(data.categories, txn.categoryId);
    final acc = findAccount(data.accounts, txn.accountId);
    final color = txn.type.isExpense ? Colors.redAccent : Colors.green.shade600;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Text(cat?.icon ?? '💸', style: const TextStyle(fontSize: 20)),
      ),
      title: Text(cat?.name ?? '未知', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([acc?.name, txn.note].whereType<String>().join(' · ')),
      trailing: Text(txnDisplay(txn, acc?.currency ?? '¥'),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      onTap: onTap,
    );
  }
}

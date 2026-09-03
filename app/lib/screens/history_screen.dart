import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models.dart';
import '../widgets/txn_tile.dart';
import '../widgets/transaction_form.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final sorted = [...data.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final Map<String, List<Txn>> groups = {};
    for (final t in sorted) {
      final key =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(t);
    }
    final keys = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      itemBuilder: (ctx, i) {
        final key = keys[i];
        final list = groups[key]!;
        double dayExp = 0, dayInc = 0;
        for (final t in list) {
          if (t.type.isExpense) {
            dayExp += t.amount;
          } else {
            dayInc += t.amount;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('支 ¥${dayExp.toStringAsFixed(2)}   收 ¥${dayInc.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Card(
              child: Column(
                children: list
                    .map((t) => Dismissible(
                          key: Key(t.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('删除这笔记录？'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(c).pop(false),
                                      child: const Text('取消')),
                                  TextButton(
                                      onPressed: () => Navigator.of(c).pop(true),
                                      child: const Text('删除')),
                                ],
                              ),
                            );
                          },
                          onDismissed: (_) =>
                              ref.read(appDataProvider.notifier).deleteTx(t.id),
                          child: TxnTile(
                            txn: t,
                            onTap: () => showTxnForm(context, editing: t),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

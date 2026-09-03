import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/txn_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final now = DateTime.now();
    final monthTxns = data.transactions
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .toList();
    double income = 0, expense = 0;
    for (final t in monthTxns) {
      if (t.type.isExpense) {
        expense += t.amount;
      } else {
        income += t.amount;
      }
    }
    final recent = [...data.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(8).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本月结余',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('¥${(income - expense).toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MiniStat(label: '收入', value: income),
                    _MiniStat(label: '支出', value: expense),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('最近记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (recentTop.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('还没有记录，点右下角 + 记一笔吧',
                      style: TextStyle(color: Colors.grey))))
        else
          Card(
            child: Column(
              children: recentTop
                  .map((t) => Column(
                        children: [
                          TxnTile(txn: t),
                          if (t != recentTop.last)
                            const Divider(height: 1, indent: 72),
                        ],
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text('¥${value.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

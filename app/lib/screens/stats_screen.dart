import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models.dart';
import '../providers.dart';
import '../utils.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final now = DateTime.now();
    final monthTxns = data.transactions
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .toList();

    double totalExp = 0, totalInc = 0;
    final Map<String, double> byCat = {};
    for (final t in monthTxns) {
      if (t.type.isExpense) {
        totalExp += t.amount;
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      } else {
        totalInc += t.amount;
      }
    }

    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.pink
    ];
    final catKeys = byCat.keys.toList();
    final sections = catKeys.asMap().entries.map((e) {
      final key = e.value;
      final v = byCat[key]!;
      final pct = totalExp > 0 ? (v / totalExp * 100) : 0;
      return PieChartSectionData(
        value: v,
        title: '${pct.toStringAsFixed(0)}%',
        color: colors[e.key % colors.length],
        radius: 70,
        titleStyle: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      );
    }).toList();

    final days = List.generate(
        7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));
    final barGroups = days.asMap().entries.map((e) {
      final day = e.key;
      final d = e.value;
      double sum = 0;
      for (final t in monthTxns) {
        if (t.type.isExpense &&
            t.date.year == d.year &&
            t.date.month == d.month &&
            t.date.day == d.day) {
          sum += t.amount;
        }
      }
      return BarChartGroupData(
        x: day,
        barRods: [
          BarChartRodData(
            toY: sum,
            width: 14,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本月支出',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('¥${totalExp.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本月收入',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('¥${totalInc.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('支出分类占比',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: sections.isEmpty
              ? const Center(child: Text('本月暂无支出记录'))
              : PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 40,
                    sectionsSpace: 2,
                  ),
                ),
        ),
        if (sections.isNotEmpty)
          const SizedBox(height: 12),
        ...catKeys.asMap().entries.map((e) {
          final cat = findCategory(data.categories, e.value);
          final v = byCat[e.value]!;
          final pct = totalExp > 0 ? (v / totalExp * 100) : 0;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: colors[e.key % colors.length].withOpacity(0.15),
              child: Text(cat?.icon ?? '💸'),
            ),
            title: Text(cat?.name ?? '未知'),
            trailing: Text('¥${v.toStringAsFixed(2)} (${pct.toStringAsFixed(0)}%)'),
          );
        }),
        const SizedBox(height: 20),
        const Text('近 7 天支出',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= days.length) {
                        return const SizedBox();
                      }
                      final d = days[idx];
                      return Text('${d.month}/${d.day}',
                          style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

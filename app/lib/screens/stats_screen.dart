import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models.dart';
import '../providers.dart';
import '../utils.dart';

enum StatsMode { week, month, year }

const _modeOrder = [StatsMode.week, StatsMode.month, StatsMode.year];
const _modeLabel = {StatsMode.week: '周', StatsMode.month: '月', StatsMode.year: '年'};
const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsMode _mode = StatsMode.month;
  // 当前展示的期间起点：周=周一，月=1号，年=1月1日
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = _startOfThis(_mode);
  }

  /// 当前「这一期」的起点（用于翻页边界与切粒度时复位）
  DateTime _startOfThis(StatsMode m) {
    final now = DateTime.now();
    if (m == StatsMode.week) {
      return DateTime(now.year, now.month, now.day - (now.weekday - 1));
    }
    if (m == StatsMode.month) return DateTime(now.year, now.month, 1);
    return DateTime(now.year, 1, 1);
  }

  /// 切换粒度：复位到「当前期」
  void _setMode(StatsMode m) {
    setState(() {
      _mode = m;
      _anchor = _startOfThis(m);
    });
  }

  /// 翻看上一期 / 下一期
  void _step(int dir) {
    final a = _anchor;
    late DateTime na;
    if (_mode == StatsMode.week) {
      na = DateTime(a.year, a.month, a.day + dir * 7);
    } else if (_mode == StatsMode.month) {
      na = DateTime(a.year, a.month + dir, 1);
    } else {
      na = DateTime(a.year + dir, 1, 1);
    }
    setState(() => _anchor = na);
  }

  /// 是否已经是最新一期（下一期会进入未来），禁止再往右翻
  bool get _canNext => _anchor.isBefore(_startOfThis(_mode));

  /// 期间区间 [start, end)
  (DateTime, DateTime) _range() {
    final s = _anchor;
    late DateTime e;
    if (_mode == StatsMode.week) {
      e = DateTime(s.year, s.month, s.day + 7);
    } else if (_mode == StatsMode.month) {
      e = DateTime(s.year, s.month + 1, 1);
    } else {
      e = DateTime(s.year + 1, 1, 1);
    }
    return (s, e);
  }

  String get _periodLabel {
    if (_mode == StatsMode.week) {
      return '${_anchor.year}年 第${_isoWeek(_anchor)}周';
    }
    if (_mode == StatsMode.month) {
      return '${_anchor.year}年${_anchor.month}月';
    }
    return '${_anchor.year}年';
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final (start, end) = _range();

    // 期间内的交易
    final periodTxns = data.transactions
        .where((t) =>
            t.date.isAfter(start.subtract(const Duration(days: 1))) &&
            t.date.isBefore(end))
        .toList();

    // 柱状图分桶
    late final List<DateTime> buckets;
    if (_mode == StatsMode.week) {
      buckets = List.generate(
          7, (i) => DateTime(_anchor.year, _anchor.month, _anchor.day + i));
    } else if (_mode == StatsMode.month) {
      final days = DateTime(_anchor.year, _anchor.month + 1, 0).day;
      buckets = List.generate(days, (i) => DateTime(_anchor.year, _anchor.month, i + 1));
    } else {
      buckets = List.generate(12, (i) => DateTime(_anchor.year, i + 1, 1));
    }

    double totalExp = 0, totalInc = 0;
    final Map<String, double> byCat = {};
    for (final t in periodTxns) {
      if (t.type.isExpense) {
        totalExp += t.amount;
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
      } else {
        totalInc += t.amount;
      }
    }

    double sumFor(DateTime b) {
      double s = 0;
      for (final t in periodTxns) {
        if (!t.type.isExpense) continue;
        if (t.date.year != b.year || t.date.month != b.month) continue;
        if (_mode == StatsMode.year) {
          s += t.amount;
        } else if (t.date.day == b.day) {
          s += t.amount;
        }
      }
      return s;
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

    final barW = _mode == StatsMode.month ? 8.0 : 16.0;
    final barGs = _mode == StatsMode.month ? 2.0 : 4.0;
    final barGroups = buckets.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: sumFor(e.value),
            width: barW,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    final barTitle = _mode == StatsMode.year
        ? '各月支出'
        : _mode == StatsMode.month
            ? '每日支出'
            : '每日支出';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 第一组：粒度切换（周 / 月 / 年）
        SegmentedButton<StatsMode>(
          segments: _modeOrder
              .map((m) => ButtonSegment<StatsMode>(
                    value: m,
                    label: Text('按${_modeLabel[m]}'),
                  ))
              .toList(),
          selected: {_mode},
          onSelectionChanged: (s) => _setMode(s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 16),
        // 第二组：期间翻页（上一期 / 下一期）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _step(-1),
              icon: const Icon(Icons.chevron_left),
              iconSize: 28,
              tooltip: '上一${_modeLabel[_mode]}',
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(_periodLabel,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: _canNext ? () => _step(1) : null,
              icon: const Icon(Icons.chevron_right),
              iconSize: 28,
              tooltip: '下一${_modeLabel[_mode]}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('支出',
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
                      const Text('收入',
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
              ? const Center(child: Text('该期间暂无支出记录'))
              : PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 40,
                    sectionsSpace: 2,
                  ),
                ),
        ),
        if (sections.isNotEmpty) const SizedBox(height: 12),
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
        Text(barTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              groupsSpace: barGs,
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
                      if (idx < 0 || idx >= buckets.length) {
                        return const SizedBox();
                      }
                      final b = buckets[idx];
                      if (_mode == StatsMode.week) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_weekdayLabels[(b.weekday - 1) % 7],
                                style: const TextStyle(fontSize: 10)),
                            Text('${b.month}/${b.day}',
                                style: const TextStyle(
                                    fontSize: 8, color: Colors.grey)),
                          ],
                        );
                      }
                      if (_mode == StatsMode.month) {
                        final d = b.day;
                        if (d % 5 == 0 || d == buckets.length) {
                          return Text('$d', style: const TextStyle(fontSize: 10));
                        }
                        return const SizedBox();
                      }
                      return Text('${b.month}月',
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

/// ISO 周序号（基于周四所在的周）
int _isoWeek(DateTime d) {
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  return 1 + (thursday.difference(firstThursday).inDays ~/ 7);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../utils.dart';
import '../widgets/bar_trend_card.dart';
import '../widgets/donut_chart.dart';

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
  // 饼图当前选中的分类(点扇区查看明细,再次点取消)
  String? _selectedCat;

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

  /// 期间的具体日期区间,如 9.28～10.4（周/月显示;年不显示,避免冗余）
  String get _periodRangeLabel {
    final (start, end) = _range();
    final last = end.subtract(const Duration(days: 1));
    return '${start.month}.${start.day}～${last.month}.${last.day}';
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

    // 分类按金额从大到小排序(饼图扇区与下方列表保持一致)
    final sortedCats = byCat.keys.toList()
      ..sort((a, b) => (byCat[b] ?? 0).compareTo(byCat[a] ?? 0));

    double sumFor(DateTime b, {bool expense = true}) {
      double s = 0;
      for (final t in periodTxns) {
        if (t.type.isExpense != expense) continue;
        if (t.date.year != b.year || t.date.month != b.month) continue;
        if (_mode == StatsMode.year) {
          s += t.amount;
        } else if (t.date.day == b.day) {
          s += t.amount;
        }
      }
      return s;
    }

    final catKeys = sortedCats;
    // 环形图数据（颜色按金额从大到小依次取 palette）
    final donutSlices = [
      for (var i = 0; i < catKeys.length; i++)
        DonutSlice(
          label: findCategory(data.categories, catKeys[i])?.name ?? '未知',
          value: byCat[catKeys[i]]!,
          color: chartPalette[i % chartPalette.length],
        ),
    ];

    // 柱状趋势数据：横轴按时间顺序，纵轴金额；浮窗显示日期与收支
    final barItems = buckets.map((b) {
      String axis;
      bool showAxis;
      String tip;
      if (_mode == StatsMode.week) {
        axis = _weekdayLabels[(b.weekday - 1) % 7];
        showAxis = true;
        tip = '${b.month}月${b.day}日';
      } else if (_mode == StatsMode.month) {
        axis = '${b.day}';
        showAxis = b.day % 5 == 0; // 只标 5 的倍数，避免挤
        tip = '${b.month}月${b.day}日';
      } else {
        axis = '${b.month}';
        showAxis = true;
        tip = '${b.year}年${b.month}月';
      }
      return BarTrendItem(
        axisLabel: axis,
        showAxisLabel: showAxis,
        tooltipTitle: tip,
        expense: sumFor(b),
        income: sumFor(b, expense: false),
      );
    }).toList();

    // 平均值的分母:当前期间还没过完时只算"已经过去的格子",
    // 否则本月后面那些空白天数会把日均摊薄(实测 25 号却按 31 天算,偏低)。
    final nowDate = DateTime.now();
    final todayStart = DateTime(nowDate.year, nowDate.month, nowDate.day);
    final elapsedBuckets = buckets.where((b) => !b.isAfter(todayStart)).length;
    final avgDivisor = elapsedBuckets > 0 ? elapsedBuckets : buckets.length;


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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_periodLabel,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  // 仅"按周"时在周期标签下补具体日期区间
                  if (_mode == StatsMode.week) ...[
                    const SizedBox(height: 2),
                    Text(_periodRangeLabel,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade700)),
                  ],
                ],
              ),
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
        const SizedBox(height: 12),
        // 结余 = 收入 - 支出
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Text('结余',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 8),
                Text('（收入 − 支出）',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 11)),
                const Spacer(),
                Text(
                  '¥${(totalInc - totalExp).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: (totalInc - totalExp) >= 0
                        ? const Color(0xFF0E9E8E)
                        : const Color(0xFFD9534F),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- 柱状趋势 ----
        BarTrendCard(
          title: _mode == StatsMode.year ? '各月支出趋势' : '每日支出趋势',
          avgLabel: _mode == StatsMode.year ? '月均' : '日均',
          maxLabel: _mode == StatsMode.year ? '单月最高' : '单日最高',
          items: barItems,
          avgDivisor: avgDivisor,
        ),
        const SizedBox(height: 16),

        // ---- 支出结构(环形) ----
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('支出结构',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('点击扇区看明细',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
                if (catKeys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text('该期间暂无支出记录',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ),
                  )
                else
                  DonutChart(
                    slices: donutSlices,
                    selectedIndex: _selectedCat == null
                        ? null
                        : catKeys.indexOf(_selectedCat!),
                    onSelect: (i) {
                      if (i == null || i >= catKeys.length) return;
                      final key = catKeys[i];
                      setState(
                          () => _selectedCat = _selectedCat == key ? null : key);
                    },
                  ),
              ],
            ),
          ),
        ),
        // 选中分类时显示该分类下的每一笔记录明细
        if (_selectedCat != null && byCat.containsKey(_selectedCat)) ...[
          const SizedBox(height: 12),
          Builder(builder: (ctx) {
            final key = _selectedCat!;
            final i = catKeys.indexOf(key);
            final cat = findCategory(data.categories, key);
            final v = byCat[key]!;
            final pct = totalExp > 0 ? (v / totalExp * 100) : 0;
            final txns = periodTxns
                .where((t) => t.type.isExpense && t.categoryId == key)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: chartPalette[i % chartPalette.length].withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            chartPalette[i % chartPalette.length].withOpacity(0.2),
                        child: Text(cat?.icon ?? '💸',
                            style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cat?.name ?? '未知',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('共 ${txns.length} 笔 · 占支出 ${pct.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('¥${v.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: chartPalette[i % chartPalette.length])),
                    ],
                  ),
                  if (txns.isNotEmpty) const Divider(height: 16),
                  ...txns.map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Text('${t.date.month}月${t.date.day}日',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  t.note?.isNotEmpty == true ? t.note! : '无备注',
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text('¥${t.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                ],
              ),
            );
          }),
        ],
        if (catKeys.isNotEmpty) const SizedBox(height: 12),
        ...catKeys.asMap().entries.map((e) {
          final cat = findCategory(data.categories, e.value);
          final v = byCat[e.value]!;
          final pct = totalExp > 0 ? (v / totalExp * 100) : 0;
          final isSel = _selectedCat == e.value;
          return ListTile(
            onTap: () => setState(
                () => _selectedCat = _selectedCat == e.value ? null : e.value),
            tileColor: isSel
                ? chartPalette[e.key % chartPalette.length].withOpacity(0.08)
                : null,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            leading: CircleAvatar(
              backgroundColor: chartPalette[e.key % chartPalette.length].withOpacity(0.15),
              child: Text(cat?.icon ?? '💸'),
            ),
            title: Text(cat?.name ?? '未知'),
            trailing: Text('¥${v.toStringAsFixed(2)} (${pct.toStringAsFixed(0)}%)'),
          );
        }),
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

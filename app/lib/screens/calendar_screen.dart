import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/day_detail_sheet.dart';

/// 净结余格式化:去掉多余的尾随 0(例如 -115.50 -> -115.5,200.00 -> 200)
String _fmtNet(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focused;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _focused = DateTime(n.year, n.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final daysInMonth =
        DateTime(_focused.year, _focused.month + 1, 0).day;
    final firstWeekday = DateTime(_focused.year, _focused.month, 1).weekday;
    final leading = firstWeekday - 1;

    final Map<int, double> daySum = {};
    for (final t in data.transactions) {
      if (t.date.year == _focused.year && t.date.month == _focused.month) {
        // 支出记负数、收入记正数,格子展示当日净结余(收入 + (-支出))
        final signed = t.type == TxType.income ? t.amount : -t.amount;
        daySum[t.date.day] = (daySum[t.date.day] ?? 0) + signed;
      }
    }

    final today = DateTime.now();
    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final has = daySum.containsKey(d);
      final sum = daySum[d] ?? 0;
      final isToday = today.year == _focused.year &&
          today.month == _focused.month &&
          today.day == d;
      cells.add(
        InkWell(
          // 任何日期（含过去的空日子）都可点开，进入当日详情增删改
          onTap: () => _showDay(
              context, DateTime(_focused.year, _focused.month, d)),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: has
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                  : null,
              border: isToday
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$d',
                    style: TextStyle(
                        fontWeight: has || isToday
                            ? FontWeight.bold
                            : FontWeight.normal)),
                if (has)
                  Text('¥${_fmtNet(sum)}',
                      style: TextStyle(
                          fontSize: 10,
                          color: sum < 0
                              ? Colors.redAccent
                              : Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(
                  '${_focused.year} 年 ${_focused.month} 月',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('一'), Text('二'), Text('三'), Text('四'),
              Text('五'), Text('六'), Text('日'),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.count(
              crossAxisCount: 7,
              children: cells,
            ),
          ),
        ),
      ],
    );
  }

  void _showDay(BuildContext context, DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DayDetailSheet(day: day),
    );
  }
}

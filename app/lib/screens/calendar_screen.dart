import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/txn_tile.dart';

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
    final Map<int, List<Txn>> dayTxns = {};
    for (final t in data.transactions) {
      if (t.date.year == _focused.year && t.date.month == _focused.month) {
        daySum[t.date.day] = (daySum[t.date.day] ?? 0) + t.amount;
        dayTxns.putIfAbsent(t.date.day, () => []).add(t);
      }
    }

    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final has = daySum.containsKey(d);
      final sum = daySum[d] ?? 0;
      cells.add(
        InkWell(
          onTap: has
              ? () => _showDay(context, d, dayTxns[d] ?? [])
              : null,
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: has
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$d',
                    style: TextStyle(
                        fontWeight: has ? FontWeight.bold : FontWeight.normal)),
                if (has)
                  Text('¥${sum.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.primary)),
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

  void _showDay(BuildContext context, int day, List<Txn> txns) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_focused.year-$_focused.month-$day',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            ...txns
                .map((t) => TxnTile(
                      txn: t,
                      onTap: () => Navigator.of(context).pop(),
                    ))
                ,
          ],
        ),
      ),
    );
  }
}

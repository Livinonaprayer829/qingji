import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../exporters.dart';
import '../models.dart';
import '../providers.dart';
import '../repository.dart';

/// 导出账单页：
/// - 预设:本周 / 本月 / 本季度 / 本年 / 全部
/// - 日历上可**任意多选**日期(可跨月、可跳选,如只选 1、3、7 号)
/// - 实时显示所选日期的 收入 / 支出 / 结余 / 笔数
/// - 两种格式:**CSV 数据表**(含末尾汇总) / **HTML 报告**(含饼图)
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  /// 选中的日期集合（key: yyyy-MM-dd）
  final Set<String> _selected = {};
  /// 日历当前显示的月份
  late DateTime _month;
  /// 当前命中的预设下标,-1 表示自定义
  int _preset = -1;
  /// 导出格式:0=CSV,1=HTML 报告
  int _format = 0;

  static const _presetLabels = ['本周', '本月', '本季度', '本年', '全部'];
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  // ---------------- 预设 ----------------
  void _applyPreset(int idx, List<Txn> txns) {
    // 再次点击同一个预设 = 取消选择
    if (_preset == idx) {
      setState(() {
        _selected.clear();
        _preset = -1;
      });
      return;
    }

    final now = DateTime.now();
    DateTime s, e;
    switch (idx) {
      case 0: // 本周（周一 ~ 周日,以系统当天为准）
        s = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        e = DateTime(s.year, s.month, s.day + 6);
        break;
      case 1: // 本月：以**日历当前展示的月份**为准
        s = DateTime(_month.year, _month.month, 1);
        e = DateTime(_month.year, _month.month + 1, 0);
        break;
      case 2: // 本季度：以**日历当前展示月份**所在季度为准
        final q = (_month.month - 1) ~/ 3;
        s = DateTime(_month.year, q * 3 + 1, 1);
        e = DateTime(_month.year, q * 3 + 4, 0);
        break;
      case 3: // 本年：以**日历当前展示的年份**为准,选满整年
        s = DateTime(_month.year, 1, 1);
        e = DateTime(_month.year, 12, 31);
        break;
      default: // 全部
        if (txns.isEmpty) return;
        final dates = txns.map((t) => t.date).toList()
          ..sort((a, b) => a.compareTo(b));
        s = dates.first;
        e = dates.last;
    }
    final set = <String>{};
    for (var d = DateTime(s.year, s.month, s.day);
        !d.isAfter(e);
        d = DateTime(d.year, d.month, d.day + 1)) {
      set.add(dateOnly(d));
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(set);
      _preset = idx;
      _month = DateTime(s.year, s.month);
    });
  }

  void _toggleDay(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
      _preset = -1; // 手动改动后不再命中预设
    });
  }

  void _shiftMonth(int dir) {
    setState(() =>
        _month = DateTime(_month.year, _month.month + dir, 1));
  }

  // ---------------- 汇总 ----------------
  /// 所选日期是否连续（用于显示 "9.28～10.4"）
  bool get _contiguous {
    if (_selected.length < 2) return true;
    final keys = _selected.toList()..sort();
    for (var i = 1; i < keys.length; i++) {
      final prev = DateTime.parse(keys[i - 1]);
      final cur = DateTime.parse(keys[i]);
      if (cur.difference(prev).inDays != 1) return false;
    }
    return true;
  }

  String get _rangeText {
    if (_selected.isEmpty) return '未选择日期';
    final keys = _selected.toList()..sort();
    String md(String k) {
      final d = DateTime.parse(k);
      return '${d.month}.${d.day}';
    }

    if (keys.length == 1) return md(keys.first);
    if (_contiguous) {
      final a = DateTime.parse(keys.first);
      final b = DateTime.parse(keys.last);
      final sameYear = a.year == b.year;
      return sameYear
          ? '${md(keys.first)}～${md(keys.last)}'
          : '${a.year}.${a.month}.${a.day}～${b.year}.${b.month}.${b.day}';
    }
    return '共 ${keys.length} 天（跳选）';
  }

  String get _fileStem {
    final keys = _selected.toList()..sort();
    if (keys.isEmpty) return 'qingji_empty';
    if (keys.length == 1) return 'qingji_${keys.first}';
    return 'qingji_${keys.first}至${keys.last}';
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final primary = Theme.of(context).colorScheme.primary;

    // 有记账的日期(日历上打点)
    final txnDates = data.transactions.map((t) => dateOnly(t.date)).toSet();

    final selectedTxns = data.transactions
        .where((t) => _selected.contains(dateOnly(t.date)))
        .toList();
    double inc = 0, exp = 0;
    for (final t in selectedTxns) {
      if (t.type.isExpense) {
        exp += t.amount;
      } else {
        inc += t.amount;
      }
    }
    final bal = inc - exp;

    // 日历网格
    final first = DateTime(_month.year, _month.month, 1);
    final offset = first.weekday - 1; // 周一为第一列
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < offset; i++) {
      cells.add(const SizedBox());
    }
    final todayKey = dateOnly(DateTime.now());
    for (var d = 1; d <= days; d++) {
      final date = DateTime(_month.year, _month.month, d);
      final key = dateOnly(date);
      cells.add(_dayCell(date, key, primary, txnDates, todayKey));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('导出账单')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('快速选择',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetLabels.asMap().entries.map((e) {
              final on = _preset == e.key;
              return ChoiceChip(
                label: Text(e.value),
                selected: on,
                onSelected: (_) => _applyPreset(e.key, data.transactions),
                selectedColor: primary.withOpacity(0.18),
                showCheckmark: false,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            '本月 / 本季度 / 本年 以日历上显示的月份为准;再次点击已选中的预设可取消',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // ---- 汇总 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_note_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$_rangeText  ·  已选 ${_selected.length} 天  ·  ${selectedTxns.length} 笔',
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _statCol('收入', inc, const Color(0xFF0E9E8E)),
                      _statCol('支出', exp, const Color(0xFFD9534F)),
                      _statCol('结余', bal,
                          bal >= 0 ? const Color(0xFF0E9E8E) : const Color(0xFFD9534F),
                          bold: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- 日历 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _shiftMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: '上个月',
                      ),
                      Expanded(
                        child: Text('${_month.year}年${_month.month}月',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        onPressed: () => _shiftMonth(1),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: '下个月',
                      ),
                    ],
                  ),
                  Row(
                    children: _weekdays
                        .map((w) => Expanded(
                              child: Center(
                                child: Text(w,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.0,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    children: cells,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primary.withOpacity(0.6)),
                      ),
                      const SizedBox(width: 6),
                      Text('有记账的日期',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                      const SizedBox(width: 14),
                      Text('点日期可多选,支持跳选',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ---- 导出格式 ----
          const Text('导出格式',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('CSV 数据表'),
                icon: Icon(Icons.table_chart_outlined, size: 18),
              ),
              ButtonSegment(
                value: 1,
                label: Text('HTML 报告'),
                icon: Icon(Icons.pie_chart_outline, size: 18),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          Text(
            _format == 0
                ? '数据表（日期/类型/分类/账户/金额/备注）,末尾附 收入/支出/结余/笔数 汇总;可用 Excel 打开'
                : '含 收入/支出/结余 汇总 + 支出分类饼图 + 交易明细;浏览器打开即可,可打印或另存为 PDF',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // ---- 操作 ----
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => setState(() {
                          _selected.clear();
                          _preset = -1;
                        }),
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      selectedTxns.isEmpty ? null : () => _export(data, selectedTxns),
                  icon: const Icon(Icons.download),
                  label: Text(selectedTxns.isEmpty
                      ? '所选日期无记录'
                      : '导出 ${selectedTxns.length} 笔'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _statCol(String label, double v, Color color, {bool bold = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('¥${v.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: bold ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, String key, Color primary,
      Set<String> txnDates, String todayKey) {
    final sel = _selected.contains(key);
    final isToday = key == todayKey;
    final hasTxn = txnDates.contains(key);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _toggleDay(key),
      child: Container(
        decoration: BoxDecoration(
          color: sel ? primary : null,
          borderRadius: BorderRadius.circular(10),
          border: (!sel && isToday)
              ? Border.all(color: primary.withOpacity(0.6))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}',
                style: TextStyle(
                    fontSize: 14,
                    color: sel ? Colors.white : Colors.black87,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(height: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasTxn
                    ? (sel ? Colors.white : primary.withOpacity(0.65))
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(AppData data, List<Txn> txns) async {
    final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
    if (_format == 0) {
      await exportCsv(context, data, sorted, fileStem: _fileStem);
    } else {
      // 传真实区间(首/末选中日),供报告里的趋势图按天分桶
      final keys = _selected.toList()..sort();
      await exportHtmlReport(context, data, sorted,
          rangeText: _rangeText,
          selectedDays: _selected.length,
          fileStem: _fileStem,
          rangeStart: keys.isEmpty ? null : DateTime.parse(keys.first),
          rangeEnd: keys.isEmpty ? null : DateTime.parse(keys.last));
    }
  }
}

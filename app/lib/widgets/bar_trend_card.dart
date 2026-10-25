import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils.dart';

/// 一根柱子（一天 / 一周 / 一月）
class BarTrendItem {
  /// 横轴文字：周=一..日，月=5/10/15，年=1..12
  final String axisLabel;

  /// 横轴是否显示该刻度（月视图只标 5 的倍数，避免挤）
  final bool showAxisLabel;

  /// 浮窗第一行：10月24日
  final String tooltipTitle;

  final double expense;
  final double income;

  const BarTrendItem({
    required this.axisLabel,
    required this.tooltipTitle,
    required this.expense,
    required this.income,
    this.showAxisLabel = true,
  });
}

/// 极简柱状趋势卡（参考设计）：
/// - 卡片内：标题 + 日均 / 最高 两个大数字 + 图表
/// - 只画横向虚线网格，纵轴刻度在**右侧**
/// - 柱子浅色圆角、无任何装饰；悬停（或按住拖动）时该柱变深、
///   出现竖向虚线指示 + 深色圆角浮窗（日期 / 支出 / 收入）
class BarTrendCard extends StatefulWidget {
  final String title;
  final String avgLabel;
  final String maxLabel;
  final List<BarTrendItem> items;
  final String currency;
  final double chartHeight;

  /// 日均/月均的分母。当前期间还没过完时应传"已过去的格子数",
  /// 否则后面那些空白天数会把平均值摊薄(例如 10 月 25 号却按 31 天算)。
  final int? avgDivisor;

  const BarTrendCard({
    super.key,
    required this.title,
    required this.avgLabel,
    required this.maxLabel,
    required this.items,
    this.currency = '¥',
    this.chartHeight = 176,
    this.avgDivisor,
  });

  @override
  State<BarTrendCard> createState() => _BarTrendCardState();
}

class _BarTrendCardState extends State<BarTrendCard> {
  int? _touched;

  // 参考图的配色：浅蓝柱 + 饱和蓝高亮
  static const _barIdle = Color(0xFFBFE0F7);
  static const _barActive = Color(0xFF0A84FF);
  static const _gridColor = Color(0xFFEDF1F5);
  static const _axisColor = Color(0xFFAFB6C1);
  static const _tooltipBg = Color(0xFF1C1C1E);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final maxV =
        items.isEmpty ? 0.0 : items.map((e) => e.expense).reduce(math.max);
    final total = items.fold<double>(0, (a, b) => a + b.expense);
    final rawDivisor = widget.avgDivisor ?? items.length;
    final divisor = rawDivisor < 1
        ? 1
        : (rawDivisor > items.length ? items.length : rawDivisor);
    final avg = items.isEmpty ? 0.0 : total / divisor;
    final (step, maxY) = _niceScale(maxV);
    final empty = maxV <= 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(
              children: [
                _bigStat(avg, widget.avgLabel),
                const SizedBox(width: 32),
                _bigStat(maxV, widget.maxLabel),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: widget.chartHeight,
              child: empty
                  ? Center(
                      child: Text('该期间暂无支出记录',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        minY: 0,
                        maxY: maxY,
                        barGroups: [
                          for (var i = 0; i < items.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: items[i].expense,
                                  width: _barWidth(items.length),
                                  color: i == _touched ? _barActive : _barIdle,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ],
                            ),
                        ],
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: step,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: _gridColor,
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: _touched == null
                            ? ExtraLinesData()
                            : ExtraLinesData(
                                verticalLines: [
                                  VerticalLine(
                                    x: _touched!.toDouble(),
                                    color: const Color(0xFF9AA4B2),
                                    strokeWidth: 1,
                                    dashArray: const [4, 4],
                                  ),
                                ],
                              ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: step,
                              getTitlesWidget: (v, meta) => Text(
                                _axisLabel(v),
                                style: const TextStyle(
                                    fontSize: 10.5, color: _axisColor),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i < 0 || i >= items.length) {
                                  return const SizedBox();
                                }
                                if (!items[i].showAxisLabel) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Text(
                                    items[i].axisLabel,
                                    style: const TextStyle(
                                        fontSize: 10.5, color: _axisColor),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (group) => _tooltipBg,
                            tooltipRoundedRadius: 12,
                            tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            tooltipMargin: 8,
                            maxContentWidth: 180,
                            fitInsideHorizontally: true,
                            getTooltipItem: (group, gi, rod, ri) {
                              if (gi < 0 || gi >= items.length) {
                                return BarTooltipItem('', const TextStyle());
                              }
                              final it = items[gi];
                              final buf = StringBuffer(it.tooltipTitle);
                              buf.write(
                                  '\n支出 ${_money(it.expense)}');
                              if (it.income > 0) {
                                buf.write('\n收入 ${_money(it.income)}');
                              }
                              return BarTooltipItem(
                                buf.toString(),
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  height: 1.55,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                          touchCallback: (event, resp) {
                            // hover 跟随；松手 / 移出则清除
                            int? next;
                            if (event is! FlPointerExitEvent &&
                                event is! FlTapUpEvent &&
                                resp?.spot != null) {
                              next = resp!.spot!.touchedBarGroupIndex;
                            }
                            if (next != _touched) {
                              setState(() => _touched = next);
                            }
                          },
                        ),
                      ),
                      swapAnimationDuration: const Duration(milliseconds: 180),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigStat(double value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMoney(value, widget.currency),
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      ],
    );
  }

  double _barWidth(int n) {
    if (n <= 8) return 14;
    if (n <= 12) return 10;
    return 7;
  }

  String _money(double v) => '${widget.currency}${shortMoney(v)}';

  /// 纵轴刻度：挑一个"整"的步长，共 4 格
  (double, double) _niceScale(double maxV) {
    if (maxV <= 0) return (20, 80);
    final raw = maxV / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    final step = (n <= 1 ? 1.0 : n <= 2 ? 2.0 : n <= 5 ? 5.0 : 10.0) * mag;
    return (step, step * 4);
  }

  String _axisLabel(double v) {
    if (v >= 10000) {
      final w = v / 10000;
      return '${w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1)}万';
    }
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

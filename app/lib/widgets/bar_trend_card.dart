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
    // 240 = 顶部浮窗带(64) + 柱子绘图区(150) + 底部日期刻度(26)
    // 按周展示时 7 根柱子（周一~周日）都在这个绘图区里，不会被裁切
    this.chartHeight = 240,
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
        // 内边距和标题/数字之间的间距都收紧了，把高度让给图表
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _bigStat(avg, widget.avgLabel),
                const SizedBox(width: 32),
                _bigStat(maxV, widget.maxLabel),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: widget.chartHeight,
              child: empty
                  ? Center(
                      child: Text('该期间暂无支出记录',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    )
                  : LayoutBuilder(
                      builder: (ctx, cons) {
                        final w = cons.maxWidth;
                        final idx = (_touched != null &&
                                _touched! >= 0 &&
                                _touched! < items.length)
                            ? _touched!
                            : null;
                        // 绘图区高度 = 图表高度 − 顶部"浮窗带"
                        final plotH = cons.maxHeight - _tipBand;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 图表整体下移 _tipBand，在顶部给浮窗留出**固定**空间：
                            // 浮窗钉死在顶部（日均/最高数字下方），柱子最高也到不了那里，
                            // 所以浮窗永远不会压住柱子。
                            Positioned(
                              left: 0,
                              right: 0,
                              top: _tipBand,
                              bottom: 0,
                              child: Stack(
                                children: [
                                  // 竖向虚线画在图表**下层**：柱子会盖住它，
                                  // 于是只露出「浮窗下沿 → 柱顶」这一段，全在浮窗下方。
                                  if (idx != null && items[idx].expense > 0)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _DashPainter(
                                          cx: _cxOf(w, idx, items.length),
                                          bottom: _topOf(plotH, maxY,
                                              items[idx].expense),
                                        ),
                                      ),
                                    ),
                                  BarChart(
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
                          // 浮窗改由我们自己画（钉在图表顶部），关掉 fl_chart 自带浮窗
                          // —— 它只能“贴着柱顶”显示，无法固定高度。
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (group) => Colors.transparent,
                            getTooltipItem: (group, gi, rod, ri) => null,
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
                                ],
                              ),
                            ),
                            // 浮窗：钉在图表顶部（日均/单日最高数字下方），
                            // 虚线全部在它下方，不会被柱子遮挡。
                            if (idx != null) _tooltip(w, idx),
                          ],
                        );
                      },
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatMoney(value, widget.currency),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      ],
    );
  }

  /// 顶部"浮窗带"的高度：足够放 3 行（日期 / 支出 / 收入）
  static const double _tipBand = 64;

  /// 深色浮窗：**固定**钉在图表顶部（日均/最高数字正下方）。
  /// 不用 fl_chart 自带浮窗，因为它只能贴着柱顶显示，
  /// 那样"浮窗下方"只剩十几个像素，虚线根本拉不长。
  Widget _tooltip(double w, int idx) {
    final it = widget.items[idx];
    final lines = <String>[it.tooltipTitle, '支出 ${_money(it.expense)}'];
    if (it.income > 0) lines.add('收入 ${_money(it.income)}');
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11.5,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );
    var textW = 0.0;
    for (final l in lines) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > textW) textW = tp.width;
    }
    const padH = 11.0, padV = 7.0;
    final tipW = textW + padH * 2;
    final cx = _cxOf(w, idx, widget.items.length);
    var left = cx - tipW / 2;
    if (left < 2) left = 2;
    final maxLeft = w - 34 - tipW; // 别盖住右侧刻度
    if (left > maxLeft) left = maxLeft;
    return Positioned(
      top: 0,
      left: left,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: _tooltipBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines.length; i++)
              Text(
                lines[i],
                style: style.copyWith(
                  color: i == 0 ? Colors.white : Colors.white70,
                  fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
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

/// 绘图区里第 i 列的中心 x（与 fl_chart 的 spaceAround 一致；
/// 右侧刻度占 34，左侧刻度隐藏，所以绘图区宽 = 总宽 - 34）
double _cxOf(double w, int i, int n) {
  final plotW = w - 34;
  return (i + 0.5) * plotW / n;
}

/// 某根柱子的顶部 y（底部刻度占 26）
double _topOf(double h, double maxY, double value) {
  final plotH = h - 26;
  if (maxY <= 0) return plotH;
  return plotH - (value / maxY) * plotH;
}

/// 竖向虚线指示：画在 BarChart 的**下层**。
/// 浮窗由 BarChart 自己在上层绘制，会盖住这条线的上半段；
/// 柱子盖住下半段 ⇒ 最终只露出「浮窗下沿 → 柱顶」这一段（和参考图一致）。
class _DashPainter extends CustomPainter {
  final double cx;
  final double bottom;
  _DashPainter({required this.cx, required this.bottom});

  @override
  void paint(Canvas canvas, Size size) {
    if (bottom <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..strokeWidth = 1;
    const dash = 4.0, gap = 4.0;
    var y = 0.0;
    while (y < bottom) {
      final y2 = (y + dash) > bottom ? bottom : (y + dash);
      canvas.drawLine(Offset(cx, y), Offset(cx, y2), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.cx != cx || old.bottom != bottom;
}

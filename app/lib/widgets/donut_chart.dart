import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 环形图配色（参考设计：珊瑚 / 青 / 紫 / 橙 / 淡紫 / 绿 / 蓝 / 粉）
const List<Color> chartPalette = [
  Color(0xFFF97A68),
  Color(0xFF12B5D4),
  Color(0xFFB57BE8),
  Color(0xFFFFB020),
  Color(0xFFC9A6F5),
  Color(0xFF4CC38A),
  Color(0xFF5B8DEF),
  Color(0xFFF58FB0),
];

class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// 极简环形图：
/// - 粗环、扇区之间留细白缝（参考图的比例：内径 ≈ 外径 62%）
/// - **占比 ≥ labelThreshold 的扇区**在环外侧标「名称 百分比」，并带折线引导；
///   小占比扇区不标注，避免互相挤压
/// - 文本按左右分组合并、纵向推开，保证不重叠
/// - 点击扇区回调索引（用于查看该分类明细）
class DonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final int? selectedIndex;
  final ValueChanged<int?>? onSelect;
  final double height;
  final double labelThreshold;

  const DonutChart({
    super.key,
    required this.slices,
    this.selectedIndex,
    this.onSelect,
    this.height = 224,
    this.labelThreshold = 0.05,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final geo = _Geo(size);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onSelect == null
                ? null
                : (d) => onSelect!(_hit(d.localPosition, geo)),
            child: CustomPaint(
              size: size,
              painter: _DonutPainter(
                slices: slices,
                selected: selectedIndex,
                threshold: labelThreshold,
                geo: geo,
              ),
            ),
          );
        },
      ),
    );
  }

  int? _hit(Offset p, _Geo geo) {
    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return null;
    final d = p - geo.center;
    if (d.distance < geo.inner || d.distance > geo.outer + 4) return null;
    var a = math.atan2(d.dy, d.dx) + math.pi / 2; // 0 = 正上方
    if (a < 0) a += math.pi * 2;
    var acc = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].value / total * math.pi * 2;
      if (a >= acc && a < acc + sweep) return i;
      acc += sweep;
    }
    return null;
  }
}

/// 几何：环的圆心/内外径
/// - 左右各留 78 给外部标注
/// - **上下各留 30**：否则宽屏下环半径会被"高度"限制死,环的上下沿顶到画布边,
///   6 点钟方向的标注就被夹到边缘、压在环上(桌面宽屏实测踩到过)
class _Geo {
  _Geo(this.size) {
    center = Offset(size.width / 2, size.height / 2);
    outer = math.max(
        math.min(size.width / 2 - 78, size.height / 2 - 30), 16.0);
    inner = outer * 0.62;
  }
  final Size size;
  late final Offset center;
  late final double outer;
  late final double inner;
}

class _Label {
  final DonutSlice slice;
  final double pct;
  final bool isLeft;
  final Offset anchor;
  double y;
  _Label({
    required this.slice,
    required this.pct,
    required this.isLeft,
    required this.anchor,
    required this.y,
  });
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  final int? selected;
  final double threshold;
  final _Geo geo;

  _DonutPainter({
    required this.slices,
    required this.selected,
    required this.threshold,
    required this.geo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return;

    final c = geo.center;
    final outer = geo.outer;
    final inner = geo.inner;

    // ---- 扇区 ----
    var start = -math.pi / 2;
    final labels = <_Label>[];
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = s.value / total * math.pi * 2;
      final o = selected == i ? outer + 3 : outer;
      final gapRad = 1.4 / outer; // ≈1.4px 的白缝
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = o - inner;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: (o + inner) / 2),
        start + gapRad,
        math.max(sweep - gapRad * 2, 0.008),
        false,
        paint,
      );

      final pct = s.value / total;
      // 最多标 6 个(调用方已按金额从大到小排序),再多必然挤在一起
      if (pct >= threshold && labels.length < 6) {
        final mid = start + sweep / 2;
        labels.add(_Label(
          slice: s,
          pct: pct,
          isLeft: math.cos(mid) < 0,
          anchor: Offset(
            c.dx + math.cos(mid) * (o + 3),
            c.dy + math.sin(mid) * (o + 3),
          ),
          y: c.dy + math.sin(mid) * (o + 20),
        ));
      }
      start += sweep;
    }

    // ---- 标注避让：分左右两组，按 y 排序后保证最小间距 ----
    const minGap = 22.0;
    for (final left in [true, false]) {
      final group = labels.where((l) => l.isLeft == left).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      for (var i = 1; i < group.length; i++) {
        if (group[i].y - group[i - 1].y < minGap) {
          group[i].y = group[i - 1].y + minGap;
        }
      }
      if (group.isNotEmpty) {
        final overflowBottom = group.last.y - (size.height - 12);
        if (overflowBottom > 0) {
          for (final l in group) {
            l.y -= overflowBottom;
          }
        }
        if (group.first.y < 12) {
          final up = 12 - group.first.y;
          for (final l in group) {
            l.y += up;
          }
        }
      }
    }

    // ---- 引导线 + 文字 ----
    final linePaint = Paint()
      ..color = const Color(0xFFDCE1E9)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final maxTextWidth = math.max(size.width / 2 - outer - 26, 24.0);

    for (final l in labels) {
      final dir = l.isLeft ? -1.0 : 1.0;
      final elbow = Offset(c.dx + dir * (outer + 14), l.y);
      final tail = Offset(elbow.dx + dir * 8, l.y);
      canvas.drawPath(
        Path()
          ..moveTo(l.anchor.dx, l.anchor.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(tail.dx, tail.dy),
        linePaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${l.slice.label} ${(l.pct * 100).round()}%',
          style: const TextStyle(
            fontSize: 11.5,
            color: Color(0xFF2C3038),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxTextWidth);

      final tx = l.isLeft ? tail.dx - 3 - tp.width : tail.dx + 3;
      tp.paint(canvas, Offset(tx, l.y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.selected != selected ||
      old.threshold != threshold ||
      old.geo.outer != geo.outer ||
      old.slices.length != slices.length ||
      !_sameSlices(old.slices, slices);

  bool _sameSlices(List<DonutSlice> a, List<DonutSlice> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value ||
          a[i].label != b[i].label ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }
}

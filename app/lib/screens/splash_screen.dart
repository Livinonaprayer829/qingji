import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 开屏动画：以「青记」图标为依托。
/// 逻辑：开着的书（图标原状,右页带对勾）淡入 → 标语浮现 → **合书** → 进入页面。
///
/// 合书为物理正确的「翻页」：右页不动，**左页绕书脊向上翻 90°、继续翻到右侧盖上右页**，
/// 两页重合后再平滑收成一本合上的书（封面 + 左侧书脊）。
///
/// 时序（总长 2000ms）：
///   0-380ms    开书（含对勾）淡入 + 轻微放大
///   300-660ms  「青记·简约清爽」淡入 + 上移 + 字距展开
///   720-1460ms **合书**：左页翻页合拢,同时整本连续收方（非线性突变）
///   1640-1900ms 合拢后的轻微回弹
///   1900ms 后   停留 → 420ms 交叉淡出，进入 [next]
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color _g1 = Color(0xFF3CCBBC);
  static const Color _g2 = Color(0xFF26BBAE);
  static const Color _g3 = Color(0xFF15A79A);

  static const Duration _total = Duration(milliseconds: 2000);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _total);

  late final Animation<double> _iconOpacity = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.21, curve: Curves.easeOut),
  );
  late final Animation<double> _iconScale = Tween<double>(begin: 0.9, end: 1.0)
      .animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.23, curve: Curves.easeOutBack),
  ));

  // 合拢瞬间的轻微回弹
  late final Animation<double> _settle = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 0.97)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.97, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 55,
    ),
  ]).animate(CurvedAnimation(parent: _c, curve: const Interval(0.82, 0.95)));

  late final Animation<double> _textOpacity = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.17, 0.36, curve: Curves.easeOut),
  );
  late final Animation<double> _textSlide = Tween<double>(begin: 14, end: 0)
      .animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.17, 0.38, curve: Curves.easeOutCubic),
  ));
  late final Animation<double> _textSpacing =
      Tween<double>(begin: 1.0, end: 5.0).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.17, 0.44, curve: Curves.easeOut),
  ));

  /// 合书进度：0=完全打开（图标原状）→ 1=合上
  late final Animation<double> _closeT = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.36, 0.86, curve: Curves.linear),
  );

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
    _c.forward();
  }

  void _go() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_g1, _g2, _g3],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Opacity(
                  opacity: _iconOpacity.value,
                  child: Transform.scale(
                    scale: _iconScale.value * _settle.value,
                    child: CustomPaint(
                      size: const Size(200, 200),
                      painter: _BookMarkPainter(closeT: _closeT.value),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Opacity(
                  opacity: _textOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: Text(
                      '青记·简约清爽',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        letterSpacing: _textSpacing.value,
                        shadows: const [
                          Shadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 矢量书本标记：左右两页独立成路径，左页可绕书脊翻转；合拢后几何平滑收成封面。
class _BookMarkPainter extends CustomPainter {
  final double closeT; // 0 打开 → 1 合上

  _BookMarkPainter({required this.closeT});

  static const int _inkR = 13, _inkG = 98, _inkB = 93; // #0D625D
  static const int _chkR = 35, _chkG = 180, _chkB = 166; // #23B4A6
  static Color _ink(double o) => Color.fromRGBO(_inkR, _inkG, _inkB, o);
  static Color _chk(double o) => Color.fromRGBO(_chkR, _chkG, _chkB, o);

  // —— 右页（打开态） ——  起点 + 4 段三次贝塞尔(c1,c2,end)
  static const Offset _pR0 = Offset(0, -0.342);
  static const List<List<Offset>> _pR = [
    [Offset(0.05, -0.350), Offset(0.12, -0.370), Offset(0.20, -0.372)],
    [Offset(0.30, -0.375), Offset(0.40, -0.365), Offset(0.5, -0.325)],
    [Offset(0.515, -0.10), Offset(0.515, 0.12), Offset(0.5, 0.295)],
    [Offset(0.30, 0.345), Offset(0.14, 0.372), Offset(0.0, 0.372)],
  ];
  // —— 左页（打开态） ——
  static const Offset _pL0 = Offset(0, -0.342);
  static const List<List<Offset>> _pL = [
    [Offset(-0.05, -0.350), Offset(-0.12, -0.370), Offset(-0.20, -0.372)],
    [Offset(-0.30, -0.375), Offset(-0.40, -0.365), Offset(-0.5, -0.325)],
    [Offset(-0.515, -0.10), Offset(-0.515, 0.12), Offset(-0.5, 0.295)],
    [Offset(-0.30, 0.345), Offset(-0.14, 0.372), Offset(0.0, 0.372)],
  ];
  // —— 封面（合上态,占右半 0..0.5） ——
  static const Offset _cR0 = Offset(0, -0.366);
  static const List<List<Offset>> _cR = [
    [Offset(0.17, -0.366), Offset(0.33, -0.366), Offset(0.5, -0.366)],
    [Offset(0.5, -0.122), Offset(0.5, 0.122), Offset(0.5, 0.366)],
    [Offset(0.33, 0.366), Offset(0.17, 0.366), Offset(0.0, 0.366)],
    [Offset(0.0, 0.122), Offset(0.0, -0.122), Offset(0.0, -0.366)],
  ];
  // —— 封面（左半镜像,供左页翻过来后重合） ——
  static const Offset _cL0 = Offset(0, -0.366);
  static const List<List<Offset>> _cL = [
    [Offset(-0.17, -0.366), Offset(-0.33, -0.366), Offset(-0.5, -0.366)],
    [Offset(-0.5, -0.122), Offset(-0.5, 0.122), Offset(-0.5, 0.366)],
    [Offset(-0.33, 0.366), Offset(-0.17, 0.366), Offset(0.0, 0.366)],
    [Offset(0.0, 0.122), Offset(0.0, -0.122), Offset(0.0, -0.366)],
  ];

  static Path _lerpPath(double w, Offset a0, List<List<Offset>> a, Offset b0,
      List<List<Offset>> b, double m) {
    Offset L(Offset p, Offset q) =>
        Offset((p.dx + (q.dx - p.dx) * m) * w, (p.dy + (q.dy - p.dy) * m) * w);
    final p0 = L(a0, b0);
    final path = Path()..moveTo(p0.dx, p0.dy);
    for (var i = 0; i < 4; i++) {
      final c1 = L(a[i][0], b[i][0]);
      final c2 = L(a[i][1], b[i][1]);
      final e = L(a[i][2], b[i][2]);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.58;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 翻页（绕书脊竖直轴,2D 投影为水平翻转）
    final flipT =
        Curves.easeInOutCubic.transform((closeT / 0.65).clamp(0.0, 1.0));
    // 收方与翻页全程同步（连续渐变,无"某一刻突变"）
    final m = flipT;

    final sx = 1 - 2 * flipT; // 1 → 0 → -1
    final gx = -0.25 * w * flipT; // 合拢过程归中

    canvas.save();
    canvas.translate(cx + gx, cy);

    final fillWhite = Paint()..style = PaintingStyle.fill;
    final strokeInk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.020 * w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final rightPath = _lerpPath(w, _pR0, _pR, _cR0, _cR, m);

    // 封面厚度（深青,下移一点）
    if (m > 0.01) {
      canvas.drawPath(
        _lerpPath(w, _pR0, _pR, _cR0, _cR, m).shift(Offset(0, 0.022 * w)),
        Paint()
          ..color = _ink(m)
          ..style = PaintingStyle.fill,
      );
    }

    // 右页（对勾画在其上）
    fillWhite.color = const Color(0xFFFFFFFF);
    canvas.drawPath(rightPath, fillWhite);
    _drawCheck(canvas, w);

    strokeInk.color = _ink(1);
    canvas.drawPath(rightPath, strokeInk);

    // 书脊竖线（翻页时淡出）
    final spineO = (1 - flipT).clamp(0.0, 1.0);
    if (spineO > 0.01) {
      canvas.drawLine(
        Offset(0, -0.342 * w),
        Offset(0, 0.372 * w),
        Paint()
          ..color = _ink(spineO)
          ..strokeWidth = 0.020 * w
          ..strokeCap = StrokeCap.round,
      );
    }

    // 左页（翻转;随翻页同步收成左侧镜像封面,最终与右页重合）
    if (sx.abs() > 0.002) {
      canvas.save();
      canvas.scale(sx, 1.0);
      final leftPath = _lerpPath(w, _pL0, _pL, _cL0, _cL, m);
      fillWhite.color = const Color(0xFFFFFFFF);
      canvas.drawPath(leftPath, fillWhite);
      strokeInk.color = _ink(1);
      canvas.drawPath(leftPath, strokeInk);
      // 翻页明暗（90° 处最暗,更像纸张背面）
      final shade = math.sin(math.pi * flipT).clamp(0.0, 1.0) * 0.16;
      if (shade > 0.01) {
        canvas.drawPath(
            leftPath,
            Paint()
              ..color = Color.fromRGBO(0, 0, 0, shade)
              ..style = PaintingStyle.fill);
      }
      canvas.restore();
    }

    // 封面左侧书脊折痕（合上后浮现）
    if (m > 0.01) {
      canvas.drawLine(
        Offset(0.055 * w, -0.30 * w),
        Offset(0.055 * w, 0.33 * w),
        Paint()
          ..color = _ink(m)
          ..strokeWidth = 0.014 * w
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  void _drawCheck(Canvas canvas, double w) {
    final p1 = Offset(0.070 * w, 0.078 * w);
    final p2 = Offset(0.150 * w, 0.160 * w);
    final p3 = Offset(0.300 * w, -0.020 * w);
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy),
      Paint()
        ..color = _chk(1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.052 * w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BookMarkPainter old) => old.closeT != closeT;
}

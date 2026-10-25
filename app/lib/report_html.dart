import 'dart:convert';
import 'dart:math' as math;

import 'csv_rows.dart';
import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// 图表配色（与统计页 chartPalette 一致）
const _pieColors = [
  '#F97A68',
  '#12B5D4',
  '#B57BE8',
  '#FFB020',
  '#C9A6F5',
  '#4CC38A',
  '#5B8DEF',
  '#F58FB0',
];

// 环形图画布（左右留出外部标注的位置）
const _cx = 210.0;
const _cy = 130.0;
const _rOuter = 92.0;
const _rInner = 57.0; // 环形内圈半径（≈外径 62%，与 App 内一致）
const _svgW = 420.0;
const _svgH = 260.0;

String _esc(String? s) => (s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _money(double v) => v.toStringAsFixed(2);

/// 生成一份**自包含**的 HTML 账单报告：
/// 汇总（收入/支出/结余/笔数）+ **可交互环形饼图**（点扇区展开该分类明细,再点收起）
/// + 分类占比列表（按占比从高到低）+ 交易明细。
/// 浏览器打开即可,也可「打印 → 另存为 PDF」。
String buildReportHtml({
  required AppData data,
  required List<Txn> txns,
  required String rangeText,
  required int selectedDays,
  DateTime? rangeStart,
  DateTime? rangeEnd,
}) {
  final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
  final s = summarizeTxns(sorted);
  final bal = s.income - s.expense;

  // 支出按分类聚合
  final byCat = <String, double>{};
  for (final t in sorted) {
    if (t.type.isExpense) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
  }
  final catIds = byCat.keys.toList()
    ..sort((a, b) => byCat[b]!.compareTo(byCat[a]!)); // 占比从高到低

  // 每个分类：名称/金额/占比/颜色/该分类下的明细
  final catData = <Map<String, dynamic>>[];
  for (var i = 0; i < catIds.length; i++) {
    final id = catIds[i];
    final cat = findCategory(data.categories, id);
    final amount = byCat[id]!;
    final items = sorted
        .where((t) => t.type.isExpense && t.categoryId == id)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    catData.add({
      'name': cat?.name ?? '未知',
      'icon': cat?.icon ?? '💸',
      'amount': amount,
      'pct': s.expense > 0 ? amount / s.expense * 100 : 0,
      'color': _pieColors[i % _pieColors.length],
      'txns': items
          .map((t) => {
                'date': '${t.date.month}月${t.date.day}日',
                'amount': t.amount,
                'note': t.note ?? '',
              })
          .toList(),
    });
  }

  final b = StringBuffer();
  b.writeln('<!DOCTYPE html>');
  b.writeln('<html lang="zh-CN"><head><meta charset="utf-8">');
  b.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">');
  b.writeln('<title>青记 · 账单报告</title>');
  b.writeln('''<style>
  :root { --primary:#0E9E8E; --red:#D9534F; }
  * { box-sizing: border-box; }
  body { margin:0; padding:28px 20px; background:#f5f7f8; color:#233;
         font-family:-apple-system,"PingFang SC","Microsoft YaHei",Helvetica,Arial,sans-serif; }
  .wrap { max-width:860px; margin:0 auto; }
  h1 { font-size:22px; margin:0 0 6px; }
  .sub { color:#6b7785; font-size:13px; margin-bottom:22px; }
  .cards { display:flex; gap:12px; flex-wrap:wrap; margin-bottom:24px; }
  .card { flex:1 1 150px; background:#fff; border-radius:14px; padding:14px 16px;
          box-shadow:0 1px 3px rgba(0,0,0,.06); }
  .card .k { color:#7a8794; font-size:12px; }
  .card .v { font-size:22px; font-weight:700; margin-top:4px; }
  .income { color:var(--primary); } .expense { color:var(--red); }
  h2 { font-size:16px; margin:26px 0 12px; }
  .panel { background:#fff; border-radius:14px; padding:18px;
           box-shadow:0 1px 3px rgba(0,0,0,.06); }
  .pieRow { display:flex; gap:22px; align-items:center; flex-wrap:wrap; }
  .chartBox { flex:0 0 auto; }
  table { border-collapse:collapse; width:100%; font-size:13px; }
  th,td { text-align:left; padding:8px 10px; border-bottom:1px solid #eef1f3; }
  th { color:#7a8794; font-weight:600; font-size:12px; }
  td.amt, th.amt { text-align:right; white-space:nowrap; }
  .dot { display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:8px; }
  .foot { margin-top:22px; color:#8b97a3; font-size:12px; text-align:center; }
  .empty { color:#8b97a3; padding:20px 0; text-align:center; }
  .tip { color:#8b97a3; font-size:12px; margin:0 0 10px; }

  /* ---- 环形图交互 ---- */
  .slice-g { cursor:pointer; transition: transform .32s cubic-bezier(.34,1.2,.64,1); }
  .slice-g .slice { transition: filter .2s ease, opacity .2s ease; }
  .slice-g:hover .slice { filter: brightness(1.08); }
  #slices.has-sel .slice-g:not(.on) .slice { opacity:.55; }
  .lbl { font-size:11.5px; fill:#2C3038; font-weight:600;
         dominant-baseline:middle; }
  .lead { stroke:#DCE1E9; stroke-width:1; fill:none; }
  #centerTop { font-size:11px; fill:#8b97a3; text-anchor:middle; }
  #centerVal { font-size:17px; font-weight:700; fill:#233; text-anchor:middle; }

  /* ---- 柱状趋势（与 App 内同款） ---- */
  .bstat { display:flex; gap:34px; margin:0 0 10px; }
  .bstat .bv { font-size:24px; font-weight:700; letter-spacing:-.3px; }
  .bstat .bk { color:#8b97a3; font-size:12px; margin-top:2px; }
  .barBox { width:100%; }
  .barBox svg { width:100%; height:auto; display:block; }
  .bt-bar { transition: fill .18s ease; }
  .bt-col:hover .bt-bar { fill:#0A84FF; }
  .bt-hit { fill:transparent; }
  .bt-ax { font-size:10px; fill:#AFB6C1; }
  .bt-tip { opacity:0; transition:opacity .15s ease; pointer-events:none; }
  .bt-col:hover .bt-tip { opacity:1; }
  .bt-ind { opacity:0; transition:opacity .15s ease; }
  .bt-col:hover .bt-ind { opacity:1; }
  .bt-t1 { font-size:10.5px; fill:#fff; font-weight:600; text-anchor:middle; }
  .bt-t2 { font-size:10px; fill:#E8EAED; text-anchor:middle; }

  /* ---- 分类列表 ---- */
  .cat-row { cursor:pointer; transition: background .2s ease; }
  .cat-row:hover { background:#f7fafb; }
  .cat-row.on { background:#eefaf8; }
  .cat-row .name { display:flex; align-items:center; gap:8px; }
  .cat-row .chev { color:#c3ccd4; font-size:12px; transition: transform .25s ease; display:inline-block; }
  .cat-row.on .chev { transform: rotate(90deg); color:var(--primary); }

  /* ---- 展开明细 ---- */
  .detail { max-height:0; opacity:0; overflow:hidden;
            transition: max-height .38s cubic-bezier(.4,0,.2,1), opacity .28s ease,
                        margin-top .3s ease; }
  .detail.open { max-height:820px; opacity:1; margin-top:14px; }
  .dbox { border-radius:12px; padding:14px 16px; }
  .dhead { display:flex; align-items:center; gap:10px; margin-bottom:6px; }
  .dhead .t { font-size:15px; font-weight:700; }
  .dhead .s { color:#7a8794; font-size:12px; margin-left:auto; }
  .dlist { margin-top:6px; }
  .ditem { display:flex; align-items:center; gap:10px; padding:7px 0;
           border-bottom:1px dashed rgba(0,0,0,.07); font-size:13px; }
  .ditem:last-child { border-bottom:0; }
  .ditem .d { color:#7a8794; white-space:nowrap; }
  .ditem .n { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .ditem .a { font-weight:600; white-space:nowrap; }
  .fade { transition: opacity .18s ease; }
</style></head><body><div class="wrap">''');

  // 头部
  b.writeln('<h1>青记 · 账单报告</h1>');
  b.writeln(
      '<div class="sub">区间：${_esc(rangeText)} &nbsp;·&nbsp; 共 ${selectedDays} 天 '
      '&nbsp;·&nbsp; ${s.count} 笔记录</div>');

  // 汇总卡
  b.writeln('<div class="cards">');
  b.writeln(
      '<div class="card"><div class="k">收入</div><div class="v income">¥${_money(s.income)}</div></div>');
  b.writeln(
      '<div class="card"><div class="k">支出</div><div class="v expense">¥${_money(s.expense)}</div></div>');
  b.writeln(
      '<div class="card"><div class="k">结余（收入 − 支出）</div><div class="v ${bal >= 0 ? 'income' : 'expense'}">¥${_money(bal)}</div></div>');
  b.writeln('</div>');

  // ---- 柱状趋势（与 App 内「每日支出趋势」同款视觉）----
  final trend = _trendPoints(sorted, rangeStart, rangeEnd);
  b.writeln('<h2>${trend.byMonth ? '各月支出趋势' : '每日支出趋势'}</h2>'
      '<div class="panel">');
  if (trend.points.isEmpty || trend.maxExpense <= 0) {
    b.writeln('<div class="empty">该区间没有支出记录</div>');
  } else {
    // 与 App 一致：日均 / 最高
    b.writeln('<div class="bstat">');
    b.writeln('<div><div class="bv">¥${_money(trend.avgExpense)}</div>'
        '<div class="bk">${trend.byMonth ? '月均' : '日均'}</div></div>');
    b.writeln('<div><div class="bv">¥${_money(trend.maxExpense)}</div>'
        '<div class="bk">${trend.byMonth ? '单月最高' : '单日最高'}</div></div>');
    b.writeln('</div>');
    b.writeln('<div class="barBox">${_barTrendSvg(trend)}</div>');
  }
  b.writeln('</div>');

  // 环形图 + 分类列表
  b.writeln('<h2>支出结构</h2><div class="panel">');
  if (catData.isEmpty || s.expense <= 0) {
    b.writeln('<div class="empty">该区间没有支出记录</div>');
  } else {
    b.writeln('<div class="pieRow">');
    b.writeln('<div class="chartBox">${_donutSvg(catData, s.expense)}</div>');
    b.writeln('<div style="flex:1 1 260px; min-width:250px">');
    b.writeln('<p class="tip">点扇区或下面任意一行,展开该分类明细;再点一次收起</p>');
    b.writeln('<table><tr><th>分类（按占比从高到低）</th>'
        '<th class="amt">金额</th><th class="amt">占比</th><th></th></tr>');
    for (var i = 0; i < catData.length; i++) {
      final c = catData[i];
      b.writeln('<tr class="cat-row" data-i="$i">'
          '<td><span class="name"><span class="dot" style="background:${c['color']}"></span>'
          '${_esc('${c['icon']}')} ${_esc('${c['name']}')}</span></td>'
          '<td class="amt">¥${_money(c['amount'] as double)}</td>'
          '<td class="amt">${(c['pct'] as double).toStringAsFixed(1)}%</td>'
          '<td class="amt"><span class="chev">▶</span></td></tr>');
    }
    b.writeln('</table></div>');
    b.writeln('</div>');

    // 展开的明细容器
    b.writeln('<div class="detail" id="detail"><div class="dbox" id="dbox">'
        '<div class="dhead"><span class="t" id="dtitle"></span>'
        '<span class="s" id="dsub"></span></div>'
        '<div class="dlist" id="dlist"></div></div></div>');
  }
  b.writeln('</div>');

  // 全量明细
  b.writeln('<h2>交易明细</h2><div class="panel">');
  if (sorted.isEmpty) {
    b.writeln('<div class="empty">该区间没有记录</div>');
  } else {
    b.writeln('<table><tr><th>日期</th><th>类型</th><th>分类</th><th>账户</th>'
        '<th class="amt">金额</th><th>备注</th></tr>');
    for (final t in sorted) {
      final cat = findCategory(data.categories, t.categoryId);
      final acc = findAccount(data.accounts, t.accountId);
      final sign = t.type.isExpense ? '-' : '+';
      final cls = t.type.isExpense ? 'expense' : 'income';
      b.writeln('<tr><td>${dateOnly(t.date)}</td>'
          '<td>${_esc(t.type.label)}</td>'
          '<td>${_esc(cat?.name ?? '')}</td>'
          '<td>${_esc(acc?.name ?? '')}</td>'
          '<td class="amt $cls">$sign¥${_money(t.amount)}</td>'
          '<td>${_esc(t.note ?? '')}</td></tr>');
    }
    b.writeln('</table>');
  }
  b.writeln('</div>');

  // 脚注
  final now = DateTime.now();
  final stamp =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  b.writeln('<div class="foot">由「青记」生成于 $stamp</div>');
  b.writeln('</div>');

  // 数据 + 交互脚本
  final json = jsonEncode({
    'total': s.expense,
    'cats': catData,
  }).replaceAll('</', '<\\/');
  b.writeln('<script>');
  b.writeln('var REPORT = $json;');
  b.writeln('''(function () {
  var slices = document.getElementById('slices');
  if (!slices) return;
  var gs   = [].slice.call(document.querySelectorAll('.slice-g'));
  var rows = [].slice.call(document.querySelectorAll('.cat-row'));
  var wrap = slices;
  var detail = document.getElementById('detail');
  var dtitle = document.getElementById('dtitle');
  var dsub   = document.getElementById('dsub');
  var dlist  = document.getElementById('dlist');
  var cTop   = document.getElementById('centerTop');
  var cVal   = document.getElementById('centerVal');
  var total  = REPORT.total;
  var sel = -1;

  function money(v) { return '¥' + v.toFixed(2); }

  function renderCenter(i) {
    if (i < 0) {
      cTop.textContent = '支出总额';
      cVal.textContent = money(total);
    } else {
      var c = REPORT.cats[i];
      cTop.textContent = c.name;
      cVal.textContent = c.pct.toFixed(1) + '%';
    }
  }

  function renderDetail(i) {
    if (i < 0) { detail.classList.remove('open'); return; }
    var c = REPORT.cats[i];
    dtitle.textContent = c.icon + ' ' + c.name;
    dsub.textContent = c.txns.length + ' 笔 · 合计 ' + money(c.amount)
                     + ' · 占支出 ' + c.pct.toFixed(1) + '%';
    var html = '';
    for (var k = 0; k < c.txns.length; k++) {
      var t = c.txns[k];
      html += '<div class="ditem"><span class="d">' + t.date + '</span>' +
              '<span class="n">' + (t.note ? t.note : '无备注') + '</span>' +
              '<span class="a">' + money(t.amount) + '</span></div>';
    }
    dlist.innerHTML = html;
    // 先收起再展开,保证每次点击都有动画
    detail.classList.remove('open');
    void detail.offsetHeight;
    detail.classList.add('open');
  }

  function select(i) {
    sel = (sel === i) ? -1 : i;
    for (var k = 0; k < gs.length; k++) {
      var on = (k === sel);
      gs[k].classList.toggle('on', on);
      gs[k].style.transform = on
        ? 'translate(' + gs[k].getAttribute('data-tx') + 'px,'
                      + gs[k].getAttribute('data-ty') + 'px)'
        : '';
    }
    for (var r = 0; r < rows.length; r++) rows[r].classList.toggle('on', r === sel);
    wrap.classList.toggle('has-sel', sel >= 0);
    renderCenter(sel);
    renderDetail(sel);
  }

  for (var k = 0; k < gs.length; k++) {
    (function (k) {
      gs[k].addEventListener('click', function () { select(k); });
      // 悬停预览(仅未选中时)
      gs[k].addEventListener('mouseenter', function () { if (sel < 0) renderCenter(k); });
      gs[k].addEventListener('mouseleave', function () { if (sel < 0) renderCenter(-1); });
    })(k);
  }
  for (var r = 0; r < rows.length; r++) {
    (function (r) { rows[r].addEventListener('click', function () { select(r); }); })(r);
  }
  renderCenter(-1);
})();''');
  b.writeln('</script>');
  b.writeln('</body></html>');
  return b.toString();
}

/// 环形图：粗环 + 扇区间白缝 + **大扇区外侧标注「名称 百分比」（带折线引导）**。
/// 占比 <5% 不标注（最多 6 个），与 App 内统计页风格一致。
/// 每个扇区仍在 `<g class="slice-g">` 里，支持点击/悬停联动与"向外弹出"动画。
String _donutSvg(List<Map<String, dynamic>> cats, double total) {
  final sb = StringBuffer();
  sb.writeln('<svg viewBox="0 0 ${_svgW.toInt()} ${_svgH.toInt()}" '
      'width="${_svgW.toInt()}" height="${_svgH.toInt()}" '
      'xmlns="http://www.w3.org/2000/svg" role="img">');
  sb.writeln('<g id="slices">');

  final mids = <double>[];
  if (cats.length == 1) {
    // 只有一个分类：整环
    mids.add(0);
    sb.writeln('<g class="slice-g" data-i="0" data-tx="0" data-ty="0">'
        '<circle class="slice" cx="$_cx" cy="$_cy" r="$_rOuter" '
        'fill="${cats[0]['color']}"/></g>');
  } else {
    var start = -math.pi / 2;
    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      final pct = c['pct'] as double;
      final sweep = pct / 100 * 2 * math.pi;
      final end = start + sweep;
      final mid = start + sweep / 2;
      mids.add(mid);

      final x1 = _cx + _rOuter * math.cos(start);
      final y1 = _cy + _rOuter * math.sin(start);
      final x2 = _cx + _rOuter * math.cos(end);
      final y2 = _cy + _rOuter * math.sin(end);
      final large = sweep > math.pi ? 1 : 0;

      // 选中时沿角平分线向外平移
      final tx = 6 * math.cos(mid);
      final ty = 6 * math.sin(mid);

      sb.writeln('<g class="slice-g" data-i="$i" '
          'data-tx="${tx.toStringAsFixed(2)}" '
          'data-ty="${ty.toStringAsFixed(2)}">');
      sb.writeln('<path class="slice" d="M $_cx $_cy '
          'L ${x1.toStringAsFixed(2)} ${y1.toStringAsFixed(2)} '
          'A $_rOuter $_rOuter 0 $large 1 ${x2.toStringAsFixed(2)} ${y2.toStringAsFixed(2)} Z" '
          'fill="${c['color']}" stroke="#ffffff" stroke-width="1.5"/>');
      sb.writeln('</g>');
      start = end;
    }
  }
  sb.writeln('</g>');

  // 中心挖空（环形）
  sb.writeln('<circle cx="$_cx" cy="$_cy" r="$_rInner" fill="#ffffff"/>');

  // ---- 外侧标注（不随扇区位移）----
  final labels = _layoutPieLabels(cats, mids);
  for (final l in labels) {
    final dir = l.isLeft ? -1.0 : 1.0;
    final elbowX = _cx + dir * (_rOuter + 12);
    final tailX = elbowX + dir * 8;
    sb.writeln('<path class="lead" d="M ${l.ax.toStringAsFixed(1)} '
        '${l.ay.toStringAsFixed(1)} L ${elbowX.toStringAsFixed(1)} '
        '${l.y.toStringAsFixed(1)} L ${tailX.toStringAsFixed(1)} '
        '${l.y.toStringAsFixed(1)}"/>');
    final tx = l.isLeft ? tailX - 4 : tailX + 4;
    final anchor = l.isLeft ? ' text-anchor="end"' : '';
    sb.writeln('<text class="lbl" x="${tx.toStringAsFixed(1)}" '
        'y="${l.y.toStringAsFixed(1)}"$anchor>${_esc(l.text)}</text>');
  }

  // 中心文字（悬停/选中时由脚本切换内容）
  sb.writeln('<text id="centerTop" x="$_cx" y="${_cy - 6}">支出总额</text>');
  sb.writeln(
      '<text id="centerVal" x="$_cx" y="${_cy + 16}">¥${_money(total)}</text>');
  sb.writeln('</svg>');
  return sb.toString();
}

class _PieLabel {
  final String text;
  final bool isLeft;
  final double ax, ay; // 弧上的锚点
  double y; // 文字中线的 y
  _PieLabel({
    required this.text,
    required this.isLeft,
    required this.ax,
    required this.ay,
    required this.y,
  });
}

/// 计算外置标注位置：≥5%、最多 6 个，左右分组后按 20px 最小间距推开
List<_PieLabel> _layoutPieLabels(
    List<Map<String, dynamic>> cats, List<double> mids) {
  final out = <_PieLabel>[];
  for (var i = 0; i < cats.length; i++) {
    final pct = cats[i]['pct'] as double;
    if (pct < 5 || out.length >= 6) continue;
    final mid = mids[i];
    final cos = math.cos(mid), sin = math.sin(mid);
    out.add(_PieLabel(
      text: '${cats[i]['name']} ${pct.toStringAsFixed(0)}%',
      isLeft: cos < 0,
      ax: _cx + cos * (_rOuter + 2),
      ay: _cy + sin * (_rOuter + 2),
      y: _cy + sin * (_rOuter + 16),
    ));
  }
  for (final left in [true, false]) {
    final g = out.where((l) => l.isLeft == left).toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    for (var i = 1; i < g.length; i++) {
      if (g[i].y - g[i - 1].y < 20) g[i].y = g[i - 1].y + 20;
    }
    if (g.isEmpty) continue;
    final over = g.last.y - (_svgH - 10);
    if (over > 0) {
      for (final l in g) {
        l.y -= over;
      }
    }
    if (g.first.y < 10) {
      final up = 10 - g.first.y;
      for (final l in g) {
        l.y += up;
      }
    }
  }
  return out;
}

// ==================== 柱状趋势 ====================

class _TrendPoint {
  final DateTime date; // 该柱子对应的日期（按月分桶时是当月 1 号）
  final String label;
  final bool showLabel;
  final String tip;
  final double expense;
  final double income;
  const _TrendPoint({
    required this.date,
    required this.label,
    required this.showLabel,
    required this.tip,
    required this.expense,
    required this.income,
  });
}

class _TrendData {
  final List<_TrendPoint> points;
  final bool byMonth;
  const _TrendData(this.points, this.byMonth);

  double get maxExpense {
    var m = 0.0;
    for (final p in points) {
      if (p.expense > m) m = p.expense;
    }
    return m;
  }

  double get totalExpense => points.fold<double>(0, (a, b) => a + b.expense);

  /// 平均值的分母：区间还没过完时只算"已经过去的格子"（与 App 内口径一致）
  int get elapsedCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final n = points.where((p) => !p.date.isAfter(today)).length;
    return n > 0 ? n : points.length;
  }

  double get avgExpense {
    if (points.isEmpty) return 0;
    final d = elapsedCount;
    return totalExpense / (d < 1 ? 1 : d);
  }
}

/// 按区间生成纵向分桶：≤45 天按天（只标 5 的倍数），否则按月
_TrendData _trendPoints(List<Txn> txns, DateTime? rs, DateTime? re) {
  var start = rs, end = re;
  if (txns.isNotEmpty) {
    start ??= txns.first.date;
    end ??= txns.last.date;
  }
  if (start == null || end == null) return const _TrendData([], false);

  start = DateTime(start.year, start.month, start.day);
  end = DateTime(end.year, end.month, end.day);
  if (end.isBefore(start)) {
    final t = start;
    start = end;
    end = t;
  }
  final days = end.difference(start).inDays + 1;
  final byMonth = days > 45;
  final points = <_TrendPoint>[];

  if (byMonth) {
    var c = DateTime(start.year, start.month, 1);
    while (!c.isAfter(end)) {
      var exp = 0.0, inc = 0.0;
      for (final t in txns) {
        if (t.date.year != c.year || t.date.month != c.month) continue;
        if (t.type.isExpense) {
          exp += t.amount;
        } else {
          inc += t.amount;
        }
      }
      points.add(_TrendPoint(
        date: c,
        label: '${c.month}',
        showLabel: true,
        tip: '${c.year}年${c.month}月',
        expense: exp,
        income: inc,
      ));
      c = DateTime(c.year, c.month + 1, 1);
    }
  } else {
    for (var k = 0; k < days; k++) {
      final d = DateTime(start.year, start.month, start.day + k);
      var exp = 0.0, inc = 0.0;
      for (final t in txns) {
        if (t.date.year != d.year ||
            t.date.month != d.month ||
            t.date.day != d.day) {
          continue;
        }
        if (t.type.isExpense) {
          exp += t.amount;
        } else {
          inc += t.amount;
        }
      }
      points.add(_TrendPoint(
        date: d,
        label: '${d.day}',
        showLabel: days <= 14 || d.day % 5 == 0,
        tip: '${d.month}月${d.day}日',
        expense: exp,
        income: inc,
      ));
    }
  }
  return _TrendData(points, byMonth);
}

/// 柱状趋势 SVG：浅色圆角柱 + 横向虚线网格 + 右侧刻度 + 悬停深色浮窗
String _barTrendSvg(_TrendData t) {
  const w = 760.0, h = 210.0;
  const padL = 8.0, padR = 44.0, padT = 34.0, padB = 22.0;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  final (step, maxY) = _niceScale(t.maxExpense);
  final n = t.points.length;
  final slot = plotW / n;
  final barW = math.min(slot * 0.55, 16.0);

  final sb = StringBuffer();
  sb.writeln('<svg viewBox="0 0 ${w.toInt()} ${h.toInt()}" '
      'xmlns="http://www.w3.org/2000/svg" role="img">');

  // 横向虚线网格 + 右侧刻度
  for (var k = 0; k <= 4; k++) {
    final v = step * k;
    final y = padT + plotH - (v / maxY) * plotH;
    sb.writeln('<line x1="$padL" y1="${y.toStringAsFixed(1)}" '
        'x2="${(w - padR).toStringAsFixed(1)}" y2="${y.toStringAsFixed(1)}" '
        'stroke="#EDF1F5" stroke-width="1" stroke-dasharray="4 4"/>');
    sb.writeln('<text class="bt-ax" x="${(w - padR + 8).toStringAsFixed(1)}" '
        'y="${y.toStringAsFixed(1)}" dominant-baseline="middle">'
        '${_axisLabel(v)}</text>');
  }

  for (var i = 0; i < n; i++) {
    final p = t.points[i];
    final cx = padL + slot * (i + 0.5);
    final bh = maxY <= 0 ? 0.0 : (p.expense / maxY) * plotH;
    final top = padT + plotH - bh;

    sb.writeln('<g class="bt-col">');
    // 悬停热区（覆盖整列，好点中）
    sb.writeln('<rect class="bt-hit" x="${(cx - slot / 2).toStringAsFixed(1)}" '
        'y="$padT" width="${slot.toStringAsFixed(1)}" '
        'height="${plotH.toStringAsFixed(1)}"/>');
    if (bh > 0) {
      sb.writeln('<line class="bt-ind" x1="${cx.toStringAsFixed(1)}" y1="$padT" '
          'x2="${cx.toStringAsFixed(1)}" y2="${(top - 2).toStringAsFixed(1)}" '
          'stroke="#9AA4B2" stroke-width="1" stroke-dasharray="4 4"/>');
      sb.writeln('<rect class="bt-bar" '
          'x="${(cx - barW / 2).toStringAsFixed(1)}" '
          'y="${top.toStringAsFixed(1)}" width="${barW.toStringAsFixed(1)}" '
          'height="${bh.toStringAsFixed(1)}" rx="3" fill="#BFE0F7"/>');
    }

    // 浮窗
    final lines = <String>[p.tip, '支出 ¥${_money(p.expense)}'];
    if (p.income > 0) lines.add('收入 ¥${_money(p.income)}');
    const tipW = 96.0;
    final tipH = 12.0 + lines.length * 13.0;
    var tx = cx - tipW / 2;
    if (tx < padL) tx = padL;
    if (tx + tipW > w - 4) tx = w - 4 - tipW;
    var ty = top - tipH - 8;
    if (ty < 2) ty = 2;
    sb.writeln('<g class="bt-tip">');
    sb.writeln('<rect x="${tx.toStringAsFixed(1)}" '
        'y="${ty.toStringAsFixed(1)}" width="$tipW" '
        'height="${tipH.toStringAsFixed(1)}" rx="8" fill="#1C1C1E"/>');
    for (var k = 0; k < lines.length; k++) {
      final ly = ty + 13 + k * 13;
      sb.writeln('<text class="${k == 0 ? 'bt-t1' : 'bt-t2'}" '
          'x="${(tx + tipW / 2).toStringAsFixed(1)}" '
          'y="${ly.toStringAsFixed(1)}">${_esc(lines[k])}</text>');
    }
    sb.writeln('</g>');
    sb.writeln('</g>');

    // 横轴标签
    if (p.showLabel) {
      sb.writeln('<text class="bt-ax" x="${cx.toStringAsFixed(1)}" '
          'y="${(h - 6).toStringAsFixed(1)}" text-anchor="middle">'
          '${_esc(p.label)}</text>');
    }
  }

  sb.writeln('</svg>');
  return sb.toString();
}

/// 纵轴"整刻度"：4 格，步长取 1/2/5/10 × 10^n
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

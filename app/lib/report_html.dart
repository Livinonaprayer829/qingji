import 'dart:convert';
import 'dart:math' as math;

import 'csv_rows.dart';
import 'models.dart';
import 'repository.dart';
import 'utils.dart';

/// 图表配色（与统计页保持一致）
const _pieColors = [
  '#4285F4',
  '#FF9800',
  '#4CAF50',
  '#9C27B0',
  '#F44336',
  '#009688',
  '#FFC107',
  '#E91E63',
];

const _cx = 110.0;
const _cy = 110.0;
const _rOuter = 92.0;
const _rInner = 58.0; // 环形内圈半径
const _rLabel = 75.0; // 百分比标注所在半径

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

  /* ---- 饼图交互 ---- */
  .slice-g { cursor:pointer; transition: transform .32s cubic-bezier(.34,1.2,.64,1); }
  .slice-g .slice { transition: filter .2s ease, opacity .2s ease; }
  .slice-g:hover .slice { filter: brightness(1.08); }
  #slices.has-sel .slice-g:not(.on) .slice { opacity:.55; }
  .pct { font-size:11px; font-weight:700; fill:#fff; pointer-events:none;
         text-anchor:middle; dominant-baseline:middle; }
  #centerTop { font-size:11px; fill:#8b97a3; text-anchor:middle; }
  #centerVal { font-size:18px; font-weight:700; fill:#233; text-anchor:middle; }

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

  // 饼图 + 分类列表
  b.writeln('<h2>支出分类占比</h2><div class="panel">');
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

/// 环形饼图：每个扇区（含百分比标注）包在 `<g class="slice-g">` 里,
/// 由脚本按 `data-tx/data-ty` 做"选中弹出"位移,实现流畅动画。
String _donutSvg(List<Map<String, dynamic>> cats, double total) {
  final sb = StringBuffer();
  sb.writeln('<svg viewBox="0 0 220 220" width="220" height="220" '
      'xmlns="http://www.w3.org/2000/svg" role="img">');
  sb.writeln('<g id="slices">');

  if (cats.length == 1) {
    // 只有一个分类:整圆
    sb.writeln('<g class="slice-g" data-i="0" data-tx="0" data-ty="0">');
    sb.writeln(
        '<circle cx="$_cx" cy="$_cy" r="$_rOuter" fill="${cats[0]['color']}"/>');
    sb.writeln('</g>');
  } else {
    var start = -math.pi / 2;
    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      final pct = c['pct'] as double;
      final sweep = pct / 100 * 2 * math.pi;
      final end = start + sweep;
      final mid = start + sweep / 2;

      final x1 = _cx + _rOuter * math.cos(start);
      final y1 = _cy + _rOuter * math.sin(start);
      final x2 = _cx + _rOuter * math.cos(end);
      final y2 = _cy + _rOuter * math.sin(end);
      final large = sweep > math.pi ? 1 : 0;

      // 选中时沿角平分线向外平移
      final tx = 10 * math.cos(mid);
      final ty = 10 * math.sin(mid);

      sb.writeln('<g class="slice-g" data-i="$i" '
          'data-tx="${tx.toStringAsFixed(2)}" data-ty="${ty.toStringAsFixed(2)}">');
      sb.writeln('<path class="slice" d="M $_cx $_cy '
          'L ${x1.toStringAsFixed(2)} ${y1.toStringAsFixed(2)} '
          'A $_rOuter $_rOuter 0 $large 1 ${x2.toStringAsFixed(2)} ${y2.toStringAsFixed(2)} Z" '
          'fill="${c['color']}" stroke="#ffffff" stroke-width="1.5"/>');
      // 占比 ≥5% 才标注,避免拥挤
      if (pct >= 5) {
        final lx = _cx + _rLabel * math.cos(mid);
        final ly = _cy + _rLabel * math.sin(mid);
        sb.writeln('<text class="pct" x="${lx.toStringAsFixed(1)}" '
            'y="${ly.toStringAsFixed(1)}">${pct.toStringAsFixed(0)}%</text>');
      }
      sb.writeln('</g>');
      start = end;
    }
  }
  sb.writeln('</g>');

  // 中心挖空(环形) + 中心文字
  sb.writeln(
      '<circle cx="$_cx" cy="$_cy" r="$_rInner" fill="#ffffff"/>');
  sb.writeln('<text id="centerTop" x="$_cx" y="${_cy - 6}">支出总额</text>');
  sb.writeln(
      '<text id="centerVal" x="$_cx" y="${_cy + 16}">¥${_money(total)}</text>');
  sb.writeln('</svg>');
  return sb.toString();
}

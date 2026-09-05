import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/txn_tile.dart';
import '../widgets/transaction_form.dart';

/// 某一天的详情面板：实时列出当天所有记录，支持新增 / 编辑 / 删除。
/// 任何日期（含过去的空日子）都可打开，满足"过往日期也可增删改"。
class DayDetailSheet extends ConsumerStatefulWidget {
  final DateTime day;
  const DayDetailSheet({super.key, required this.day});

  @override
  ConsumerState<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends ConsumerState<DayDetailSheet> {
  void _edit(Txn t) {
    // 不关闭日详情，直接在其上叠开编辑表单；保存后日详情会因 watch 自动刷新
    showTxnForm(context, editing: t);
  }

  Future<void> _delete(Txn t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这笔记录？'),
        content: Text(
            '${t.type.label} ¥${t.amount.toStringAsFixed(2)} 将被永久删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(appDataProvider.notifier).deleteTx(t.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final dayTxns = data.transactions
        .where((t) =>
            t.date.year == widget.day.year &&
            t.date.month == widget.day.month &&
            t.date.day == widget.day.day)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    double exp = 0, inc = 0;
    for (final t in dayTxns) {
      if (t.type.isExpense) {
        exp += t.amount;
      } else {
        inc += t.amount;
      }
    }

    final dateStr =
        '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dateStr,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 18)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '支出 ¥${exp.toStringAsFixed(2)}   收入 ¥${inc.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          if (dayTxns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('这一天还没有记录',
                      style: TextStyle(color: Colors.grey))),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: dayTxns.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final t = dayTxns[i];
                  return Row(
                    children: [
                      Expanded(
                        child: TxnTile(
                          txn: t,
                          onTap: () => _edit(t),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _delete(t),
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        tooltip: '删除',
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showTxnForm(context, initialDate: widget.day),
              icon: const Icon(Icons.add),
              label: const Text('添加记录'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

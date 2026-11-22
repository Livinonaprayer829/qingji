import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';

void showTxnForm(BuildContext context, {Txn? editing, DateTime? initialDate}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: TxnForm(editing: editing, initialDate: initialDate),
    ),
  );
}

class TxnForm extends ConsumerStatefulWidget {
  final Txn? editing;
  final DateTime? initialDate;
  const TxnForm({super.key, this.editing, this.initialDate});
  @override
  ConsumerState<TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends ConsumerState<TxnForm> {
  late TxType _type;
  late String _categoryId;
  String? _accountId;
  final _amountCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final data = ref.read(appDataProvider);
    if (e != null) {
      _type = e.type;
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _amountCtl.text = e.amount.toStringAsFixed(2);
      _noteCtl.text = e.note ?? '';
      _date = e.date;
    } else {
      _type = TxType.expense;
      final expenses =
          data.categories.where((c) => c.type == TxType.expense).toList();
      // 默认分类：第一个支出分类（购物）
      _categoryId = expenses.isEmpty
          ? data.categories.first.id
          : expenses.first.id;
      // 再按当前时段自动换成 早餐 / 午餐 / 晚餐（不在时段内就保持上面的默认）
      final timed = _timeBasedCategoryId(expenses);
      if (timed != null) _categoryId = timed;
      _accountId = data.accounts.isNotEmpty ? data.accounts.first.id : null;
      // 预填全局默认账户;未设置(或该账户已不存在)时沿用原逻辑:取第一个账户
      final def = ref.read(defaultAccountProvider);
      if (def != null && data.accounts.any((a) => a.id == def)) {
        _accountId = def;
      }
      _date = widget.initialDate ?? DateTime.now();
    }
  }

  /// 按**当前小时**挑默认分类：
  /// - 6~10 点 ⇒ 早餐
  /// - 11~14 点 ⇒ 午餐
  /// - 16~22 点 ⇒ 晚餐
  /// - 其余时段（15 点、23 点、凌晨）⇒ **购物**
  ///
  /// 注意：这里对"购物"是**按名字显式指定**的，不能依赖"分类列表第一个"，
  /// 因为本地/云端存下来的分类顺序并不固定（实测第一个可能是「其他」）。
  ///
  /// 找不到对应分类（用户改名/删掉）时返回 null，调用方继续用原默认。
  String? _timeBasedCategoryId(List<Category> expenses) {
    final h = DateTime.now().hour;
    final String want;
    if (h >= 6 && h <= 10) {
      want = '早餐';
    } else if (h >= 11 && h <= 14) {
      want = '午餐';
    } else if (h >= 16 && h <= 22) {
      want = '晚餐';
    } else {
      want = '购物';
    }

    for (final c in expenses) {
      if (c.name == want) return c.id;
    }
    // 改名了也尽量命中（例如"早餐(自制)"）
    for (final c in expenses) {
      if (c.name.contains(want)) return c.id;
    }
    return null;
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  List<Category> get _cats =>
      ref.read(appDataProvider).categories.where((c) => c.type == _type).toList();

  /// 账户下拉:直接把所有账户列出来(包含「支付宝（余额）/ 支付宝（花呗）」两个渠道),
  /// 不做任何二级弹窗/展开——真机上最稳、最少意外。
  List<DropdownMenuItem<String>> _dropdownItems(List<Account> all) {
    return all
        .map((a) => DropdownMenuItem(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis),
            ))
        .toList();
  }

  void _onAccountChanged(String? v) {
    if (v == null) return;
    setState(() => _accountId = v);
  }

  void _save() {
    final amt = double.tryParse(_amountCtl.text);
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入有效金额')));
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先添加账户')));
      return;
    }
    final note = _noteCtl.text.trim();
    final txn = Txn(
      id: widget.editing?.id,
      amount: amt,
      type: _type,
      categoryId: _categoryId,
      accountId: _accountId!,
      date: _date,
      note: note.isEmpty ? null : note,
    );
    final notifier = ref.read(appDataProvider.notifier);
    if (widget.editing != null) {
      notifier.updateTx(txn);
    } else {
      notifier.addTx(txn);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(appDataProvider).accounts;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          SegmentedButton<TxType>(
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() {
                _type = s.first;
                final list = _cats;
                if (list.isNotEmpty) _categoryId = list.first.id;
              });
            },
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('支出')),
              ButtonSegment(value: TxType.income, label: Text('收入')),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('分类', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cats
                .map((c) => ChoiceChip(
                      label: Text('${c.icon} ${c.name}'),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          // 点账户栏先收起键盘,避免键盘遮住下拉弹层
          Listener(
            onPointerDown: (_) => FocusScope.of(context).unfocus(),
            child: DropdownButtonFormField<String>(
              value: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: '账户', border: OutlineInputBorder()),
              items: _dropdownItems(accounts),
              onChanged: _onAccountChanged,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: '日期', border: OutlineInputBorder()),
              child: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtl,
            decoration: const InputDecoration(
                labelText: '备注（可选）', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

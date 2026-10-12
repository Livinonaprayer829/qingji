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
      _categoryId = data.categories
              .where((c) => c.type == TxType.expense)
              .isEmpty
          ? data.categories.first.id
          : data.categories.firstWhere((c) => c.type == TxType.expense).id;
      _accountId = data.accounts.isNotEmpty ? data.accounts.first.id : null;
      _date = widget.initialDate ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  List<Category> get _cats =>
      ref.read(appDataProvider).categories.where((c) => c.type == _type).toList();

  /// 下拉里展示的账户:隐藏支付宝的两个子渠道(它们由「支付宝」二级选择进入);
  /// 但当前选中的若是子渠道,则补进列表,保证 Dropdown 的 value 能匹配到项。
  List<DropdownMenuItem<String>> _dropdownItems(List<Account> all) {
    final list = all.where((a) => !AlipayAccounts.isChannel(a.id)).toList();
    for (final a in all) {
      if (a.id == _accountId && !list.any((x) => x.id == a.id)) {
        list.add(a);
      }
    }
    return list
        .map((a) => DropdownMenuItem(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis),
            ))
        .toList();
  }

  /// 选中「支付宝」时先弹二级渠道选择;其他账户直接切换。
  Future<void> _onAccountChanged(String? v) async {
    if (v == null) return;
    if (v != AlipayAccounts.parentId) {
      setState(() => _accountId = v);
      return;
    }
    final picked = await _pickAlipayChannel();
    if (picked != null && mounted) {
      setState(() => _accountId = picked);
    }
  }

  /// 二级选项:支付宝余额 / 花呗。返回选中的账户 id,取消则返回 null。
  Future<String?> _pickAlipayChannel() async {
    final accounts = ref.read(appDataProvider).accounts;
    String? idOf(String name) {
      for (final a in accounts) {
        if (a.name == name) return a.id;
      }
      return null;
    }

    final balanceId = idOf(AlipayAccounts.balanceName);
    final huabeiId = idOf(AlipayAccounts.huabeiName);
    if (balanceId == null && huabeiId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账户数据未就绪,请稍后再试')));
      return null;
    }

    final primary = Theme.of(context).colorScheme.primary;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('支付宝 · 选择支付渠道',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            Text('选完后账户记为「支付宝-余额 / 支付宝-花呗」',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            if (balanceId != null)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: primary.withOpacity(0.12),
                  child: const Text('💳', style: TextStyle(fontSize: 18)),
                ),
                title: const Text('余额'),
                subtitle: const Text('支付宝余额支付'),
                onTap: () => Navigator.of(ctx).pop(balanceId),
              ),
            if (huabeiId != null)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: primary.withOpacity(0.12),
                  child: const Text('🧾', style: TextStyle(fontSize: 18)),
                ),
                title: const Text('花呗'),
                subtitle: const Text('先用后付'),
                onTap: () => Navigator.of(ctx).pop(huabeiId),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
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
          DropdownButtonFormField<String>(
            value: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: '账户', border: OutlineInputBorder()),
            items: _dropdownItems(accounts),
            onChanged: _onAccountChanged,
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

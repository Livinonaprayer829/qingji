import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';

void showLoanForm(BuildContext context, {Loan? editing, LoanType? initialType}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: LoanForm(editing: editing, initialType: initialType),
    ),
  );
}

class LoanForm extends ConsumerStatefulWidget {
  final Loan? editing;
  final LoanType? initialType;
  const LoanForm({super.key, this.editing, this.initialType});

  @override
  ConsumerState<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<LoanForm> {
  late LoanType _type;
  final _personCtl = TextEditingController();
  final _amountCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  late DateTime _date;
  DateTime? _dueDate;
  late bool _repaid;

  // 当从筛选页点 + 带入 initialType 时,锁定该类型(不显示另一个、不可切换)
  bool get _locked => widget.initialType != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _type = widget.initialType ?? e?.type ?? LoanType.borrowOut;
    _personCtl.text = e?.person ?? '';
    _amountCtl.text = e?.amount.toString() ?? '';
    _noteCtl.text = e?.note ?? '';
    _date = e?.date ?? DateTime.now();
    _dueDate = e?.dueDate;
    _repaid = e?.repaid ?? false;
  }

  @override
  void dispose() {
    _personCtl.dispose();
    _amountCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isDue) async {
    final initial = isDue ? (_dueDate ?? _date) : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isDue) {
          _dueDate = picked;
        } else {
          _date = picked;
        }
      });
    }
  }

  void _save() {
    final person = _personCtl.text.trim();
    final amount = double.tryParse(_amountCtl.text.trim());
    if (person.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写对方姓名')));
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写有效金额')));
      return;
    }
    final loan = Loan(
      id: widget.editing?.id,
      type: _type,
      person: person,
      amount: amount,
      date: _date,
      dueDate: _dueDate,
      repaid: _repaid,
      repaidDate: _repaid ? (widget.editing?.repaidDate ?? DateTime.now()) : null,
      note: _noteCtl.text.trim().isEmpty ? null : _noteCtl.text.trim(),
    );
    if (widget.editing == null) {
      ref.read(appDataProvider.notifier).addLoan(loan);
    } else {
      ref.read(appDataProvider.notifier).updateLoan(loan);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isEditing ? '编辑记录' : '记一笔借还',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const SizedBox(height: 14),
          if (_locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _type == LoanType.borrowOut ? '借出(别人欠我)' : '借入(我欠别人)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 15),
                  ),
                ],
              ),
            )
          else
            SegmentedButton<LoanType>(
              segments: const [
                ButtonSegment(
                    value: LoanType.borrowOut, label: Text('借出(别人欠我)')),
                ButtonSegment(
                    value: LoanType.borrowIn, label: Text('借入(我欠别人)')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _personCtl,
            decoration: const InputDecoration(
                labelText: '对方姓名', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: '金额', prefixText: '¥ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _DateTile(
              label: '借入/借出日期',
              date: _date,
              onTap: () => _pickDate(false)),
          const SizedBox(height: 8),
          _DateTile(
              label: '约定还款日期(可选)',
              date: _dueDate,
              onTap: () => _pickDate(true),
              onClear: _dueDate == null
                  ? null
                  : () => setState(() => _dueDate = null)),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtl,
            decoration: const InputDecoration(
                labelText: '备注(可选)', border: OutlineInputBorder()),
          ),
          if (isEditing) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _repaid,
              title: const Text('已还清'),
              onChanged: (v) => setState(() => _repaid = v ?? false),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(isEditing ? '保存' : '添加')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateTile(
      {required this.label, required this.date, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(
                    date == null
                        ? '未设置'
                        : '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              TextButton(onPressed: onClear, child: const Text('清除')),
            const Icon(Icons.calendar_month_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../widgets/loan_form.dart';

class LoanScreen extends ConsumerStatefulWidget {
  const LoanScreen({super.key});

  @override
  ConsumerState<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends ConsumerState<LoanScreen> {
  // 0=全部 1=借出(别人欠我) 2=借入(我欠别人)
  int _filter = 0;

  List<Loan> _filtered(List<Loan> all) {
    if (_filter == 1) {
      return all.where((l) => l.type == LoanType.borrowOut).toList();
    }
    if (_filter == 2) {
      return all.where((l) => l.type == LoanType.borrowIn).toList();
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final loans = _filtered(data.loans)
      ..sort((a, b) => b.date.compareTo(a.date));

    final owe = data.loans
        .where((l) => l.type == LoanType.borrowIn && !l.repaid)
        .fold(0.0, (s, l) => s + l.amount); // 我欠别人
    final lent = data.loans
        .where((l) => l.type == LoanType.borrowOut && !l.repaid)
        .fold(0.0, (s, l) => s + l.amount); // 别人欠我

    return Scaffold(
      body: Column(
        children: [
          // 汇总卡
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: '我欠别人',
                    amount: owe,
                    color: Colors.redAccent,
                    icon: Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: '别人欠我',
                    amount: lent,
                    color: Colors.green,
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
          ),
          // 筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('全部')),
                ButtonSegment(value: 1, label: Text('借出')),
                ButtonSegment(value: 2, label: Text('借入')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loans.isEmpty
                ? const Center(child: Text('还没有记录,点右下角 + 添加'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: loans.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _LoanTile(
                      loan: loans[i],
                      onTap: () => showLoanForm(context, editing: loans[i]),
                      onDelete: () => _confirmDelete(loans[i]),
                      onToggleRepaid: () => _toggleRepaid(loans[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => showLoanForm(
          context,
          initialType: _filter == 1
              ? LoanType.borrowOut
              : (_filter == 2 ? LoanType.borrowIn : null),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(Loan loan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这条记录?'),
        content: Text('${loan.type.label} · ${loan.person} · ¥${loan.amount}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(appDataProvider.notifier).deleteLoan(loan.id);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _toggleRepaid(Loan loan) {
    final updated = loan.copyWith(
      repaid: !loan.repaid,
      repaidDate: !loan.repaid ? DateTime.now() : null,
      updatedAt: DateTime.now(),
    );
    ref.read(appDataProvider.notifier).updateLoan(updated);
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  const _SummaryCard(
      {required this.title, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(color: color, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Text('¥${amount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const Text('未还清', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _LoanTile extends StatelessWidget {
  final Loan loan;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleRepaid;

  const _LoanTile(
      {required this.loan,
      required this.onTap,
      required this.onDelete,
      required this.onToggleRepaid});

  bool get _overdue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !loan.repaid &&
        loan.dueDate != null &&
        loan.dueDate!.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    final isOut = loan.type == LoanType.borrowOut;
    final color = isOut ? Colors.green : Colors.redAccent;
    final d = loan.date;
    final due = loan.dueDate;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(isOut ? Icons.arrow_upward : Icons.arrow_downward,
            color: color, size: 18),
      ),
      title: Row(
        children: [
          Text(loan.person, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(loan.type.label,
                style: TextStyle(fontSize: 11, color: color)),
          ),
          if (loan.repaid)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('已还', style: TextStyle(fontSize: 11)),
            )
          else if (_overdue)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('逾期', style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¥${loan.amount.toStringAsFixed(2)}'
              '  ·  ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
              '${loan.note != null && loan.note!.isNotEmpty ? '  · ${loan.note}' : ''}'),
          if (due != null)
            Text(
              '约定还款: ${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(loan.repaid ? Icons.refresh : Icons.check_circle_outline,
                color: loan.repaid ? Colors.grey : Colors.green),
            tooltip: loan.repaid ? '标记未还' : '标记已还',
            onPressed: onToggleRepaid,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

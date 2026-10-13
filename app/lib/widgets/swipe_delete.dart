import 'package:flutter/material.dart';

/// 统一的「左滑删除」包装：
/// 从右往左滑动露出红色删除背景,松手前先弹确认框,确认后才真正删除。
/// 概览的最近记录、账单列表、账户详情流水都用它,保证交互一致。
class SwipeDelete extends StatelessWidget {
  final String message;
  final VoidCallback onDelete;
  final Widget child;

  const SwipeDelete({
    super.key,
    required this.message,
    required this.onDelete,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(message),
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
      },
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }
}

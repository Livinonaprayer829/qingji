import 'package:flutter/material.dart';

import 'calendar_screen.dart';

/// 独立日历页（从统计页 push 进入）。
///
/// - 左上角自带返回按钮（AppBar），点返回到统计页
/// - **永远是月视图**，并用 [initialMonth] 定位到指定月份
class CalendarPage extends StatelessWidget {
  /// 要定位到的月份（只会取 year/month，日会被忽略）
  final DateTime initialMonth;

  const CalendarPage({super.key, required this.initialMonth});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日历')),
      body: CalendarScreen(initialMonth: initialMonth),
    );
  }
}

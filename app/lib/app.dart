import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/loan_screen.dart';
import 'widgets/transaction_form.dart';
import 'widgets/loan_form.dart';
import 'widgets/update_dialog.dart';
import 'update_config.dart';
import 'update_service.dart';

class DakaApp extends StatefulWidget {
  const DakaApp({super.key});
  @override
  State<DakaApp> createState() => _DakaAppState();
}

class _DakaAppState extends State<DakaApp> {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    // 首帧渲染完再检测,避免弹窗和启动画面抢焦点
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
  }

  /// 启动时静默检测更新:没有新版本就完全无感;有则弹窗。
  /// 同一版本一天只提示一次,免得每次开 App 都弹。
  Future<void> _autoCheckUpdate() async {
    if (!UpdateConfig.enabled) return;
    if (!mounted) return;

    final info = await UpdateService().checkForUpdate();
    if (info == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'update_prompt_${info.version}';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(key) == today) return; // 今天已提示过这个版本
    await prefs.setString(key, today);

    if (!mounted) return;
    await showUpdateDialog(context, info);
  }

  final _pages = const [
    HomeScreen(),
    HistoryScreen(),
    CalendarScreen(),
    StatsScreen(),
    SettingsScreen(),
    LoanScreen(),
  ];
  final _titles = const ['概览', '账单', '日历', '统计', '我的', '借还'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_idx])),
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '概览'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: '账单'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '日历'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: '统计'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
          NavigationDestination(
              icon: Icon(Icons.swap_horiz_outlined),
              selectedIcon: Icon(Icons.swap_horiz),
              label: '借还'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          if (_idx == 5) {
            showLoanForm(context);
          } else {
            showTxnForm(context);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

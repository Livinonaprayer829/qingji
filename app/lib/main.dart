import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// 青记主题色(青绿)
  static const Color seed = Color(0xFF0E9E8E);
  static const Color surfaceBg = Color(0xFFF2F7F6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青记记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: surfaceBg,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
          elevation: 2,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shadowColor: Colors.black.withOpacity(0.06),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.black87,
          titleTextStyle: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: seed.withOpacity(0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 4,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: seed.withOpacity(0.1),
          labelStyle: const TextStyle(color: Colors.black87),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        listTileTheme: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16)),
        dividerTheme: DividerThemeData(
            color: Colors.grey.shade200, thickness: 1, space: 1),
      ),
      home: const AuthGate(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../providers.dart';

/// 登录守卫:未登录显示登录页,已登录显示主页。
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  final _client = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(offlineModeProvider);
    return StreamBuilder<AuthState>(
      stream: _client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        _client.auth.currentSession,
      ),
      builder: (context, snap) {
        final session = snap.data?.session;
        if (session != null || offline) return const DakaApp();
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtl = TextEditingController();
  final _pwdCtl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  String? _info;
  bool _needConfirm = false;

  /// 是否为「网络类」错误(可重试);账号密码错等业务错误不重试。
  bool _isNetworkError(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Connection reset') ||
        s.contains('Connection refused') ||
        s.contains('Failed host lookup') ||
        s.contains('TimeoutException') ||
        s.contains('connection closed') ||
        s.contains('Connection closed');
  }

  String _friendly(Object e) {
    if (_isNetworkError(e)) {
      return '网络连接失败(连接被重置),请检查网络或开启代理后重试。\n'
          '若暂时无法联网,可先用「离线模式」记账,联网后再登录同步。';
    }
    return '出错了: $e';
  }

  Future<void> _authOnce(String email, String pwd) async {
    final client = Supabase.instance.client;
    if (_isLogin) {
      await client.auth.signInWithPassword(email: email, password: pwd);
    } else {
      final res = await client.auth.signUp(email: email, password: pwd);
      if (res.session == null) _needConfirm = true;
    }
  }

  Future<void> _submit() async {
    final email = _emailCtl.text.trim();
    final pwd = _pwdCtl.text;
    if (email.isEmpty || pwd.length < 6) {
      setState(() => _error = '请输入邮箱,密码至少 6 位');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
      _needConfirm = false;
    });
    try {
      // 连接被重置多为偶发,自动重试一次;账号密码错不重试。
      var attempt = 0;
      while (true) {
        try {
          await _authOnce(email, pwd);
          break;
        } catch (e) {
          if (_isNetworkError(e) && attempt < 1) {
            attempt++;
            await Future.delayed(const Duration(milliseconds: 900));
            continue;
          }
          rethrow;
        }
      }

      if (_needConfirm) {
        setState(() => _info = '注册成功!请查收验证邮件并点击链接,然后回来登录。');
        return;
      }
      // 登录/注册成功:若本页是被 push 进来的(例如从「数据同步」页点「去登录」进入),
      // 就自动返回上一页;若本页是 AuthGate 的 home,则无需 pop,由 AuthGate 切到主页。
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      setState(() => _error = _isNetworkError(e) ? _friendly(e) : e.message);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 76,
                    height: 76,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 14),
                Text(_isLogin ? '登录 青记' : '注册 青记',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('青记·简约清爽',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: '邮箱', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '密码(至少6位)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13)),
                if (_info != null)
                  Text(_info!, style: TextStyle(color: Colors.green.shade700)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isLogin ? '登录' : '注册'),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin ? '没有账号?去注册' : '已有账号?去登录'),
                ),
                Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: _loading
                        ? null
                        : () => ref.read(offlineModeProvider.notifier).state =
                            true,
                    child: Text('先用离线模式(跳过登录)',
                        style: TextStyle(color: primary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

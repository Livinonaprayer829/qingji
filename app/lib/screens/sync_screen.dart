import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart';
import '../repository.dart';
import 'auth_screen.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  AppData? _cloud;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCloud();
  }

  bool get _signedIn => Supabase.instance.client.auth.currentSession != null;

  Future<void> _loadCloud() async {
    if (!_signedIn) return;
    setState(() => _loading = true);
    final cloud = await ref.read(repositoryProvider).fetchCloud();
    if (mounted) {
      setState(() {
        _cloud = cloud;
        _loading = false;
      });
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s)));
  }

  Future<bool?> _confirm(String title, String msg) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _incremental() async {
    setState(() => _loading = true);
    try {
      await ref.read(appDataProvider.notifier).syncIncremental();
      await _loadCloud();
      final loansErr = ref.read(appDataProvider.notifier).lastLoansError;
      if (mounted) {
        if (loansErr != null) {
          final missing =
              loansErr.contains('does not exist') || loansErr.contains('relation');
          _toast(missing
              ? '记账已同步;借还失败:云端 loans 表未创建,请在 Supabase 执行建表 SQL'
              : '记账已同步;借还失败: $loansErr');
        } else {
          _toast('同步完成');
        }
      }
    } catch (e) {
      if (mounted) _toast('同步失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forceUpload() async {
    final ok = await _confirm(
        '强制覆盖上传', '将本机的所有数据全量推送到云端(覆盖云端同 id 的记录)。继续?');
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await ref.read(appDataProvider.notifier).forceUpload();
      await _loadCloud();
      if (mounted) _toast('已覆盖上传');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final ok =
        await _confirm('从云端下载', '将丢弃本地未同步的数据,以云端为准。确定?');
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await ref.read(appDataProvider.notifier).downloadFromCloud();
      if (mounted) _toast('已从云端下载');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm('退出登录',
        '退出后本地数据保留,可在离线模式下继续使用,或重新登录合并。');
    if (ok != true) return;
    await ref.read(appDataProvider.notifier).signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final data = ref.watch(appDataProvider);
    final signedIn = session != null;
    final localCount = data.transactions.length;
    final cloudCount = _cloud?.transactions.length ?? (signedIn ? -1 : 0);

    const accent = Color(0xFF66FFCC);
    const cardBg = Color(0xFF12332A);
    const danger = Color(0xFFE3A0FF);

    return Scaffold(
      appBar: AppBar(title: const Text('数据 · 同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cardBg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(signedIn ? Icons.cloud : Icons.cloud_off,
                        color: signedIn ? accent : Colors.grey, size: 32),
                    const SizedBox(width: 12),
                    Text(signedIn ? '已连接云端' : '未登录',
                        style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (signedIn)
                      const Chip(
                        label: Text('空闲'),
                        backgroundColor: Colors.white24,
                        labelStyle: TextStyle(color: Colors.white),
                      ),
                  ]),
                  if (signedIn)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 44),
                      child: Text(session.user.email ?? '',
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('本地 $localCount 条记录',
                          style: const TextStyle(color: Colors.white)),
                      Text(signedIn ? '云端 $cloudCount 条' : '云端 - 条',
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.sync, color: accent),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text(
                              '修改记录/设置/资料后会自动同步到云端(登录状态下)',
                              style: TextStyle(color: Colors.white))),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (signedIn) ...[
            ElevatedButton.icon(
              onPressed: _loading ? null : _incremental,
              icon: const Icon(Icons.sync),
              label: const Text('立即同步 (增量)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F8F6F),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _loading ? null : _forceUpload,
              style: OutlinedButton.styleFrom(
                foregroundColor: danger,
                side: const BorderSide(color: Color(0xFF6E4A8E)),
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text('强制覆盖上传'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _loading ? null : _download,
              style: OutlinedButton.styleFrom(
                foregroundColor: danger,
                side: const BorderSide(color: Color(0xFF6E4A8E)),
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text('从云端下载'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loading ? null : _signOut,
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B)),
              child: const Text('退出登录'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      // 真正跳转到登录页(此前这里只做了 pop,点了像"没反应")
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AuthScreen()),
                      );
                      // 从登录页返回后:刷新登录状态,已登录则重新拉取云端数据
                      if (!mounted) return;
                      setState(() {});
                      if (_signedIn) await _loadCloud();
                    },
              child: const Text('去登录'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ],
      ),
    );
  }
}
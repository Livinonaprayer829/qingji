import 'package:flutter/material.dart';

import '../update_config.dart';
import '../update_service.dart';
import 'update_dialog.dart';

/// 设置页里的「检查更新」入口：
/// 显示当前版本 → 点击请求 GitHub → 有更新弹 UpdateDialog，无更新提示已是最新。
class UpdateCheckTile extends StatelessWidget {
  const UpdateCheckTile({super.key});

  Future<void> _check(BuildContext context) async {
    if (!UpdateConfig.enabled) {
      _toast(context, '尚未配置更新源(需在 update_config.dart 填写 GitHub 仓库)');
      return;
    }

    // 加载中
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await UpdateService().checkDetailed();

    // 关闭加载框
    if (context.mounted) Navigator.of(context).pop();
    if (!context.mounted) return;

    // 不再"失败也当作已最新"：把真实原因说出来，方便判断是网络还是被限流
    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        await showUpdateDialog(context, result.info!);
        break;
      case UpdateCheckStatus.upToDate:
        _toast(context, '已是最新版本 v${result.localVersion}');
        break;
      case UpdateCheckStatus.rateLimited:
        _toast(context, 'GitHub 接口限流，请稍后再试（挂 VPN 时更容易触发）');
        break;
      case UpdateCheckStatus.networkError:
        _toast(context, '网络不通，检查更新失败');
        break;
      case UpdateCheckStatus.notConfigured:
        _toast(context, '尚未配置更新源（update_config.dart）');
        break;
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.system_update_alt_rounded),
        title: const Text('检查更新'),
        subtitle: FutureBuilder<String>(
          future: UpdateService.currentVersion(),
          builder: (context, snap) => Text(
            snap.hasData ? '当前版本 v${snap.data}' : '当前版本',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _check(context),
      ),
    );
  }
}

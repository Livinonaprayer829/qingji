import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../update_service.dart';

/// 弹出更新提示框(内含下载进度与安装唤起)
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => UpdateDialog(info: info),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _service = UpdateService();
  bool _downloading = false;
  bool _finished = false;
  double _progress = 0;
  String? _error;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final v = await UpdateService.currentVersion();
    if (mounted) setState(() => _currentVersion = v);
  }

  Future<void> _startDownload() async {
    if (kIsWeb) {
      setState(() => _error = '网页端不支持安装 APK,请用手机打开 App 更新');
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await _service.downloadApk(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _finished = true;
        _progress = 1;
      });
      // 唤起系统安装界面(需用户首次授权"允许安装未知应用")
      await _service.installApk(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _downloading = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Connection')) {
      return '网络异常,下载失败,请检查网络后重试';
    }
    if (s.contains('UnsupportedError')) {
      return '当前平台不支持应用内安装';
    }
    return '下载失败: $s';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt_rounded, color: cs.primary),
          const SizedBox(width: 8),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _currentVersion.isEmpty ? '当前版本' : 'v$_currentVersion',
                  style: const TextStyle(color: Colors.grey),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                ),
                Text(
                  'v${info.version}',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (info.sizeText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('(${info.sizeText})',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('更新内容',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    info.notes.trim(),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                _finished
                    ? '下载完成,正在唤起安装…'
                    : '下载中 ${(_progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(fontSize: 12, color: cs.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading && !_finished
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('稍后再说'),
        ),
        FilledButton.icon(
          onPressed: (_downloading || _finished) ? null : _startDownload,
          icon: _finished
              ? const Icon(Icons.check, size: 18)
              : const Icon(Icons.download, size: 18),
          label: Text(_finished ? '已下载' : '立即更新'),
        ),
      ],
    );
  }
}

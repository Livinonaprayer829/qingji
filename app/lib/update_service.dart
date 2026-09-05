import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_config.dart';

/// 一次可用的更新信息
class UpdateInfo {
  /// 远端版本号,如 1.1.7
  final String version;

  /// Release 说明(body)
  final String notes;

  /// APK 下载地址
  final String apkUrl;

  /// APK 文件名
  final String apkName;

  /// APK 体积(字节),可能为 null
  final int? apkSize;

  UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.apkName,
    this.notes = '',
    this.apkSize,
  });

  /// 体积的可读文本,如 53.4 MB
  String get sizeText {
    final s = apkSize;
    if (s == null) return '';
    if (s >= 1024 * 1024) return '${(s / 1024 / 1024).toStringAsFixed(1)} MB';
    if (s >= 1024) return '${(s / 1024).toStringAsFixed(0)} KB';
    return '$s B';
  }
}

/// App 内更新服务:检测 → 下载 → 唤起系统安装
class UpdateService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: const {'Accept': 'application/vnd.github+json'},
    ),
  );

  /// 当前 App 版本名,如 1.1.6
  static Future<String> currentVersion() async {
    if (kIsWeb) return '0.0.0';
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 检测更新。无更新、未配置、或请求失败都返回 null(静默,不打扰用户)。
  /// force=true 时忽略本地"今日已提示"记录。
  Future<UpdateInfo?> checkForUpdate() async {
    if (!UpdateConfig.enabled) return null;
    try {
      final resp = await _dio.get(UpdateConfig.latestReleaseApi);
      if (resp.statusCode != 200 || resp.data == null) return null;
      final data = resp.data;
      if (data is! Map<String, dynamic>) return null;

      final tag = (data['tag_name'] ?? '').toString();
      final remote = _normalize(tag);
      if (remote.isEmpty) return null;

      // 找 Release 附件里的第一个 .apk
      final assets = data['assets'];
      Map<String, dynamic>? apk;
      if (assets is List) {
        for (final a in assets) {
          if (a is Map<String, dynamic>) {
            final name = (a['name'] ?? '').toString();
            if (name.toLowerCase().endsWith('.apk')) {
              apk = a;
              break;
            }
          }
        }
      }
      if (apk == null) return null;

      final local = await currentVersion();
      if (!_isNewer(remote, local)) return null;

      return UpdateInfo(
        version: remote,
        notes: (data['body'] ?? '').toString(),
        apkUrl: (apk['browser_download_url'] ?? '').toString(),
        apkName: (apk['name'] ?? 'app-release.apk').toString(),
        apkSize: apk['size'] is int ? apk['size'] as int : null,
      );
    } catch (_) {
      // 网络不通 / 仓库未建 / 接口限流:都不应该弹错误打扰用户
      return null;
    }
  }

  /// 去掉 tag 前缀 v/V 与空白
  static String _normalize(String tag) =>
      tag.trim().replaceAll(RegExp(r'^[vV]'), '');

  /// 按数字分段比较,避免 "1.1.10" < "1.1.6" 这种字符串比较错误
  static bool _isNewer(String remote, String local) {
    final r = _parts(remote);
    final l = _parts(local);
    final n = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < n; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .split(RegExp(r'[.+_\-]'))
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  /// 下载 APK 到 App 私有外部目录,onProgress 回调 0~1。返回本地路径。
  Future<String> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('网页端不支持下载安装 APK');
    }
    final dir = await getExternalStorageDirectory();
    final base = dir?.path;
    if (base == null || base.isEmpty) {
      throw StateError('无法获取存储目录');
    }
    // 用版本号命名,避免多次下载互相覆盖导致装到旧包
    final savePath = '$base/qingji-v${info.version}.apk';
    await _dio.download(
      info.apkUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    return savePath;
  }

  /// 唤起系统安装界面(需用户授权"允许安装未知应用")
  Future<void> installApk(String path) async {
    if (kIsWeb) return;
    await OpenFilex.open(path);
  }
}

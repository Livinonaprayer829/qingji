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

/// 检测结果状态
enum UpdateCheckStatus {
  /// 有新版本
  updateAvailable,

  /// 已是最新
  upToDate,

  /// 网络不通 / 源都失败
  networkError,

  /// GitHub 接口限流（403/429，常见于挂了 VPN 的共享出口 IP）
  rateLimited,

  /// 没配置 owner/repo
  notConfigured,
}

/// 一次检测的完整结果（带可读原因，供设置页提示）
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;
  final String localVersion;

  /// 命中的源：jsdelivr / raw / github-api
  final String source;

  const UpdateCheckResult({
    required this.status,
    required this.localVersion,
    this.info,
    this.source = '',
  });

  bool get hasUpdate =>
      status == UpdateCheckStatus.updateAvailable && info != null;
}

/// 内部用：某个源返回的候选版本
class _Candidate {
  final String version;
  final String notes;
  final String url;
  final String name;
  final int? size;
  final String source;

  const _Candidate({
    required this.version,
    required this.url,
    required this.name,
    required this.source,
    this.notes = '',
    this.size,
  });
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

  /// 这一次检测里 GitHub API 是否被限流（403/429）
  bool _rateLimited = false;

  /// 当前 App 版本名,如 1.1.6
  static Future<String> currentVersion() async {
    if (kIsWeb) return '0.0.0';
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 兼容旧调用：只在"有新版本"时返回信息，其余一律 null（启动静默检测用）。
  Future<UpdateInfo?> checkForUpdate() async {
    final r = await checkDetailed();
    return r.hasUpdate ? r.info : null;
  }

  /// 完整检测：**并行**请求三个源，取版本号最大的那个结果
  /// - 静态清单（jsDelivr CDN）：国内可直连，不消耗 GitHub API 额度
  /// - 静态清单（raw.githubusercontent.com）：无缓存，实时
  /// - GitHub API：兜底（未认证 60 次/小时，挂 VPN 常被限流）
  ///
  /// 取"最大版本"而不是"第一个成功的"，是为了避免 jsDelivr 缓存滞后
  /// 导致把已发布的新版本误判成"已是最新"。
  Future<UpdateCheckResult> checkDetailed() async {
    final local = await currentVersion();
    if (!UpdateConfig.enabled) {
      return UpdateCheckResult(
          status: UpdateCheckStatus.notConfigured, localVersion: local);
    }

    _rateLimited = false;

    final results = await Future.wait<_Candidate?>([
      _fromManifest(UpdateConfig.manifestJsDelivr, 'jsdelivr'),
      _fromManifest(UpdateConfig.manifestRaw, 'raw'),
      _fromApi(),
    ]);

    _Candidate? best;
    for (final c in results) {
      if (c == null) continue;
      if (best == null || _isNewer(c.version, best.version)) best = c;
    }

    if (best == null) {
      return UpdateCheckResult(
        status: _rateLimited
            ? UpdateCheckStatus.rateLimited
            : UpdateCheckStatus.networkError,
        localVersion: local,
      );
    }

    final info = UpdateInfo(
      version: best.version,
      notes: best.notes,
      apkUrl: best.url,
      apkName: best.name,
      apkSize: best.size,
    );

    if (!_isNewer(best.version, local)) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        info: info,
        localVersion: local,
        source: best.source,
      );
    }

    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      info: info,
      localVersion: local,
      source: best.source,
    );
  }

  /// 读仓库根目录的静态清单 `version.json`
  ///
  /// 格式：
  /// ```json
  /// { "version": "1.5.14", "notes": "更新说明",
  ///   "url": "https://github.com/{owner}/{repo}/releases/download/v1.5.14/qingji-latest.apk",
  ///   "size": 58245678, "name": "qingji-latest.apk" }
  /// ```
  Future<_Candidate?> _fromManifest(String url, String source) async {
    try {
      final resp = await _dio.get(
        url,
        options: Options(
          validateStatus: (_) => true,
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );
      if (resp.statusCode != 200) return null;
      final data = resp.data;
      if (data is! Map) return null;

      final version = _normalize((data['version'] ?? '').toString());
      final apkUrl = (data['url'] ?? '').toString();
      if (version.isEmpty || apkUrl.isEmpty) return null;

      return _Candidate(
        version: version,
        notes: (data['notes'] ?? '').toString(),
        url: apkUrl,
        name: (data['name'] ?? 'qingji-latest.apk').toString(),
        size: data['size'] is int ? data['size'] as int : null,
        source: source,
      );
    } catch (_) {
      return null;
    }
  }

  /// 读 GitHub Release API（兜底；403/429 记为"被限流"）
  Future<_Candidate?> _fromApi() async {
    try {
      final resp = await _dio.get(
        UpdateConfig.latestReleaseApi,
        options: Options(validateStatus: (_) => true),
      );
      if (resp.statusCode == 403 || resp.statusCode == 429) {
        _rateLimited = true;
        return null;
      }
      if (resp.statusCode != 200) return null;
      final data = resp.data;
      if (data is! Map) return null;

      final tag = (data['tag_name'] ?? '').toString();
      final remote = _normalize(tag);
      if (remote.isEmpty) return null;

      // 找 Release 附件里的第一个 .apk
      final assets = data['assets'];
      Map? apk;
      if (assets is List) {
        for (final a in assets) {
          if (a is Map &&
              (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
            apk = a;
            break;
          }
        }
      }
      if (apk == null) return null;

      return _Candidate(
        version: remote,
        notes: (data['body'] ?? '').toString(),
        url: (apk['browser_download_url'] ?? '').toString(),
        name: (apk['name'] ?? 'qingji-latest.apk').toString(),
        size: apk['size'] is int ? apk['size'] as int : null,
        source: 'github-api',
      );
    } catch (_) {
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

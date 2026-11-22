/// =========================================================
/// 青记 · App 内更新配置
/// ---------------------------------------------------------
/// 【需要你填的地方】只有下面两个常量 —— owner 和 repo。
///
/// 假设你在 GitHub 建的仓库地址是：
///     https://github.com/zhangsan/qingji
/// 那么这里就填：
///     static const String owner = 'zhangsan';
///     static const String repo  = 'qingji';
///
/// 更新原理：App 启动或手动点「检查更新」时，会去请求
///     https://api.github.com/repos/{owner}/{repo}/releases/latest
/// 读取最新 Release 的 tag 和里面的 .apk 附件，和当前版本比对。
/// 所以发布新版本 = 在 GitHub 上发一个 Release，tag 填 v1.1.7，
/// 并把打包好的 app-release.apk 作为附件上传。
/// =========================================================
class UpdateConfig {
  UpdateConfig._();

  /// GitHub 用户名（或组织名）
  static const String owner = 'Livinonaprayer829';

  /// GitHub 仓库名
  static const String repo = 'qingji';

  /// 是否启用 App 内更新检测。填好 owner/repo 前先关掉，避免每次启动白请求。
  static bool get enabled =>
      owner != 'YOUR_GITHUB_OWNER' && owner.isNotEmpty && repo.isNotEmpty;

  /// GitHub 最新 Release 接口
  static String get latestReleaseApi =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// ===== 静态版本清单（主检测源）=====
  /// 发版时更新仓库根目录的 `version.json`，App 优先读它 ——
  /// 这样不依赖 api.github.com（未认证限流 60 次/小时、按出口 IP 算；
  /// 挂 VPN 时出口 IP 常被多人共用 ⇒ 403 ⇒ 表现为"检查不到更新"）。
  ///
  /// 1) jsDelivr CDN：国内可直连（有缓存，可能滞后几小时）
  /// 2) raw.githubusercontent.com：无缓存、实时
  /// 3) api.github.com：最后兜底
  /// App 会**并行**请求这几个源，取版本号最大的那个 ⇒ 缓存滞后也不会误判"已是最新"。
  static String get manifestJsDelivr =>
      'https://cdn.jsdelivr.net/gh/$owner/$repo@main/version.json';

  static String get manifestRaw =>
      'https://raw.githubusercontent.com/$owner/$repo/main/version.json';

  /// Release 页面（网页端/兜底跳转用）
  static String get releasesPage =>
      'https://github.com/$owner/$repo/releases/latest';
}

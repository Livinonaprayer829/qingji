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

  /// Release 页面（网页端/兜底跳转用）
  static String get releasesPage =>
      'https://github.com/$owner/$repo/releases/latest';
}

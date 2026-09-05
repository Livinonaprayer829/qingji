// 条件导出:web 平台用 universal_html 触发浏览器下载,mobile 平台用
// path_provider 写临时文件 + share_plus 调起系统分享/保存。
// 这样真机(安卓)也能导出 CSV,而不再依赖仅 web 可用的 universal_html。
export 'csv_export_mobile.dart' if (dart.library.html) 'csv_export_web.dart';

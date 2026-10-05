// 平台分发:移动端(dart:io)与 Web 各自的导出实现。
// 导出 CSV 与 HTML 报告两种格式。
export 'exporters_mobile.dart' if (dart.library.html) 'exporters_web.dart';

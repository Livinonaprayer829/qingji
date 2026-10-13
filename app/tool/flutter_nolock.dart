// 绕过 Flutter 缓存锁的启动入口。
//
// 背景:某些环境下 `D:\soft\flutter\bin\cache\lockfile` 会被 ACL/沙箱卡成"只读",
// flutter 工具启动时就报 "Failed to open or create the artifact cache lockfile"。
// 而 Cache.disableLocking() 是测试专用 API,没有命令行开关。
// 这个脚本直接用 flutter_tools 源码启动并关掉锁,等价于运行 flutter 命令。
//
// 用法(在 app 目录下):
//   dart --packages=<flutter_tools/.dart_tool/package_config.json> tool/flutter_nolock.dart build web
import 'package:flutter_tools/executable.dart' as executable;
import 'package:flutter_tools/src/cache.dart';

void main(List<String> args) {
  Cache.disableLocking();
  executable.main(args);
}

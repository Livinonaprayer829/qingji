// 平台分发:移动端(dart:io)用真实实现,Web 用空实现。
export 'ipv4_stub.dart' if (dart.library.io) 'ipv4_io.dart';

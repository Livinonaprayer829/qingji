import 'dart:io';

/// 让 App 的 HTTP 连接**只走 IPv4**。
///
/// 背景:国内部分运营商给手机分配了 IPv6,但到 Cloudflare(如 `*.supabase.co`)的
/// IPv6 路由不可用,App 直连时会报 `Connection reset by peer`;
/// 而浏览器有 Happy Eyeballs,IPv6 不通会自动回退 IPv4,所以表现为
/// "浏览器能打开、App 不行""借别人的热点/换张卡就好了"。
///
/// 这里通过全局 [HttpOverrides] 把 dart:io 的连接工厂换成"仅解析并连接 IPv4 地址",
/// 从根上规避该问题(supabase / dio / package:http 默认都走 dart:io 的 HttpClient)。
///
/// 若某天需要关掉,把 [enabled] 设为 false 即可。
const bool enabled = true;

void applyForceIPv4() {
  if (!enabled) return;
  HttpOverrides.global = _IPv4HttpOverrides();
}

class _IPv4HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = _connectViaIPv4;
    return client;
  }
}

Future<ConnectionTask<Socket>> _connectViaIPv4(
    Uri url, String? proxyHost, int? proxyPort) async {
  // 有代理时按原样连代理(代理本身负责后续解析)
  if (proxyHost != null && proxyHost.isNotEmpty) {
    return Socket.startConnect(proxyHost, proxyPort ?? 8080);
  }

  final port = url.port != 0 ? url.port : (url.scheme == 'https' ? 443 : 80);

  try {
    final addrs = await InternetAddress.lookup(url.host,
        type: InternetAddressType.IPv4);
    Object? lastError;
    for (final addr in addrs) {
      try {
        return await Socket.startConnect(addr, port);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
  } catch (_) {
    // 解析不到 IPv4(或全部失败)→ 落到下面的默认行为,避免把请求彻底打死
  }

  // 兜底:交给系统按域名默认连接
  return Socket.startConnect(url.host, port);
}

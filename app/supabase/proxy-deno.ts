/**
 * 青记 Supabase 反向代理 —— Deno Deploy 版（v2：修复响应头编码问题）
 * ------------------------------------------------------------------
 * 为什么需要它:
 *   国内部分运营商(实测中国移动)对整个 `supabase.co` 域做域名级(SNI)封锁,
 *   导致 App 报 "Connection reset by peer"。用自有反代域名即可绕开。
 *
 * ⚠️ v2 关键修复:
 *   fetch 取回响应时 body 已被**自动解压**,但响应头里仍带着 Supabase 的
 *   `content-encoding: gzip` / `content-length`(压缩后长度)。若原样转发,
 *   客户端会按 gzip 去解一份**纯文本** → 解码失败:
 *     - 浏览器: fetch 直接失败(`Failed to fetch`)
 *     - dart:io: 同样会解压失败
 *   所以必须删掉这几个头,让运行时按实际内容重新协商。
 *
 * 部署(免费,不用买域名,约 3 分钟):
 *   1. 打开 https://dash.deno.com/ → Playgrounds → 打开你已有的那个(或 New Playground)
 *   2. 把本文件内容整段替换编辑器里的代码
 *   3. 点 Save & Deploy
 *   4. 地址形如 https://<项目名>.deno.net
 *
 * 说明:
 *   - 青记只用 auth + 数据库(REST),无需 WebSocket/Realtime,简单透传即可。
 *   - anon key 仍在 App 里,本代理不存储任何密钥;数据安全由 Supabase RLS 保证。
 */

// 你的 Supabase 项目地址(勿改)
const UPSTREAM = 'https://xlwghqpagobwmrjqofkq.supabase.co';

Deno.serve(async (req: Request): Promise<Response> => {
  const url = new URL(req.url);
  // 保留 path / query,原样转发到 Supabase
  const target = UPSTREAM + url.pathname + url.search;

  // ---- 转发请求 ----
  const reqHeaders = new Headers(req.headers);
  reqHeaders.delete('host'); // 交给 fetch 按目标地址自动设置

  const init: RequestInit = {
    method: req.method,
    headers: reqHeaders,
    redirect: 'manual',
  };

  const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
  if (hasBody && req.body) {
    init.body = req.body;
  }

  try {
    const resp = await fetch(target, init);

    // ---- 转发响应(关键:清掉内容编码相关头) ----
    const resHeaders = new Headers(resp.headers);
    resHeaders.delete('content-encoding'); // body 已被自动解压
    resHeaders.delete('content-length'); // 长度已变化
    resHeaders.delete('transfer-encoding');
    resHeaders.delete('connection');

    return new Response(resp.body, {
      status: resp.status,
      headers: resHeaders,
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ message: 'proxy error: ' + String(e) }),
      { status: 502, headers: { 'content-type': 'application/json' } },
    );
  }
});

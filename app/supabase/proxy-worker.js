/**
 * 青记 Supabase 反向代理 —— Cloudflare Worker 版（v2：修复响应头编码问题）
 * ------------------------------------------------------------------
 * 注意:实测国内部分网络对 `*.workers.dev` 同时做了 DNS 污染 + SNI 封锁,
 * 所以**没有自有域名时请用 Deno Deploy 版**(app/supabase/proxy-deno.ts)。
 * 本文件适用于:你买了自有域名并接入 Cloudflare 的场景(在 Worker 里配路由)。
 *
 * ⚠️ v2 关键修复:同 Deno 版 —— fetch 已自动解压 body,必须删掉
 * `content-encoding` / `content-length` 等头,否则客户端解码失败。
 *
 * 部署:
 *   1. Cloudflare → Workers 和 Pages → 创建 Worker → 粘贴本文件 → 部署
 *   2. 在 Worker 的「设置 → 域和路由」里绑定你的自有域名(如 api.你的域名.com)
 */

const UPSTREAM = 'https://xlwghqpagobwmrjqofkq.supabase.co';

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = UPSTREAM + url.pathname + url.search;

    const reqHeaders = new Headers(request.headers);
    reqHeaders.delete('host');

    const hasBody = !['GET', 'HEAD'].includes(request.method);
    const init = {
      method: request.method,
      headers: reqHeaders,
      redirect: 'manual',
    };
    if (hasBody && request.body) {
      init.body = request.body;
      init.duplex = 'half'; // 流式透传所需
    }

    try {
      const resp = await fetch(target, init);

      // 关键:清掉内容编码相关头(body 已解压)
      const resHeaders = new Headers(resp.headers);
      resHeaders.delete('content-encoding');
      resHeaders.delete('content-length');
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
  },
};

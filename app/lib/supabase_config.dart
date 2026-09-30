// Supabase 连接配置
// ------------------------------------------------------------------
// 说明:anon/public key 是公开密钥,必须打包进客户端 App 才能用,
// 真正的数据安全由后端 RLS 行级权限保证。请勿替换为 service_role key。
//
// ⚠️ 关于 supabaseUrl 为什么不是 *.supabase.co:
//   国内部分运营商(实测:中国移动的移动数据 + 移动宽带)对整个 `supabase.co` 域
//   做了**域名级(SNI)封锁**——TLS 握手阶段直接重置 TCP 连接。表现为 App 报
//   "Connection reset by peer"、无法登录/同步,而浏览器(走 QUIC)却正常。
//   电信网络暂未封锁,所以换网络/开 VPN 就好——但这不可持续。
//
//   解法:走一层自己的反向代理,让 App 连接的域名里不含 `supabase.co`,从而绕开该规则。
//   代理是透明转发(路径/头/体原样转发),不存储任何密钥,安全性不变。
//   代理源码见 app/supabase/proxy-deno.ts（部署在 Deno Deploy,免费）。
//   若代理挂了/被墙,可先把下面 supabaseUrl 换回直连地址临时应急。
//
// 直连地址(备用):https://xlwghqpagobwmrjqofkq.supabase.co
const String supabaseUrl =
    'https://loyal-warbler-4100.livinonaprayer829.deno.net';
const String supabaseAnonKey =
    'sb_publishable_YgudJ-S1-HCPJ0z9SIGi4Q_YnyU2iIi';

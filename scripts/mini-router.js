// mini-router.js — 最简透传路由代理，只解析 model 字段做路由选择，其余全部原样转发
// 约束: api_base_url 须为根路径（如 https://api.deepseek.com/anthropic），不含 /v1/messages
const http = require('http');
const https = require('https');
const fs = require('fs');
const { randomBytes } = require('crypto');

if (!process.env.ROUTER_CONFIG) { console.error('FATAL: ROUTER_CONFIG 环境变量未设置'); process.exit(1); }
const CFG = JSON.parse(fs.readFileSync(process.env.ROUTER_CONFIG, 'utf8'));
const PORT = parseInt(process.env.PORT || '3457', 10);
const AUTH = process.env.ROUTER_AUTH || 'sk-ccr-proxy';
if (!process.env.ROUTER_AUTH) console.error('[WARN] ROUTER_AUTH 为空，服务将无认证运行');
const MAX_BODY = 10 * 1024 * 1024; // 10MB
const UPSTREAM_TIMEOUT = 60_000;   // 60s

const PROVIDERS = {};
for (const p of (CFG.Providers || [])) {
  if (!p.name || !p.api_base_url || !p.api_key) {
    console.error(`FATAL: Provider "${p.name || '(unnamed)'}" 缺少 name/api_base_url/api_key`);
    process.exit(1);
  }
  try { new URL(p.api_base_url); } catch { console.error(`FATAL: Provider "${p.name}" api_base_url 无效: ${p.api_base_url}`); process.exit(1); }
  PROVIDERS[p.name] = p;
}

// Header 过滤集 — 透传时移除的 hop-by-hop 和认证头
const DROP_HEADERS = new Set(['host','connection','transfer-encoding','x-api-key','authorization','content-length',
  'accept-encoding','x-forwarded-for','x-forwarded-host','x-forwarded-proto','forwarded','x-real-ip']);

// 启动时校验 Router.default
const def = (CFG.Router || {}).default;
if (!def || !def.includes(',') || def.split(',').length !== 2) {
  console.error('FATAL: Router.default 缺失或格式错误（需 "provider,model"）');
  process.exit(1);
}
const [defProv, defModel] = [def.slice(0, def.indexOf(',')).trim(), def.slice(def.indexOf(',') + 1).trim()];
if (!PROVIDERS[defProv]) {
  console.error(`FATAL: Router.default provider "${defProv}" 不在 Providers 列表中`);
  process.exit(1);
}

// 可观测性基础设施
const M = { startTime: Date.now(), total: 0, active: 0, s2xx: 0, s4xx: 0, s5xx: 0 };
const rid = () => randomBytes(6).toString('hex');
const log = (r, f) => console.log(JSON.stringify(Object.assign({}, f, { ts: Date.now(), rid: r })));
let _el = Date.now();
setInterval(() => { const l = Date.now() - _el - 10000; if (l > 500) log('', { ev: 'ev_loop_lag', ms: l }); _el = Date.now(); }, 10000).unref();

// 加载自定义路由器
let routerFn = null;
if (CFG.CUSTOM_ROUTER_PATH) {
  try { routerFn = require(CFG.CUSTOM_ROUTER_PATH); }
  catch (e) { console.error('load router failed, 将使用默认路由:', e.message); }
}

async function resolveRoute(model) {
  if (routerFn) {
    try {
      const result = await routerFn({ body: { model } }, CFG);
      if (result && typeof result === 'string') {
        const trimmed = result.trim();
        const idx = trimmed.indexOf(',');
        if (idx !== -1)
          return { provider: PROVIDERS[trimmed.slice(0, idx).trim()], model: trimmed.slice(idx + 1).trim() || model };
      }
    } catch (e) { console.error('router error:', e.message); }
  }
  // 兜底: Router.default
  return { provider: PROVIDERS[defProv], model: defModel };
}

// models 列表
function getModels() {
  const data = [];
  for (const p of (CFG.Providers || []))
    for (const m of (p.models || [])) {
      const id = typeof m === 'string' ? m : (m?.id || m?.name || '');
      if (id) data.push({ id });
    }
  return { data };
}

// 认证校验
function checkAuth(req) {
  const key = req.headers['x-api-key'] || (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  return key === AUTH;
}

const server = http.createServer((req, res) => {
  const _rid = rid(); M.total++; M.active++; const _t0 = Date.now();
  let _err = '', _up = '', _mod = '', _bin = 0, _bout = 0, _logged = false;
  res.setHeader('x-request-id', _rid);
  const _done = () => {
    if (_logged) return;
    _logged = true;
    M.active--;
    const s = res.statusCode || 0;
    if (s >= 200 && s < 300) M.s2xx++;
    else if (s >= 400 && s < 500) M.s4xx++;
    else if (s >= 500) M.s5xx++;
    res.removeListener('finish', _done);
    res.removeListener('close', _done);
    if (req.method === 'GET' && req.url === '/') return;
    log(_rid, { method: req.method, path: req.url, status: s, ms: Date.now() - _t0, bytesIn: _bin, bytesOut: _bout, upstream: _up, model: _mod, err: _err || undefined });
  };
  res.on('finish', _done);
  res.on('close', _done);

  // GET / — 健康检查
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok', port: PORT, uptime: Date.now() - M.startTime, requests: M.total, active: M.active, s2xx: M.s2xx, s4xx: M.s4xx, s5xx: M.s5xx }));
  }

  // GET /v1/models — 返回模型列表
  if (req.method === 'GET' && req.url.startsWith('/v1/models')) {
    return checkAuth(req)
      ? (res.writeHead(200, { 'content-type': 'application/json' }), res.end(JSON.stringify(getModels())))
      : (_err = 'unauth', res.writeHead(401), res.end('Unauthorized'));
  }

  // POST /v1/messages — 核心路由转发
  if (req.method === 'POST' && req.url.startsWith('/v1/messages')) {
    if (!checkAuth(req)) { _err = 'unauth'; res.writeHead(401); return res.end('Unauthorized'); }

    req.setEncoding('utf8');
    req.on('error', err => { if (!_err) _err = err.message; console.error('client request error:', err.message); req.destroy(); });
    let body = '';
    let bodyLen = 0;
    let bodyTooLarge = false;
    req.on('data', chunk => {
      if (bodyTooLarge) return;
      bodyLen += Buffer.byteLength(chunk, 'utf8');
      if (bodyLen > MAX_BODY) { bodyTooLarge = true; _err = 'body_too_large'; console.error('body too large:', bodyLen); res.writeHead(413); res.end('Body too large'); req.destroy(); return; }
      body += chunk;
    });
    req.on('end', async () => {
      if (bodyTooLarge) return;
      let json;
      try { json = JSON.parse(body); } catch { _err = 'invalid_json'; res.writeHead(400); return res.end('Invalid JSON'); }

      json.model = String(json.model || '').replace(/\[1m\]$/, '');
      const target = await resolveRoute(json.model);
      if (!target || !target.provider) { _err = 'no_provider'; res.writeHead(502); return res.end('No provider for route'); }
      json.model = target.model;
      _mod = target.model; _up = target.provider.name;

      let upstreamUrl;
      try { upstreamUrl = new URL(target.provider.api_base_url); }
      catch { _err = 'invalid_upstream_url'; res.writeHead(500); return res.end('Invalid upstream URL'); }
      const newBody = JSON.stringify(json);
      _bin = Buffer.byteLength(newBody);

      const fwdHeaders = {};
      for (const [k, v] of Object.entries(req.headers))
        if (!DROP_HEADERS.has(k)) fwdHeaders[k] = v;
      fwdHeaders.host = upstreamUrl.host;
      fwdHeaders['x-api-key'] = target.provider.api_key;
      fwdHeaders['content-length'] = Buffer.byteLength(newBody).toString();

      const transport = upstreamUrl.protocol === 'https:' ? https : http;
      const proxyReq = transport.request({
        hostname: upstreamUrl.hostname,
        port: upstreamUrl.port || (upstreamUrl.protocol === 'https:' ? 443 : 80),
        path: upstreamUrl.pathname.replace(/\/+$/, '') + '/v1/messages',
        method: 'POST',
        headers: fwdHeaders,
        timeout: UPSTREAM_TIMEOUT,
      }, proxyRes => {
        const resHeaders = {};
        for (const [k, v] of Object.entries(proxyRes.headers))
          if (!DROP_HEADERS.has(k)) resHeaders[k] = v;
        res.writeHead(proxyRes.statusCode, resHeaders);
        proxyRes.pipe(res);
        proxyRes.on('data', chunk => { _bout += chunk.length; });
        proxyRes.on('error', err => { if (!_err) _err = err.message; console.error('upstream response error:', err.message); res.destroy(); });
      });

      proxyReq.on('timeout', () => { _err = 'upstream_timeout'; proxyReq.destroy(); if (!res.headersSent) { res.writeHead(504); res.end('Upstream timeout'); } });
      proxyReq.on('error', err => { if (!_err) _err = err.message; console.error('upstream error:', err.message); if (!res.headersSent) { res.writeHead(502); res.end('Upstream error'); } });
      res.on('error', err => { if (!_err) _err = err.message; console.error('client response error:', err.message); if (proxyReq && !proxyReq.destroyed) proxyReq.destroy(); });
      res.on('close', () => { if (!res.writableEnded) proxyReq.destroy(); });

      proxyReq.write(newBody);
      proxyReq.end();
    });
    return;
  }

  res.writeHead(404); res.end('Not Found');
});

server.on('error', err => { console.error('server error:', err.message); process.exit(1); });
server.listen(PORT, '127.0.0.1', () => console.log(`mini-router on :${PORT}`));

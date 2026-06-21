# cc-tee

**一路分叉，水流无痕。Claude Code 多层路由切换 + 零依赖透传代理。**

> Split the stream, keep it clean. Multi-profile router switch + zero-dependency passthrough proxy for Claude Code.

---

## 命名哲学 / Why "tee"

**tee** = 三通接头。水管工的一分二利器——一路水管进来，分两路出去。

就像 `deepqwen`：Claude Code 发来一个模型名，tee 把它分叉到 DeepSeek 和 Qwen 两个上游。换个 profile 就是换种分法。水经过三通，不加工，不改性——mini-router.js 只透传，不翻译。

> A plumbing tee fitting: one stream in, two (or more) out. Like the `deepqwen` profile — Claude Code sends one model name, tee splits it to DeepSeek and Qwen upstreams. Switch profile, switch the split. Water passes through unchanged — the mini-router only forwards, never translates.

---

## 多重切换 / Profiles

`./scripts/switch-profile.sh` 一键切换所有路由层，从裸直连到全功能网关：

| Profile | 路由规则 | 代理层 |
|---------|---------|--------|
| `deepqwen` | Haiku→DS Flash / Sonnet→DS Pro / Opus→Qwen3.7-Max | **mini-router** 透传 |
| `deepseek` | Haiku→DS Flash / 其余→DS Pro | CCR |
| `deepseek-tc` | 全量→DS + tool_choice 降级修复 | CCR |
| `deepseek-anthropic` | 全量→DS Anthropic 协议透传 | CCR |
| `direct deepseek` | 全量→DeepSeek | 无（直连） |
| `direct qwen` | 全量→百炼 Qwen | 无（直连） |
| `hybrid-ds` | Haiku→DS Flash / Sonnet→DS Pro / Opus→Qwen3.7-Max | CCR |
| `hybrid` | Haiku→DS / Sonnet+Opus→Qwen | CCR |
| `hybrid-toolfree` | 全量→DS V4 Flash | CCR |
| `layer2-search` | CCR + Tavily 搜索注入 | CCR |
| `layer2` | CCR + LiteLLM | CCR + LiteLLM |
| `layer3` | CCR + LiteLLM(OpenRouter) | CCR + LiteLLM |

> 更多 profile 见 `./scripts/switch-profile.sh help`。

---

## 是什么 / What

[mini-router.js](scripts/mini-router.js) — **196 行**，解析 model 字段做路由选择，其余 body 原样透传。不做格式翻译（Anthropic ↔ OpenAI），只做最纯粹的 HTTP 转发。

对比 [claude-code-router](https://github.com/musistudio/claude-code-router)（35k+ stars）等全功能网关，cc-tee 的哲学是：**如果上游已原生支持 Anthropic Messages API，就不要在中间加翻译层。**

> **196 lines**. Routes by model field, forwards everything else as-is. No format translation, just pure HTTP passthrough. Built for providers that already speak Anthropic natively.

---

## 为什么不用 cc-router / Why not cc-router?

| | cc-router | **cc-tee (mini-router)** |
|---|---|---|
| 代码量 | 数千行 TypeScript | **196 行 JavaScript** |
| 格式翻译 | 默认翻译，passthrough 是二等公民 | **只透传，零翻译** |
| 依赖 | npm 生态 | **零依赖（Node.js 内置模块）** |
| 兼容性风险 | CC 升级频繁导致 break | **只依赖 HTTP 协议，无版本绑定** |
| 适用 | 多 Provider 不同协议 | **Anthropic-native Provider** |

---

## 快速开始 / Quick Start

### 1. 配置

```bash
cp config/secret.template.json config/secret.json
# 编辑 secret.json 填入 API Key
```

### 2. 启动

```bash
# 直连 DeepSeek
./scripts/switch-profile.sh direct deepseek

# mini-router 透传（推荐）
./scripts/switch-profile.sh deepqwen
```

### 3. Claude Code 使用

启动后 `ANTHROPIC_BASE_URL` 已自动写入 `~/.claude/settings.local.json`，Reload VSCode 窗口即可。

> `ANTHROPIC_BASE_URL` auto-configured in `~/.claude/settings.local.json`. Reload VSCode to apply.

---

## 架构 / Architecture

```
Claude Code (VSCode / CLI)
    │
    │  ANTHROPIC_BASE_URL=http://localhost:3457
    ▼
┌─────────────────────────────┐
│  mini-router.js  :3457      │
│                             │
│  ① 解析 model 字段           │
│  ② 匹配路由规则              │
│  ③ 原样透传 body 到上游       │
│     不改一个字               │
└──────────┬──────────────────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
  DeepSeek     Qwen 百炼
  (Flash/Pro)  (3.7-Max)
```

---

## 目录 / Structure

```
cc-tee/
├── scripts/
│   ├── mini-router.js          ← 核心：196 行透传代理
│   ├── switch-profile.sh       ← 一键切换路由模式
│   └── merge-config.py         ← 配置合并工具
├── profiles/                   ← 各 Provider 路由配置
│   ├── deepqwen/               ← DeepSeek+Qwen 透传
│   ├── deepseek/               ← DeepSeek CCR 路由
│   ├── direct/                 ← 直连模式
│   └── ...
├── config/
│   └── secret.template.json    ← 密钥模板（不提交真实密钥）
└── .github/workflows/          ← GitHub → Gitee 自动镜像
```

---

## 许可 / License

MIT

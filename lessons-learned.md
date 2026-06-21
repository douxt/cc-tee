# cc-tee 踩坑记录

记录集成 Claude Code + DeepSeek + WebSearch 中遇到的坑和解决方案。

## 1. DeepSeek 思考模式 + tool_choice 冲突

**症状：** WebSearch 请求报错 `Thinking mode does not support this tool_choice`

**根因：** DeepSeek V4 Flash/Pro 在思考模式下只接受 `tool_choice: "auto"` 或 `"none"`，不接受：
- `"required"`
- `{type: "tool", name: "web_search"}`（Anthropic 格式的强制调工具）
- `{type: "function", function: {name: "..."}}`（OpenAI 格式的强制调函数）

**修复：** 在 CCR custom-router 中检测到 web_search 请求时，直接调 Tavily API 搜索，把结果注入用户消息后删掉 tools。不让 DeepSeek 参与工具调用。

## 2. LiteLLM websearch_interception callback 加载失败

**症状：** callback hook 永远不触发，搜无报错

**根因1：** `litellm.yaml` 配置 `callbacks` 后，`merge-config.py` 的 `merge_litellm` 只合并 `model_list`，不合并 `litellm_settings`。配置根本没写进去。

**修复：** `profile/layer2-search` 改用 `cp` 直接覆盖 `litellm.yaml`

**根因2：** LiteLLM 的 `get_instance_fn` 要求 callback 模块导出的是**实例**而非类：
```python
# ❌ 错误：导出类
class MyHandler(CustomLogger): ...
# ⚠️ litellm.callbacks 收到类，isinstance 检查为 False，hook 静默跳过

# ✅ 正确：导出实例
class MyHandler(CustomLogger): ...
my_handler = MyHandler()  # 导出实例
```

## 3. CCR transformer 组合

**症状：** `Provider 'undefined' not found`

**根因：** `deepseek` transformer 没有 `endPoint`，不会注册 `/v1/chat/completions` 路由。

**修复：** 必须用 `["openai", "deepseek"]` 组合：
- `openai`：注册 `/v1/chat/completions` 端点，做 Anthropic→OpenAI 格式转换
- `deepseek`：处理 DeepSeek 特有的响应格式（max_tokens 限制、reasoning_content 转 thinking）

## 4. CCR custom-router 修改 req.body

**发现的机制：** custom-router 修改 `req.body` 会在路由决策后透传到下游请求。可以用来：
- 改 `tool_choice`（Anthropic 格式 → 字符串）
- 注入搜索结果到 `messages`
- 删 `tools`
- 改 `model`

**限制：** router 是 async 函数，内部 `fetch` 调用会阻塞路由决策。网络超时会影响 CCR 响应速度。

## 5. [1m] 后缀规则

**规则：** `deepseek-v4-flash[1m]` / `deepseek-v4-pro[1m]` 中的 `[1m]` 只在 Claude Code 的 settings.json 中需要（告知 CC 启用百万上下文）。其他所有层（CCR config、LiteLLM config、custom-router 返回值）都不要带 `[1m]`。

**修复位置：** 在 `custom-router.js` 中用 `.includes('v4-flash')` 做子串匹配，避免 `[1m]` 干扰。

## 6. 环境变量注入

**症状：** Tavily/Exa 搜索返回空

**根因：** LiteLLM 进程启动时没有 `TAVILY_API_KEY` / `EXA_API_KEY` 环境变量。

**修复：** 在 `switch-profile.sh` 的启动命令前加 export：
```bash
export TAVILY_API_KEY="tvly-dev-xxx"
export EXA_API_KEY="69b7b765-xxx"
```

## 7. 最终方案对比

| 方案 | 复杂度 | 维护成本 | 稳定性 |
|------|--------|---------|--------|
| CCR custom-router 直调 Tavily | 低（2个文件） | 低 | ✅ 运行稳定 |
| LiteLLM websearch_interception + agentic loop | 高（CCR+LiteLLM+callback） | 中 | ❌ DeepSeek 思考模式不兼容 |
| Python callback pre_call_deployment_hook | 中 | 中 | ❌ hook 加载易出问题 |

**结论：** 简化后的方案（CCR → custom-router Tavily注入 → DeepSeek）最可靠，不依赖 LLM 的工具调用能力。

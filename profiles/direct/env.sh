#!/bin/bash
# 直连模式 — CC 直连供应商（支持 Anthropic Messages API）
#
# 使用: source profiles/direct/env.sh && claude
#       source profiles/direct/env.sh && claude "写个 hello world"
# 切换模型: 进入 CC 后 /model opus（或用具体模型名）

# ── 选供应商：取消注释你想用的那个 ──

# ── 选供应商：取消注释你想用的那个 ──

# 1) Anthropic 官方
# export ANTHROPIC_BASE_URL="https://api.anthropic.com"
# export ANTHROPIC_AUTH_TOKEN="your-anthropic-api-key"
# export ANTHROPIC_MODEL="claude-sonnet-4-20250514"

# 2) DeepSeek（走 Anthropic 协议）
# export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
# export ANTHROPIC_AUTH_TOKEN="__DEEPSEEK_API_KEY__"
# export ANTHROPIC_MODEL="deepseek-v4-flash"
# export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
# export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash"
# export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
# export CLAUDE_CODE_EFFORT_LEVEL="max"
# export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"

# 3) 百炼 Qwen（走 Anthropic 协议）
export ANTHROPIC_BASE_URL="https://dashscope.aliyuncs.com/apps/anthropic"
export ANTHROPIC_AUTH_TOKEN="__DASHSCOPE_API_KEY__"
export ANTHROPIC_MODEL="qwen3.7-plus[1m]"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="qwen3.7-flash"
export ANTHROPIC_DEFAULT_SONNET_MODEL="qwen3.7-plus[1m]"
export ANTHROPIC_DEFAULT_OPUS_MODEL="qwen3.7-max[1m]"
export CLAUDE_CODE_SUBAGENT_MODEL="qwen3.7-flash[1m]"
export CLAUDE_CODE_EFFORT_LEVEL="max"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"

echo "🔗 直连: $ANTHROPIC_BASE_URL"
echo "   模型级别: Haiku=$ANTHROPIC_DEFAULT_HAIKU_MODEL  Sonnet=$ANTHROPIC_DEFAULT_SONNET_MODEL  Opus=$ANTHROPIC_DEFAULT_OPUS_MODEL"
echo "   Effort: $CLAUDE_CODE_EFFORT_LEVEL"
echo "   运行: claude"
echo "   切换: /model haiku | /model sonnet | /model opus"

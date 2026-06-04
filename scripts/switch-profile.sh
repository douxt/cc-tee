#!/bin/bash
# 一键切换 CC 运行模式
# 用法: ./switch-profile.sh <deepseek|direct [qwen|deepseek]|hybrid|hybrid-toolfree|layer1|layer2|layer3>

set -e

CC_STACK="$HOME/cc-stack"
PROFILES_DIR="$CC_STACK/profiles"
CCR_CONFIG_DIR="$HOME/.claude-code-router"
LITELLM_DIR="$CC_STACK/litellm"
LITELLM_LOG="$CC_STACK/logs/litellm.log"
SECRET_FILE="$CC_STACK/config/secret.json"
MERGE="$CC_STACK/scripts/merge-config.py"

PROFILE=$1
DIRECT_PROVIDER=${2:-qwen}

# ── 加载秘钥 ──
load_secret() { python3 -c "import json; print(json.load(open('$SECRET_FILE'))['$1'])"; }
DEEPSEEK_API_KEY=$(load_secret DEEPSEEK_API_KEY)
DASHSCOPE_API_KEY=$(load_secret DASHSCOPE_API_KEY)
TAVILY_API_KEY=$(load_secret TAVILY_API_KEY)
CCR_APIKEY=$(load_secret CCR_APIKEY)

# ── resolve_secret: 替换配置中的 __PLACEHOLDER__ 为实际秘钥 ──
resolve_secret() {
  local src="$1" dst="$2"
  python3 "$MERGE" resolve "$src" "$dst"
}

if [ -z "$PROFILE" ]; then
  echo "用法: $0 <deepseek|layer2-search|direct [qwen|deepseek]|hybrid|hybrid-toolfree|layer1|layer2|layer3>"
  echo ""
  echo "  deepseek          — 纯 DeepSeek CCR 路由（Opus→Pro, Haiku/Sonnet→Flash）"
  echo "  layer2-search     — CCR + LiteLLM + WebSearch随机二选一（Tavily/Exa）"
  echo "  hybrid            — Haiku→DeepSeek / Sonnet+Opus→Qwen（有tool走Qwen）"
  echo "  hybrid-toolfree   — 全部→DeepSeek V4 Flash（不判断tool）"
  exit 1
fi

case "$PROFILE" in
  direct)
    case "$DIRECT_PROVIDER" in
      qwen|deepseek) ;;
      *) echo "错误: direct 可选 qwen 或 deepseek"; exit 1 ;;
    esac
    ;;
  hybrid|hybrid-toolfree|layer1|layer2|layer3|deepseek|layer2-search) ;;
  *) echo "错误: 未知 '$PROFILE'"; exit 1 ;;
esac

# ── 停服务 ──
echo "🛑 停止当前服务..."
~/cc-stack/scripts/ccr-serve.sh stop >/dev/null 2>&1; sleep 1
echo "   CCR 已停止"
LITELLM_PID=$(lsof -ti :4000 2>/dev/null || true)
[ -n "$LITELLM_PID" ] && kill "$LITELLM_PID" 2>/dev/null && echo "   LiteLLM 已停止" || true
sleep 1

# ── 部署配置 ──
echo "📁 部署 $PROFILE 配置..."

case "$PROFILE" in
  direct)
    echo "   直连模式不需要 CCR/LiteLLM"
    ;;
  hybrid)
    mkdir -p "$CCR_CONFIG_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/hybrid/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    cp "$PROFILES_DIR/hybrid/custom-router.js" "$CCR_CONFIG_DIR/custom-router.js"
    rm -f "$TMPCFG"
    echo "   Hybrid: Haiku→DeepSeek / Sonnet+Opus→Qwen"
    ;;
  hybrid-toolfree)
    mkdir -p "$CCR_CONFIG_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/hybrid-toolfree/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    cp "$PROFILES_DIR/hybrid-toolfree/custom-router.js" "$CCR_CONFIG_DIR/custom-router.js"
    rm -f "$TMPCFG"
    echo "   ToolFreeFree: 全部→DeepSeek V4 Flash"
    ;;
  layer1)
    mkdir -p "$CCR_CONFIG_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/layer1/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    rm -f "$TMPCFG"
    echo "   Layer1 CCR 已部署"
    ;;
  deepseek)
    mkdir -p "$CCR_CONFIG_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/deepseek/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    cp "$PROFILES_DIR/deepseek/custom-router.js" "$CCR_CONFIG_DIR/custom-router.js"
    rm -f "$TMPCFG"
    echo "   DeepSeek: 全量→DeepSeek (Opus→Pro, Haiku/Sonnet→Flash)"
    ;;
  layer2)
    mkdir -p "$CCR_CONFIG_DIR" "$LITELLM_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/layer2/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    rm -f "$TMPCFG"
    python3 "$MERGE" litellm "$LITELLM_DIR/config.yaml" "$PROFILES_DIR/layer2/litellm.yaml"
    echo "   Layer2 CCR + LiteLLM 已部署"
    ;;
  layer2-search)
    mkdir -p "$CCR_CONFIG_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/layer2-search/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    cp "$PROFILES_DIR/layer2-search/custom-router.js" "$CCR_CONFIG_DIR/custom-router.js"
    rm -f "$TMPCFG"
    echo "   Layer2-Search: CCR + Tavily 搜索注入（无需 LiteLLM）"
    ;;
  layer3)
    mkdir -p "$CCR_CONFIG_DIR" "$LITELLM_DIR"
    TMPCFG=$(mktemp)
    resolve_secret "$PROFILES_DIR/layer3/ccr-config.json" "$TMPCFG"
    if [ -f "$CCR_CONFIG_DIR/config.json" ]; then
      python3 "$MERGE" ccr "$CCR_CONFIG_DIR/config.json" "$TMPCFG"
    else
      cp "$TMPCFG" "$CCR_CONFIG_DIR/config.json"
    fi
    rm -f "$TMPCFG"
    python3 "$MERGE" litellm "$LITELLM_DIR/config.yaml" "$PROFILES_DIR/layer3/litellm.yaml"
    echo "   Layer3 CCR + LiteLLM(OR) 已部署"
    ;;
esac

# ── 启动服务（注入 Tavily 环境变量供 custom-router.js 使用）──
echo "🚀 启动 $PROFILE 服务..."
export TAVILY_API_KEY

case "$PROFILE" in
  hybrid|hybrid-toolfree|layer1|deepseek|layer2-search)
    ~/cc-stack/scripts/ccr-serve.sh start 2>&1
    ;;
  layer2|layer3)
    PYTHONPATH="$LITELLM_DIR:$PYTHONPATH" nohup .venv/bin/litellm --config config.yaml --port 4000 --host 127.0.0.1 > "$LITELLM_LOG" 2>&1 &
    echo "   LiteLLM 已启动 (PID $!)"
    sleep 3
    ~/cc-stack/scripts/ccr-serve.sh start 2>&1
    ;;
esac

# ── 同步 VS Code 设置（模板 + 秘钥替换）──
VSCODE_SETTINGS="/mnt/c/Users/dou/AppData/Roaming/Code/User/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
  echo "🔄 同步 VS Code 设置..."
  case "$PROFILE" in
    direct)
      if [ "$DIRECT_PROVIDER" = "qwen" ]; then
        V_T='[{"name":"ANTHROPIC_BASE_URL","value":"https://dashscope.aliyuncs.com/apps/anthropic"},{"name":"ANTHROPIC_AUTH_TOKEN","value":"__DASHSCOPE_API_KEY__"},{"name":"ANTHROPIC_MODEL","value":"qwen3.6-plus"},{"name":"ANTHROPIC_DEFAULT_HAIKU_MODEL","value":"qwen3.6-flash"},{"name":"ANTHROPIC_DEFAULT_SONNET_MODEL","value":"qwen3.6-plus"},{"name":"ANTHROPIC_DEFAULT_OPUS_MODEL","value":"qwen3.7-max"}]'
      else
        V_T='[{"name":"ANTHROPIC_BASE_URL","value":"https://api.deepseek.com/anthropic"},{"name":"ANTHROPIC_AUTH_TOKEN","value":"__DEEPSEEK_API_KEY__"},{"name":"ANTHROPIC_MODEL","value":"deepseek-v4-flash"},{"name":"ANTHROPIC_DEFAULT_HAIKU_MODEL","value":"deepseek-v4-flash"},{"name":"ANTHROPIC_DEFAULT_SONNET_MODEL","value":"deepseek-v4-flash"},{"name":"ANTHROPIC_DEFAULT_OPUS_MODEL","value":"deepseek-v4-pro"}]'
      fi
      ;;
    deepseek|layer2-search)
      V_T='[{"name":"ANTHROPIC_BASE_URL","value":"http://localhost:3456"},{"name":"ANTHROPIC_AUTH_TOKEN","value":"__CCR_APIKEY__"},{"name":"ANTHROPIC_DEFAULT_HAIKU_MODEL","value":"deepseek-v4-flash[1m]"},{"name":"ANTHROPIC_DEFAULT_SONNET_MODEL","value":"deepseek-v4-flash[1m]"},{"name":"ANTHROPIC_DEFAULT_OPUS_MODEL","value":"deepseek-v4-pro[1m]"}]'
      ;;
    hybrid|hybrid-toolfree|layer1|layer2|layer3)
      V_T='[{"name":"ANTHROPIC_BASE_URL","value":"http://localhost:3456"},{"name":"ANTHROPIC_AUTH_TOKEN","value":"__CCR_APIKEY__"},{"name":"ANTHROPIC_DEFAULT_HAIKU_MODEL","value":"deepseek-v4-flash[1m]"},{"name":"ANTHROPIC_DEFAULT_SONNET_MODEL","value":"qwen3.6-plus"},{"name":"ANTHROPIC_DEFAULT_OPUS_MODEL","value":"qwen3.7-max"}]'
      ;;
  esac
  VSCODE_ENVS="${V_T//__DEEPSEEK_API_KEY__/$DEEPSEEK_API_KEY}"
  VSCODE_ENVS="${VSCODE_ENVS//__DASHSCOPE_API_KEY__/$DASHSCOPE_API_KEY}"
  VSCODE_ENVS="${VSCODE_ENVS//__CCR_APIKEY__/$CCR_APIKEY}"
  python3 "$MERGE" vscode "$VSCODE_SETTINGS" "$VSCODE_ENVS"
  echo "   VS Code 已同步 → Reload Window 生效"
else
  echo "⚠️  VS Code settings.json 未找到"
fi

# ── 同步 WSL 终端配置 ──
WSL_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$WSL_SETTINGS" ]; then
  echo "🔄 同步 WSL 终端配置..."
  case "$PROFILE" in
    direct)
      if [ "$DIRECT_PROVIDER" = "qwen" ]; then
        W_T='{"ANTHROPIC_BASE_URL":"https://dashscope.aliyuncs.com/apps/anthropic","ANTHROPIC_AUTH_TOKEN":"__DASHSCOPE_API_KEY__","ANTHROPIC_MODEL":"qwen3.6-plus","ANTHROPIC_DEFAULT_HAIKU_MODEL":"qwen3.6-flash","ANTHROPIC_DEFAULT_SONNET_MODEL":"qwen3.6-plus","ANTHROPIC_DEFAULT_OPUS_MODEL":"qwen3.7-max"}'
      else
        W_T='{"ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"__DEEPSEEK_API_KEY__","ANTHROPIC_MODEL":"deepseek-v4-flash","ANTHROPIC_DEFAULT_HAIKU_MODEL":"deepseek-v4-flash","ANTHROPIC_DEFAULT_SONNET_MODEL":"deepseek-v4-flash","ANTHROPIC_DEFAULT_OPUS_MODEL":"deepseek-v4-pro"}'
      fi
      ;;
    deepseek|layer2-search)
      W_T='{"ANTHROPIC_BASE_URL":"http://localhost:3456","ANTHROPIC_AUTH_TOKEN":"__CCR_APIKEY__","ANTHROPIC_DEFAULT_HAIKU_MODEL":"deepseek-v4-flash[1m]","ANTHROPIC_DEFAULT_SONNET_MODEL":"deepseek-v4-flash[1m]","ANTHROPIC_DEFAULT_OPUS_MODEL":"deepseek-v4-pro[1m]"}'
      ;;
    hybrid|hybrid-toolfree|layer1|layer2|layer3)
      W_T='{"ANTHROPIC_BASE_URL":"http://localhost:3456","ANTHROPIC_AUTH_TOKEN":"__CCR_APIKEY__","ANTHROPIC_DEFAULT_HAIKU_MODEL":"deepseek-v4-flash[1m]","ANTHROPIC_DEFAULT_SONNET_MODEL":"qwen3.6-plus","ANTHROPIC_DEFAULT_OPUS_MODEL":"qwen3.7-max"}'
      ;;
  esac
  WSL_ENVS="${W_T//__DEEPSEEK_API_KEY__/$DEEPSEEK_API_KEY}"
  WSL_ENVS="${WSL_ENVS//__DASHSCOPE_API_KEY__/$DASHSCOPE_API_KEY}"
  WSL_ENVS="${WSL_ENVS//__CCR_APIKEY__/$CCR_APIKEY}"
  python3 "$MERGE" wsl "$WSL_SETTINGS" "$WSL_ENVS"
  echo "   WSL 终端已同步"
else
  echo "⚠️  WSL ~/.claude/settings.json 未找到"
fi

# ── 使用说明 ──
echo ""
echo "═══════════════════════════════════════"
echo "  ✅ 当前模式: $PROFILE"
case "$PROFILE.$DIRECT_PROVIDER" in
  direct.qwen)         echo "     供应商: 百炼 Qwen" ;;
  direct.deepseek)     echo "     供应商: DeepSeek (直连)" ;;
  deepseek)            echo "     供应商: DeepSeek (CCR路由, Opus→Pro)" ;;
  layer2-search)       echo "     CCR + Tavily 搜索注入 + Qwen视觉" ;;
  hybrid)              echo "     Haiku→DeepSeek | Sonnet→QwenPlus | Opus→QwenMax" ;;
  hybrid-toolfree)     echo "     全部→DeepSeek V4 Flash（不判断tool）" ;;
  layer1)              echo "     CCR 协议转换路由" ;;
  layer2|layer3)       echo "     CCR + LiteLLM 网关" ;;
esac
echo "═══════════════════════════════════════"

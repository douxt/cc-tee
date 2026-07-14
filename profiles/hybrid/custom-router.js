// 三级模型自动分流路由器
// Haiku → DeepSeek V4 Flash / Opus → DeepSeek V4 Pro / Sonnet → 百炼 Qwen
// 安全兜底：如果本次请求需要调用工具，不走 DeepSeek
module.exports = async function router(req, config) {
  const model = req.body.model;

  // 本次请求带了 tools → CC 期望模型调用工具
  // DeepSeek 在多轮 tool call 中存在 reasoning_content 问题
  const needsTools = Array.isArray(req.body.tools) && req.body.tools.length > 0;

  if (needsTools && (model.includes('v4-flash') || model.includes('v4-pro'))) {
    return 'dashscope,qwen3.7-flash'; // 需要工具调用 → 降级到 Qwen Flash
  }

  // Opus → DeepSeek Pro（深度推理）
  if (model.includes('opus')) return 'deepseek,deepseek-v4-pro';
  // Sonnet → Qwen（中等任务）
  if (model.includes('sonnet')) return 'dashscope,qwen3.7-plus';
  // Haiku → DeepSeek Flash（轻量任务）
  if (model.includes('deepseek-v4-flash')) return 'deepseek,deepseek-v4-flash';
  // Dashscope 请求 → 直接走百炼
  if (model.includes('qwen3.7-max'))       return 'dashscope,qwen3.7-max';
  if (model.includes('qwen3.7-plus'))      return 'dashscope,qwen3.7-plus';

  return null;
};

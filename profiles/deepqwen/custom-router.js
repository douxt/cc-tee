// deepqwen: DeepSeek+Qwen 组合，mini-router 真透传
// Haiku→DeepSeek Flash / Sonnet→DeepSeek Pro / Opus→Qwen3.7-Max
module.exports = async function router(req, config) {
  req.body.model = req.body.model.replace(/\[1m\]$/, '');
  const model = req.body.model;

  if (model.includes('qwen3.7-max'))       return 'dashscope,qwen3.7-max';
  if (model.includes('qwen3.7-plus'))      return 'dashscope,qwen3.7-plus';
  if (model.includes('qwen3.7-flash'))     return 'dashscope,qwen3.7-flash';
  if (model.includes('deepseek-v4-pro'))   return 'deepseek,deepseek-v4-pro';
  if (model.includes('deepseek-v4-flash')) return 'deepseek,deepseek-v4-flash';

  return null;
};

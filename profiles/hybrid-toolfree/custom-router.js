// 所有模型层级 → DeepSeek V4 Flash（不判断 tool call）
module.exports = async function router(req, config) {
  const model = req.body.model;
  // Opus 走 Pro，其余走 Flash
  if (model.includes('opus')) return 'deepseek,deepseek-v4-pro';
  return 'deepseek,deepseek-v4-flash';
};

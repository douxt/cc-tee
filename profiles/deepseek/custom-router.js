module.exports = async function router(req, config) {
  const model = req.body.model;
  // Opus → Pro（深度推理）
  if (model.includes('opus') || model.includes('v4-pro')) return 'deepseek,deepseek-v4-pro';
  // 其余 → Flash（轻量/中等任务）
  return 'deepseek,deepseek-v4-flash';
};

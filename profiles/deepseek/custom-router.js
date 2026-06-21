module.exports = async function router(req, config) {
  const model = req.body.model;
  // Haiku → Flash（轻量）
  if (model.includes('haiku')) return 'deepseek,deepseek-v4-flash';
  // 其余 → Pro（默认+Sonnet+Opus 全走深度推理）
  return 'deepseek,deepseek-v4-pro';
};

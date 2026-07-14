module.exports = async function router(req, config) {
  // 检测消息中是否含图片（Anthropic 格式 {type:"image",source:{...}}）
  const hasImage = req.body.messages?.some(msg =>
    Array.isArray(msg.content) && msg.content.some(c => c?.type === 'image')
  );

  if (hasImage) {
    // 有图片 → 走 Qwen Flash 多模态（DeepSeek V4 不支持视觉）
    return 'dashscope,qwen3.7-flash';
  }

  const hasWebSearch = req.body.tools?.some(t =>
    t?.name === 'web_search' ||
    t?.type === 'web_search_20250305' ||
    t?.function?.name === 'litellm_web_search'
  );

  if (hasWebSearch && req.body.messages?.length) {
    // 提取搜索查询
    const msgs = req.body.messages;
    let query = '';
    for (let i = msgs.length - 1; i >= 0; i--) {
      const c = msgs[i].content;
      if (msgs[i].role === 'user') {
        query = typeof c === 'string' ? c : c?.find(b => b.type === 'text')?.text || '';
        break;
      }
    }

    if (query) {
      try {
        const res = await fetch('https://api.tavily.com/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            api_key: process.env.TAVILY_API_KEY,
            query: query,
            max_results: 5,
          }),
        });
        const data = await res.json();
        const results = data.results?.map(r =>
          `- ${r.title}\n  ${r.url}\n  ${r.content?.slice(0, 200)}`
        ).join('\n') || '';

        if (results) {
          const prefix = `[网络搜索结果]\n${results}\n\n---\n用户问题: `;
          for (let i = msgs.length - 1; i >= 0; i--) {
            const c = msgs[i].content;
            if (msgs[i].role === 'user') {
              if (typeof c === 'string') {
                msgs[i].content = prefix + c;
              } else if (Array.isArray(c)) {
                for (const b of c) {
                  if (b.type === 'text') { b.text = prefix + b.text; break; }
                }
              }
              break;
            }
          }
          // 移除 tools，DeepSeek 直接基于搜索结果回答
          req.body.tools = [];
          req.body.tool_choice = 'none';
        }
      } catch (e) {
        // 搜索失败，继续正常流程
      }
    }
  }

  const model = req.body.model;
  if (model.includes('haiku')) return 'deepseek,deepseek-v4-flash';
  return 'deepseek,deepseek-v4-pro';
};

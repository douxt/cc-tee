#!/bin/bash
# ccr-routes.sh — 快速查看 CCR 路由统计
# 用法: ./ccr-routes.sh [hours]  # 默认只看最近 N 小时的请求

LOG_DIR="$HOME/.claude-code-router/logs"
HOURS=${1:-1}

#!/bin/bash
# ccr-routes.sh — 快速查看 CCR 路由统计
# 用法: ./ccr-routes.sh [hours]  # 默认只看最近 N 小时的请求

LOG_DIR="$HOME/.claude-code-router/logs"
HOURS=${1:-1}

grep -h '"msg":"final request"' "$LOG_DIR"/ccr-*.log 2>/dev/null | \
tail -n 5000 | \
python3 -c "
import sys, json, re, os, datetime
hours = int(os.environ.get('CCR_HOURS', '1'))
now_ts = datetime.datetime.now().timestamp() * 1000
cutoff = now_ts - hours * 3600000
stats = {'total':0,'deepseek':0,'dashscope':0,'openrouter':0,'other':0}
models = {}
tool_yes = 0
tool_no = 0
skipped_ts = 0
for line in sys.stdin:
    try: d = json.loads(line.strip())
    except: continue
    ts = d.get('time', 0)
    if ts and ts < cutoff: skipped_ts += 1; continue
    url = d.get('requestUrl','')
    req_body = d.get('request',{}).get('body','')
    data_field = d.get('data','')
    # Extract model from actual JSON body first, then data field
    name = '?'
    if isinstance(req_body, str):
        m = re.search(r'\"model\":\"([^\"]+)\"', req_body)
        if m: name = m.group(1)[:40]
    if name == '?' and isinstance(data_field, str):
        m = re.search(r'\"model\":\"([^\"]+)\"', data_field)
        if m: name = m.group(1)[:40]
    if 'deepseek.com' in url: stats['deepseek']+=1
    elif 'dashscope' in url: stats['dashscope']+=1
    elif 'openrouter.ai' in url: stats['openrouter']+=1
    else: stats['other']+=1
    models[name] = models.get(name,0)+1
    combined = (str(req_body)+' '+str(data_field))
    if '\"tools\"' in combined: tool_yes+=1
    else: tool_no+=1
    stats['total']+=1
t=stats['total'] or 1
print(f'📊 CCR 路由 (近 {hours}h, 最多 5000 条, 跳过{skipped_ts}条超期)')
print('='*50)
for k,v in stats.items():
    if k=='total': continue
    print(f'  → {k:12s}: {v} ({v/t*100:.0f}%)')
print(f'  with_tools={tool_yes}  without={tool_no}')
if models:
    print()
    print('模型:')
    for mk,mc in sorted(models.items(),key=lambda x:-x[1]):
        if mc < t/50: break
        print(f'  → {mk:40s}: {mc}')
" CCR_HOURS=$HOURS 2>&1

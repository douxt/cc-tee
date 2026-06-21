#!/usr/bin/env python3
"""
部分合并配置文件，只替换指定字段，保留其他自定义配置。
用法:
  merge-config.py resolve <模板文件> <输出文件>       # 替换 __PLACEHOLDER__ 为 secret.json 实际值
  merge-config.py ccr <目标文件> <profile配置>        # 合并 CCR config.json
  merge-config.py litellm <目标文件> <profile配置>     # 合并 LiteLLM config.yaml
  merge-config.py vscode <目标文件> <envs_json>       # 合并 VS Code settings.json
  merge-config.py wsl <目标文件> <envs_json>          # 合并 WSL ~/.claude/settings.json
"""
import json
import sys
import copy
import os
from datetime import datetime

def merge_ccr(target_path, profile_path):
    with open(target_path) as f:
        target = json.load(f)
    with open(profile_path) as f:
        profile = json.load(f)

    # 替换关键路由字段，其他自定义配置保留
    target['Providers'] = copy.deepcopy(profile['Providers'])
    target['Router'] = copy.deepcopy(profile['Router'])
    # 同步必要的基础设置（如果在 profile 中有定义）
    for key in ('APIKEY', 'HOST', 'LOG', 'API_TIMEOUT_MS', 'CUSTOM_ROUTER_PATH', 'transformers'):
        if key in profile:
            target[key] = copy.deepcopy(profile[key])

    with open(target_path, 'w') as f:
        json.dump(target, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"   已合并 Providers + Router，其他配置保持不动")

def merge_litellm(target_path, profile_path):
    import yaml
    with open(target_path) as f:
        target = yaml.safe_load(f) or {}
    with open(profile_path) as f:
        profile = yaml.safe_load(f) or {}

    # 只替换 model_list，其他全部保留
    target['model_list'] = copy.deepcopy(profile['model_list'])

    with open(target_path, 'w') as f:
        yaml.dump(target, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    print(f"   已合并 model_list，其他配置保持不动")

def resolve_config(template_path, secret_path, output_path):
    """替换模板中的 __PLACEHOLDER__ 为 secret.json 的实际值。"""
    with open(secret_path) as f:
        secrets = json.load(f)
    with open(template_path) as f:
        content = f.read()
    for key, val in secrets.items():
        content = content.replace(f'__{key}__', val)
    with open(output_path, 'w') as f:
        f.write(content)
    print(f"   已注入秘钥 → {os.path.basename(output_path)}")

def merge_vscode(target_path, envs_json_str):
    # envs_json_str 是 JSON 字符串: [{"name":"...","value":"..."}, ...]
    envs = json.loads(envs_json_str)

    with open(target_path) as f:
        target = json.load(f)

    # 只改 claudeCode 相关设置
    target['claudeCode.disableLoginPrompt'] = True
    target['claudeCode.environmentVariables'] = envs

    with open(target_path, 'w') as f:
        json.dump(target, f, indent=4, ensure_ascii=False)
        f.write('\n')

    print(f"   已更新 VS Code claudeCode 设置（其他设置保持不动）")

def merge_wsl(target_path, envs_json_str):
    # envs_json_str 是 JSON 字符串: {"KEY": "VALUE", ...}
    new_env = json.loads(envs_json_str)

    # 时间戳备份
    bak = target_path + '.bak.' + datetime.now().strftime('%Y%m%d_%H%M%S')
    import shutil
    shutil.copy2(target_path, bak)
    print(f"   已备份: {os.path.basename(bak)}")

    with open(target_path) as f:
        target = json.load(f)

    # 只替换 env 字段，其他全部保留
    target['env'] = new_env

    with open(target_path, 'w') as f:
        json.dump(target, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"   已更新 env 配置（permissions/hooks/plugins 等保持不动）")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("用法: merge-config.py <ccr|litellm|vscode|wsl> <目标文件> [<profile配置>|<envs_json>]")
        sys.exit(1)

    mode = sys.argv[1]
    target = sys.argv[2]
    SECRET = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'config', 'secret.json')

    if mode == 'resolve':
        resolve_config(target, SECRET, sys.argv[3])
    elif mode == 'vscode':
        envs_json = sys.argv[3]
        merge_vscode(target, envs_json)
    elif mode == 'wsl':
        envs_json = sys.argv[3]
        merge_wsl(target, envs_json)
    elif len(sys.argv) != 4:
        print("用法: merge-config.py <ccr|litellm> <目标文件> <profile配置>")
        sys.exit(1)
    else:
        profile = sys.argv[3]
        if mode == 'ccr':
            merge_ccr(target, profile)
        elif mode == 'litellm':
            try:
                merge_litellm(target, profile)
            except ImportError:
                print("需要 PyYAML: pip install pyyaml")
                import subprocess
                subprocess.run(['cp', profile, target])
                print("   (fallback 直接覆盖)")
        else:
            print(f"未知模式: {mode}")
            sys.exit(1)

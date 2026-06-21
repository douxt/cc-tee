#!/bin/bash
# ccr-serve.sh — CCR 常驻守护脚本
# 用法: ./ccr-serve.sh start|stop|status|restart

NODEBIN="/usr/bin/node"
CCRBIN="/home/dou/.npm-global/lib/node_modules/@musistudio/claude-code-router/dist/cli.js"
PIDFILE="/tmp/ccr-serve.pid"
LOGFILE="/home/dou/.claude-code-router/logs/ccr-serve.log"

is_running() {
    [ -f "$PIDFILE" ] && {
        local pid=$(cat "$PIDFILE")
        kill -0 "$pid" 2>/dev/null && curl -sf http://localhost:3456/ >/dev/null 2>&1 && \
            echo "$pid" && return 0
    }
    rm -f "$PIDFILE"; return 1
}

start() {
    local pid; pid=$(is_running)
    [ $? -eq 0 ] && { echo "CCR 已在运行 (PID $pid)"; return 0; }
    pkill -f "claude-code-router/dist/cli.js" 2>/dev/null; sleep 1
    nohup "$NODEBIN" "$CCRBIN" start >> "$LOGFILE" 2>&1 &
    disown; echo $! > "$PIDFILE"
    for i in $(seq 1 10); do
        curl -sf http://localhost:3456/ >/dev/null 2>&1 && { echo "CCR 已启动 (PID $(cat "$PIDFILE"))"; return 0; }
        sleep 0.5
    done
    echo "启动超时:"; tail -20 "$LOGFILE"; return 1
}

stop() {
    is_running >/dev/null 2>&1 || { rm -f "$PIDFILE"; echo "未运行"; return 0; }
    kill "$(cat "$PIDFILE")" 2>/dev/null; sleep 2; kill -9 "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"; echo "已停止"
}

status() {
    local pid; pid=$(is_running) && echo "运行中 (PID $pid)" || echo "未运行"
}

case "${1:-status}" in
    start|stop|restart|status) "$1"; shift ;;
    *) echo "用法: $0 {start|stop|restart|status}" ;;
esac

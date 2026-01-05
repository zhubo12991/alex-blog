#!/bin/bash

# 配置
FILE_PATH="/tmp/.npm"
mkdir -p "$FILE_PATH"
HTTP_PORT="${PORT:-8080}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[启动] 端口: $HTTP_PORT"

# HTTP 服务器
cat > "${FILE_PATH}/server.js" <<'JSEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');
const port = process.argv[2] || 8080;
const publicDir = process.argv[3] || './public';
const subFile = '/tmp/.npm/sub.txt';

http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    if (url.includes('health')) { res.end('OK'); return; }
    if (url.includes('/sub')) {
        try { res.end(fs.readFileSync(subFile, 'utf8')); } 
        catch(e) { res.end('Loading...'); }
        return;
    }
    if (url.includes('/log')) {
        try { res.end(fs.readFileSync('/tmp/.npm/debug.log', 'utf8')); } 
        catch(e) { res.end('No log'); }
        return;
    }
    const file = url === '/' ? path.join(publicDir, 'index.html') : path.join(publicDir, url);
    fs.readFile(file, (err, data) => {
        res.writeHead(err ? 404 : 200);
        res.end(err ? '404' : data);
    });
}).listen(port, () => console.log('[HTTP] :' + port));
JSEOF

node "${FILE_PATH}/server.js" $HTTP_PORT "${SCRIPT_DIR}/public" &
echo "[HTTP] Started"

# 调试日志
LOG="${FILE_PATH}/debug.log"
echo "=== Debug Log ===" > "$LOG"
echo "Time: $(date)" >> "$LOG"
echo "Arch: $(uname -m)" >> "$LOG"
echo "Script Dir: $SCRIPT_DIR" >> "$LOG"

# UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "[UUID] $UUID"
echo "UUID: $UUID" >> "$LOG"

# 二进制文件检查
SB="${SCRIPT_DIR}/bin/sb"
CF="${SCRIPT_DIR}/bin/cloudflared"

echo "Checking binaries..." >> "$LOG"
ls -la "${SCRIPT_DIR}/bin/" >> "$LOG" 2>&1

if [ -f "$SB" ]; then
    chmod +x "$SB"
    echo "SB exists: $(file $SB 2>&1)" >> "$LOG"
else
    echo "SB not found!" >> "$LOG"
fi

if [ -f "$CF" ]; then
    chmod +x "$CF"
    echo "CF exists: $(file $CF 2>&1)" >> "$LOG"
else
    echo "CF not found!" >> "$LOG"
fi

# sing-box 配置
cat > "${FILE_PATH}/config.json" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "vless",
    "listen": "127.0.0.1",
    "listen_port": 8081,
    "users": [{"uuid": "$UUID"}],
    "transport": {"type": "ws", "path": "/$UUID-vl"}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF

# 启动 sing-box
echo "Starting SB..." >> "$LOG"
"$SB" run -c "${FILE_PATH}/config.json" >> "$LOG" 2>&1 &
SB_PID=$!
sleep 2
if kill -0 $SB_PID 2>/dev/null; then
    echo "[SB] Started (PID: $SB_PID)"
    echo "SB running: PID $SB_PID" >> "$LOG"
else
    echo "[SB] Failed to start"
    echo "SB failed!" >> "$LOG"
fi

# 启动 cloudflared
ARGO_LOG="${FILE_PATH}/argo.log"
echo "Starting CF..." >> "$LOG"
echo "[Argo] Starting cloudflared..."

# 测试 cloudflared 版本
"$CF" --version >> "$LOG" 2>&1
echo "CF version check done" >> "$LOG"

# 启动隧道
"$CF" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:8081 > "$ARGO_LOG" 2>&1 &
CF_PID=$!
echo "CF started with PID: $CF_PID" >> "$LOG"

# 等待获取域名
echo "[Argo] Waiting for tunnel..."
for i in {1..40}; do
    sleep 1
    echo "Wait $i..." >> "$LOG"
    
    # 检查进程是否还在运行
    if ! kill -0 $CF_PID 2>/dev/null; then
        echo "[Argo] Process died!"
        echo "CF process died at wait $i" >> "$LOG"
        echo "Argo log:" >> "$LOG"
        cat "$ARGO_LOG" >> "$LOG" 2>&1
        break
    fi
    
    DOMAIN=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$ARGO_LOG" 2>/dev/null | head -1 | sed 's|https://||')
    if [ -n "$DOMAIN" ]; then
        echo "[Argo] Domain: $DOMAIN"
        echo "Got domain: $DOMAIN" >> "$LOG"
        echo "vless://${UUID}@cf.090227.xyz:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2F${UUID}-vl#VL-Node" > "${FILE_PATH}/sub.txt"
        echo "[Done] Subscription ready!"
        break
    fi
done

# 如果没有获取到域名
if [ -z "$DOMAIN" ]; then
    echo "[Error] Failed to get tunnel domain"
    echo "=== Argo Log ===" >> "$LOG"
    cat "$ARGO_LOG" >> "$LOG" 2>&1
fi

echo "=== End ===" >> "$LOG"
echo "[Info] Check /log for debug info"

# 保持运行
while true; do sleep 60; done

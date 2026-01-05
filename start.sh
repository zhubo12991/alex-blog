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
    const file = url === '/' ? path.join(publicDir, 'index.html') : path.join(publicDir, url);
    fs.readFile(file, (err, data) => {
        res.writeHead(err ? 404 : 200);
        res.end(err ? '404' : data);
    });
}).listen(port, () => console.log('[HTTP] :' + port));
JSEOF

node "${FILE_PATH}/server.js" $HTTP_PORT "${SCRIPT_DIR}/public" &
echo "[HTTP] Started"

# UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "[UUID] $UUID"

# 二进制文件
SB="${SCRIPT_DIR}/bin/sb"
CF="${SCRIPT_DIR}/bin/cloudflared"
chmod +x "$SB" "$CF" 2>/dev/null

# sing-box 配置 (只用一个 vless)
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
"$SB" run -c "${FILE_PATH}/config.json" &
sleep 2
echo "[SB] Started"

# 启动一个 Argo 隧道
LOG="${FILE_PATH}/argo.log"
"$CF" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:8081 > "$LOG" 2>&1 &
echo "[Argo] Starting..."

# 等待获取域名
for i in {1..40}; do
    sleep 1
    DOMAIN=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | head -1 | sed 's|https://||')
    if [ -n "$DOMAIN" ]; then
        echo "[Argo] Domain: $DOMAIN"
        echo "vless://${UUID}@cf.090227.xyz:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2F${UUID}-vl#VL-Node" > "${FILE_PATH}/sub.txt"
        echo "[Done] Subscription ready!"
        break
    fi
    echo "[Argo] Waiting... $i/40"
done

# 如果失败，显示日志
if [ -z "$DOMAIN" ]; then
    echo "[Error] Argo tunnel failed. Log:"
    cat "$LOG"
fi

# 保持运行
while true; do sleep 60; done

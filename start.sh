#!/bin/bash

# ===== 配置 =====
export FILE_PATH="/tmp/.npm"
mkdir -p "$FILE_PATH"

# ===== 获取端口 =====
if [ -n "$SERVER_PORT" ]; then
    HTTP_PORT="$SERVER_PORT"
elif [ -n "$PORT" ]; then
    HTTP_PORT="$PORT"
else
    HTTP_PORT=8080
fi

echo "[启动] 端口: $HTTP_PORT"

# ===== 立即启动 HTTP 服务器（满足健康检查） =====
PUBLIC_DIR="${PWD}/public"
cat > "${FILE_PATH}/server.js" <<'JSEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');
const port = process.argv[2] || 8080;
const bind = process.argv[3] || '0.0.0.0';
const publicDir = process.argv[4] || './public';
const filePathDir = process.argv[5] || '/tmp/.npm';

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
};

http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    
    // 健康检查
    if (url.includes('health') || url.includes('check')) {
        res.writeHead(200, {'Content-Type': 'text/plain'});
        res.end('OK');
        return;
    }
    
    if (url.includes('/sub')) {
        res.writeHead(200, {
            'Content-Type': 'text/plain; charset=utf-8',
            'Cache-Control': 'no-cache'
        });
        try { 
            res.end(fs.readFileSync(path.join(filePathDir, 'sub.txt'), 'utf8')); 
        } catch(e) { 
            res.end('Subscription not ready, please wait...'); 
        }
        return;
    }
    
    let filePath = url === '/' ? path.join(publicDir, 'index.html') : path.join(publicDir, url);
    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || 'text/plain';
    
    fs.readFile(filePath, (err, content) => {
        if (err) {
            fs.readFile(path.join(publicDir, 'index.html'), (e, html) => {
                res.writeHead(e ? 404 : 200, {'Content-Type': 'text/html'});
                res.end(e ? '404 Not Found' : html);
            });
        } else {
            res.writeHead(200, {'Content-Type': contentType});
            res.end(content);
        }
    });
}).listen(port, bind, () => console.log('[HTTP] Started on ' + bind + ':' + port));
JSEOF

echo "[HTTP] 启动服务器..."
node "${FILE_PATH}/server.js" $HTTP_PORT 0.0.0.0 "$PUBLIC_DIR" "$FILE_PATH" &
HTTP_PID=$!
sleep 1

# 验证 HTTP 服务器已启动
if ! kill -0 $HTTP_PID 2>/dev/null; then
    echo "[错误] HTTP 服务器启动失败"
    exit 1
fi
echo "[HTTP] PID: $HTTP_PID - 服务器已就绪"

# ===== 后台初始化其他服务 =====
(
    sleep 2
    
    echo "[初始化] 开始后台设置..."
    
    # UUID
    UUID_FILE="${FILE_PATH}/uuid.txt"
    if [ -f "$UUID_FILE" ]; then
        UUID=$(cat "$UUID_FILE")
    else
        UUID=$(cat /proc/sys/kernel/random/uuid)
        echo "$UUID" > "$UUID_FILE"
    fi
    echo "[UUID] $UUID"
    
    # 二进制文件
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    SB_FILE="${FILE_PATH}/sb"
    ARGO_FILE="${FILE_PATH}/cloudflared"
    
    if [ -f "${SCRIPT_DIR}/bin/sb" ]; then
        cp "${SCRIPT_DIR}/bin/sb" "$SB_FILE" && chmod +x "$SB_FILE"
        echo "[二进制] sb 已就绪"
    fi
    
    if [ -f "${SCRIPT_DIR}/bin/cloudflared" ]; then
        cp "${SCRIPT_DIR}/bin/cloudflared" "$ARGO_FILE" && chmod +x "$ARGO_FILE"
        echo "[二进制] cloudflared 已就绪"
    fi
    
    # 证书
    if [ ! -f "${FILE_PATH}/cert.pem" ]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
                -keyout "${FILE_PATH}/private.key" \
                -out "${FILE_PATH}/cert.pem" \
                -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
        fi
        echo "[证书] 已生成"
    fi
    
    # CF 优选
    CF_DOMAINS=("cf.090227.xyz" "cf.877774.xyz" "cf.130519.xyz")
    BEST_CF_DOMAIN="${CF_DOMAINS[0]}"
    
    # ISP
    ISP="Node"
    
    # Sing-box 配置
    INTERNAL_VL_PORT=8081
    INTERNAL_VM_PORT=8082
    INTERNAL_TJ_PORT=8083
    
    cat > "${FILE_PATH}/config.json" <<CFGEOF
{
    "log": {"level": "warn"},
    "inbounds": [
        {
            "type": "vless",
            "tag": "vl-in",
            "listen": "127.0.0.1",
            "listen_port": ${INTERNAL_VL_PORT},
            "users": [{"uuid": "${UUID}"}],
            "transport": {"type": "ws", "path": "/${UUID}-vl"}
        },
        {
            "type": "vmess",
            "tag": "vm-in",
            "listen": "127.0.0.1",
            "listen_port": ${INTERNAL_VM_PORT},
            "users": [{"uuid": "${UUID}", "alterId": 0}],
            "transport": {"type": "ws", "path": "/${UUID}-vm"}
        },
        {
            "type": "trojan",
            "tag": "tj-in",
            "listen": "127.0.0.1",
            "listen_port": ${INTERNAL_TJ_PORT},
            "users": [{"password": "${UUID}"}],
            "transport": {"type": "ws", "path": "/${UUID}-tj"}
        }
    ],
    "outbounds": [{"type": "direct", "tag": "direct"}]
}
CFGEOF
    
    # 启动 Sing-box
    if [ -x "$SB_FILE" ]; then
        "$SB_FILE" run -c "${FILE_PATH}/config.json" > /dev/null 2>&1 &
        SB_PID=$!
        sleep 2
        if kill -0 $SB_PID 2>/dev/null; then
            echo "[SB] PID: $SB_PID"
        else
            echo "[警告] SB 启动失败"
        fi
    fi
    
    # 启动 Argo 隧道
    start_argo() {
        local port=$1
        local log="${FILE_PATH}/argo_${port}.log"
        "$ARGO_FILE" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:${port} > "$log" 2>&1 &
        for i in {1..30}; do
            sleep 1
            local domain=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$log" 2>/dev/null | head -1 | sed 's|https://||')
            if [ -n "$domain" ]; then
                echo "$domain"
                return 0
            fi
        done
        return 1
    }
    
    if [ -x "$ARGO_FILE" ]; then
        echo "[Argo] 启动隧道..."
        VL_DOMAIN=$(start_argo $INTERNAL_VL_PORT)
        VM_DOMAIN=$(start_argo $INTERNAL_VM_PORT)
        TJ_DOMAIN=$(start_argo $INTERNAL_TJ_PORT)
        
        [ -n "$VL_DOMAIN" ] && echo "[Argo] VL: $VL_DOMAIN"
        [ -n "$VM_DOMAIN" ] && echo "[Argo] VM: $VM_DOMAIN"
        [ -n "$TJ_DOMAIN" ] && echo "[Argo] TJ: $TJ_DOMAIN"
        
        # 生成订阅
        > "${FILE_PATH}/list.txt"
        [ -n "$VL_DOMAIN" ] && echo "vless://${UUID}@${BEST_CF_DOMAIN}:443?encryption=none&security=tls&sni=${VL_DOMAIN}&type=ws&host=${VL_DOMAIN}&path=%2F${UUID}-vl#VL-${ISP}" >> "${FILE_PATH}/list.txt"
        [ -n "$VM_DOMAIN" ] && echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"VM-${ISP}\",\"add\":\"${BEST_CF_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${VM_DOMAIN}\",\"path\":\"/${UUID}-vm\",\"tls\":\"tls\",\"sni\":\"${VM_DOMAIN}\"}" | base64 -w 0)" >> "${FILE_PATH}/list.txt"
        [ -n "$TJ_DOMAIN" ] && echo "trojan://${UUID}@${BEST_CF_DOMAIN}:443?security=tls&sni=${TJ_DOMAIN}&type=ws&host=${TJ_DOMAIN}&path=%2F${UUID}-tj#TJ-${ISP}" >> "${FILE_PATH}/list.txt"
        cat "${FILE_PATH}/list.txt" > "${FILE_PATH}/sub.txt"
        
        echo "[完成] 订阅已生成"
    fi
    
    echo "[初始化] 所有服务已启动"
) &

# 保持主进程运行
echo "[主进程] 等待服务..."
trap "kill $HTTP_PID 2>/dev/null; pkill -P $$; exit" SIGTERM SIGINT

while true; do
    sleep 30
    if ! kill -0 $HTTP_PID 2>/dev/null; then
        echo "[错误] HTTP 服务器已停止"
        exit 1
    fi
done

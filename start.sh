#!/bin/bash
set -e

# ===== 配置 =====
ARGO_TOKEN=""

# ===== CF 优选列表 =====
CF_DOMAINS=(
    "cf.090227.xyz"
    "cf.877774.xyz"
    "cf.130519.xyz"
    "cf.008500.xyz"
    "store.ubi.com"
    "saas.sin.fan"
)

# ===== 检查 curl =====
echo "[依赖] 检查 curl..."
if ! command -v curl &> /dev/null; then
    echo "[依赖] 安装 curl..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq 2>/dev/null && apt-get install -y curl -qq 2>/dev/null
    elif command -v yum &> /dev/null; then
        yum install -y curl -q 2>/dev/null
    elif command -v apk &> /dev/null; then
        apk add --no-cache curl -q 2>/dev/null
    fi
    command -v curl &> /dev/null && CURL_AVAILABLE=true || CURL_AVAILABLE=false
else
    CURL_AVAILABLE=true
fi

# ===== 环境准备 =====
cd "$(dirname "$0")"
export FILE_PATH="/tmp/.npm"
mkdir -p "$FILE_PATH"

# ===== 获取公网 IP =====
echo "[网络] 获取 IP..."
PUBLIC_IP=""
if [ "$CURL_AVAILABLE" = true ]; then
    PUBLIC_IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || curl -s --max-time 5 api.ipify.org 2>/dev/null || echo "")
fi
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="${SERVER_IP:-127.0.0.1}"
echo "[网络] IP: $PUBLIC_IP"

# ===== CF 优选 =====
select_random_cf_domain() {
    local available=()
    if [ "$CURL_AVAILABLE" = true ]; then
        for domain in "${CF_DOMAINS[@]}"; do
            curl -s --max-time 2 -o /dev/null "https://$domain" 2>/dev/null && available+=("$domain")
        done
    fi
    [ ${#available[@]} -gt 0 ] && echo "${available[$((RANDOM % ${#available[@]}))]}" || echo "${CF_DOMAINS[0]}"
}

echo "[CF] 测试中..."
BEST_CF_DOMAIN=$(select_random_cf_domain)
echo "[CF] $BEST_CF_DOMAIN"

# ===== 端口获取与分配 =====
if [ -n "$SERVER_PORT" ]; then
    PORTS_STRING="$SERVER_PORT"
elif [ -n "$PORT" ]; then
    PORTS_STRING="$PORT"
else
    PORTS_STRING=""
fi

if [ -n "$PORTS_STRING" ]; then
    read -ra AVAILABLE_PORTS <<< "$PORTS_STRING"
else
    AVAILABLE_PORTS=()
fi

PORT_COUNT=${#AVAILABLE_PORTS[@]}

if [ $PORT_COUNT -eq 0 ]; then
    echo "[端口] 未检测到可用端口,使用默认端口 3000-3003"
    AVAILABLE_PORTS=(3000 3001 3002 3003)
    PORT_COUNT=4
fi

echo "[端口] 可用端口: ${AVAILABLE_PORTS[*]} (共 $PORT_COUNT 个)"

if [ $PORT_COUNT -eq 1 ]; then
    echo "[模式] 单端口模式 ${AVAILABLE_PORTS[0]}"
    HTTP_PORT=${AVAILABLE_PORTS[0]}
    VL_PORT=8081
    VM_PORT=8082
    TJ_PORT=8083
    SINGLE_PORT_MODE=true
elif [ $PORT_COUNT -eq 2 ]; then
    echo "[模式] 双端口模式"
    HTTP_PORT=${AVAILABLE_PORTS[0]}
    VL_PORT=8081
    VM_PORT=8082
    TJ_PORT=8083
    SINGLE_PORT_MODE=true
else
    echo "[模式] 多端口模式"
    HTTP_PORT=${AVAILABLE_PORTS[0]}
    VL_PORT=${AVAILABLE_PORTS[1]}
    VM_PORT=${AVAILABLE_PORTS[2]}
    TJ_PORT=${AVAILABLE_PORTS[3]:-8083}
    SINGLE_PORT_MODE=false
fi

# ===== 清理旧进程 =====
echo "[清理] 旧进程..."
pkill -f "sing-box" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true
pkill -f "server.js" 2>/dev/null || true
sleep 2

# ===== UUID 持久化 =====
UUID_FILE="${FILE_PATH}/uuid.txt"
if [ -f "$UUID_FILE" ]; then
    UUID=$(cat "$UUID_FILE")
else
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "$UUID" > "$UUID_FILE"
fi
echo "[UUID] $UUID"

# ===== 架构检测 & 二进制文件 =====
ARCH=$(uname -m)
[[ "$ARCH" == "aarch64" ]] && BASE_URL="https://arm64.ssss.nyc.mn" || BASE_URL="https://amd64.ssss.nyc.mn"
[[ "$ARCH" == "aarch64" ]] && ARGO_ARCH="arm64" || ARGO_ARCH="amd64"

SB_FILE="${FILE_PATH}/sb"
ARGO_FILE="${FILE_PATH}/cloudflared"

# 查找本地二进制文件（仓库中的 bin/ 目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_SB="${SCRIPT_DIR}/bin/sb"
LOCAL_ARGO="${SCRIPT_DIR}/bin/cloudflared"

# 也检查 /app/bin/ (Docker 环境)
if [ -f "$LOCAL_SB" ]; then
    echo "[二进制] 使用仓库中的 sb"
    cp "$LOCAL_SB" "$SB_FILE" && chmod +x "$SB_FILE"
elif [ -x "/app/bin/sb" ]; then
    echo "[二进制] 使用 /app/bin/sb"
    cp "/app/bin/sb" "$SB_FILE" && chmod +x "$SB_FILE"
else
    echo "[下载] sb..."
    if [ "$CURL_AVAILABLE" = true ]; then
        curl -L -sS --max-time 60 -o "$SB_FILE" "${BASE_URL}/sb" && chmod +x "$SB_FILE"
    fi
fi

if [ -f "$LOCAL_ARGO" ]; then
    echo "[二进制] 使用仓库中的 cloudflared"
    cp "$LOCAL_ARGO" "$ARGO_FILE" && chmod +x "$ARGO_FILE"
elif [ -x "/app/bin/cloudflared" ]; then
    echo "[二进制] 使用 /app/bin/cloudflared"
    cp "/app/bin/cloudflared" "$ARGO_FILE" && chmod +x "$ARGO_FILE"
else
    echo "[下载] cloudflared..."
    if [ "$CURL_AVAILABLE" = true ]; then
        curl -L -sS --max-time 60 -o "$ARGO_FILE" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARGO_ARCH}" && chmod +x "$ARGO_FILE"
    fi
fi

[ ! -x "$SB_FILE" ] && echo "[错误] sb 不可用" && exit 1
[ ! -x "$ARGO_FILE" ] && echo "[错误] cloudflared 不可用" && exit 1

# ===== 证书 =====
if [ ! -f "${FILE_PATH}/cert.pem" ] || [ ! -f "${FILE_PATH}/private.key" ]; then
    echo "[证书] 生成中..."
    if command -v openssl >/dev/null 2>&1; then
        openssl req -x509 -newkey rsa:2048 -nodes -sha256 -keyout "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
    else
        printf -- "-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYV/+siNnfBYsdUYsoAoGCCqGSM49\nAwEHoUQDQgAE1kHafPj07rJG+HboH2ekAI4r+e6TL38GWASAnngZreoQDF16ARa/\nTsyLyFoPkhTxSbehH/OBEjHtSZGaDhMqQ==\n-----END EC PRIVATE KEY-----\n" > "${FILE_PATH}/private.key"
        printf -- "-----BEGIN CERTIFICATE-----\nMIIBejCCASGgAwIBAgIUFWeQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw\nEzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwMTAxMDEwMTAwWhcNMzUwMTAxMDEw\nMTAwWjATMREwDwYDVQQDDAhiaW5nLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEH\nA0IABNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgJ54Ga3qEAxdegEWv07Mi8ha\nD5IU8Um3oR/zgRIx7UmRmg4TKkOjUzBRMB0GA1UdDgQWBBTV1cFID7UISE7PLTBR\nBfGbgrkMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgrkMNzAPBgNVHRMB\nAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIARDAJvg0vd/ytrQVvEcSm6XTlB+\neQ6OFb9LbLYL9Zi+AiB+foMbi4y/0YUQlTtz7as9S8/lciBF5VCUoVIKS+vX2g==\n-----END CERTIFICATE-----\n" > "${FILE_PATH}/cert.pem"
    fi
fi

# ===== ISP =====
ISP="Node"
if [ "$CURL_AVAILABLE" = true ]; then
    JSON_DATA=$(curl -s --max-time 2 -H "Referer: https://speed.cloudflare.com/" https://speed.cloudflare.com/meta 2>/dev/null)
    if [ -n "$JSON_DATA" ]; then
        ORG=$(echo "$JSON_DATA" | sed -n 's/.*"asOrganization":"\([^"]*\)".*/\1/p')
        CITY=$(echo "$JSON_DATA" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
        if [ -n "$ORG" ] && [ -n "$CITY" ]; then
            ISP="${ORG}-${CITY}"
        fi
    fi
fi
[ -z "$ISP" ] && ISP="Node"

# ===== 生成订阅 =====
generate_sub() {
    local vl_domain="$1"
    local vm_domain="$2"
    local tj_domain="$3"
    > "${FILE_PATH}/list.txt"
    
    [ -n "$vl_domain" ] && echo "vless://${UUID}@${BEST_CF_DOMAIN}:443?encryption=none&security=tls&sni=${vl_domain}&type=ws&host=${vl_domain}&path=%2F${UUID}-vl#VL-${ISP}" >> "${FILE_PATH}/list.txt"
    
    [ -n "$vm_domain" ] && echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"VM-${ISP}\",\"add\":\"${BEST_CF_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${vm_domain}\",\"path\":\"/${UUID}-vm\",\"tls\":\"tls\",\"sni\":\"${vm_domain}\"}" | base64 -w 0)" >> "${FILE_PATH}/list.txt"
    
    [ -n "$tj_domain" ] && echo "trojan://${UUID}@${BEST_CF_DOMAIN}:443?security=tls&sni=${tj_domain}&type=ws&host=${tj_domain}&path=%2F${UUID}-tj#TJ-${ISP}" >> "${FILE_PATH}/list.txt"
    
    cat "${FILE_PATH}/list.txt" > "${FILE_PATH}/sub.txt"
}

# ===== HTTP 服务器 =====
PUBLIC_DIR="${PWD}/public"
cat > "${FILE_PATH}/server.js" <<'JSEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');
const port = process.argv[2] || 8080;
const bind = process.argv[3] || '0.0.0.0';
const publicDir = process.argv[4] || './public';
const filePathDir = process.argv[5] || './.npm';

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
    
    if (url.includes('/sub')) {
        res.writeHead(200, {
            'Content-Type': 'text/plain; charset=utf-8',
            'Cache-Control': 'no-cache'
        });
        try { 
            res.end(fs.readFileSync(path.join(filePathDir, 'sub.txt'), 'utf8')); 
        } catch(e) { 
            res.end('Subscription not ready'); 
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
}).listen(port, bind, () => console.log('[HTTP] ' + bind + ':' + port));
JSEOF

# ===== 启动 HTTP =====
echo "[HTTP] 启动..."
node "${FILE_PATH}/server.js" $HTTP_PORT 0.0.0.0 "$PUBLIC_DIR" "$FILE_PATH" > /dev/null 2>&1 &
HTTP_PID=$!
sleep 2
kill -0 $HTTP_PID 2>/dev/null || { echo "[错误] HTTP 失败"; exit 1; }
echo "[HTTP] PID: $HTTP_PID"

# ===== 生成配置 =====
echo "[CONFIG] 生成..."

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

# ===== 启动 sb =====
echo "[SB] 启动..."
"$SB_FILE" run -c "${FILE_PATH}/config.json" > /dev/null 2>&1 &
SB_PID=$!
sleep 3
kill -0 $SB_PID 2>/dev/null || { echo "[错误] SB 失败"; "$SB_FILE" run -c "${FILE_PATH}/config.json"; exit 1; }
echo "[SB] PID: $SB_PID"

# ===== Argo =====
ARGO_LOG="${FILE_PATH}/argo.log"

start_argo_tunnel() {
    local port=$1
    local log="${FILE_PATH}/argo_${port}.log"
    
    "$ARGO_FILE" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:${port} > "$log" 2>&1 &
    local pid=$!
    
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

echo "[Argo] 启动..."

VL_DOMAIN=$(start_argo_tunnel $INTERNAL_VL_PORT)
VM_DOMAIN=$(start_argo_tunnel $INTERNAL_VM_PORT)
TJ_DOMAIN=$(start_argo_tunnel $INTERNAL_TJ_PORT)

[ -n "$VL_DOMAIN" ] && echo "[Argo] VL: $VL_DOMAIN" || echo "[警告] Argo-VL 失败"
[ -n "$VM_DOMAIN" ] && echo "[Argo] VM: $VM_DOMAIN" || echo "[警告] Argo-VM 失败"
[ -n "$TJ_DOMAIN" ] && echo "[Argo] TJ: $TJ_DOMAIN" || echo "[警告] Argo-TJ 失败"

# ===== 生成订阅 =====
generate_sub "$VL_DOMAIN" "$VM_DOMAIN" "$TJ_DOMAIN"

# ===== 输出结果 =====
SUB_URL="http://${PUBLIC_IP}:${HTTP_PORT}/sub"

echo ""
echo "===== 完成 ====="
if [ "$SINGLE_PORT_MODE" = true ]; then
    echo "模式: 单端口 (HTTP: $HTTP_PORT)"
else
    echo "模式: 多端口"
fi
echo ""
echo "VL: ${VL_DOMAIN:-N/A}"
echo "VM: ${VM_DOMAIN:-N/A}"
echo "TJ: ${TJ_DOMAIN:-N/A}"
echo ""
echo "订阅: $SUB_URL"
echo "UUID: $UUID"
echo "================"
echo ""

# ===== 静态订阅 =====
cp "${FILE_PATH}/sub.txt" "${PWD}/sub.txt" 2>/dev/null || true
mkdir -p "${PWD}/sub"
cp "${FILE_PATH}/sub.txt" "${PWD}/sub/index.html" 2>/dev/null || true

# ===== 保持运行 =====
trap "pkill -P $$; exit" SIGTERM SIGINT

echo "[完成] 所有服务已启动"

while true; do
    sleep 60
    kill -0 $SB_PID 2>/dev/null || { echo "[错误] SB 停止"; exit 1; }
    kill -0 $HTTP_PID 2>/dev/null || { echo "[错误] HTTP 停止"; exit 1; }
done

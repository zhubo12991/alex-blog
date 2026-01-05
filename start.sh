#!/bin/bash
set -e

# ================== 配置区域 ==================
# 固定隧道填写token，不填默认为临时隧道
ARGO_TOKEN=""

# 单端口模式 UDP 协议选择: hy2 (默认) 或 tuic
SINGLE_PORT_UDP="hy2"

# ================== CF 优选域名列表 ==================
CF_DOMAINS=(
    "cf.090227.xyz"
    "cf.877774.xyz"
    "cf.130519.xyz"
    "cf.008500.xyz"
    "store.ubi.com"
    "saas.sin.fan"
)

# ================== 切换到脚本目录 ==================
cd "$(dirname "$0")"
export FILE_PATH="${PWD}/.npm"
export PUBLIC_DIR="${PWD}/public"

rm -rf "$FILE_PATH"
mkdir -p "$FILE_PATH"

# ================== 获取公网 IP ==================
echo "[网络] 获取公网 IP..."
PUBLIC_IP=$(curl -s --max-time 5 ipv4.ip.sb || curl -s --max-time 5 api.ipify.org || echo "")
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="${SERVER_IP:-127.0.0.1}"
echo "[网络] 公网 IP: $PUBLIC_IP"

# ================== CF 优选：随机选择可用域名 ==================
select_random_cf_domain() {
    local available=()
    for domain in "${CF_DOMAINS[@]}"; do
        if curl -s --max-time 2 -o /dev/null "https://$domain" 2>/dev/null; then
            available+=("$domain")
        fi
    done
    [ ${#available[@]} -gt 0 ] && echo "${available[$((RANDOM % ${#available[@]}))]}" || echo "${CF_DOMAINS[0]}"
}

echo "[CF优选] 测试中..."
BEST_CF_DOMAIN=$(select_random_cf_domain)
echo "[CF优选] $BEST_CF_DOMAIN"

# ================== 获取端口 ==================
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
    echo "[端口] 未找到环境端口，使用默认 3000"
    AVAILABLE_PORTS=(3000)
    PORT_COUNT=1
fi

echo "[端口] 发现 $PORT_COUNT 个: ${AVAILABLE_PORTS[*]}"

# ================== 端口分配逻辑 ==================
if [ $PORT_COUNT -eq 1 ]; then
    UDP_PORT=${AVAILABLE_PORTS[0]}
    TUIC_PORT=""
    HY2_PORT=""
    [[ "$SINGLE_PORT_UDP" == "tuic" ]] && TUIC_PORT=$UDP_PORT || HY2_PORT=$UDP_PORT
    REALITY_PORT=""
    HTTP_PORT=${AVAILABLE_PORTS[0]}
    SINGLE_PORT_MODE=true
else
    TUIC_PORT=${AVAILABLE_PORTS[0]}
    HY2_PORT=${AVAILABLE_PORTS[1]}
    REALITY_PORT=${AVAILABLE_PORTS[0]}
    HTTP_PORT=${AVAILABLE_PORTS[1]}
    SINGLE_PORT_MODE=false
fi

ARGO_PORT=8081

# ================== UUID ==================
UUID_FILE="${FILE_PATH}/uuid.txt"
[ -f "$UUID_FILE" ] && UUID=$(cat "$UUID_FILE") || { UUID=$(cat /proc/sys/kernel/random/uuid); echo "$UUID" > "$UUID_FILE"; }
echo "[UUID] $UUID"

# ================== 架构检测 & 下载 ==================
ARCH=$(uname -m)
[[ "$ARCH" == "aarch64" ]] && BASE_URL="https://arm64.ssss.nyc.mn" || BASE_URL="https://amd64.ssss.nyc.mn"
[[ "$ARCH" == "aarch64" ]] && ARGO_ARCH="arm64" || ARGO_ARCH="amd64"
echo "[架构] $ARCH"

SB_FILE="${FILE_PATH}/sb"
ARGO_FILE="${FILE_PATH}/cloudflared"

download_file() {
    local url=$1 output=$2
    [ -x "$output" ] && return 0
    echo "[下载] $output..."
    curl -L -sS --max-time 60 -o "$output" "$url" && chmod +x "$output" && echo "[下载] $output 完成" && return 0
    echo "[下载] $output 失败" && return 1
}

download_file "${BASE_URL}/sb" "$SB_FILE"
download_file "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARGO_ARCH}" "$ARGO_FILE"

# ================== Reality 密钥 ==================
if [ "$SINGLE_PORT_MODE" = false ]; then
    echo "[密钥] 检查中..."
    KEY_FILE="${FILE_PATH}/key.txt"
    if [ -f "$KEY_FILE" ]; then
        private_key=$(grep "PrivateKey:" "$KEY_FILE" | awk '{print $2}')
        public_key=$(grep "PublicKey:" "$KEY_FILE" | awk '{print $2}')
    else
        output=$("$SB_FILE" generate reality-keypair)
        echo "$output" > "$KEY_FILE"
        private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
        public_key=$(echo "$output" | awk '/PublicKey:/ {print $2}')
    fi
    echo "[密钥] 已就绪"
fi

# ================== 证书生成 ==================
echo "[证书] 生成中..."
if command -v openssl >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -keyout "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -days 3650 -subj "/CN=www.bing.com" >/dev/null 2>&1
else
    printf -- "-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYV/+siNnfBYsdUYsoAoGCCqGSM49\nAwEHoUQDQgAE1kHafPj07rJG+HboH2ekAI4r+e6TL38GWASAnngZreoQDF16ARa/\nTsyLyFoPkhTxSbehH/OBEjHtSZGaDhMqQ==\n-----END EC PRIVATE KEY-----\n" > "${FILE_PATH}/private.key"
    printf -- "-----BEGIN CERTIFICATE-----\nMIIBejCCASGgAwIBAgIUFWeQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw\nEzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwMTAxMDEwMTAwWhcNMzUwMTAxMDEw\nMTAwWjATMREwDwYDVQQDDAhiaW5nLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEH\nA0IABNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgJ54Ga3qEAxdegEWv07Mi8ha\nD5IU8Um3oR/zgRIx7UmRmg4TKkOjUzBRMB0GA1UdDgQWBBTV1cFID7UISE7PLTBR\nBfGbgrkMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgrkMNzAPBgNVHRMB\nAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIARDAJvg0vd/ytrQVvEcSm6XTlB+\neQ6OFb9LbLYL9Zi+AiB+foMbi4y/0YUQlTtz7as9S8/lciBF5VCUoVIKS+vX2g==\n-----END CERTIFICATE-----\n" > "${FILE_PATH}/cert.pem"
fi
echo "[证书] 已就绪"

# ================== ISP 信息 ==================
ISP="Node"
JSON_DATA=$(curl -s --max-time 2 -H "Referer: https://speed.cloudflare.com/" https://speed.cloudflare.com/meta 2>/dev/null || echo "")
if [ -n "$JSON_DATA" ]; then
    ORG=$(echo "$JSON_DATA" | sed -n 's/.*"asOrganization":"\([^"]*\)".*/\1/p')
    CITY=$(echo "$JSON_DATA" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
    [ -n "$ORG" ] && [ -n "$CITY" ] && ISP="${ORG}-${CITY}"
fi

# ================== 生成订阅函数 ==================
generate_sub() {
    local argo_domain="$1"
    > "${FILE_PATH}/list.txt"
    
    # TUIC
    [ -n "$TUIC_PORT" ] && echo "tuic://${UUID}:admin@${PUBLIC_IP}:${TUIC_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr&allowInsecure=1#TUIC-${ISP}" >> "${FILE_PATH}/list.txt"
    
    # HY2
    [ -n "$HY2_PORT" ] && echo "hysteria2://${UUID}@${PUBLIC_IP}:${HY2_PORT}/?sni=www.bing.com&insecure=1#Hysteria2-${ISP}" >> "${FILE_PATH}/list.txt"
    
    # Reality
    [ -n "$REALITY_PORT" ] && echo "vless://${UUID}@${PUBLIC_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=chrome&pbk=${public_key}&type=tcp#Reality-${ISP}" >> "${FILE_PATH}/list.txt"
    
    # Argo VLESS
    [ -n "$argo_domain" ] && echo "vless://${UUID}@${BEST_CF_DOMAIN}:443?encryption=none&security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2F${UUID}-vless#Argo-${ISP}" >> "${FILE_PATH}/list.txt"

    cat "${FILE_PATH}/list.txt" > "${FILE_PATH}/sub.txt"
}

# ================== HTTP 服务器 (带伪装页) ==================
cat > "${FILE_PATH}/server.js" <<'JSEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.argv[2] || 8080;
const bind = process.argv[3] || '0.0.0.0';
const publicDir = process.argv[4] || './public';
const subFile = process.argv[5] || './.npm/sub.txt';
const uuid = process.argv[6] || '';

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.json': 'application/json'
};

http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    
    // 订阅端点
    if (url.includes('/sub') || (uuid && url.includes('/' + uuid))) {
        res.writeHead(200, {
            'Content-Type': 'text/plain; charset=utf-8',
            'Cache-Control': 'no-cache'
        });
        try {
            res.end(fs.readFileSync(subFile, 'utf8'));
        } catch(e) {
            res.end('Subscription not ready');
        }
        return;
    }
    
    // 静态文件服务 (伪装页)
    let filePath = url === '/' ? path.join(publicDir, 'index.html') : path.join(publicDir, url);
    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || 'application/octet-stream';
    
    fs.readFile(filePath, (err, content) => {
        if (err) {
            // 尝试返回 index.html (SPA 支持)
            fs.readFile(path.join(publicDir, 'index.html'), (e, html) => {
                if (e) {
                    res.writeHead(404, {'Content-Type': 'text/plain'});
                    res.end('404 Not Found');
                } else {
                    res.writeHead(200, {'Content-Type': 'text/html'});
                    res.end(html);
                }
            });
        } else {
            res.writeHead(200, {'Content-Type': contentType});
            res.end(content);
        }
    });
}).listen(port, bind, () => console.log('[HTTP] 服务已启动: ' + bind + ':' + port));
JSEOF

# ================== 启动 HTTP 服务 ==================
echo "[HTTP] 启动服务 (端口 $HTTP_PORT)..."
node "${FILE_PATH}/server.js" "$HTTP_PORT" "0.0.0.0" "$PUBLIC_DIR" "${FILE_PATH}/sub.txt" "$UUID" &
HTTP_PID=$!
sleep 1
echo "[HTTP] 已启动 PID: $HTTP_PID"

# ================== 生成 sing-box 配置 ==================
echo "[CONFIG] 生成配置..."

INBOUNDS=""

# TUIC
if [ -n "$TUIC_PORT" ]; then
    INBOUNDS="{
        \"type\": \"tuic\",
        \"tag\": \"tuic-in\",
        \"listen\": \"::\",
        \"listen_port\": ${TUIC_PORT},
        \"users\": [{\"uuid\": \"${UUID}\", \"password\": \"admin\"}],
        \"congestion_control\": \"bbr\",
        \"tls\": {
            \"enabled\": true,
            \"alpn\": [\"h3\"],
            \"certificate_path\": \"${FILE_PATH}/cert.pem\",
            \"key_path\": \"${FILE_PATH}/private.key\"
        }
    }"
fi

# HY2
if [ -n "$HY2_PORT" ]; then
    [ -n "$INBOUNDS" ] && INBOUNDS="${INBOUNDS},"
    INBOUNDS="${INBOUNDS}{
        \"type\": \"hysteria2\",
        \"tag\": \"hy2-in\",
        \"listen\": \"::\",
        \"listen_port\": ${HY2_PORT},
        \"users\": [{\"password\": \"${UUID}\"}],
        \"tls\": {
            \"enabled\": true,
            \"alpn\": [\"h3\"],
            \"certificate_path\": \"${FILE_PATH}/cert.pem\",
            \"key_path\": \"${FILE_PATH}/private.key\"
        }
    }"
fi

# Reality
if [ -n "$REALITY_PORT" ]; then
    [ -n "$INBOUNDS" ] && INBOUNDS="${INBOUNDS},"
    INBOUNDS="${INBOUNDS}{
        \"type\": \"vless\",
        \"tag\": \"vless-reality-in\",
        \"listen\": \"::\",
        \"listen_port\": ${REALITY_PORT},
        \"users\": [{\"uuid\": \"${UUID}\", \"flow\": \"xtls-rprx-vision\"}],
        \"tls\": {
            \"enabled\": true,
            \"server_name\": \"www.nazhumi.com\",
            \"reality\": {
                \"enabled\": true,
                \"handshake\": {\"server\": \"www.nazhumi.com\", \"server_port\": 443},
                \"private_key\": \"${private_key}\",
                \"short_id\": [\"\"]
            }
        }
    }"
fi

# Argo VLESS
[ -n "$INBOUNDS" ] && INBOUNDS="${INBOUNDS},"
INBOUNDS="${INBOUNDS}{
    \"type\": \"vless\",
    \"tag\": \"vless-argo-in\",
    \"listen\": \"127.0.0.1\",
    \"listen_port\": ${ARGO_PORT},
    \"users\": [{\"uuid\": \"${UUID}\"}],
    \"transport\": {\"type\": \"ws\", \"path\": \"/${UUID}-vless\"}
}"

cat > "${FILE_PATH}/config.json" <<CFGEOF
{
    "log": {"level": "warn"},
    "inbounds": [${INBOUNDS}],
    "outbounds": [{"type": "direct", "tag": "direct"}]
}
CFGEOF
echo "[CONFIG] 已生成"

# ================== 启动 sing-box ==================
echo "[SING-BOX] 启动中..."
"$SB_FILE" run -c "${FILE_PATH}/config.json" &
SB_PID=$!
sleep 2

if ! kill -0 $SB_PID 2>/dev/null; then
    echo "[SING-BOX] 启动失败，调试信息:"
    "$SB_FILE" run -c "${FILE_PATH}/config.json" 2>&1 | head -20
    exit 1
fi
echo "[SING-BOX] 已启动 PID: $SB_PID"

# ================== Argo 隧道 ==================
ARGO_LOG="${FILE_PATH}/argo.log"
ARGO_DOMAIN=""

echo "[Argo] 启动隧道..."
"$ARGO_FILE" tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://127.0.0.1:${ARGO_PORT} > "$ARGO_LOG" 2>&1 &
ARGO_PID=$!

for i in {1..30}; do
    sleep 1
    ARGO_DOMAIN=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$ARGO_LOG" 2>/dev/null | head -1 | sed 's|https://||')
    [ -n "$ARGO_DOMAIN" ] && break
done

[ -n "$ARGO_DOMAIN" ] && echo "[Argo] 域名: $ARGO_DOMAIN" || echo "[Argo] 获取域名失败"

# ================== 生成订阅 ==================
generate_sub "$ARGO_DOMAIN"

# ================== 输出结果 ==================
SUB_URL="http://${PUBLIC_IP}:${HTTP_PORT}/sub"

echo ""
echo "==================================================="
if [ "$SINGLE_PORT_MODE" = true ]; then
    echo "模式: 单端口 (${SINGLE_PORT_UDP^^} + Argo)"
    echo ""
    echo "代理节点:"
    [ -n "$HY2_PORT" ] && echo "  - HY2 (UDP): ${PUBLIC_IP}:${HY2_PORT}"
    [ -n "$TUIC_PORT" ] && echo "  - TUIC (UDP): ${PUBLIC_IP}:${TUIC_PORT}"
    [ -n "$ARGO_DOMAIN" ] && echo "  - Argo (WS): ${ARGO_DOMAIN}"
else
    echo "模式: 多端口 (TUIC + HY2 + Reality + Argo)"
    echo ""
    echo "代理节点:"
    echo "  - TUIC (UDP): ${PUBLIC_IP}:${TUIC_PORT}"
    echo "  - HY2 (UDP): ${PUBLIC_IP}:${HY2_PORT}"
    echo "  - Reality (TCP): ${PUBLIC_IP}:${REALITY_PORT}"
    [ -n "$ARGO_DOMAIN" ] && echo "  - Argo (WS): ${ARGO_DOMAIN}"
fi
echo ""
echo "订阅链接: $SUB_URL"
echo "UUID: $UUID"
echo "==================================================="
echo ""

# ================== 保持运行 ==================
trap "kill $SB_PID $HTTP_PID $ARGO_PID 2>/dev/null; exit" SIGTERM SIGINT

echo "[完成] 所有服务已启动，等待进程..."
wait $SB_PID

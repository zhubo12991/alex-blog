FROM node:18-slim

# 安装必要依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    bash \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 预下载二进制文件（带错误检查）
RUN mkdir -p /app/bin \
    && echo "Downloading sb..." \
    && curl -L --fail -o /app/bin/sb https://amd64.ssss.nyc.mn/sb \
    && echo "Downloading cloudflared..." \
    && curl -L --fail -o /app/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /app/bin/sb /app/bin/cloudflared \
    && echo "Verifying downloads..." \
    && ls -la /app/bin/ \
    && /app/bin/sb version || echo "sb version check skipped" \
    && /app/bin/cloudflared --version || echo "cloudflared version check skipped"

# 复制项目文件
COPY package.json ./
COPY index.js ./
COPY start.sh ./
COPY public ./public

# 处理文件编码和创建用户
RUN sed -i '1s/^\xEF\xBB\xBF//' start.sh \
    && sed -i '1s/^\xEF\xBB\xBF//' index.js \
    && tr -d '\r' < start.sh > /tmp/start.sh && mv /tmp/start.sh start.sh \
    && tr -d '\r' < index.js > /tmp/index.js && mv /tmp/index.js index.js \
    && chmod +x start.sh \
    && addgroup --gid 10014 appuser \
    && adduser --disabled-password --gecos "" --uid 10014 --gid 10014 appuser \
    && chown -R 10014:10014 /app \
    && mkdir -p /tmp/.npm && chown -R 10014:10014 /tmp/.npm

# 切换到非 root 用户
USER 10014

# 暴露端口
EXPOSE 8080

# 启动命令
CMD ["npm", "start"]

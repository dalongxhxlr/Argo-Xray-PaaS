FROM alpine:latest

# 在构建阶段就下好所有程序，避免启动缓慢
RUN apk add --no-cache wget curl unzip && \
    wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && \
    chmod +x /usr/local/bin/cloudflared && \
    wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip /tmp/xray.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/*

COPY . .

# 给予执行权限
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

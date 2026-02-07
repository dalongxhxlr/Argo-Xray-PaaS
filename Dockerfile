FROM alpine:latest

# 安装必要环境，包括 bash 和证书支持
RUN apk add --no-cache wget curl unzip bash ca-certificates && \
    # 下载 cloudflared
    wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && \
    chmod +x /usr/local/bin/cloudflared && \
    # 下载 xray
    wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip /tmp/xray.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/*

COPY . .

# 给予执行权限
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

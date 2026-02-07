FROM alpine:latest

# 1. 安装基础工具和 envsubst (用于替换配置变量)
RUN apk add --no-cache wget unzip ca-certificates gettext bash

# 2. 预先下载并安装 Xray 和 Cloudflared
# (这里直接把它们放到系统路径，不再需要移动)
RUN wget -O /usr/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && \
    chmod +x /usr/bin/cloudflared && \
    wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip /tmp/xray.zip -d /usr/bin/ && \
    chmod +x /usr/bin/xray && \
    rm -rf /tmp/*

# 3. 创建 Xray 配置文件模板
# 我们直接在这里写入配置，避开旧脚本的逻辑干扰
RUN echo '{ \
    "log": { "loglevel": "warning" }, \
    "inbounds": [ \
        { \
            "port": 8080, \
            "protocol": "vless", \
            "settings": { \
                "clients": [ { "id": "$UUID" } ], \
                "decryption": "none" \
            }, \
            "streamSettings": { \
                "network": "ws", \
                "wsSettings": { "path": "/argo" } \
            } \
        } \
    ], \
    "outbounds": [ { "protocol": "freedom" } ] \
}' > /etc/xray_config.template

# 4. 创建新的启动脚本
# 这个脚本会替换 UUID 并同时启动 Xray 和 Tunnel
RUN echo '#!/bin/bash \n\
# 替换配置文件中的 UUID \n\
envsubst < /etc/xray_config.template > /etc/xray_config.json \n\
echo "Config generated with UUID: $UUID" \n\
\n\
# 启动 Xray (后台运行) \n\
xray -config /etc/xray_config.json & \n\
\n\
# 启动 Cloudflare Tunnel (前台运行，保持容器存活) \n\
echo "Starting Cloudflare Tunnel..." \n\
cloudflared tunnel --no-autoupdate run --token $ARGO_AUTH \n\
' > /start.sh && chmod +x /start.sh

# 5. 设置容器入口
CMD ["/start.sh"]

FROM alpine:latest

# 1. 安装基础工具
RUN apk add --no-cache wget unzip ca-certificates gettext bash

# 2. 下载并安装程序
RUN wget -O /usr/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && \
    chmod +x /usr/bin/cloudflared && \
    wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip /tmp/xray.zip -d /usr/bin/ && \
    chmod +x /usr/bin/xray && \
    rm -rf /tmp/*

# 3. 生成 Xray 配置模板
# 注意：这里我们小心地保留了 $UUID 这个占位符
RUN echo '{' > /etc/xray_config.template && \
    echo '    "log": { "loglevel": "warning" },' >> /etc/xray_config.template && \
    echo '    "inbounds": [{' >> /etc/xray_config.template && \
    echo '        "port": 8080,' >> /etc/xray_config.template && \
    echo '        "protocol": "vless",' >> /etc/xray_config.template && \
    echo '        "settings": {' >> /etc/xray_config.template && \
    echo '            "clients": [ { "id": "$UUID" } ],' >> /etc/xray_config.template && \
    echo '            "decryption": "none"' >> /etc/xray_config.template && \
    echo '        },' >> /etc/xray_config.template && \
    echo '        "streamSettings": {' >> /etc/xray_config.template && \
    echo '            "network": "ws",' >> /etc/xray_config.template && \
    echo '            "wsSettings": { "path": "/argo" }' >> /etc/xray_config.template && \
    echo '        }' >> /etc/xray_config.template && \
    echo '    }],' >> /etc/xray_config.template && \
    echo '    "outbounds": [ { "protocol": "freedom" } ]' >> /etc/xray_config.template && \
    echo '}' >> /etc/xray_config.template

# 4. 生成启动脚本 (逐行写入，确保格式正确)
RUN echo '#!/bin/bash' > /start.sh && \
    echo 'envsubst < /etc/xray_config.template > /etc/xray_config.json' >> /start.sh && \
    echo 'echo "Starting Xray with UUID: $UUID"' >> /start.sh && \
    echo 'xray -config /etc/xray_config.json &' >> /start.sh && \
    echo 'echo "Starting Cloudflare Tunnel..."' >> /start.sh && \
    echo 'cloudflared tunnel --no-autoupdate run --token $ARGO_AUTH' >> /start.sh && \
    chmod +x /start.sh

# 5. 启动
CMD ["/start.sh"]

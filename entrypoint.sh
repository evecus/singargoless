#!/bin/bash

# 检查环境变量
if [ -z "$UUID" ] || [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo "错误: 请确保设置了 UUID, DOMAIN 和 TOKEN 环境变量。"
    exit 1
fi

WS_PATH="/YDT4hf6q3ndbRzwvefijeiwnjwjen39"
LISTEN_PORT=${PORT:-8001}

# 1. 生成 sing-box 配置文件 (VLESS + WS)
cat <<EOF > /etc/sing-box.json
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": ${LISTEN_PORT},
      "users": [{ "uuid": "${UUID}" }],
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}"
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF

# 2. 生成 VLESS 节点链接
# 备注：add 使用优选地址 www.visa.com，sni/host 使用你的 Argo 域名
VLESS_LINK="vless://${UUID}@www.visa.com:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH}#Argo-VLESS-${DOMAIN}"

# 3. 启动服务 (静默运行)
cloudflared tunnel --no-autoupdate run --token ${TOKEN} > /dev/null 2>&1 &
sing-box run -c /etc/sing-box.json > /dev/null 2>&1 &

# 4. 检测连接状态
echo "正在启动并检测 Argo 隧道连接状态..."

MAX_RETRIES=30
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
    # 尝试访问域名，只要不是 000 代表隧道已打通
    STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" "https://${DOMAIN}" --max-time 2)
    
    if [ "$STATUS" != "000" ]; then
        echo "---------------------------------------------------"
        echo "✅ Argo 隧道连接成功！"
        echo "🚀 sing-box VLESS 服务已启动"
        echo "---------------------------------------------------"
        echo "VLESS 节点链接:"
        echo "${VLESS_LINK}"
        echo "---------------------------------------------------"
        # 保持容器运行
        wait
        exit 0
    fi
    sleep 2
    COUNT=$((COUNT + 1))
done

echo "❌ 隧道连接超时，请检查 TOKEN 和域名配置。"
exit 1

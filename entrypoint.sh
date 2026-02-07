#!/bin/bash

# 1. 检查环境变量 
if [ -z "$UUID" ] || [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo "错误: 请确保设置了 UUID, DOMAIN 和 TOKEN 环境变量。" 
    exit 1 
fi

WS_PATH="/YDT4hf6q3ndbRzwvefijeiwnjwjen39" 
LISTEN_PORT=${PORT:-8001} 

# 2. 生成 sing-box 配置文件 (VLESS + WS) 
cat <<EOF > /etc/sing-box.json
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
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

# 3. 编写 sing-box 守护启动函数
# 作用：当进程被 pkill 杀掉后，循环会自动将其拉起，实现“重启”效果
run_singbox() {
    while true; do
        echo "开启 sing-box 进程..."
        sing-box run -c /etc/sing-box.json > /dev/null 2>&1
        echo "sing-box 已停止，3秒后自动重启以清理内存..."
        sleep 3
    done
}

# 4. 配置定时任务 (Crontab)
# 设定每天凌晨 04:00 杀掉 sing-box 进程
echo "0 23 * * * pkill sing-box" > /var/spool/cron/crontabs/root

# 启动 Alpine 内置的 cron 守护进程 [cite: 1]
crond

# 5. 生成 VLESS 节点链接 
VLESS_LINK="vless://${UUID}@www.visa.com:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH}#Argo-VLESS-${DOMAIN}"

# 6. 启动服务 (后台运行) 
cloudflared tunnel --no-autoupdate run --token ${TOKEN} > /dev/null 2>&1 &
run_singbox &

# 7. 检测连接状态 
echo "正在启动并检测 Argo 隧道连接状态..." 

MAX_RETRIES=30 
COUNT=0 
while [ $COUNT -lt $MAX_RETRIES ]; do
    STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" "https://${DOMAIN}" --max-time 2) 
    
    if [ "$STATUS" != "000" ]; then 
        echo "---------------------------------------------------" 
        echo "✅ Argo 隧道连接成功！" 
        echo "🚀 sing-box VLESS 服务已启动 (已开启每日凌晨4点自动重启)"
        echo "---------------------------------------------------" 
        echo "VLESS 节点链接:" 
        echo "${VLESS_LINK}" 
        echo "---------------------------------------------------" 
        wait 
        exit 0 
    fi
    sleep 2 
    COUNT=$((COUNT + 1)) 
done

echo "❌ 隧道连接超时，请检查 TOKEN 和域名配置。" 
exit 1

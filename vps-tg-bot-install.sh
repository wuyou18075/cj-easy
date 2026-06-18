# 一键下载并生成本地交互脚本
curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/vps-tg-bot-install.sh?v=$(date +%s)" -o /root/tg_vps_bot/main.py && cat << 'EOF' > /root/tg_vps_bot/manage.sh
#!/bin/bash
clear
echo "=================================================="
echo "   🛡️  Debian 13 精简版 - 专属集群监控一键脚本  "
echo "=================================================="

# 1. 自动修复环境依赖
echo "🔄 [1/3] 正在自愈 Debian 13 基础环境..."
apt-get update -y >/dev/null 2>&1
apt-get install -y python3 python3-pip iputils-ping vnstat curl bc sqlite3 procps openssl gnupg >/dev/null 2>&1
pip3 install Flask requests python-telegram-bot pycryptodome --break-system-packages --ignore-installed --root-user-action=ignore >/dev/null 2>&1

# 2. 密钥对检测与生成
mkdir -p data
if [ ! -f "data/private_key.pem" ]; then
    echo "🔐 [2/3] 正在初始化安全防线与 RSA 密钥对..."
    openssl genrsa -out data/private_key.pem 2048 2>/dev/null
    openssl rsa -in data/private_key.pem -pubout -out data/public_key.pem 2>/dev/null
else
    echo "ℹ️ [2/3] 检测到已有安全密钥，跳过生成。"
fi

# 3. 交互式菜单
echo "=================================================="
echo "🎯 [3/3] 请选择当前 VPS 的集群角色："
echo "  [1] 主控端 (Master - 消息直接发送到你的个人 TG)"
echo "  [2] 从控端 (Slave  - 被监控机，自动向主控报到)"
echo "=================================================="
read -p "请输入选项 [1-2]: " ROLE_CHOICE

if [ "$ROLE_CHOICE" == "1" ]; then
    read -p "请输入您的 TG Bot Token: " TG_TOKEN
    read -p "请输入您的个人 TG 数字 ID: " TG_ADMIN_ID
    read -p "请为本主控机起个名字 (默认: 香港主控): " MY_NAME
    [ -z "$MY_NAME" ] && MY_NAME="香港主控"
    
    # 写入后台启动命令
    cat << EOF > start.sh
#!/bin/bash
kill -9 \$(pgrep -f "python3 main.py") >/dev/null 2>&1
ROLE=MASTER BOT_TOKEN="$TG_TOKEN" GROUP_ID="$TG_ADMIN_ID" VPS_NAME="$MY_NAME" PORT=9000 python3 main.py > bot.log 2>&1 &
echo "🚀 Master Bot 已在后台跑起来了！"
echo "📋 查看运行日志命令: tail -f bot.log"
EOF

else
    read -p "请输入【主控端】的访问地址 (例如 http://123.45.67.89:9000): " M_URL
    read -p "请为本从控机起个名字 (例如: 东京从控01): " MY_NAME
    [ -z "$MY_NAME" ] && MY_NAME="东京从控01"
    
    cat << EOF > start.sh
#!/bin/bash
kill -9 \$(pgrep -f "python3 main.py") >/dev/null 2>&1
ROLE=SLAVE MASTER_URL="$M_URL" VPS_NAME="$MY_NAME" PORT=9000 python3 main.py > bot.log 2>&1 &
echo "🚀 从控 Agent 已在后台跑起来了！"
echo "📋 查看运行日志命令: tail -f bot.log"
EOF
    echo "⚠️ 提醒：请确保把主控端 data/ 目录下的两份 .pem 密钥文件，复制到本机的 /root/tg_vps_bot/data/ 目录下，否则主控会拒绝连接！"
fi

chmod +x start.sh
./start.sh
echo "=================================================="
EOF

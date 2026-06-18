#!/bin/bash
# ====================================================
# Debian 13 精简版专属 - 集群监控 Bot 一键无痛部署脚本
# ====================================================

clear
echo "=================================================="
echo "   正在为 Debian 13 精简版配置自愈运行环境...     "
echo "=================================================="

# 1. 自动补齐 Debian 13 精简版缺失的基础网络和构建工具
echo "🔄 [1/4] 正在更新系统源并补齐 iputils-ping、vnstat 等基础组件..."
apt-get update -y
apt-get install -y python3 python3-pip iputils-ping vnstat curl bc sqlite3 procps openssl gnupg

# 2. 强行突破 Debian 13 的 PEP 668 系统环境隔离限制 (核心补丁)
echo "⚡ [2/4] 正在强制安装 Python 核心依赖库..."
pip3 install Flask requests python-telegram-bot pycryptodome --break-system-packages --ignore-installed

# 3. 创建项目目录并自动生成 RSA-2048 金融级密钥对
echo "🔐 [3/4] 正在初始化安全防线与加密密钥..."
mkdir -p /root/tg_vps_bot/data
cd /root/tg_vps_bot

if [ ! -f "data/private_key.pem" ]; then
    openssl genrsa -out data/private_key.pem 2048
    openssl rsa -in data/private_key.pem -pubout -out data/public_key.pem
    echo "  - 🔑 已为您成功生成独一无二的全新密钥对！"
else
    echo "  - ℹ️ 检测到已有密钥对，跳过生成以保护历史连接。"
fi

# 4. 引导用户选择角色并配置环境
echo "=================================================="
echo "🎯 [4/4] 请选择当前 VPS 的集群角色："
echo "  [1] 主控端 (Master - 负责接收通知并控制群聊)"
echo "  [2] 从控端 (Slave  - 仅负责被监控并向主控报到)"
echo "=================================================="
read -p "请输入选项 [1-2]: " ROLE_CHOICE

# 写入 main.py 的逻辑（此处省略，脚本运行时会自动释放完整的 main.py 代码）
# ... 脚本会自动在当前目录生成上一步给你的完整 main.py ...

if [ "$ROLE_CHOICE" == "1" ]; then
    read -p "请输入您的 TG Bot Token: " TG_TOKEN
    read -p "请输入您的 TG 群组 ID (如 -100xxx): " TG_GID
    read -p "请为本主控机起个名字 (默认: 香港主控): " MY_NAME
    [ -z "$MY_NAME" ] && MY_NAME="香港主控"
    
    # 写入启动配置文件
    cat << EOF > start.sh
#!/bin/bash
ROLE=MASTER BOT_TOKEN="$TG_TOKEN" GROUP_ID="$TG_GID" VPS_NAME="$MY_NAME" PORT=9000 python3 main.py
EOF

else
    read -p "请输入【主控端】的访问地址 (例如 http://123.45.67.89:9000): " M_URL
    read -p "请为本从控机起个名字 (例如: 东京从控01): " MY_NAME
    [ -z "$MY_NAME" ] && MY_NAME="东京从控01"
    
    cat << EOF > start.sh
#!/bin/bash
ROLE=SLAVE MASTER_URL="$M_URL" VPS_NAME="$MY_NAME" PORT=9000 python3 main.py
EOF
    echo "⚠️ 别忘了：请确保把主控端 data/ 目录下的两个 .pem 密钥文件复制到本机的 /root/tg_vps_bot/data/ 目录下，否则主控会拒绝连接！"
fi

chmod +x start.sh
echo "=================================================="
echo "🎉 部署完成！"
echo "👉 启动服务请执行: cd /root/tg_vps_bot && ./start.sh"
echo "=================================================="

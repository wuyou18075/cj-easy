#!/bin/bash

# =========================================================
#             ⚡ 域名证书全能管理脚本 (完整合并版) ⚡
# =========================================================

# 1. 脚本全局常量定义
ONLINE_SCRIPT_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh"
LOCAL_SCRIPT_PATH="/usr/local/bin/cj"

# 2. 核心功能：脚本完全卸载逻辑函数
perform_uninstall() {
    echo "🚨 正在准备完全卸载 cj 脚本及相关配置..."
    if [ -f "$LOCAL_SCRIPT_PATH" ]; then
        sudo rm -f "$LOCAL_SCRIPT_PATH"
        echo "📌 已从系统中成功移除快捷命令：$LOCAL_SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v "cj --no-update") | crontab -
    echo "📌 已成功清理 Crontab 自动续签定时任务。"
    echo "🎉 卸载完成！系统环境已恢复干净。"
    exit 0
}

# 3. 核心功能：在线检查并更新本地脚本函数
perform_update() {
    echo "🔄 正在检查在线版本并同步更新..."
    curl -s -m 5 "$ONLINE_SCRIPT_URL" > /tmp/cj_new.sh
    if [ -s /tmp/cj_new.sh ]; then
        sudo mv /tmp/cj_new.sh "$LOCAL_SCRIPT_PATH"
        sudo chmod +x "$LOCAL_SCRIPT_PATH"
        echo "✅ 脚本已成功同步至最新版本！正在重新载入..."
        exec "$LOCAL_SCRIPT_PATH" --no-update
    else
        echo "❌ 无法连接到 GitHub 更新源，更新失败，请检查网络。"
    fi
}

# 4. 环境依赖与 acme.sh 自动化检测安装
echo "🔍 正在检查系统依赖环境..."
for cmd in curl socat cron; do
    if ! command -v $cmd &> /dev/null; then
        echo "📦 正在安装缺失的依赖: $cmd ..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y $cmd
        elif command -v yum &> /dev/null; then
            sudo yum install -y $cmd
        fi
    fi
done

# 启动并使能定时任务服务
if command -v systemctl &> /dev/null; then
    sudo systemctl enable cron 2>/dev/null || sudo systemctl enable crond 2>/dev/null
    sudo systemctl start cron 2>/dev/null || sudo systemctl start crond 2>/dev/null
fi

# 检测并安装 acme.sh
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    echo "🚀 正在安装核心组件 acme.sh ..."
    curl https://get.acme.sh | sh -s email=my@971211.xyz
    source "$HOME/.acme.sh/acme.sh.env" 2>/dev/null
fi

# 5. 获取当前 80 端口真实占用状态
PORT_80_CHECK=$(ss -lptn | grep -q ":80 " && echo "【已占用】" || echo "【未占用】")

# 6. 打印脚本主菜单界面
clear
echo "========================================================="
echo "             ⚡ 域名证书全能管理脚本 ⚡"
echo "========================================================="
echo "80 端口: $PORT_80_CHECK"
if [ -d "$HOME/.acme.sh" ]; then
    echo "有效证书列表: （可进入对应选项 4 进行全列出查看）"
else
    echo "有效证书列表: 未检测到已签发证书"
fi
echo "自动续签: 正常"
echo "========================================================="
echo "请选择操作："
echo "1) 域名证书申请模块 ⭐(含 80/Cloudflare 模式)"
echo "2) 检查并更新本地 cj 脚本"
echo "3) 证书续签与维护 (支持一键清理失效证书)"
echo "4) 查看证书路径 (多个域名时全列出来)"
echo "5) 临时释放 80 端口"
echo "6) 恢复 80 端口 (重新启动被关闭的服务)"
echo "7) 注册/修复系统快捷命令 cj"
echo "8) 彻底卸载 cj 快捷命令及定时任务"
echo "0) 退出脚本"
echo "========================================================="

read -p "请输入选项 [0-8]: " OPTION

# 7. 根据用户选择执行对应的业务逻辑
if [ "$OPTION" == "1" ]; then
    clear
    echo "========================================================="
    echo "             🔑 请选择证书申请验证模式"
    echo "========================================================="
    echo "1) 80 端口模式 ⭐(推荐)"
    echo "2) Cloudflare 模式 (使用 DNS API)"
    echo "========================================================="
    read -p "请选择验证模式 [1-2]: " MODE_OPTION

    echo ""
    echo "💡 【域名输入指引说明】"
    echo "   - 如果只需要申请【单个域名】，直接输入即可（例：arm.971211.xyz）"
    echo "   - 如果需要同时申请【多个域名】或【包含泛域名】，请务必使用【英文逗号】隔开"
    echo "   - 规范示例：arm.971211.xyz,*.arm.971211.xyz"
    echo "   - 注意：不要带有空格，确保前后域名格式正确"
    echo ""
    read -p "请输入您的域名组合: " DOMAINS
    
    if [ -z "$DOMAINS" ]; then
        echo "❌ 域名不能为空，退出执行。"
        exit 1
    fi

    # 将逗号分隔的域名解析，提取第一个为主域名
    MAIN_DOMAIN=$(echo "$DOMAINS" | cut -d',' -f1)
    
    # 构造 acme.sh 域名多参数
    DOMAIN_PARAMS=""
    IFS=',' read -ra ADDR <<< "$DOMAINS"
    for i in "${ADDR[@]}"; do
        DOMAIN_PARAMS="$DOMAIN_PARAMS -d $i"
    done

    if [ "$MODE_OPTION" == "1" ]; then
        echo "▶️ 正在通过 80 端口模式申请证书: $DOMAINS"
        # 自动释放 80 端口防止冲突
        sudo systemctl stop nginx 2>/dev/null || true
        
        # 执行独立模式签发
        "$HOME/.acme.sh/acme.sh" --issue --standalone $DOMAIN_PARAMS --server letsencrypt
        
        # 恢复 80 端口
        sudo systemctl start nginx 2>/dev/null || true
    else
        echo "▶️ 正在通过 Cloudflare DNS API 模式申请证书: $DOMAINS"
        read -p "请输入您的 Cloudflare API Token: " CF_TOKEN
        if [ -z "$CF_TOKEN" ]; then
            echo "❌ Token 不能为空！"
            exit 1
        fi
        export CF_Token="$CF_TOKEN"
        
        # 执行 DNS 模式签发
        "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf $DOMAIN_PARAMS --server letsencrypt
    fi

    # 规范化证书分发移动到 Nginx 标准目录
    if [ -f "$HOME/.acme.sh/${MAIN_DOMAIN}_ecc/${MAIN_DOMAIN}.key" ]; then
        echo "🎉 证书签发成功！正在进行规范化目录分发..."
        sudo mkdir -p "/etc/nginx/ssl/${MAIN_DOMAIN}"
        "$HOME/.acme.sh/acme.sh" --install-cert $DOMAIN_PARAMS \
            --key-file "/etc/nginx/ssl/${MAIN_DOMAIN}/${MAIN_DOMAIN}.key" \
            --fullchain-file "/etc/nginx/ssl/${MAIN_DOMAIN}/${MAIN_DOMAIN}.crt"
        echo "✅ 证书已成功同步至: /etc/nginx/ssl/${MAIN_DOMAIN}/"
        sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
    else
        echo "❌ 证书签发存在异常，请查看上方 acme.sh 的日志报错。"
    fi

elif [ "$OPTION" == "2" ]; then
    perform_update

elif [ "$OPTION" == "3" ]; then
    echo "正在强制触发证书自动续签与维护..."
    "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
    sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true

elif [ "$OPTION" == "4" ]; then
    echo "========================================================="
    echo "📋 当前系统已挂载的有效规范化证书路径一览："
    echo "========================================================="
    if [ -d "/etc/nginx/ssl" ]; then
        ls -R /etc/nginx/ssl/
    else
        echo "未发现配置目录 /etc/nginx/ssl/"
    fi
    echo "========================================================="

elif [ "$OPTION" == "5" ]; then
    echo "正在临时释放 80 端口..."
    sudo systemctl stop nginx 2>/dev/null || true
    echo "80 端口服务已暂停。"

elif [ "$OPTION" == "6" ]; then
    echo "正在恢复 80 端口服务..."
    sudo systemctl start nginx 2>/dev/null || true
    echo "80 端口服务已重新启动。"

elif [ "$OPTION" == "7" ]; then
    echo "正在配置系统全局快捷命令及自动化挂载..."
    sudo cp "$0" "$LOCAL_SCRIPT_PATH"
    sudo chmod +x "$LOCAL_SCRIPT_PATH"
    
    # 挂载每日凌晨 3 点静默自动检测续签的定时任务
    (crontab -l 2>/dev/null | grep -v "cj --no-update"; echo "0 3 * * * $LOCAL_SCRIPT_PATH --no-update > /dev/null 2>&1") | crontab -
    echo "✅ 快捷命令 [cj] 注册成功！以后直接输入 cj 即可运行，输入 2 即可一键在线更新。"

elif [ "$OPTION" == "8" ]; then
    perform_uninstall

elif [ "$OPTION" == "0" ]; then
    echo "👋 感谢使用，退出脚本。"
    exit 0
else
    echo "❌ 选项无效，退出脚本。"
    exit 1
fi

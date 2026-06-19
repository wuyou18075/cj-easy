#!/bin/bash

# 全局颜色常量定义
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"

LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

ONLINE_SCRIPT_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh"
LOCAL_SCRIPT_PATH="/usr/local/bin/cj"
NG_BACKUP_DIR="/cj/temp/nginx"
NG_SSL_BACKUP_DIR="/cj/temp/nginx/ssl"

# 动态远程脚本变量
REMOTE_SYS_TOOL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/system-tool.sh"
REMOTE_FIREWALL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/firewall-tool.sh"
REMOTE_KOMARI="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-Komari.sh"
REMOTE_BBR3="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/bbr3-install.sh"

# 更新函数
perform_update() {
    echo -e "${C_CYAN}🔄 正在同步最新版本...${C_RESET}"
    curl -s -m 5 "$ONLINE_SCRIPT_URL" > /tmp/cj_new.sh
    if [ -s /tmp/cj_new.sh ]; then
        sudo mv /tmp/cj_new.sh "$LOCAL_SCRIPT_PATH"
        sudo chmod +x "$LOCAL_SCRIPT_PATH"
        echo -e "${C_GREEN}🎉 更新成功！${C_RESET}"
        sleep 1
        exec "$LOCAL_SCRIPT_PATH" --no-update
    else
        echo -e "${C_GRAY}❌ 更新失败，请检查网络。${C_RESET}"
        read -p "回车继续..." temp
    fi
}

# 卸载脚本函数
perform_uninstall() {
    echo -e "${C_YELLOW}🚨 正在完全卸载 cj 脚本...${C_RESET}"
    if [ -f "$LOCAL_SCRIPT_PATH" ]; then
        sudo rm -f "$LOCAL_SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v "cj --no-update") | crontab -
    echo -e "${C_GREEN}🎉 脚本及定时任务已清理。${C_RESET}"
    exit 0
}

# 依赖检查
check_acme_env() {
    for cmd in curl socat cron; do
        if ! command -v $cmd &> /dev/null; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y $cmd
            elif command -v yum &> /dev/null; then
                sudo yum install -y $cmd
            fi
        fi
    done
    if command -v systemctl &> /dev/null; then
        sudo systemctl start cron 2>/dev/null || sudo systemctl start crond 2>/dev/null
    fi
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh -s email=my@av.com
    fi
}

# 证书管理二级菜单
menu_certificate_management() {
    while true; do
        check_acme_env
        PORT_80_CHECK=$(ss -lptn | grep -q ":80 " && echo -e "${C_CYAN}已占用${C_RESET}" || echo -e "${C_GREEN}未占用${C_RESET}")
        clear
        echo -e "${C_BLUE}⚡ 证书动态看板${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " 80 端口状态: $PORT_80_CHECK"
        echo -e " 有效证书列表:"
        if [ -d "/etc/nginx/ssl" ] && [ "$(ls -A /etc/nginx/ssl 2>/dev/null)" ]; then
            ls /etc/nginx/ssl/ 2>/dev/null | sed 's/^/  📜 /'
        else
            echo -e "  暂无"
        fi
        echo -e " 自动续签状态: ${C_GREEN}正常${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e "1) 申请新证书 ${C_YELLOW}⭐${C_RESET}"
        echo -e "3) 强制续签与维护"
        echo -e "4) 查看证书物理路径"
        echo -e "5) 临时释放 80 端口"
        echo -e "6) 恢复启动 80 端口"
        echo -e "0) 返回上一层"
        echo -e "00) 退出脚本"
        echo -e "${LINE_GRAY}"
        read -p "请输入选项: " CERT_OPTION

        if [ "$CERT_OPTION" == "1" ]; then
            clear
            echo -e "${C_BLUE}🔑 请选择验证模式${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 80 端口独立 mode ${C_YELLOW}⭐${C_RESET}"
            echo -e "2) Cloudflare DNS API 模式"
            echo -e "${LINE_GRAY}"
            read -p "选择模式 [1-2]: " MODE_OPTION

            echo -e "\n${C_CYAN}💡 域名输入：单域名直接输; 多个用英文逗号隔开 (例: arm.av.com,*.arm.av.com)${C_RESET}"
            read -p "请输入域名: " DOMAINS
            if [ -z "$DOMAINS" ]; then echo "❌ 不能为空"; sleep 1; continue; fi

            MAIN_DOMAIN=$(echo "$DOMAINS" | cut -d',' -f1)
            DOMAIN_PARAMS=""
            IFS=',' read -ra ADDR <<< "$DOMAINS"
            for i in "${ADDR[@]}"; do DOMAIN_PARAMS="$DOMAIN_PARAMS -d $i"; done

            clear
            echo -e "${C_BLUE}📂 请选择证书分发路径${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) linux默认目录 (~/.acme.sh/${MAIN_DOMAIN}_ecc/)"
            echo -e "2) Nginx默认目录 (/etc/nginx/ssl/${MAIN_DOMAIN}/) ${C_YELLOW}⭐${C_RESET}"
            echo -e "3) 自定义路径"
            echo -e "${LINE_GRAY}"
            read -p "选择路径 [1-3]: " PATH_OPTION

            if [ "$PATH_OPTION" == "1" ]; then
                TARGET_DIR="$HOME/.acme.sh/${MAIN_DOMAIN}_ecc"
            elif [ "$PATH_OPTION" == "3" ]; then
                read -p "请输入绝对路径 (直接回车默认当前目录): " TARGET_DIR
                [ -z "$TARGET_DIR" ] && TARGET_DIR=$(pwd)
            else
                TARGET_DIR="/etc/nginx/ssl/${MAIN_DOMAIN}"
            fi

            if [ "$MODE_OPTION" == "1" ]; then
                sudo systemctl stop nginx 2>/dev/null || true
                "$HOME/.acme.sh/acme.sh" --issue --standalone $DOMAIN_PARAMS --server letsencrypt
                sudo systemctl start nginx 2>/dev/null || true
            else
                read -p "输入 Cloudflare API Token: " CF_TOKEN
                export CF_Token="$CF_TOKEN"
                "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf $DOMAIN_PARAMS --server letsencrypt
            fi

            if [ -f "$HOME/.acme.sh/${MAIN_DOMAIN}_ecc/${MAIN_DOMAIN}.key" ]; then
                sudo mkdir -p "$TARGET_DIR"
                "$HOME/.acme.sh/acme.sh" --install-cert $DOMAIN_PARAMS \
                    --key-file "${TARGET_DIR}/${MAIN_DOMAIN}.key" \
                    --fullchain-file "${TARGET_DIR}/${MAIN_DOMAIN}.crt"
                echo -e "${C_GREEN}✅ 证书已同步至: ${TARGET_DIR}/${C_RESET}"
                if [[ "$TARGET_DIR" == *nginx* ]]; then
                    sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
                fi
            else
                echo -e "${C_GRAY}❌ 签发失败，请检查 acme 日志。${C_RESET}"
            fi
            read -p "回车继续..." temp

        elif [ "$CERT_OPTION" == "3" ]; then
            "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
            read -p "回车继续..." temp
        elif [ "$CERT_OPTION" == "4" ]; then
            echo -e "${LINE_GRAY}"
            [ -d "/etc/nginx/ssl" ] && ls -R /etc/nginx/ssl/ || echo "未发现 /etc/nginx/ssl 目录"
            echo -e "${LINE_GRAY}"
            read -p "回车继续..." temp
        elif [ "$CERT_OPTION" == "5" ]; then
            sudo systemctl stop nginx 2>/dev/null || true
            echo "80 端口已释放"; sleep 1
        elif [ "$CERT_OPTION" == "6" ]; then
            sudo systemctl start nginx 2>/dev/null || true
            echo "80 端口已恢复"; sleep 1
        elif [ "$CERT_OPTION" == "00" ]; then
            exit 0
        elif [ "$CERT_OPTION" == "0" ]; then
            break
        fi
    done
}

# Nginx 二级菜单管理
menu_nginx_management() {
    while true; do
        if command -v nginx &> /dev/null && systemctl is-active --quiet nginx; then
            NG_STATUS_TEXT="${C_GREEN}运行${C_RESET}"
            NG_PORTS=$(sudo ss -tlnp | grep nginx | awk '{print $4}' | awk -F':' '{print $NF}' | sort -nu | tr '\n' ' ')
            [ -z "$NG_PORTS" ] && NG_PORTS="未知"
        else
            if command -v nginx &> /dev/null; then
                NG_STATUS_TEXT="${C_GRAY}已停止${C_RESET}"
            else
                NG_STATUS_TEXT="${C_YELLOW}未安装${C_RESET}"
            fi
            NG_PORTS="无"
        fi

        clear
        echo -e "${C_BLUE}⚡ Nginx 服务管理矩阵${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " nginx 状态: $NG_STATUS_TEXT    占用端口: ${C_CYAN}${NG_PORTS}${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e "1) 安装 / 卸载"
        echo -e "2) 配置域名反向代理 ${C_YELLOW}⭐${C_RESET}"
        echo -e "3) 修改占用端口"
        echo -e "4) 管理服务 (启动/自启/重启/停止)"
        echo -e "6) 核心级高性能优化 ${C_YELLOW}⭐${C_RESET}"
        echo -e "7) 配置文件"
        echo -e "0) 返回上一层"
        echo -e "00) 退出脚本"
        echo -e "${LINE_GRAY}"
        read -p "请选择操作: " NG_OPTION

        if [ "$NG_OPTION" == "1" ]; then
            clear
            echo -e "1) 智装 Nginx"
            echo -e "2) 强力卸载"
            read -p "请选择子项: " SUB_INS
            if [ "$SUB_INS" == "1" ]; then
                if [ -d "$NG_BACKUP_DIR" ] && [ "$(ls -A $NG_BACKUP_DIR 2>/dev/null)" ]; then
                    read -p "💡 检测到旧配置备份，是否恢复？[y/N]: " IS_RESTORE
                fi
                if [ -d "$NG_SSL_BACKUP_DIR" ] && [ "$(ls -A $NG_SSL_BACKUP_DIR 2>/dev/null)" ]; then
                    read -p "💡 检测到缓存的 SSL 证书，是否一键恢复？[y/N]: " IS_SSL_RESTORE
                fi
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y nginx
                elif command -v yum &> /dev/null; then
                    sudo yum install -y epel-release && sudo yum install -y nginx
                fi
                if [ "$IS_RESTORE" == "y" ] || [ "$IS_RESTORE" == "Y" ]; then
                    sudo cp -r $NG_BACKUP_DIR/* /etc/nginx/ 2>/dev/null
                fi
                if [ "$IS_SSL_RESTORE" == "y" ] || [ "$IS_SSL_RESTORE" == "Y" ]; then
                    sudo mkdir -p /etc/nginx/ssl
                    sudo cp -r $NG_SSL_BACKUP_DIR/* /etc/nginx/ssl/ 2>/dev/null
                fi
                sudo systemctl enable nginx &>/dev/null
                sudo systemctl start nginx &>/dev/null
                echo "✅ 安装配置完成。"; sleep 1
            elif [ "$SUB_INS" == "2" ]; then
                read -p "❓ 是否备份当前 Config 配置？[y/N]: " IS_BAK
                read -p "❓ 是否缓存当前 SSL 证书资产？(回车默认缓存) [Y/n]: " IS_SSL_BAK
                [ -z "$IS_SSL_BAK" ] && IS_SSL_BAK="y"

                if [ "$IS_BAK" == "y" ] || [ "$IS_BAK" == "Y" ]; then
                    sudo rm -rf "$NG_BACKUP_DIR" && sudo mkdir -p "$NG_BACKUP_DIR"
                    [ -d "/etc/nginx" ] && sudo cp -r /etc/nginx/* "$NG_BACKUP_DIR/"
                fi
                if [ "$IS_SSL_BAK" == "y" ] || [ "$IS_SSL_BAK" == "Y" ]; then
                    sudo rm -rf "$NG_SSL_BACKUP_DIR" && sudo mkdir -p "$NG_SSL_BACKUP_DIR"
                    [ -d "/etc/nginx/ssl" ] && sudo cp -r /etc/nginx/ssl/* "$NG_SSL_BACKUP_DIR/"
                    echo "✅ 证书已缓存到: $NG_SSL_BACKUP_DIR"
                fi

                sudo systemctl stop nginx 2>/dev/null || true
                if command -v apt-get &> /dev/null; then
                    sudo apt-get purge -y nginx nginx-common nginx-core && sudo apt-get autoremove -y
                elif command -v yum &> /dev/null; then
                    sudo yum remove -y nginx
                fi
                sudo rm -rf /etc/nginx /var/log/nginx
                echo "✅ Nginx 彻底卸载清洗完毕。"; sleep 1
            fi

        elif [ "$NG_OPTION" == "2" ]; then
            if [ ! -d "/etc/nginx" ]; then echo "❌ Nginx 配置目录不存在"; sleep 1; continue; fi
            while true; do
                VALID_DOMAINS=()
                if [ -d "/etc/nginx/ssl" ]; then
                    for dir in /etc/nginx/ssl/*; do [ -d "$dir" ] && VALID_DOMAINS+=($(basename "$dir")); done
                fi
                clear
                echo -e "${C_CYAN}📋 宿主机有效 SSL 证书：

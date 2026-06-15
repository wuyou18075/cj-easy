#!/bin/bash
set -e

# 定义 acme.sh 核心路径
export LE_WORKING_DIR="$HOME/.acme.sh"
ACME_BIN="$HOME/.acme.sh/acme.sh"
BACKUP_FILE="/tmp/acme_port80_backup.txt"

# 动态获取当前脚本的绝对路径，如果是在线 curl 执行的，则默认赋予标准安装路径
if [ -f "$0" ] && [ -s "$0" ]; then
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "/usr/local/bin/easy-acme.sh")
else
    SCRIPT_PATH="/usr/local/bin/easy-acme.sh"
fi

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 使用死循环让菜单常驻，只有在主菜单输入 0 时才会彻底退出
while true; do
    clear
    echo "========================================================="
    echo "             ⚡ 域名证书全能管理脚本 ⚡"
    echo "========================================================="

    # 1. 检查 80 端口 (多维精准检测版：支持原生进程 + Docker 容器)
    PORT_80_INFO=""
    DOCKER_80_INFO=""
    
    if command -v docker &> /dev/null; then
        DOCKER_80_INFO=$(sudo docker ps --filter "publish=80" --format "{{.Names}}" | head -n 1 || true)
    fi

    if command -v ss &> /dev/null; then
        PORT_80_INFO=$(sudo ss -tlpn | grep -E '(:80)\b' || true)
    elif command -v netstat &> /dev/null; then
        PORT_80_INFO=$(sudo netstat -tlpn | grep -E '(:80)\b' || true)
    else
        PORT_80_INFO=$(sudo lsof -i tcp:80 | grep LISTEN || true)
    fi

    if [ -n "$DOCKER_80_INFO" ]; then
        echo -e "80 端口: ${RED}【已占用】(Docker容器: $DOCKER_80_INFO)${RESET}"
    elif [ -n "$PORT_80_INFO" ]; then
        echo -e "80 端口: ${RED}【已占用】${RESET}"
    else
        echo -e "80 端口: ${GREEN}【空闲】${RESET}"
    fi

    # 2. 有有效证书简易看板
    echo -n "有效证书列表: "
    HAS_VALID_CERT=0
    if [ -d "$HOME/.acme.sh" ]; then
        for dir in $(find "$HOME/.acme.sh" -maxdepth 1 -type d ! -name ".acme.sh" ! -name "ca" ! -name "http.header" ! -name "dnsapi" ! -name "notify" ! -name "deploy" 2>/dev/null); do
            DOMAIN_NAME=$(basename "$dir")
            CLEAN_NAME=$(echo "$DOMAIN_NAME" | sed 's/_ecc//g')
            CERT_FILE="$dir/fullchain.cer"
            if [ -f "$CERT_FILE" ]; then
                if command -v openssl &> /dev/null; then
                    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
                    EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || echo 0)
                    NOW_SECONDS=$(date +%s)
                    if [ "$EXPIRY_SECONDS" -gt "$NOW_SECONDS" ]; then
                        REMAINING_DAYS=$(( (EXPIRY_SECONDS - NOW_SECONDS) / 86400 ))
                        echo -n "${CLEAN_NAME}(${REMAINING_DAYS}天) "
                        HAS_VALID_CERT=1
                    fi
                fi
            fi
        done
    fi
    [ "$HAS_VALID_CERT" -eq 0 ] && echo -n "无"
    echo ""

    # 3. 自动续签看守检测逻辑
    CRON_SERVICE_RUNNING=false
    if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
        CRON_SERVICE_RUNNING=true
    elif service cron status 2>/dev/null | grep -q "running" || service crond status 2>/dev/null | grep -q "running"; then
        CRON_SERVICE_RUNNING=true
    elif pgrep cron > /dev/null || pgrep crond > /dev/null; then
        CRON_SERVICE_RUNNING=true
    fi

    CRON_JOB_EXISTS=false
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        CRON_JOB_EXISTS=true
    fi

    if [ "$CRON_SERVICE_RUNNING" = true ] && [ "$CRON_JOB_EXISTS" = true ]; then
        echo -e "自动续签: ${GREEN}正常${RESET}"
    else
        echo -e "自动续签: ${YELLOW}异常 (定时服务未运行或无续签条目)${RESET}"
    fi

    echo "========================================================="

    # 4. 菜单选择
    echo "请选择操作："
    echo -e "1) 80 端口模式 ${YELLOW}⭐(推荐)${RESET}"
    echo "2) Cloudflare 模式 (使用 DNS API)"
    echo "3) 证书续签与维护 (支持一键清理失效证书)"
    echo "4) 查看证书路径 (多个域名时全列出来)"
    echo "5) 临时释放 80"
    echo "6) 恢复 80 端口 (重新启动被关闭的服务)"
    echo -e "7) ${GREEN}注册为系统快捷命令 cj${RESET}"
    echo -e "0) ${RED}退出脚本${RESET}"
    echo "========================================================="
    read -p "请输入选项 [0-7]: " MODE_CHOICE

    if [ "$MODE_CHOICE" = "0" ]; then
        echo "谢谢使用，再见！"
        exit 0
    fi

    # ----------------- 选项 1 和 选项 2 的逻辑 -----------------
    if [ "$MODE_CHOICE" = "1" ] || [ "$MODE_CHOICE" = "2" ]; then
        read -p "👉 请输入您的域名 (多个用逗号隔开，如 arm.971211.xyz,*.arm.971211.xyz): " RAW_INPUT_DOMAINS
        if [ "$RAW_INPUT_DOMAINS" = "0" ] || [ -z "$RAW_INPUT_DOMAINS" ]; then continue; fi

        SPACE_DOMAINS=$(echo "$RAW_INPUT_DOMAINS" | tr ',' ' ')
        FIRST_DOMAIN=$(echo $SPACE_DOMAINS | awk '{print $1}')
        MAIN_NAMING_DOMAIN=$(echo "$FIRST_DOMAIN" | sed 's/\*//g' | sed 's/^\.//g' | sed 's/_ecc//g')

        ACME_D_PARAMS=""
        for dm in $SPACE_DOMAINS; do
            ACME_D_PARAMS="$ACME_D_PARAMS -d $dm"
        done

        # --- 有效证书防重复申请拦截检测逻辑 ---
        DETECT_DIR="$HOME/.acme.sh/${MAIN_NAMING_DOMAIN}_ecc"
        [ ! -d "$DETECT_DIR" ] && DETECT_DIR="$HOME/.acme.sh/${MAIN_NAMING_DOMAIN}"
        
        SHOULD_ISSUE=true
        if [ -d "$DETECT_DIR" ] && [ -f "$DETECT_DIR/fullchain.cer" ]; then
            if command -v openssl &> /dev/null; then
                EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$DETECT_DIR/fullchain.cer" | cut -d= -f2)
                EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || echo 0)
                NOW_SECONDS=$(date +%s)
                
                if [ "$EXPIRY_SECONDS" -gt "$NOW_SECONDS" ]; then
                    REMAINING_DAYS=$(( (EXPIRY_SECONDS - NOW_SECONDS) / 86400 ))
                    echo -e "${YELLOW}=========================================================${RESET}"
                    echo -e "${YELLOW}⚠️  提醒：检测到域名 [${MAIN_NAMING_DOMAIN}] 的证书仍在有效期内（还剩 ${REMAINING_DAYS} 天）！${RESET}"
                    echo "---------------------------------------------------------"
                    echo "1) 继续使用之前的证书 (直接强制提取并建立标准路径规范)"
                    echo "2) 删除并重新申请 (覆盖旧证书)"
                    echo "0) 返回上一层"
                    echo -e "${YELLOW}=========================================================${RESET}"
                    read -p "请选择操作 [1-2, 或0返回]: " EXIST_CHOICE
                    [ -z "$EXIST_CHOICE" ] && EXIST_CHOICE="1"
                    
                    if [ "$EXIST_CHOICE" = "0" ]; then continue; fi
                    if [ "$EXIST_CHOICE" = "1" ]; then SHOULD_ISSUE=false; fi
                fi
            fi
        fi

        echo "---------------------------------------------------------"
        echo "请选择证书及私钥的导出路径："
        echo "1) 官方通用标准路径 (默认 /etc/ssl/certs/主域名/)"
        echo -e "2) ${GREEN}原生 Nginx 默认证书目录 (/etc/nginx/ssl/主域名/)${RESET}"
        echo "3) 当前路径下的 certs 文件夹 (./certs/)"
        echo "4) 完全自定义指定的路径"
        echo "0) 返回上一层"
        echo "---------------------------------------------------------"
        read -p "请输入路径选项 [1-4, 或0返回, 默认1]: " PATH_CHOICE
        [ -z "$PATH_CHOICE" ] && PATH_CHOICE="1"

        if [ "$PATH_CHOICE" = "0" ]; then continue; fi

        CURRENT_DIR=$(pwd)
        if [ "$PATH_CHOICE" = "1" ]; then
            CERT_DIR="/etc/ssl/certs/$MAIN_NAMING_DOMAIN"
        elif [ "$PATH_CHOICE" = "2" ]; then
            CERT_DIR="/etc/nginx/ssl/$MAIN_NAMING_DOMAIN"
        elif [ "$PATH_CHOICE" = "3" ]; then
            CERT_DIR="$CURRENT_DIR/certs"
        elif [ "$PATH_CHOICE" = "4" ]; then
            read -p "请输入自定义绝对路径 (输入 0 返回): " CUSTOM_PATH
            if [ "$CUSTOM_PATH" = "0" ] || [ -z "$CUSTOM_PATH" ]; then continue; fi
            CERT_DIR="$CUSTOM_PATH"
        else
            echo "无效选项！"; sleep 2; continue
        fi

        sudo mkdir -p "$CERT_DIR"
        REAL_CERT_DIR=$(cd "$CERT_DIR" && pwd)

        if [ -f /etc/debian_version ]; then
            sudo apt-get update -y && sudo apt-get install -y curl cron socat tar openssl
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y curl crontabs socat tar openssl
        fi

        if [ ! -f "$ACME_BIN" ]; then
            curl https://get.acme.sh | sh -s email=admin@$MAIN_NAMING_DOMAIN
        fi
        "$ACME_BIN" --set-default-ca --server letsencrypt

        if [ "$SHOULD_ISSUE" = "true" ]; then
            CF_TOKEN=""
            if [ "$MODE_CHOICE" = "2" ]; then
                read -p "🔑 请输入您的 Cloudflare API Token (输入 0 返回): " CF_TOKEN
                if [ "$CF_TOKEN" = "0" ] || [ -z "$CF_TOKEN" ]; then continue; fi
            fi

            if [ "$MODE_CHOICE" = "1" ]; then
                "$ACME_BIN" --issue --standalone $ACME_D_PARAMS --keylength ec-256 --force || true
            else
                export CF_Token="$CF_TOKEN"
                "$ACME_BIN" --issue --dns dns_cf $ACME_D_PARAMS --keylength ec-256 --force || true
            fi
        fi

        echo "正在执行规范化证书路径分发..."
        "$ACME_BIN" --install-cert -d "$FIRST_DOMAIN" --ecc \
            --key-file       "$REAL_CERT_DIR/${MAIN_NAMING_DOMAIN}.key"  \
            --fullchain-file "$REAL_CERT_DIR/${MAIN_NAMING_DOMAIN}.crt"

        CONF_TARGET_DIR="$HOME/.acme.sh/${FIRST_DOMAIN}_ecc"
        [ ! -d "$CONF_TARGET_DIR" ] && CONF_TARGET_DIR="$HOME/.acme.sh/${FIRST_DOMAIN}"
        if [ -d "$CONF_TARGET_DIR" ]; then
            sed -i '/Real_Export_Cert_Dir=/d' "$CONF_TARGET_DIR/$(basename $CONF_TARGET_DIR).conf" 2>/dev/null || true
            sed -i '/Real_Export_Cert_Dir=/d' "$CONF_TARGET_DIR/${FIRST_DOMAIN}.conf" 2>/dev/null || true
            echo "Real_Export_Cert_Dir='${REAL_CERT_DIR}'" >> "$CONF_TARGET_DIR/$(basename $CONF_TARGET_DIR).conf"
        fi

        echo -e "${GREEN}========================================================="
        echo " 🎉 规范化多域名证书分发成功！"
        echo " 📄 证书路径 (.crt): $REAL_CERT_DIR/${MAIN_NAMING_DOMAIN}.crt"
        echo " 🔑 私钥路径 (.key): $REAL_CERT_DIR/${MAIN_NAMING_DOMAIN}.key"
        echo -e "=========================================================${RESET}"
        read -p "按回车键返回主菜单..."

    # ----------------- 选项 3：精细化续签与一键删除逻辑 -----------------
    elif [ "$MODE_CHOICE" = "3" ]; then
        if [ ! -f "$ACME_BIN" ] || [ ! -d "$HOME/.acme.sh" ]; then echo "⚠️ 未检测到任何证书记录。"; sleep 2; continue; fi
        
        DOMAINS=($(find "$HOME/.acme.sh" -maxdepth 1 -type d ! -name ".acme.sh" ! -name "ca" ! -name "http.header" ! -name "dnsapi" ! -name "notify" ! -name "deploy" -exec basename {} \;))
        if [ ${#DOMAINS[@]} -eq 0 ]; then echo "ℹ️ 没有发现合法的域名记录。"; sleep 2; continue; fi

        echo "---------------------------------------------------------"
        echo "全部域名健康状态列表："
        INVALID_DOMAINS=()
        
        for i in "${!DOMAINS[@]}"; do
            TARGET_DOM="${DOMAINS[$i]}"
            CLEAN_DOM=$(echo "$TARGET_DOM" | sed 's/_ecc//g' | sed 's/\*//g' | sed 's/^\.//g')
            CERT_FILE="$HOME/.acme.sh/$TARGET_DOM/fullchain.cer"
            STATUS_STR=""
            
            if [ -f "$CERT_FILE" ] && command -v openssl &> /dev/null; then
                EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
                EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || echo 0)
                NOW_SECONDS=$(date +%s)
                if [ "$EXPIRY_SECONDS" -gt "$NOW_SECONDS" ]; then
                    REMAINING_DAYS=$(( (EXPIRY_SECONDS - NOW_SECONDS) / 86400 ))
                    STATUS_STR="${GREEN}有效 (剩余 ${REMAINING_DAYS} 天)${RESET}"
                else
                    STATUS_STR="${RED}无效 (证书已过期)${RESET}"
                    INVALID_DOMAINS+=("$TARGET_DOM")
                fi
            else
                STATUS_STR="${RED}无效 (未发现完整证书文件)${RESET}"
                INVALID_DOMAINS+=("$TARGET_DOM")
            fi
            echo -e "  [$((i+1))] ${CLEAN_DOM} --> ${STATUS_STR}"
        done
        echo "---------------------------------------------------------"
        echo -e "  [99] ${RED}一键安全删除以上所有无效/过期的域名证书${RESET}"
        echo -e "  [0]  ${YELLOW}返回上一层${RESET}"
        echo "---------------------------------------------------------"
        read -p "请输入操作序号 (续签输入数字，空格隔开; 0返回; 99清理): " CHOICES

        if [ "$CHOICES" = "0" ] || [ -z "$CHOICES" ]; then continue; fi

        if [ "$CHOICES" = "99" ]; then
            if [ ${#INVALID_DOMAINS[@]} -eq 0 ]; then
                echo "🟢 系统内没有需要清理的无效证书！"; sleep 2; continue;
            fi
            echo -e "${YELLOW}正在安全注销并移除过期或残存的无效域名文件夹...${RESET}"
            for INV_DOM in "${INVALID_DOMAINS[@]}"; do
                REAL_NAME=$(echo "$INV_DOM" | sed 's/_ecc//g')
                "$ACME_BIN" --remove -d "$REAL_NAME" --ecc &>/dev/null || true
                "$ACME_BIN" --remove -d "$INV_DOM" --ecc &>/dev/null || true
                rm -rf "$HOME/.acme.sh/$INV_DOM"
                echo -e "  🗑️  已成功移除: $INV_DOM"
            done
            echo -e "${GREEN}✅ 无效域名证书一键清理完毕！${RESET}"; read -p "按回车键返回主菜单..." ; continue;
        fi

        NGINX_DOCKER_RUNNING=$(sudo docker ps --format '{{.Names}}' | grep "nginx" || true)
        for CHOICE in $CHOICES; do
            INDEX=$((CHOICE-1))
            if [ $INDEX -lt 0 ] || [ $INDEX -ge ${#DOMAINS[@]} ]; then continue; fi
            TARGET_DOMAIN="${DOMAINS[$INDEX]}"
            CLEAN_DOMAIN=$(echo "$TARGET_DOMAIN" | sed 's/_ecc//g')
            
            if grep -q "Le_Webroot='6'" "$HOME/.acme.sh/${TARGET_DOMAIN}/${TARGET_DOMAIN}.conf" 2>/dev/null; then
                if [ -n "$NGINX_DOCKER_RUNNING" ]; then sudo docker stop nginx-proxy || true; fi
            fi
            "$ACME_BIN" --renew -d "$CLEAN_DOMAIN" --force --ecc || "$ACME_BIN" --renew -d "$TARGET_DOMAIN" --force --ecc || true
            if [ -n "$NGINX_DOCKER_RUNNING" ]; then sudo docker start nginx-proxy || true; fi
        done
        read -p "强制续签任务结束，按回车键返回主菜单..."

    # ----------------- 选项 4：查看证书 file 路径 -----------------
    elif [ "$MODE_CHOICE" = "4" ]; then
        if [ ! -d "$HOME/.acme.sh" ]; then echo "⚠️ 系统内无任何证书记录。"; sleep 2; continue; fi
        echo "========================================================="
        for dir in $(find "$HOME/.acme.sh" -maxdepth 1 -type d ! -name ".acme.sh" ! -name "ca" ! -name "http.header" ! -name "dnsapi" ! -name "notify" ! -name "deploy" 2>/dev/null); do
            DOMAIN_NAME=$(basename "$dir")
            CLEAN_NAME=$(echo "$DOMAIN_NAME" | sed 's/_ecc//g' | sed 's/\*//g' | sed 's/^\.//g')
            
            CONF_FILE="$dir/${DOMAIN_NAME}.conf"
            [ ! -f "$CONF_FILE" ] && CONF_FILE="$dir/${CLEAN_NAME}.conf"
            
            EXPORT_DIR=""
            if [ -f "$CONF_FILE" ]; then 
                EXPORT_DIR=$(grep "Real_Export_Cert_Dir=" "$CONF_FILE" | cut -d"'" -f2 || true)
            fi
            
            echo "🌐 域名看板: $CLEAN_NAME"
            if [ -n "$EXPORT_DIR" ] && [ -f "$EXPORT_DIR/${CLEAN_NAME}.crt" ]; then
                echo "   📄 证书 (.crt): $EXPORT_DIR/${CLEAN_NAME}.crt"
                echo "   🔑 私钥 (.key): $EXPORT_DIR/${CLEAN_NAME}.key"
            elif [ -n "$EXPORT_DIR" ] && [ -f "$EXPORT_DIR/${DOMAIN_NAME}.crt" ]; then
                echo "   📄 证书 (.crt): $EXPORT_DIR/${DOMAIN_NAME}.crt"
                echo "   🔑 私钥 (.key): $EXPORT_DIR/${DOMAIN_NAME}.key"
            else
                echo "   📄 原始缓存证书: $dir/fullchain.cer"
                echo "   🔑 原始缓存私钥: $dir/${DOMAIN_NAME}.key"
            fi
            echo "---------------------------------------------------------"
        done
        read -p "按回车键返回主菜单..."

    # ----------------- 选项 5：临时释放 80 端口 -----------------
    elif [ "$MODE_CHOICE" = "5" ]; then
        if [ -z "$PORT_80_INFO" ] && [ -z "$DOCKER_80_INFO" ]; then echo "🟢 80 端口本就处于空闲状态！"; sleep 2; continue; fi
        rm -f "$BACKUP_FILE"
        DOCKER_CONTAINER=$(sudo docker ps --filter "publish=80" --format "{{.Names}}" | head -n 1 || true)
        if [ -n "$DOCKER_CONTAINER" ]; then
            echo "docker:$DOCKER_CONTAINER" > "$BACKUP_FILE"
            sudo docker stop "$DOCKER_CONTAINER"
            echo "✅ 容器 [$DOCKER_CONTAINER] 已成功停止！"
        else
            if echo "$PORT_80_INFO" | grep -qi "nginx"; then
                echo "system:nginx" > "$BACKUP_FILE"
                sudo systemctl stop nginx || sudo service nginx stop || sudo killall nginx || true
                echo "✅ 系统级 Nginx 已成功关闭！"
            else
                echo "❌ 无法自动识别该进程，请手动执行 kill 杀死占用进程。"
            fi
        fi
        read -p "按回车键返回主菜单..."

    # ----------------- 选项 6：恢复 80 端口 -----------------
    elif [ "$MODE_CHOICE" = "6" ]; then
        if [ ! -f "$BACKUP_FILE" ]; then echo "⚠️ 未检测到释放记录，无需恢复。"; sleep 2; continue; fi
        SERVICE_TYPE=$(cut -d':' -f1 "$BACKUP_FILE")
        SERVICE_NAME=$(cut -d':' -f2 "$BACKUP_FILE")
        if [ "$SERVICE_TYPE" = "docker" ]; then
            sudo docker start "$SERVICE_NAME"
            echo "🟢 [$SERVICE_NAME] 容器已恢复运行！"
        elif [ "$SERVICE_TYPE" = "system" ]; then
            sudo systemctl start nginx || sudo service nginx start || true
            echo "🟢 系统级 Nginx 服务已恢复运行！"
        fi
        rm -f "$BACKUP_FILE"
        read -p "按回车键返回主菜单..."

    # ----------------- 选项 7：注册全局命令 cj -----------------
    elif [ "$MODE_CHOICE" = "7" ]; then
        echo "正在检查快捷命令 [cj] 的可用性..."
        
        if command -v cj &> /dev/null && [ ! -L /usr/local/bin/cj ]; then
            echo -e "${RED}❌ 注册失败：系统已存在名为 [cj] 的内置命令或软件，请换个名字。${RESET}"
            sleep 3
            continue
        fi

        if [ ! -w /usr/local/bin ]; then
            echo -e "${RED}❌ 注册失败：当前脚本用户没有 /usr/local/bin 的写入权限。${RESET}"
            sleep 3
            continue
        fi

        if [ -f "$0" ] && [ -s "$0" ] && [ "$0" != "/dev/fd/63" ]; then
            ln -sf "$SCRIPT_PATH" /usr/local/bin/cj
            chmod +x "$SCRIPT_PATH"
        else
            echo "检测到您正在使用网络一键连接运行，正在自动拉取并固化脚本实体..."
            curl -fsSL -o /usr/local/bin/easy-acme.sh "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/install.sh"
            chmod +x /usr/local/bin/easy-acme.sh
            ln -sf /usr/local/bin/easy-acme.sh /usr/local/bin/cj
        fi

        echo -e "${GREEN}✅ 注册成功！以后直接在任意目录下输入【cj】即可快速运行面板！${RESET}"
        read -p "按回车键返回主菜单..."
    else
        echo "错误：无效选项！"; sleep 1
    fi
done

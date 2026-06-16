# 1. 强行将最新的无红线全码写入本地快捷命令（不允许省略）
cat > /usr/local/bin/cj << 'EOF'
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

# 更新函数
perform_update() {
    echo -e "${C_CYAN}🔄 正在同步最新版本...${C_RESET}"
    curl -s -m 5 "$ONLINE_SCRIPT_URL" > /tmp/cj_new.sh
    if [ -s /tmp/cj_new.sh ]; then
        sudo mv /tmp/cj_new.sh "$LOCAL_SCRIPT_PATH"
        sudo chmod +x "$LOCAL_SCRIPT_PATH"
        echo -e "${C_GREEN}🎉 更新成功！快捷命令已就绪。${C_RESET}"
        sleep 1
        exec "$LOCAL_SCRIPT_PATH" --no-update
    else
        echo -e "${C_GRAY}❌ 更新失败，请检查 network 或 GitHub 仓库状态。${C_RESET}"
        read -p "按回车继续..." temp
    fi
}

# 卸载脚本函数
perform_uninstall() {
    echo -e "${C_YELLOW}🚨 正在完全卸载 cj 脚本...${C_RESET}"
    if [ -f "$LOCAL_SCRIPT_PATH" ]; then
        sudo rm -f "$LOCAL_SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v "cj --no-update") | crontab -
    echo -e "${C_GREEN}🎉 脚本及定时任务已清理干净。${C_RESET}"
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
            echo -e "1) 80 端口独立模式 ${C_YELLOW}⭐${C_RESET}"
            echo -e "2) Cloudflare DNS API 模式"
            echo -e "${LINE_GRAY}"
            read -p "选择模式 [1-2]: " MODE_OPTION

            echo -e "\n${C_CYAN}💡 域名输入规范：单域名直接输; 多个或泛域名用英文逗号隔开 (例: arm.av.com,*.arm.av.com)${C_RESET}"
            read -p "请输入域名组合: " DOMAINS
            if [ -z "$DOMAINS" ]; then echo "❌ 不能为空"; sleep 1; continue; fi

            MAIN_DOMAIN=$(echo "$DOMAINS" | cut -d',' -f1)
            DOMAIN_PARAMS=""
            IFS=',' read -ra ADDR <<< "$DOMAINS"
            for i in "${ADDR[@]}"; do DOMAIN_PARAMS="$DOMAIN_PARAMS -d $i"; done

            echo -e "\n${C_BLUE}📂 请选择证书分发路径${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 家目录 (~/.acme.sh/${MAIN_DOMAIN}_ecc/)"
            echo -e "2) Nginx 规范目录 (/etc/nginx/ssl/${MAIN_DOMAIN}/) ${C_YELLOW}⭐${C_RESET}"
            echo -e "3) 自定义绝对路径"
            echo -e "${LINE_GRAY}"
            read -p "选择路径 [1-3]: " PATH_OPTION

            if [ "$PATH_OPTION" == "1" ]; then
                TARGET_DIR="$HOME/.acme.sh/${MAIN_DOMAIN}_ecc"
            elif [ "$PATH_OPTION" == "3" ]; then
                read -p "请输入绝对路径: " TARGET_DIR
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
            read -p "按回车继续..." temp

        elif [ "$CERT_OPTION" == "3" ]; then
            "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
            read -p "按回车继续..." temp
        elif [ "$CERT_OPTION" == "4" ]; then
            echo -e "${LINE_GRAY}"
            [ -d "/etc/nginx/ssl" ] && ls -R /etc/nginx/ssl/ || echo "未发现 /etc/nginx/ssl 目录"
            echo -e "${LINE_GRAY}"
            read -p "按回车继续..." temp
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
        # 动态探测运行状态
        if command -v nginx &> /dev/null && systemctl is-active --quiet nginx; then
            NG_STATUS_TEXT="${C_GREEN}运行${C_RESET}"
            # 动态抓取 Nginx 实际监听的端口
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
        echo -e "1) 安装 / 彻底卸载"
        echo -e "2) 配置域名反向代理 ${C_YELLOW}⭐${C_RESET}"
        echo -e "3) 自定义修改占用端口"
        echo -e "4) 重新启动服务"
        echo -e "5) 关闭当前服务"
        echo -e "6) 核心级高性能优化 ${C_YELLOW}⭐${C_RESET}"
        echo -e "7) 视窗化查看/改写配置文件"
        echo -e "0) 返回上一层"
        echo -e "00) 退出脚本"
        echo -e "${LINE_GRAY}"
        read -p "请选择操作: " NG_OPTION

        if [ "$NG_OPTION" == "1" ]; then
            clear
            echo -e "1) 智装 Nginx (自动检测是否有旧备份)"
            echo -e "2) 强力卸载 (可选备份现有 Config 资产)"
            read -p "请选择子项: " SUB_INS
            if [ "$SUB_INS" == "1" ]; then
                if [ -d "$NG_BACKUP_DIR" ] && [ "$(ls -A $NG_BACKUP_DIR 2>/dev/null)" ]; then
                    read -p "💡 检测到有旧的备份配置，是否直接恢复还原？[y/N]: " IS_RESTORE
                fi
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y nginx
                elif command -v yum &> /dev/null; then
                    sudo yum install -y epel-release && sudo yum install -y nginx
                fi
                if [ "$IS_RESTORE" == "y" ] || [ "$IS_RESTORE" == "Y" ]; then
                    sudo cp -r $NG_BACKUP_DIR/* /etc/nginx/ 2>/dev/null
                    echo "🎉 历史备份配置已无缝恢复。"
                fi
                sudo systemctl enable nginx &>/dev/null
                sudo systemctl start nginx &>/dev/null
                echo "✅ 安装配置启动流程完毕。"; sleep 1
            elif [ "$SUB_INS" == "2" ]; then
                read -p "❓ 卸载前是否将当前配置打包备份到 $NG_BACKUP_DIR ？[y/N]: " IS_BAK
                if [ "$IS_BAK" == "y" ] || [ "$IS_BAK" == "Y" ]; then
                    sudo rm -rf "$NG_BACKUP_DIR" && sudo mkdir -p "$NG_BACKUP_DIR"
                    [ -d "/etc/nginx" ] && sudo cp -r /etc/nginx/* "$NG_BACKUP_DIR/"
                    echo "✅ 配置已备份。"
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
                echo -e "${C_CYAN}📋 宿主机有效 SSL 根资产证书：${C_RESET}"
                if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
                    echo "  (⚠️ /etc/nginx/ssl/ 下未检测到有效证书)"
                else
                    for i in "${!VALID_DOMAINS[@]}"; do echo "  $((i+1)) [ ${VALID_DOMAINS[$i]} ]"; done
                fi
                echo ""
                echo -e "${C_CYAN}📋 当前活跃反代集群一览 (前50条)：${C_RESET}"
                COUNT=0
                if [ -d "/etc/nginx/conf.d" ]; then
                    for conf_file in /etc/nginx/conf.d/*.conf; do
                        if [ -f "$conf_file" ] && [ $COUNT -lt 50 ]; then
                            EXTRACT_PASS=$(grep -oP 'proxy_pass \K[^;]+' "$conf_file" | head -n 1 | sed 's/http:\/\///')
                            EXTRACT_DOMAIN=$(grep -oP 'server_name \K[^;]+' "$conf_file" | head -n 2 | tail -n 1)
                            if [ -n "$EXTRACT_PASS" ] && [ -n "$EXTRACT_DOMAIN" ]; then
                                echo "  📍 $EXTRACT_PASS  ──►  $EXTRACT_DOMAIN"
                                let COUNT++
                            fi
                        fi
                    done
                fi
                [ $COUNT -eq 0 ] && echo "  (暂无已生效的反向代理配置)"
                echo -e "\n[ a ] 展现资产大盘  [ c ] 强力清扫闭合无效代理"
                echo -e "${LINE_GRAY}"
                read -p "请输入根证书序号或操作码 [0 返回]: " USER_CHOOSE

                if [ "$USER_CHOOSE" == "0" ] || [ -z "$USER_CHOOSE" ]; then break
                elif [ "$USER_CHOOSE" == "a" ] || [ "$USER_CHOOSE" == "A" ]; then
                    clear
                    echo "1) 专项调阅指定域名的专属反代"
                    echo "2) 归类展现全部分组域名资产"
                    read -p "请选子项: " SUB_A
                    if [ "$SUB_A" == "1" ]; then
                        for i in "${!VALID_DOMAINS[@]}"; do echo "  $((i+1))) ${VALID_DOMAINS[$i]}"; done
                        read -p "输入域名编号: " T_IDX
                        if [[ "$T_IDX" =~ ^[0-9]+$ ]] && [ "$T_IDX" -le "${#VALID_DOMAINS[@]}" ]; then
                            F_DOM="${VALID_DOMAINS[$((T_IDX-1))]}"
                            echo -e "🔎 属于 [ $F_DOM ] 的反代明细:"
                            for cf in /etc/nginx/conf.d/*.conf; do
                                if [ -f "$cf" ]; then
                                    ED=$(grep -oP 'server_name \K[^;]+' "$cf" | head -n 2 | tail -n 1)
                                    if [[ "$ED" == *"$F_DOM"* ]]; then
                                        EP=$(grep -oP 'proxy_pass \K[^;]+' "$cf" | head -n 1 | sed 's/http:\/\///')
                                        echo "  📍 $EP  ──►  $ED"
                                    fi
                                fi
                            done
                        fi
                    elif [ "$SUB_A" == "2" ]; then
                        for rd in "${VALID_DOMAINS[@]}"; do
                            echo -e "\n📂 根域归属: ${C_CYAN}$rd${C_RESET}"
                            for cf in /etc/nginx/conf.d/*.conf; do
                                if [ -f "$cf" ]; then
                                    ED=$(grep -oP 'server_name \K[^;]+' "$cf" | head -n 2 | tail -n 1)
                                    if [[ "$ED" == *"$rd"* ]]; then
                                        EP=$(grep -oP 'proxy_pass \K[^;]+' "$cf" | head -n 1 | sed 's/http:\/\///')
                                        echo "  📍 $EP  ──►  $ED"
                                    fi
                                fi
                            done
                        done
                    fi
                    read -p "按回车继续..." temp; continue
                elif [ "$USER_CHOOSE" == "c" ] || [ "$USER_CHOOSE" == "C" ]; then
                    clear
                    echo "🔍 正在进行物理传输层四局握手深度雷达探测..."
                    if [ -d "/etc/nginx/conf.d" ]; then
                        for cf in /etc/nginx/conf.d/*.conf; do
                            if [ -f "$cf" ]; then
                                EP=$(grep -oP 'proxy_pass \K[^;]+' "$cf" | head -n 1 | sed 's/http:\/\///')
                                ED=$(grep -oP 'server_name \K[^;]+' "$cf" | head -n 2 | tail -n 1)
                                if [ -n "$EP" ] && [ -n "$ED" ]; then
                                    TI=$(echo "$EP" | cut -d':' -f1); TP=$(echo "$EP" | cut -d':' -f2)
                                    if timeout 1.5 bash -c "</dev/tcp/${TI}/${TP}" &>/dev/null; then
                                        echo -e "🟢 健康: $ED ──► $EP"
                                    else
                                        echo -e "${C_GRAY}🚨 残效: $ED ──► $EP (断连)${C_RESET}"
                                        read -p "是否直接切除该残效配置文件？[y/N]: " IS_DEL
                                        [ "$IS_DEL" == "y" ] || [ "$IS_DEL" == "Y" ] && sudo rm -f "$cf"
                                    fi
                                fi
                            fi
                        done
                    fi
                    sudo nginx -t &>/dev/null && sudo systemctl reload nginx &>/dev/null
                    read -p "清理结束。按回车继续..." temp; continue
                fi

                if [[ "$USER_CHOOSE" =~ ^[0-9]+$ ]] && [ "$USER_CHOOSE" -le "${#VALID_DOMAINS[@]}" ] && [ "$USER_CHOOSE" -gt 0 ]; then
                    ROOT_DOMAIN="${VALID_DOMAINS[$((USER_CHOOSE-1))]}"
                else
                    echo "❌ 无效编号"; sleep 1; continue
                fi

                read -p "请输入子域前缀 (留空随机4位): " SUB_PREFIX
                [ -z "$SUB_PREFIX" ] && SUB_PREFIX=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 4)
                
                read -p "请输入后端目标端口 (❗必填): " NG_PORT
                if [ -z "$NG_PORT" ]; then echo "❌ 端口必填"; read -p "回车返回..." temp; continue; fi

                NG_DOMAIN="${SUB_PREFIX}.${ROOT_DOMAIN}"
                CONF_FILE_PATH="/etc/nginx/conf.d/${NG_DOMAIN}.conf"
                
                LOCAL_PRIVATE_IP=$(hostname -I | awk '{print $1}')
                [ -z "$LOCAL_PRIVATE_IP" ] && LOCAL_PRIVATE_IP="127.0.0.1"

                CUSTOM_HTTP=$(sudo grep -r "listen " /etc/nginx/conf.d/ /etc/nginx/nginx.conf 2>/dev/null | grep -v "443" | grep -oP 'listen \K[0-9]+' | head -n 1)
                CUSTOM_HTTPS=$(sudo grep -r "listen " /etc/nginx/conf.d/ /etc/nginx/nginx.conf 2>/dev/null | grep "ssl" | grep -oP 'listen \K[0-9]+' | head -n 1)
                [ -z "$CUSTOM_HTTP" ] && CUSTOM_HTTP="80"
                [ -z "$CUSTOM_HTTPS" ] && CUSTOM_HTTPS="443"

                sudo mkdir -p /etc/nginx/conf.d
                echo "server {
    listen $CUSTOM_HTTP;
    listen [::]:$CUSTOM_HTTP;
    server_name $NG_DOMAIN;
    return 301 https://\$host:\$server_port\$request_uri;
}
server {
    listen $CUSTOM_HTTPS ssl;
    listen [::]:$CUSTOM_HTTPS ssl;
    server_name $NG_DOMAIN;
    ssl_certificate /etc/nginx/ssl/$ROOT_DOMAIN/$ROOT_DOMAIN.crt;
    ssl_certificate_key /etc/nginx/ssl/$ROOT_DOMAIN/$ROOT_DOMAIN.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_pass http://$LOCAL_PRIVATE_IP:$NG_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}" | sudo tee "$CONF_FILE_PATH" > /dev/null

                sudo nginx -t &>/dev/null
                if [ $? -eq 0 ]; then
                    sudo systemctl reload nginx &>/dev/null
                    if timeout 1.5 bash -c "</dev/tcp/${LOCAL_PRIVATE_IP}/${NG_PORT}" &>/dev/null; then
                        echo -e "${C_GREEN}🎉 配置成功！反代已完美生效并打通后端端口。${C_RESET}"
                    else
                        if timeout 1.5 bash -c "</dev/tcp/127.0.0.1/${NG_PORT}" &>/dev/null; then
                            sed -i "s/$LOCAL_PRIVATE_IP:$NG_PORT/127.0.0.1:$NG_PORT/g" "$CONF_FILE_PATH"
                            sudo systemctl reload nginx &>/dev/null
                            echo -e "${C_GREEN}🎉 配置成功！已自动智能对齐至 127.0.0.1 环回口通路。${C_RESET}"
                        else
                            echo -e "${C_YELLOW}⚠️ 反代规则已留存，但探测到后端目标端口 $NG_PORT 当前处于闭合挂起状态，请排查后端服务！${C_RESET}"
                        fi
                    fi
                else
                    echo -e "${C_GRAY}❌ Nginx 核心语法校验失败，请检查根证书完整度！${C_RESET}"
                    sudo rm -f "$CONF_FILE_PATH"
                fi
                read -p "按回车继续..." temp
            done

        elif [ "$NG_OPTION" == "3" ]; then
            read -p "请输入自定义 HTTP 端口 (直接回车默认80): " SET_HTTP
            read -p "请输入自定义 HTTPS 端口 (直接回车默认443): " SET_HTTPS
            [ -z "$SET_HTTP" ] && SET_HTTP="80"
            [ -z "$SET_HTTPS" ] && SET_HTTPS="443"
            
            if [ -f "/etc/nginx/sites-enabled/default" ]; then
                sudo sed -i -E "s/listen [0-9]+ default_server/listen $SET_HTTP default_server/g" /etc/nginx/sites-enabled/default
            fi
            sudo sed -i -E "s/listen [0-9]+;/listen $SET_HTTP;/g" /etc/nginx/conf.d/*.conf 2>/dev/null
            sudo sed -i -E "s/listen \[::\]:[0-9]+;/listen \[::\]:$SET_HTTP;/g" /etc/nginx/conf.d/*.conf 2>/dev/null
            sudo sed -i -E "s/listen [0-9]+ ssl;/listen $SET_HTTPS ssl;/g" /etc/nginx/conf.d/*.conf 2>/dev/null
            sudo sed -i -E "s/listen \[::\]:[0-9]+ ssl;/listen \[::\]:$SET_HTTPS ssl;/g" /etc/nginx/conf.d/*.conf 2>/dev/null
            
            sudo nginx -t && sudo systemctl restart nginx
            echo -e "${C_GREEN}✅ 端口改写改版应用成功！${C_RESET}"; sleep 1

        elif [ "$NG_OPTION" == "4" ]; then
            sudo nginx -t &>/dev/null
            if [ $? -eq 0 ]; then
                sudo systemctl restart nginx 2>/dev/null || sudo systemctl start nginx
                echo "✅ Nginx 启动/重启成功"; sleep 1
            else
                echo "❌ 语法错误，拒绝启动"; sleep 2
            fi
        elif [ "$NG_OPTION" == "5" ]; then
            sudo systemctl stop nginx
            echo "✅ 服务已彻底阻断关闭"; sleep 1

        elif [ "$NG_OPTION" == "6" ]; then
            clear
            echo -e "${C_BLUE}⚡ Nginx 顶级高性能核心级优化预设${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 低延迟预设 (开启 Tcp_nodelay / 极速握手反代)"
            echo -e "2) 高并发预设 (极度扩充 Worker_connections / 内存级多路复用)"
            echo -e "3) 均衡稳定预设 (经典高兼容生产标准生产调优)"
            echo -e "${LINE_GRAY}"
            read -p "请注入您需要的预设调优编号: " OPT_TYPE
            
            if [ -f "/etc/nginx/nginx.conf" ] && ! grep -q "limit_conn_zone" /etc/nginx/nginx.conf; then
                sudo sed -i '/http {/a \    limit_conn_zone $binary_remote_addr zone=addr:10m;\n    limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;\n    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=cj_cache:10m max_size=1g inactive=60m use_temp_path=off;' /etc/nginx/nginx.conf
                sudo mkdir -p /var/cache/nginx
            fi

            if [ "$OPT_TYPE" == "1" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 2048;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 低延迟优化参数已打入。"; sleep 1
            elif [ "$OPT_TYPE" == "2" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 65535;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 高并发超大句柄容量参数已打入。"; sleep 1
            elif [ "$OPT_TYPE" == "3" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 4096;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 经典生产均衡优化已就绪。"; sleep 1
            fi
            sudo nginx -t && sudo systemctl reload nginx 2>/dev/null

        elif [ "$NG_OPTION" == "7" ]; then
            if ! command -v nano &> /dev/null; then
                echo "📦 正在无感配置 nano 精简文字流视窗工具..."
                if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y nano
                elif command -v yum &> /dev/null; then sudo yum install -y nano; fi
            fi
            while true; do
                clear
                echo -e "${C_CYAN}📋 请点选您要使用 nano 视窗改写的配置文件：${C_RESET}"
                echo -e "${LINE_GRAY}"
                echo "1) [主核心配置文件]  /etc/nginx/nginx.conf"
                CONF_LIST=()
                if [ -d "/etc/nginx/conf.d" ]; then
                    for f in /etc/nginx/conf.d/*.conf; do [ -f "$f" ] && CONF_LIST+=("$f"); done
                fi
                for idx in "${!CONF_LIST[@]}"; do
                    echo "$((idx+2))) [反代子配置文件]  $(basename "${CONF_LIST[$idx]}")"
                done
                echo -e "${LINE_GRAY}"
                read -p "请输入对应配置文件序号 [0 返回]: " NANO_CHOOSE
                if [ "$NANO_CHOOSE" == "0" ] || [ -z "$NANO_CHOOSE" ]; then break; fi
                if [ "$NANO_CHOOSE" == "1" ]; then
                    nano /etc/nginx/nginx.conf
                else
                    REAL_IDX=$((NANO_CHOOSE-2))
                    if [ $REAL_IDX -ge 0 ] && [ $REAL_IDX -lt ${#CONF_LIST[@]} ]; then
                        nano "${CONF_LIST[$REAL_IDX]}"
                    else
                        echo "❌ 序号错误"; sleep 1
                    fi
                fi
                sudo nginx -t && sudo systemctl reload nginx 2>/dev/null
            done
        elif [ "$NG_OPTION" == "00" ] ; then exit 0
        elif [ "$NG_OPTION" == "0" ] ; then break
        fi
    done
}

# 全局主菜单循环
while true; do
    clear
    echo -e "${C_BLUE}⚡ cj 全能系统管理与证书脚本${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "1) 查询当前基础系统现状"
    echo -e "2) 在线更新本地脚本 ${C_YELLOW}⭐${C_RESET}"
    echo -e "3) Nginx 核心矩阵服务管理 ${C_YELLOW}⭐${C_RESET}"
    echo -e "4) acme.sh 自动化证书管家 ${C_YELLOW}⭐${C_RESET}"
    echo -e "5) BBR3 内核及传输层安装 (占位)"
    echo -e "6) Network 内核吞吐优化 (占位)"
    echo -e "7) 一键分布式轻量 SB (占位)"
    echo -e "8) Docker 全栈容器管理 (占位)"
    echo -e "9) Komari 服务可用性探针 (占位)"
    echo -e "98) 全局注册本地快捷命令 cj"
    echo -e "99) 强力完全卸载此脚本"
    echo -e "0) 安全退出"
    echo -e "${LINE_GRAY}"
    read -p "请注入主操作编号 [0-9]: " MAIN_OPTION

    case $MAIN_OPTION in
        1)
            clear
            echo -e "${C_CYAN}📋 系统现状大盘查${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo " 内核版本: $(uname -r)"
            echo " 系统架构: $(uname -m)"
            echo " 运行时间: $(uptime -p)"
            echo " 节点时间: $(date)"
            echo -e "${LINE_GRAY}"
            read -p "按回回车返回主菜单..." temp
            ;;
        2) perform_update ;;
        3) menu_nginx_management ;;
        4) menu_certificate_management ;;
        5|6|7|8|9) echo "🚧 功能占位开发中..."; sleep 1.5 ;;
        98)
            sudo cp "$0" "$LOCAL_SCRIPT_PATH"
            sudo chmod +x "$LOCAL_SCRIPT_PATH"
            (crontab -l 2>/dev/null | grep -v "cj --no-update"; echo "0 3 * * * $LOCAL_SCRIPT_PATH --no-update > /dev/null 2>&1") | crontab -
            echo -e "${C_GREEN}✅ [cj] 全局命令注册成功。可在任意目录直接输入 cj 唤醒！${C_RESET}"; sleep 1.5
            ;;
        99) perform_uninstall ;;
        0) echo "👋 感谢使用。"; exit 0 ;;
        *) echo "❌ 无效编号"; sleep 1 ;;
    esac
done
EOF

# 2. 赋予执行权限并立刻运行
chmod +x /usr/local/bin/cj
cj

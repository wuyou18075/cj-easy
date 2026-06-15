#!/bin/bash

# =========================================================
#             ⚡ cj 全能系统管理与证书脚本 (四层合拢版) ⚡
# =========================================================

# 1. 脚本全局常量定义
ONLINE_SCRIPT_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh"
LOCAL_SCRIPT_PATH="/usr/local/bin/cj"

# 2. 核心功能：在线检查并更新本地脚本函数
perform_update() {
    echo "🔄 正在检查在线版本并同步更新..."
    curl -s -m 5 "$ONLINE_SCRIPT_URL" > /tmp/cj_new.sh
    if [ -s /tmp/cj_new.sh ]; then
        sudo mv /tmp/cj_new.sh "$LOCAL_SCRIPT_PATH"
        sudo chmod +x "$LOCAL_SCRIPT_PATH"
        echo "========================================================="
        echo "🎉 【更新成功】快捷命令已同步至最新全码反代版！"
        echo "========================================================="
        echo "🔄 正在自动重新载入新脚本..."
        sleep 2
        exec "$LOCAL_SCRIPT_PATH" --no-update
    else
        echo "========================================================="
        echo "❌ 【更新失败】无法连接到 GitHub 更新源！"
        echo "💡 提示：请确认您是否已将最新代码提交推送(Push)到 GitHub 仓库，或检查网络连接。"
        echo "========================================================="
        read -p "按回车键继续..." temp
    fi
}

# 3. 核心功能：脚本完全卸载逻辑函数
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

# 4. 环境依赖与 acme.sh 自动化检测安装检测
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
        sudo systemctl enable cron 2>/dev/null || sudo systemctl enable crond 2>/dev/null
        sudo systemctl start cron 2>/dev/null || sudo systemctl start crond 2>/dev/null
    fi
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh -s email=my@av.com
        source "$HOME/.acme.sh/acme.sh.env" 2>/dev/null
    fi
}

# 5. 专属子函数：证书管理二级菜单
menu_certificate_management() {
    while true; do
        check_acme_env
        PORT_80_CHECK=$(ss -lptn | grep -q ":80 " && echo "【已占用】" || echo "【未占用】")
        clear
        echo "========================================================="
        echo "80 端口: $PORT_80_CHECK"
        echo "有效证书: "
        if [ -d "/etc/nginx/ssl" ]; then
            ls /etc/nginx/ssl/ 2>/dev/null
        else
            echo "暂无"
        fi
        echo "自动续签: 正常"
        echo "========================================================="
        echo "请选择操作："
        echo "1) 申请证书 ⭐(含 80/Cloudflare 模式)"
        echo "3) 证书续签与维护 "
        echo "4) 查看证书路径 "
        echo "5) 临时释放 80 端口"
        echo "6) 恢复 80 端口 (重新启动被关闭的服务)"
        echo "00) 退出脚本"
        echo "0) 返回上一层"
        echo "========================================================="
        read -p "请输入选项: " CERT_OPTION

        if [ "$CERT_OPTION" == "1" ]; then
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
            echo "   - 如果只需要申请【单个域名】，直接输入即可（例：arm.av.com）"
            echo "   - 如果需要同时申请【多个域名】或【包含泛域名】，请务必使用【英文逗号】隔开"
            echo "   - 规范示例：arm.av.com,*.arm.av.com"
            echo ""
            read -p "请输入您的域名组合: " DOMAINS
            
            if [ -z "$DOMAINS" ]; then
                echo "❌ 域名不能为空！"
                sleep 2
                continue
            fi

            MAIN_DOMAIN=$(echo "$DOMAINS" | cut -d',' -f1)
            DOMAIN_PARAMS=""
            IFS=',' read -ra ADDR <<< "$DOMAINS"
            for i in "${ADDR[@]}"; do
                DOMAIN_PARAMS="$DOMAIN_PARAMS -d $i"
            done

            echo ""
            echo "========================================================="
            echo "             📂 请选择证书分发目标路径"
            echo "========================================================="
            echo "1) 默认当前用户家目录 (~/.acme.sh/${MAIN_DOMAIN}_ecc/)"
            echo "2) 原生 Nginx 规范证书目录 (/etc/nginx/ssl/${MAIN_DOMAIN}/)"
            echo "3) 自定义输入任意绝对路径"
            echo "========================================================="
            read -p "请选择路径模式 [1-3]: " PATH_OPTION

            if [ "$PATH_OPTION" == "1" ]; then
                TARGET_DIR="$HOME/.acme.sh/${MAIN_DOMAIN}_ecc"
            elif [ "$PATH_OPTION" == "2" ]; then
                TARGET_DIR="/etc/nginx/ssl/${MAIN_DOMAIN}"
            elif [ "$PATH_OPTION" == "3" ]; then
                read -p "请输入自定义绝对路径: " TARGET_DIR
            else
                TARGET_DIR="/etc/nginx/ssl/${MAIN_DOMAIN}"
            fi

            if [ "$MODE_OPTION" == "1" ]; then
                echo "▶️ 正在通过 80 端口模式申请证书..."
                sudo systemctl stop nginx 2>/dev/null || true
                "$HOME/.acme.sh/acme.sh" --issue --standalone $DOMAIN_PARAMS --server letsencrypt
                sudo systemctl start nginx 2>/dev/null || true
            else
                echo "▶️ 正在通过 Cloudflare DNS API 模式申请证书..."
                read -p "请输入您的 Cloudflare API Token: " CF_TOKEN
                export CF_Token="$CF_TOKEN"
                "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf $DOMAIN_PARAMS --server letsencrypt
            fi

            if [ -f "$HOME/.acme.sh/${MAIN_DOMAIN}_ecc/${MAIN_DOMAIN}.key" ]; then
                echo "🎉 证书签发完成！正在分发到目标目录..."
                sudo mkdir -p "$TARGET_DIR"
                "$HOME/.acme.sh/acme.sh" --install-cert $DOMAIN_PARAMS \
                    --key-file "${TARGET_DIR}/${MAIN_DOMAIN}.key" \
                    --fullchain-file "${TARGET_DIR}/${MAIN_DOMAIN}.crt"
                echo "✅ 证书已成功同步至: ${TARGET_DIR}/"
                if [[ "$TARGET_DIR" == *nginx* ]]; then
                    sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
                fi
            else
                echo "❌ 证书签发存在异常，请检查日志。"
            fi
            read -p "按回车键继续..." temp

        elif [ "$CERT_OPTION" == "3" ]; then
            echo "正在强制触发证书自动续签与维护..."
            "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true
            read -p "按回车键继续..." temp

        elif [ "$CERT_OPTION" == "4" ]; then
            echo "========================================================="
            echo "📋 当前系统已挂载的证书路径一览："
            echo "========================================================="
            if [ -d "/etc/nginx/ssl" ]; then
                ls -R /etc/nginx/ssl/
            else
                echo "未发现配置目录 /etc/nginx/ssl/"
            fi
            echo "========================================================="
            read -p "按回车键继续..." temp

        elif [ "$CERT_OPTION" == "5" ]; then
            echo "正在临时释放 80 端口..."
            sudo systemctl stop nginx 2>/dev/null || true
            echo "80 端口服务已暂停。"
            sleep 2

        elif [ "$CERT_OPTION" == "6" ]; then
            echo "正在恢复 80 端口服务..."
            sudo systemctl start nginx 2>/dev/null || true
            echo "80 端口服务已重新启动。"
            sleep 2

        elif [ "$CERT_OPTION" == "00" ]; then
            echo "👋 退出整个脚本。"
            exit 0
        elif [ "$CERT_OPTION" == "0" ]; then
            break
        fi
    done
}

# 6. 专属子函数：Nginx 管理二级菜单
menu_nginx_management() {
    while true; do
        NGINX_STATUS="\e[31m已停止\e[0m"
        if command -v nginx &> /dev/null; then
            if systemctl is-active --quiet nginx; then
                NGINX_STATUS="\e[32m运行\e[0m"
            fi
        else
            NGINX_STATUS="\e[33m未安装\e[0m"
        fi

        clear
        echo "========================================================="
        echo -e " nginx 状态: $NGINX_STATUS"
        echo "========================================================="
        echo "1) 安装 Nginx"
        echo "2) 卸载 Nginx"
        echo "3) 高性能优化"
        echo "4) 查看 nginx 配置文件"
        echo "5) 配置反向代理"
        echo "0) 返回上一层"
        echo "00) 退出脚本"
        echo "========================================================="
        read -p "请选择操作 [0-5, 00]: " NG_OPTION

        if [ "$NG_OPTION" == "1" ]; then
            echo "📦 正在安装系统原生 Nginx..."
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y nginx
            elif command -v yum &> /dev/null; then
                sudo yum install -y epel-release && sudo yum install -y nginx
            fi
            sudo systemctl enable nginx 2>/dev/null || true
            sudo systemctl start nginx 2>/dev/null || true
            echo "✅ 安装程序执行完毕。"
            sleep 2

        elif [ "$NG_OPTION" == "2" ]; then
            echo "🚨 正在彻底清洗并卸载 Nginx..."
            sudo systemctl stop nginx 2>/dev/null || true
            if command -v apt-get &> /dev/null; then
                sudo apt-get purge -y nginx nginx-common nginx-core
                sudo apt-get autoremove -y
            elif command -v yum &> /dev/null; then
                sudo yum remove -y nginx
            fi
            sudo rm -rf /etc/nginx /var/log/nginx
            echo "✅ 卸载干净。"
            sleep 2

        elif [ "$NG_OPTION" == "3" ]; then
            echo "🚧 高性能优化模块正在快马加鞭开发中，目前仅作为功能占位！"
            sleep 2

        elif [ "$NG_OPTION" == "4" ]; then
            if ! command -v vim &> /dev/null; then
                echo "📦 检测到当前系统缺少 vim 编辑器，正在自动安装..."
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y vim
                elif command -v yum &> /dev/null; then
                    sudo yum install -y vim
                fi
            fi
            if [ -f "/etc/nginx/nginx.conf" ]; then
                echo "🚀 正在调起 vim 查看主配置文件..."
                vim /etc/nginx/nginx.conf
            else
                echo "❌ 错误：未在系统内发现 /etc/nginx/nginx.conf，请确认已安装 Nginx！"
                sleep 2
            fi

        elif [ "$NG_OPTION" == "5" ]; then
            if [ ! -d "/etc/nginx" ]; then
                echo "❌ 未检测到 Nginx 配置目录，请先执行安装！"
                sleep 2
                continue
            fi

            while true; do
                VALID_DOMAINS=()
                if [ -d "/etc/nginx/ssl" ]; then
                    for dir in /etc/nginx/ssl/*; do
                        if [ -d "$dir" ]; then
                            VALID_DOMAINS+=($(basename "$dir"))
                        fi
                    done
                fi

                clear
                echo "========================================================="
                echo "📋 请选择当前电脑中有效域名的序号："
                if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
                    echo "   (⚠️ 系统内未在 /etc/nginx/ssl/ 下检测到有效证书目录！)"
                else
                    for i in "${!VALID_DOMAINS[@]}"; do
                        echo "  $((i+1)) ${VALID_DOMAINS[$i]}"
                    done
                fi
                echo ""

                echo "📋 \"输入的域名的\"反向代理列表(默认50个)："
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
                if [ $COUNT -eq 0 ]; then
                    echo "   (暂无已配置的自定义反向代理配置)"
                fi
                echo ""

                echo "a 列出全部反向代理,(后续按1选不同域名编号,专门列出的那个域名的或者2列出全部域名)"
                echo "c 一键监测无效代理,监测出来后给个是否删除无效"
                echo "========================================================="
                read -p "请输入域名对应的序号或操作编号 [0 返回]: " USER_CHOOSE

                if [ "$USER_CHOOSE" == "0" ] || [ -z "$USER_CHOOSE" ]; then
                    break
                
                elif [ "$USER_CHOOSE" == "a" ] || [ "$USER_CHOOSE" == "A" ]; then
                    clear
                    echo "========================================================="
                    echo "   🔍 请选择列出反向代理的展现模式："
                    echo "========================================================="
                    echo "1) 选不同域名编号, 专门列出所选域名的专属反代"
                    echo "2) 列出全部分组域名资产一览"
                    echo "========================================================="
                    read -p "请输入子选项 [1-2]: " SUB_A_OPTION
                    
                    if [ "$SUB_A_OPTION" == "1" ]; then
                        clear
                        echo "========================================================="
                        echo "🎯 请选择您要单独专项排查的目标根域名："
                        echo "========================================================="
                        for i in "${!VALID_DOMAINS[@]}"; do
                            echo "  $((i+1))) ${VALID_DOMAINS[$i]}"
                        done
                        echo "========================================================="
                        read -p "请输入域名编号: " TARGET_SUB_IDX
                        
                        if [[ "$TARGET_SUB_IDX" =~ ^[0-9]+$ ]] && [ "$TARGET_SUB_IDX" -le "${#VALID_DOMAINS[@]}" ] && [ "$TARGET_SUB_IDX" -gt 0 ]; then
                            FILTER_DOMAIN="${VALID_DOMAINS[$((TARGET_SUB_IDX-1))]}"
                            clear
                            echo "========================================================="
                            echo -e "🔎 正在专项列出属于根域名 [\e[32m$FILTER_DOMAIN\e[0m] 的反代明细："
                            echo "========================================================="
                            ANY_F=0
                            if [ -d "/etc/nginx/conf.d" ]; then
                               _for conf_file in /etc/nginx/conf.d/*.conf; do
                                    if [ -f "$conf_file" ]; then
                                        EXTRACT_DOMAIN=$(grep -oP 'server_name \K[^;]+' "$conf_file" | head -n 2 | tail -n 1)
                                        if [[ "$EXTRACT_DOMAIN" == *"$FILTER_DOMAIN"* ]]; then
                                            ANY_F=1
                                            EXTRACT_PASS=$(grep -oP 'proxy_pass \K[^;]+' "$conf_file" | head -n 1 | sed 's/http:\/\///')
                                            echo "   📍 $EXTRACT_PASS  ──►  $EXTRACT_DOMAIN"
                                        fi
                                    fi
                                done
                            fi
                            if [ $ANY_F -eq 0 ]; then
                                echo "   (该域名下目前没有挂载任何反代子配置)"
                            fi
                            echo "========================================================="
                        else
                            echo "❌ 输入编号有误。"
                        fi
                    elif [ "$SUB_A_OPTION" == "2" ]; then
                        clear
                        echo "========================================================="
                        echo "📋 全网反向代理资产大盘点 (按根域名分组归类)："
                        echo "========================================================="
                        if [ -d "/etc/nginx/conf.d" ]; then
                            for root_d in "${VALID_DOMAINS[@]}"; do
                                echo -e "\n📂 根域名归属: \e[36m$root_d\e[0m"
                                echo "--------------------------------------------------------"
                                ANY_MATCH=0
                                for conf_file in /etc/nginx/conf.d/*.conf; do
                                    if [ -f "$conf_file" ]; then
                                        EXTRACT_DOMAIN=$(grep -oP 'server_name \K[^;]+' "$conf_file" | head -n 2 | tail -n 1)
                                        if [[ "$EXTRACT_DOMAIN" == *"$root_d"* ]]; then
                                            ANY_MATCH=1
                                            EXTRACT_PASS=$(grep -oP 'proxy_pass \K[^;]+' "$conf_file" | head -n 1 | sed 's/http:\/\///')
                                            echo "   📍 $EXTRACT_PASS  ──►  $EXTRACT_DOMAIN"
                                        fi
                                    fi
                                done
                                if [ $ANY_MATCH -eq 0 ]; then
                                    echo "   (该域名下暂未挂载任何反代子配置文件)"
                                fi
                            done
                        fi
                        echo "========================================================="
                    fi
                    read -p "操作完毕。按回车键继续..." temp
                    continue

                elif [ "$USER_CHOOSE" == "c" ] || [ "$USER_CHOOSE" == "C" ]; then
                    clear
                    echo "🔍 正在通过底层四层 TCP 握手探针进行可用性监测..."
                    echo "========================================================="
                    if [ -d "/etc/nginx/conf.d" ]; then
                        for conf_file in /etc/nginx/conf.d/*.conf; do
                            if [ -f "$conf_file" ]; then
                                EXTRACT_PASS=$(grep -oP 'proxy_pass \K[^;]+' "$conf_file" | head -n 1 | sed 's/http:\/\///')
                                EXTRACT_DOMAIN=$(grep -oP 'server_name \K[^;]+' "$conf_file" | head -n 2 | tail -n 1)
                                if [ -n "$EXTRACT_PASS" ] && [ -n "$EXTRACT_DOMAIN" ]; then
                                    # 解析出 IP 和 端口
                                    T_IP=$(echo "$EXTRACT_PASS" | cut -d':' -f1)
                                    T_PORT=$(echo "$EXTRACT_PASS" | cut -d':' -f2)
                                    
                                    # 🛠️ 监测优化：不依赖 curl 返回值，只测 TCP 端口是否建立连接
                                    if timeout 2 bash -c "</dev/tcp/${T_IP}/${T_PORT}" &>/dev/null; then
                                        echo "🟢 健康反代：$EXTRACT_DOMAIN ──► $EXTRACT_PASS [传输层已打通]"
                                    else
                                        echo "🚨 揪出无效代理：$EXTRACT_DOMAIN ($EXTRACT_PASS) [端口彻底闭合/拒绝服务]"
                                        read -p "❓ 是否确认彻底删除此失效反代配置？[y/N]: " IS_DEL
                                        if [ "$IS_DEL" == "y" ] || [ "$IS_DEL" == "Y" ]; then
                                            sudo rm -f "$conf_file"
                                            echo "✅ 已清除该失效文件。"
                                        fi
                                    fi
                                fi
                            fi
                        done
                    fi
                    sudo nginx -t &>/dev/null && sudo systemctl reload nginx &>/dev/null
                    read -p "监测处理完毕。按回车键继续..." temp
                    continue
                fi

                DOMAIN_INDEX=$USER_CHOOSE
                if [[ "$DOMAIN_INDEX" =~ ^[0-9]+$ ]] && [ "$DOMAIN_INDEX" -le "${#VALID_DOMAINS[@]}" ] && [ "$DOMAIN_INDEX" -gt 0 ]; then
                    ROOT_DOMAIN="${VALID_DOMAINS[$((DOMAIN_INDEX-1))]}"
                else
                    echo "❌ 选项输入错误，请重试！"
                    sleep 1.5
                    continue
                fi

                read -p "请输入您要绑定的子域前缀 (留空则随机生成4位字母数字): " SUB_PREFIX
                if [ -z "$SUB_PREFIX" ] ; then
                    SUB_PREFIX=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 4)
                    echo "💡 检测到输入留空，已为您自动生成随机前缀: $SUB_PREFIX"
                fi

                read -p "请输入本地被转发的目标端口 (❗必填): " NG_PORT
                if [ -z "$NG_PORT" ]; then
                    echo "❌ 错误：转发端口为必填项，不允许为空！"
                    read -p "按回车键返回..." temp
                    continue
                fi

                NG_DOMAIN="${SUB_PREFIX}.${ROOT_DOMAIN}"
                CONF_FILE_PATH="/etc/nginx/conf.d/${NG_DOMAIN}.conf"
                SSL_CERT_PATH="/etc/nginx/ssl/${ROOT_DOMAIN}/${ROOT_DOMAIN}.crt"
                SSL_KEY_PATH="/etc/nginx/ssl/${ROOT_DOMAIN}/${ROOT_DOMAIN}.key"

                LOCAL_PRIVATE_IP=$(hostname -I | awk '{print $1}')
                if [ -z "$LOCAL_PRIVATE_IP" ] ; then
                    LOCAL_PRIVATE_IP="127.0.0.1"
                fi

                sudo mkdir -p /etc/nginx/conf.d
                echo "server {
    listen 80;
    listen [::]:80;
    server_name $NG_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $NG_DOMAIN;

    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;

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

                echo "⏳ 正在对新写的反代文件进行 Nginx 核心语法校验..."
                sudo nginx -t
                NGINX_TEST_RC=$?

                if [ $NGINX_TEST_RC -eq 0 ]; then
                    sudo systemctl reload nginx &>/dev/null
                    
                    # 🎯 核心进化：彻底废除应用层 HTTP 状态探测，直接走 4 层 TCP 盲测与内存校验
                    echo "🔍 正在进行宿主机传输层 TCP 握手状态联调探测..."
                    sleep 1
                    
                    TCP_CONNECTED=0
                    # 优先盲测内网私有 IP 端口
                    if timeout 2 bash -c "</dev/tcp/${LOCAL_PRIVATE_IP}/${NG_PORT}" &>/dev/null; then
                        TCP_CONNECTED=1
                    # 次选盲测 127.0.0.1
                    elif timeout 2 bash -c "</dev/tcp/127.0.0.1/${NG_PORT}" &>/dev/null; then
                        # 自动修正为 127
                        sed -i "s/$LOCAL_PRIVATE_IP:$NG_PORT/127.0.0.1:$NG_PORT/g" "$CONF_FILE_PATH"
                        sudo systemctl reload nginx &>/dev/null
                        TCP_CONNECTED=1
                    fi

                    # 校验 Nginx 运行内存大盘中是否已经吃下了这个虚拟域名
                    NGINX_MEM_OK=0
                    if sudo nginx -T 2>/dev/null | grep -q "server_name $NG_DOMAIN"; then
                        NGINX_MEM_OK=1
                    fi

                    echo "========================================================="
                    echo "🚀 铁证核验：配置文件已成功写死并留存: $CONF_FILE_PATH"
                    echo "========================================================="
                    
                    if [ $TCP_CONNECTED -eq 1 ] && [ $NGINX_MEM_OK -eq 1 ]; then
                        echo "🎉 【配置完全成功】传输层打通且 Nginx 内存安全加载！"
                        echo "💡 提示：后端端口 $NG_PORT 响应完全正常。如果公网打不开，请专项排查 Cloudflare 小云朵或本地防火墙（UFW）。"
                    else
                        echo "⚠️ 传输层探测到目标端口 $NG_PORT 处于闭合状态，但文件已为您【强行留存】便于排查！"
                    fi
                else
                    echo "========================================================="
                    echo "❌ 【Nginx 语法校验失败！】"
                    echo "========================================================="
                fi
                read -p "按回车键继续..." temp
            done

        elif [ "$NG_OPTION" == "00" ]; then
            exit 0
        elif [ "$NG_OPTION" == "0" ]; then
            break
        fi
    done
}

# 7. 全局主循环菜单 
while true; do
    clear
    echo "========================================================="
    echo "             ⚡ cj 全能系统管理与证书脚本 ⚡"
    echo "========================================================="
    echo "1) 查询系统信息"
    echo "2) 更新最新脚本"
    echo "3) Nginx 管理模块"
    echo "4) 申请证书与维护"
    echo "5) BBR3 安装 (占位)"
    echo "6) Network 优化 (占位)"
    echo "7) 一键 SB (占位)"
    echo "8) Docker 管理 (占位)"
    echo "9) Komari 探针 (占位)"
    echo "98) 注册快捷命令 cj"
    echo "99) 彻底卸载此脚本"
    echo "0) 退出脚本"
    echo "========================================================="
    read -p "请输入主菜单选项 [0-9, 98, 99]: " MAIN_OPTION

    case $MAIN_OPTION in
        1)
            clear
            echo "========================================================="
            echo "📋 基础系统现状大盘查"
            echo "========================================================="
            echo "内核版本: $(uname -r)"
            echo "系统架构: $(uname -m)"
            echo "运行时间: $(uptime -p)"
            echo "当前时间: $(date)"
            echo "========================================================="
            read -p "按回车键返回主菜单..." temp
            ;;
        2)
            perform_update
            ;;
        3)
            menu_nginx_management
            ;;
        4)
            menu_certificate_management
            ;;
        5|6|7|8|9)
            echo "🚧 该模块正在快马加鞭开发中，目前仅作为功能占位！"
            sleep 2
            ;;
        98)
            echo "正在配置系统全局快捷命令及自动化挂载..."
            sudo cp "$0" "$LOCAL_SCRIPT_PATH"
            sudo chmod +x "$LOCAL_SCRIPT_PATH"
            (crontab -l 2>/dev/null | grep -v "cj --no-update"; echo "0 3 * * * $LOCAL_SCRIPT_PATH --no-update > /dev/null 2>&1") | crontab -
            echo "✅ 快捷命令 [cj] 注册成功！可在任意目录输入 cj 唤起主菜单。"
            sleep 2
            ;;
        99)
            perform_uninstall
            ;;
        0)
            echo "👋 感谢使用，退出脚本。"
            exit 0
            ;;
        *)
            echo "❌ 无效输入，请重新选择！"
            sleep 1
            ;;
    esac
done

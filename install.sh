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
KOMARI_DIR="/cj/dockercompose"
KOMARI_YML_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-compose-tools.yml"

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

# 20) 基础系统初始化运维专属菜单
menu_system_initialization() {
    while true; do
        clear
        echo -e "${C_BLUE}⚡ 基础系统初始化运维调控中心${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e "1) 常用核心开发运维工具检测与部署"
        echo -e "2) 交互式系统主机名安全合规改写"
        echo -e "3) 一键强行对齐至标准网络北京时间 (CST)"
        echo -e "0) 返回上一层菜单"
        echo -e "${LINE_GRAY}"
        read -p "请注入系统子项操作编号: " SYS_OPT

        if [ "$SYS_OPT" == "0" ] || [ -z "$SYS_OPT" ]; then
            break
        fi

        if [ "$SYS_OPT" == "1" ]; then
            while true; do
                clear
                echo -e "${C_BLUE}📦 常用运维工具环境看板${C_RESET}"
                echo -e "${LINE_GRAY}"
                
                # 定义工具阵列
                TOOLS_LIST=("sudo" "curl" "git" "tar" "wget" "unzip")
                TOOLS_STATUS=()
                
                # 动态探查上色逻辑
                for idx in "${!TOOLS_LIST[@]}"; do
                    T_NAME="${TOOLS_LIST[$idx]}"
                    if command -v "$T_NAME" &> /dev/null; then
                        TOOLS_STATUS[$idx]="INSTALLED"
                        echo -e " $((idx+1))) [${C_GREEN}已安装${C_RESET}] $T_NAME"
                    else
                        TOOLS_STATUS[$idx]="MISSING"
                        echo -e " $((idx+1))) [${C_YELLOW}未安装${C_RESET}] $T_NAME"
                    fi
                done
                
                echo -e "${LINE_GRAY}"
                echo -e "1) 启动全量工具包一件深度部署"
                echo -e "2) 自由指定工具编号个性化自由组装部署"
                echo -e "0) 返回系统管理上级菜单"
                echo -e "${LINE_GRAY}"
                read -p "请选部署模式: " INS_OPT
                
                if [ "$INS_OPT" == "0" ] || [ -z "$INS_OPT" ]; then
                    break
                fi
                
                if [ "$INS_OPT" == "1" ]; then
                    echo -e "${C_CYAN}⏳ 正在同步更新容器软件存储库并拉取全量依赖...${C_RESET}"
                    sudo apt-get update -y && sudo apt-get install -y sudo curl git tar wget unzip
                    echo -e "${C_GREEN}✅ 全量工具箱环境构筑洗礼完毕！${C_RESET}"
                    read -p "回车刷新状态..." temp
                elif [ "$INS_OPT" == "2" ]; then
                    read -p "请输入欲部署的工具编号 (多选用空格或逗号隔开，例: 2,3,6): " CHOOSE_NUMS
                    # 将逗号标准化转为空格
                    CHOOSE_NUMS=$(echo "$CHOOSE_NUMS" | tr ',' ' ')
                    INSTALL_TARGETS=""
                    
                    for num in $CHOOSE_NUMS; do
                        if [[ "$num" =~ ^[1-6]$ ]]; then
                            TARGET_NAME="${TOOLS_LIST[$((num-1))]}"
                            INSTALL_TARGETS="$INSTALL_TARGETS $TARGET_NAME"
                        fi
                    done
                    
                    if [ -n "$INSTALL_TARGETS" ]; then
                        echo -e "${C_CYAN}⏳ 正在按需装载以下指定工具组件: $INSTALL_TARGETS ...${C_RESET}"
                        sudo apt-get update -y && sudo apt-get install -y $INSTALL_TARGETS
                        echo -e "${C_GREEN}✅ 指定组件单元个性化部署完成。${C_RESET}"
                    else
                        echo -e "${C_GRAY}❌ 未检测到合规的数字编号，未执行任何改动。${C_RESET}"
                    fi
                    read -p "回车刷新状态..." temp
                fi
            done
        elif [ "$SYS_OPT" == "2" ]; then
            clear
            echo -e "${C_BLUE}🔧 交互式系统主机名安全合规改写${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "当前主机名称: $(hostname)"
            echo -e "${LINE_GRAY}"
            
            while true; do
                read -p "请输入您拟定设定的全新主机名 (必须输入): " NEW_HOSTNAME
                # 去除前后空格
                NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | xargs)
                
                if [ -z "$NEW_HOSTNAME" ]; then
                    echo -e "${C_GRAY}❌ 报错：主机名称绝对不允许为空，请重新判定！${C_RESET}"
                    continue
                fi
                
                # 遵循 FQDN 规则：只允许字母、数字、点和横杠，且不能以横杠或点开头结尾
                if [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] && [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9]$ ]]; then
                    echo -e "${C_GRAY}❌ 报错：主机名存在非法字符！只允许字母、数字、点号(.)和横杠(-)${C_RESET}"
                    continue
                fi
                break
            done
            
            echo -e "${C_CYAN}⏳ 正在物理锁死系统内核主机名并改写网络本地域名映射拓扑...${C_RESET}"
            sudo hostnamectl set-hostname "$NEW_HOSTNAME"
            
            # 安全删除旧的回路映射，防止污染冲突
            sudo sed -i "/127.0.0.1/s/\b$NEW_HOSTNAME\b//g" /etc/hosts
            sudo sed -i "/::1/s/\b$NEW_HOSTNAME\b//g" /etc/hosts
            
            # 追加纯净的基础映射绑定
            echo "127.0.0.1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
            echo "::1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
            
            echo -e "${C_GREEN}✅ 物理改写生效，以下为当前最新 /etc/hosts 局部拓扑截面：${C_RESET}"
            tail -n 5 /etc/hosts
            echo -e "${LINE_GRAY}"
            echo -e "${C_CYAN}👉 准备就绪。正在为您重置刷新当前宿主终端 Shell 视窗环境...${C_RESET}"
            sleep 2
            exec bash
        elif [ "$SYS_OPT" == "3" ]; then
            clear
            echo -e "${C_BLUE}⏳ 正在重构底层时间服务框架...${C_RESET}"
            echo -e "${LINE_GRAY}"
            
            # 强制设定时区为亚洲/上海
            sudo timedatectl set-timezone Asia/Shanghai
            
            # 智能判定体系架构保障组件
            if command -v apt-get &> /dev/null; then
                sudo apt-get update -y && sudo apt-get install -y systemd-timesyncd
                sudo timedatectl set-ntp true
                sudo systemctl restart systemd-timesyncd
            elif command -v yum &> /dev/null; then
                sudo yum install -y chrony
                sudo systemctl enable --now chronyd
                sudo chronyc sources -v
            fi
            
            echo -e "${C_CYAN}🔄 触发底层时钟网络校准同步锁...${C_RESET}"
            sleep 1.5
            echo -e "${C_GREEN}🎉 系统北京时间校准大功告成！当前最新时间参数：${C_RESET}"
            echo -e "${LINE_GRAY}"
            date
            echo -e "${LINE_GRAY}"
            read -p "回车返回上层菜单..." temp
        fi
    done
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
                echo -e "${C_CYAN}📋 宿主机有效 SSL 证书：${C_RESET}"
                if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
                    echo "  (⚠️ 未检测到有效证书)"
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
                [ $COUNT -eq 0 ] && echo "  (暂无配置)"
                echo -e "\n[ a ] 展现资产大盘  [ c ] 清扫无效代理"
                echo -e "${LINE_GRAY}"
                read -p "请输入证书序号或操作码 [0 返回]: " USER_CHOOSE

                if [ "$USER_CHOOSE" == "0" ] || [ -z "$USER_CHOOSE" ]; then break
                elif [ "$USER_CHOOSE" == "a" ] || [ "$USER_CHOOSE" == "A" ]; then
                    clear
                    echo "1) 查看指定域名专属反代"
                    echo "2) 展现全部分组域名资产"
                    read -p "请选子项: " SUB_A
                    if [ "$SUB_A" == "1" ]; then
                        for i in "${!VALID_DOMAINS[@]}"; do echo "  $((i+1))) ${VALID_DOMAINS[$i]}"; done
                        read -p "输入域名编号: " T_IDX
                        if [[ "$T_IDX" =~ ^[0-9]+$ ]] && [ "$T_IDX" -le "${#VALID_DOMAINS[@]}" ]; then
                            F_DOM="${VALID_DOMAINS[$((T_IDX-1))]}"
                            echo -e "🔎 [ $F_DOM ] 反代明细:"
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
                    read -p "回车继续..." temp; continue
                elif [ "$USER_CHOOSE" == "c" ] || [ "$USER_CHOOSE" == "C" ]; then
                    clear
                    echo "🔍 正在进行物理传输层探测..."
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
                                        echo -e "${C_GRAY}🚨 断连: $ED ──► $EP${C_RESET}"
                                        read -p "是否彻底切除该残效配置？[y/N]: " IS_DEL
                                        [ "$IS_DEL" == "y" ] || [ "$IS_DEL" == "Y" ] && sudo rm -f "$cf"
                                    fi
                                fi
                            fi
                        done
                    fi
                    sudo nginx -t &>/dev/null && sudo systemctl reload nginx &>/dev/null
                    read -p "清理结束。回车继续..." temp; continue
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
                
                # 改用标准 echo 构建反代配置文件，规避 cat << EOF
                sudo rm -f "$CONF_FILE_PATH"
                echo "server {" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    listen $CUSTOM_HTTP;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    listen [::]:$CUSTOM_HTTP;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    server_name $NG_DOMAIN;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    return 301 https://\$host:\$server_port\$request_uri;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "}" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "server {" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    listen $CUSTOM_HTTPS ssl;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    listen [::]:$CUSTOM_HTTPS ssl;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    server_name $NG_DOMAIN;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    ssl_certificate /etc/nginx/ssl/$ROOT_DOMAIN/$ROOT_DOMAIN.crt;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    ssl_certificate_key /etc/nginx/ssl/$ROOT_DOMAIN/$ROOT_DOMAIN.key;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    ssl_protocols TLSv1.2 TLSv1.3;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    ssl_ciphers HIGH:!aNULL:!MD5;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    ssl_prefer_server_ciphers on;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    location / {" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "        proxy_pass http://$LOCAL_PRIVATE_IP:$NG_PORT;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "        proxy_set_header Host \$host;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "        proxy_set_header X-Real-IP \$remote_addr;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "        proxy_set_header X-Forwarded-Proto \$scheme;" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "    }" | sudo tee -a "$CONF_FILE_PATH" > /dev/null
                echo "}" | sudo tee -a "$CONF_FILE_PATH" > /dev/null

                sudo nginx -t &>/dev/null
                if [ $? -eq 0 ]; then
                    sudo systemctl reload nginx &>/dev/null
                    if timeout 1.5 bash -c "</dev/tcp/${LOCAL_PRIVATE_IP}/${NG_PORT}" &>/dev/null; then
                        echo -e "${C_GREEN}🎉 配置成功！通路已打通。${C_RESET}"
                    else
                        if timeout 1.5 bash -c "</dev/tcp/127.0.0.1/${NG_PORT}" &>/dev/null; then
                            sed -i "s/$LOCAL_PRIVATE_IP:$NG_PORT/127.0.0.1:$NG_PORT/g" "$CONF_FILE_PATH"
                            sudo systemctl reload nginx &>/dev/null
                            echo -e "${C_GREEN}🎉 配置成功！已自动智能对齐至 127.0.0.1 环回口通路。${C_RESET}"
                        else
                            echo -e "${C_YELLOW}⚠️ 反代已留存，但检测到目标端口 $NG_PORT 当前闭合，请检查后端！${C_RESET}"
                        fi
                    fi
                else
                    echo -e "${C_GRAY}❌ Nginx 语法校验失败，请检查根证书完整度！${C_RESET}"
                    sudo rm -f "$CONF_FILE_PATH"
                fi
                read -p "回车继续..." temp
            done

        elif [ "$NG_OPTION" == "3" ]; then
            read -p "自定义 HTTP 端口 (直接回车默认80): " SET_HTTP
            read -p "自定义 HTTPS 端口 (直接回车默认443): " SET_HTTPS
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
            echo -e "${C_GREEN}✅ 端口改写应用成功！${C_RESET}"; sleep 1

        elif [ "$NG_OPTION" == "4" ]; then
            clear
            echo -e "${C_BLUE}⚡ Nginx 服务进程调控中心${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 启动服务                👉 (systemctl start nginx)"
            echo -e "2) 注册开机自启 (自动从启)      👉 (systemctl enable nginx)"
            echo -e "3) 强力重新启动                 👉 (systemctl restart nginx)"
            echo -e "4) 停止当前服务               👉 (systemctl stop nginx)"
            echo -e "0) 返回上一层"
            echo -e "${LINE_GRAY}"
            read -p "请选择控制指令: " SVC_OPT
            if [ "$SVC_OPT" == "1" ]; then
                sudo nginx -t &>/dev/null && sudo systemctl start nginx && echo "✅ 启动成功"
            elif [ "$SVC_OPT" == "2" ]; then
                sudo systemctl enable nginx &>/dev/null && echo "✅ 已注册全局系统开机自启进程！"
            elif [ "$SVC_OPT" == "3" ]; then
                sudo nginx -t &>/dev/null && (sudo systemctl restart nginx 2>/dev/null || sudo systemctl start nginx) && echo "✅ 重启成功"
            elif [ "$SVC_OPT" == "4" ]; then
                sudo systemctl stop nginx && echo "✅ 服务已关停"
            fi
            sleep 1.2

        elif [ "$NG_OPTION" == "6" ]; then
            clear
            echo -e "${C_BLUE}⚡ Nginx 高性能核心优化预设${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 低延迟预设"
            echo -e "2) 高并发预设"
            echo -e "3) 均衡稳定预设"
            echo -e "${LINE_GRAY}"
            read -p "请注入调优编号: " OPT_TYPE
            
            if [ -f "/etc/nginx/nginx.conf" ] && ! grep -q "limit_conn_zone" /etc/nginx/nginx.conf; then
                sudo sed -i '/http {/a \    limit_conn_zone $binary_remote_addr zone=addr:10m;\n    limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;\n    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=cj_cache:10m max_size=1g inactive=60m use_temp_path=off;' /etc/nginx/nginx.conf
                sudo mkdir -p /var/cache/nginx
            fi

            if [ "$OPT_TYPE" == "1" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 2048;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 低延迟优化应用。"; sleep 1
            elif [ "$OPT_TYPE" == "2" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 65535;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 高并发调优应用。"; sleep 1
            elif [ "$OPT_TYPE" == "3" ]; then
                sudo sed -i -E 's/worker_connections [0-9]+;/worker_connections 4096;/g' /etc/nginx/nginx.conf 2>/dev/null
                echo "✅ 均衡稳定调优应用。"; sleep 1
            fi
            sudo nginx -t && sudo systemctl reload nginx 2>/dev/null

        elif [ "$NG_OPTION" == "7" ]; then
            if ! command -v nano &> /dev/null; then
                echo "📦 正在自动配置 nano 编辑器..."
                if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y nano
                elif command -v yum &> /dev/null; then sudo yum install -y nano; fi
            fi
            while true; do
                clear
                echo -e "${C_CYAN}📋 请点选您要使用 nano 视窗改写的配置文件：${C_RESET}"
                echo -e "${LINE_GRAY}"
                echo "1) [主核心配置] /etc/nginx/nginx.conf"
                CONF_LIST=()
                if [ -d "/etc/nginx/conf.d" ]; then
                    for f in /etc/nginx/conf.d/*.conf; do [ -f "$f" ] && CONF_LIST+=("$f"); done
                fi
                for idx in "${!CONF_LIST[@]}"; do
                    echo "$((idx+2))) [反代子配置] $(basename "${CONF_LIST[$idx]}")"
                done
                echo -e "${LINE_GRAY}"
                read -p "请输入序号 [0 返回]: " NANO_CHOOSE
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

# 网络调优模块
menu_network_tuning() {
    clear
    echo -e "${C_BLUE}⚡ Linux 核心级网络性能调控矩阵${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "1) 常规 Web 服务器 TCP 综合深度优化"
    echo -e "2) 代理专属极速优化 (低延迟 / 宽吞吐拓扑优化)"
    echo -e "0) 返回上一层"
    echo -e "${LINE_GRAY}"
    read -p "选择调优模式: " NET_OPT

    if [ "$NET_OPT" == "1" ]; then
        echo "⏳ 正在重构底层内核 Web 缓冲栈参数..."
        sudo sysctl -w net.core.somaxconn=1024 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_max_syn_backlog=2048 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_keepalive_time=1200 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_keepalive_intvl=30 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" 2>/dev/null
        sudo sysctl -p 2>/dev/null
        echo -e "${C_GREEN}✅ Web TCP 综合吞吐调优完成。${C_RESET}"; sleep 1.5
    elif [ "$NET_OPT" == "2" ]; then
        echo "⏳ 正在注入网络代理专用低延宽带核心锁..."
        sudo sysctl -w net.core.netdev_max_backlog=65535 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_notsent_lowat=16384 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_no_metrics_save=1 2>/dev/null
        sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
        sudo sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null
        sudo sysctl -w net.core.rmem_max=67108864 2>/dev/null
        sudo sysctl -w net.core.wmem_max=67108864 2>/dev/null
        sudo ip link set lo txqueuelen 10000 2>/dev/null
        sudo sysctl -p 2>/dev/null
        echo -e "${C_GREEN}✅ 代理网络低延迟专属优化完毕！${C_RESET}"; sleep 1.5
    fi
}

# Komari 探针自动化模块
menu_komari_probe() {
    while true; do
        clear
        echo -e "${C_BLUE}⚡ Komari 自动化服务监控面板${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e "1) 一键拉取部署安装"
        echo -e "2) 热拉取最新镜像更新"
        echo -e "3) 阻断并彻底卸载服务"
        echo -e "4) 独立安全归类备份配置文件及项目资产"
        echo -e "0) 返回上一层"
        echo -e "${LINE_GRAY}"
        read -p "选择探针控制令: " KO_OPT

        if [ "$KO_OPT" == "0" ] || [ -z "$KO_OPT" ]; then break; fi

        if [ "$KO_OPT" == "1" ]; then
            echo "⏳ 正在初始化基础物理拓扑目录..."
            sudo mkdir -p "$KOMARI_DIR/data"
            echo "⏳ 正在同步拉取云端工具库模块..."
            curl -s -L "$KOMARI_YML_URL" > "$KOMARI_DIR/docker-compose-tools.yml"
            
            if [ ! -s "$KOMARI_DIR/docker-compose-tools.yml" ]; then
                echo "❌ 错误：拉取核心模块失败，请检查网络通路！"; sleep 2; continue
            fi

            read -p "🔑 请设置系统管理员初始用户名: " KO_USER
            read -p "🔑 请设置系统管理员初始密码: " KO_PASS
            [ -z "$KO_USER" ] && KO_USER="admin"
            [ -z "$KO_PASS" ] && KO_PASS="komari_secure_pwd"

            sed -i "s/ADMIN_USERNAME=.*/ADMIN_USERNAME=$KO_USER/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$KO_PASS/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s|-\s\./komari:|- ./data:|g" "$KOMARI_DIR/docker-compose-tools.yml"

            echo "🚀 正在拉起编排多路容器群生态..."
            docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
            echo -e "${C_GREEN}🎉 安装部署全部完成！${C_RESET}"; sleep 1.5

        elif [ "$KO_OPT" == "2" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo "⏳ 正在通过容器名 komari 热追踪拉取最新镜像流..."
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" pull
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
                echo -e "${C_GREEN}✅ 探针群落热升级刷新完成。${C_RESET}"
            else
                echo "❌ 错误：未在系统内检索到名为 komari 的活跃容器，请先安装！"
            fi
            sleep 1.5

        elif [ "$KO_OPT" == "3" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo "🚨 正在彻底摧毁并注销该探针服务生态..."
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" down -v
                sudo rm -f "$KOMARI_DIR/docker-compose-tools.yml"
                echo -e "${C_GREEN}✅ 服务彻底清除销毁。${C_RESET}"
            else
                echo "❌ 系统内未发现运行中的 komari 监控实例。"
            fi
            sleep 1.5

        elif [ "$KO_OPT" == "4" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo -e "${C_YELLOW}⚠️  安全隐患提示：明文密码备份到本地归档文件中可能存在安全泄露风险。${C_RESET}"
                read -p "❓ 是否确认将当前管理员账号和密码写入备份归档？(回车默认不备份) [y/N]: " IS_PWD_BAK
                [ -z "$IS_PWD_BAK" ] && IS_PWD_BAK="n"

                echo "⏳ 正在通过容器名匹配进行物理集群资产冷备份..."
                BACKUP_TAR="/cj/temp/komari_bak_$(date +%Y%m%d%H%M%S).tar.gz"
                sudo mkdir -p /cj/temp
                
                TMP_BAK_DIR="/tmp/komari_bak_dir"
                sudo rm -rf "$TMP_BAK_DIR" && mkdir -p "$TMP_BAK_DIR"
                
                if [ "$IS_PWD_BAK" == "y" ] || [ "$IS_PWD_BAK" == "Y" ]; then
                    EXT_USER=$(grep "ADMIN_USERNAME=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    EXT_PASS=$(grep "ADMIN_PASSWORD=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    echo -e "【Komari 凭证备份】\n用户名: $EXT_USER\n密码: $EXT_PASS" > "$TMP_BAK_DIR/credentials.txt"
                fi

                cp "$KOMARI_DIR/docker-compose-tools.yml" "$TMP_BAK_DIR/"
                cp -r "$KOMARI_DIR/data" "$TMP_BAK_DIR/" 2>/dev/null

                tar -czf "$BACKUP_TAR" -C "$TMP_BAK_DIR" . 2>/dev/null
                sudo rm -rf "$TMP_BAK_DIR"

                echo -e "${C_GREEN}🎉 备份完全成功！${C_RESET}"
                echo -e "📦 物理打包压缩资产锁留存绝对路径:\n👉 ${C_CYAN}$BACKUP_TAR${C_RESET}"
            else
                echo "❌ 无法执行备份：系统底层未通过容器名检索到活跃的 komari 项目结构。"
            fi
            read -p "回车继续..." temp
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
    echo -e "6) Network 内核吞吐优化 ${C_YELLOW}⭐${C_RESET}"
    echo -e "7) 一键分布式轻量 SB (占位)"
    echo -e "8) Docker 全栈容器管理 (占位)"
    echo -e "9) Komari 服务可用性探针 ${C_YELLOW}⭐${C_RESET}"
    echo -e "20) 基础系统初始化运维 ${C_YELLOW}⭐${C_RESET}"
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
            read -p "按回车返回主菜单..." temp
            ;;
        2) perform_update ;;
        3) menu_nginx_management ;;
        4) menu_certificate_management ;;
        6) menu_network_tuning ;;
        9) menu_komari_probe ;;
        20) menu_system_initialization ;;
        5|7|8) echo "🚧 功能占位开发中..."; sleep 1.5 ;;
        98)
            sudo cp "$0" "$LOCAL_SCRIPT_PATH"
            sudo chmod +x "$LOCAL_SCRIPT_PATH"
            (crontab -l 2>/dev/null | grep -v "cj --no-update"; echo "0 3 * * * $LOCAL_SCRIPT_PATH --no-update > /dev/null 2>&1") | crontab -
            echo -e "${C_GREEN}✅ [cj] 命令注册成功，可在任意目录直接输入 cj 唤醒！${C_RESET}"; sleep 1.5
            ;;
        99) perform_uninstall ;;
        0) echo "👋 感谢使用。"; exit 0 ;;
        *) echo "❌ 无效编号"; sleep 1 ;;
    esac
done

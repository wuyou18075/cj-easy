#!/bin/bash

# 全局颜色常量
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"
LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

# ================= 知识库大拆解：分门别类 =================

# 1. UFW 专属命令集
CMDS_UFW=(
    "ufw status # 查看 UFW 防火墙简易状态"
    "ufw status verbose # 查看 UFW 防火墙详细运行状态"
    "ufw status numbered # 查看所有规则并显示编号，方便删除"
    "ufw enable # 开启 UFW 防火墙"
    "ufw disable # 关闭 UFW 防火墙"
    "ufw reload # 重新加载 UFW 配置，不中断现有连接"
    "ufw default deny incoming # 设置默认拒绝所有入站连接"
    "ufw default allow outgoing # 设置默认允许所有出站连接"
    "ufw allow 80/tcp # 允许 80 端口的 TCP 流量"
    "ufw deny 3306 # 阻止对 MySQL 默认端口 3306 的访问"
    "ufw delete allow 80/tcp # 删除允许 80 端口入站的规则"
    "ufw delete 3 # 删除 'ufw status numbered' 中显示的第3条规则"
    "ufw allow from 192.168.1.100 # 允许特定 IP 地址的所有流量"
    "ufw deny from 10.0.0.5 # 拒绝来自特定 IP 地址的所有流量"
    "ufw allow from 192.168.1.0/24 # 允许特定网段内的所有机器访问"
    "ufw limit 22/tcp # 开启 22 端口限流保护，防止暴力破解"
    "ufw reset # 强力重置 UFW，清除所有自定义规则（需谨慎）"
)

# 2. Firewalld 专属命令集
CMDS_FWD=(
    "firewall-cmd --state # 查看 firewalld 的运行状态"
    "firewall-cmd --list-all # 查看 firewalld 的放行白名单总览"
    "firewall-cmd --list-ports # 仅查看当前放行的独立端口"
    "firewall-cmd --get-active-zones # 查看当前绑定的活跃区域"
    "firewall-cmd --zone=public --add-port=80/tcp --permanent # 永久放行 80 端口"
    "firewall-cmd --zone=public --remove-port=80/tcp --permanent # 永久移除 80 端口"
    "firewall-cmd --zone=trusted --add-source=192.168.1.100 --permanent # 永久添加 IP 白名单"
    "firewall-cmd --reload # 重新载入 firewalld 使新规则生效"
    "systemctl status firewalld # 查看服务守护进程状态"
    "firewall-cmd --panic-on # 【危险】瞬间切断机器的所有网络连接"
    "firewall-cmd --panic-off # 恢复被 panic-on 切断的网络连通性"
)

# 3. iptables/nftables 专属硬核命令集
CMDS_IPT=(
    "iptables -L -n -v # 查看底层内核的 iptables 详细过滤规则"
    "iptables -F # 清空当前内核中 iptables 的所有过滤规则"
    "iptables -P INPUT DROP # 【危险】设置默认丢弃所有入站包"
    "iptables -P FORWARD DROP # 默认丢弃所有过境转发数据包"
    "iptables -A INPUT -p tcp --dport 80 -j ACCEPT # 放行 80 端口"
    "iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT # 插入放行 22 为第一优先级"
    "iptables -D INPUT 1 # 删除 INPUT 链的第一条规则"
    "iptables -A INPUT -s 192.168.1.100 -j ACCEPT # 允许指定 IP 访问"
    "iptables-save > /etc/iptables.rules # 将内存中的规则持久化导出到文件"
    "iptables-restore < /etc/iptables.rules # 从文件中恢复底层防火墙规则"
    "nft list ruleset # 查看最新的 nftables 内核规则集"
    "nft add table inet filter # 针对 nftables 添加一个过滤表"
)

# 4. 全局通用网络排障指令集 (随时挂载)
CMDS_NET=(
    "ss -tulnp # 查看当前系统所有正在监听的 TCP/UDP 端口"
    "ss -s # 统计当前系统的网络连接总览（Time-wait, Estab等）"
    "netstat -anp | grep 80 # 查看 80 端口是否被占用 (需 net-tools)"
    "lsof -i :8080 # 反查出占用 8080 端口的具体进程和 PID"
    "ip route show # 显示系统内核的路由表条目"
    "ip addr show # 查看系统所有网卡设备的 IP 及 MAC 信息"
    "ip link set eth0 up # 将指定的网卡接口状态设为启动"
    "ping -c 4 8.8.8.8 # 向目标 IP 发送 4 个 ICMP 探测包测试连通性"
    "traceroute google.com # 路由追踪，查看包到达目标经过的节点"
    "mtr 1.1.1.1 # 动态路由连通性及丢包率综合诊断工具"
    "curl -I https://www.google.com # 探测目标网站，仅获取其 HTTP Header 响应头"
    "wget -qO- ifconfig.me # 快速查询并回显当前主机的公网出口 IP"
    "telnet 127.0.0.1 3306 # 测试本地的 3306 端口是否处于通讯监听状态"
    "nmap -sT -O localhost # 扫描本机开放的 TCP 端口并探测操作系统"
    "tcpdump -i any port 80 # 监听任何网卡上 80 端口的通信数据包"
    "tcpdump -i eth0 icmp # 专门抓取经由 eth0 网卡的所有 Ping (ICMP) 流量"
)

# ================= 核心探针与调度模块 =================

# 探针：获取当前防火墙类型
get_current_engine() {
    if command -v ufw &> /dev/null && systemctl is-active --quiet ufw; then
        CURRENT_FW="ufw"; FW_NAME="UFW (Uncomplicated Firewall)"; FW_STATUS="${C_GREEN}已开启 (Active)${C_RESET}"
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        CURRENT_FW="firewalld"; FW_NAME="firewalld (CentOS系高级路由)"; FW_STATUS="${C_GREEN}已开启 (Active)${C_RESET}"
    else
        if command -v ufw &> /dev/null; then
            CURRENT_FW="ufw"; FW_NAME="UFW (Uncomplicated Firewall)"; FW_STATUS="${C_GRAY}已关闭 (Inactive)${C_RESET}"
        elif command -v firewall-cmd &> /dev/null; then
            CURRENT_FW="firewalld"; FW_NAME="firewalld (CentOS系高级路由)"; FW_STATUS="${C_GRAY}已关闭 (Inactive)${C_RESET}"
        else
            CURRENT_FW="iptables"; FW_NAME="iptables (复杂底层规则)"; FW_STATUS="${C_YELLOW}未接管 (原生内核裸奔)${C_RESET}"
        fi
    fi
}

get_ssh_port() {
    SSH_PORT=$(ss -tlpn 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F':' '{print $NF}' | sort -nu | head -n 1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
}

# 跨引擎 SSH 防失联保护
enforce_ssh_safe() {
    get_ssh_port
    if [ "$CURRENT_FW" == "ufw" ]; then
        sudo ufw allow $SSH_PORT/tcp >/dev/null 2>&1
    elif [ "$CURRENT_FW" == "firewalld" ]; then
        sudo firewall-cmd --add-port=$SSH_PORT/tcp --permanent >/dev/null 2>&1
        sudo firewall-cmd --reload >/dev/null 2>&1
    elif [ "$CURRENT_FW" == "iptables" ]; then
        sudo iptables -C INPUT -p tcp --dport $SSH_PORT -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -p tcp --dport $SSH_PORT -j ACCEPT
    fi
}

# 智能学习模块：刷新缓存
refresh_learning_cache() {
    local COMBINED_CMDS=()
    if [ "$CURRENT_FW" == "ufw" ]; then COMBINED_CMDS=("${CMDS_UFW[@]}" "${CMDS_NET[@]}")
    elif [ "$CURRENT_FW" == "firewalld" ]; then COMBINED_CMDS=("${CMDS_FWD[@]}" "${CMDS_NET[@]}")
    elif [ "$CURRENT_FW" == "iptables" ]; then COMBINED_CMDS=("${CMDS_IPT[@]}" "${CMDS_NET[@]}")
    else COMBINED_CMDS=("${CMDS_NET[@]}"); fi

    if command -v shuf &> /dev/null; then
        LEARNING_CACHE=$(printf "%s\n" "${COMBINED_CMDS[@]}" | shuf | head -n 10 | sed 's/^/  👉 /')
    else
        LEARNING_CACHE=$(printf "%s\n" "${COMBINED_CMDS[@]}" | head -n 10 | sed 's/^/  👉 /')
    fi
}

# 环境依赖监测 (首次无防火墙时自动装UFW)
if ! command -v ufw &> /dev/null && ! command -v firewall-cmd &> /dev/null; then
    echo -e "${C_CYAN}⏳ 正在为系统部署安全防火墙默认引擎 (UFW)...${C_RESET}"
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install ufw -y >/dev/null 2>&1
fi

# 初始化
get_current_engine
refresh_learning_cache

# 主菜单循环
while true; do
    get_current_engine
    get_ssh_port
    
    # 探针检测当前 SSH 是否被墙
    SSH_SAFE="yes"
    if [[ "$FW_STATUS" == *"已开启"* ]]; then
        if [ "$CURRENT_FW" == "ufw" ]; then
            sudo ufw status | grep -E -q "^$SSH_PORT(/tcp)? +ALLOW " || SSH_SAFE="no"
        elif [ "$CURRENT_FW" == "firewalld" ]; then
            sudo firewall-cmd --list-ports | grep -q "$SSH_PORT" || SSH_SAFE="no"
        fi
    fi
    
    if [ "$SSH_SAFE" == "yes" ]; then
        if [[ "$FW_STATUS" == *"已关闭"* ]] || [[ "$FW_STATUS" == *"未接管"* ]]; then
            SSH_STATUS_TEXT="${C_YELLOW}未设防 (防火墙关闭中)${C_RESET}"
        else
            SSH_STATUS_TEXT="${C_GREEN}安全开放中${C_RESET}"
        fi
    else
        SSH_STATUS_TEXT="${C_RED}极度危险: 未开放! (失联预警)${C_RESET}"
    fi

    clear
    echo -e "${C_BLUE}⚡ 网络防火墙安全调度中心${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e " 🛡️ 防火墙引擎: $FW_NAME"
    echo -e " 🚥 当前状况: $FW_STATUS"
    echo -e " 🔑 SSH 使用端口: ${C_CYAN}$SSH_PORT${C_RESET}  状态: $SSH_STATUS_TEXT"
    echo -e "${LINE_GRAY}"
    
    # 防失联自动阻断器
    if [ "$SSH_SAFE" == "no" ]; then
        echo -e "${C_RED}🚨 严重警告: 当前防火墙未放行您的 SSH 端口 ($SSH_PORT)，退出即失联！${C_RESET}"
        read -p "❓ 是否立即为您打通生命通道？[Y/n] (回车默认Y): " FIX_SSH
        if [[ -z "$FIX_SSH" || "$FIX_SSH" =~ ^[Yy]$ ]]; then
            enforce_ssh_safe
            echo -e "${C_GREEN}✅ SSH 端口防失联指令注入成功！${C_RESET}"; sleep 1; continue
        fi
    fi

    echo -e "1) 开启防火墙"
    echo -e "2) 关闭防火墙"
    echo -e "3) 开放端口 ${C_GRAY}(3种高级过滤模式)${C_RESET}"
    echo -e "4) 关闭端口 ${C_GRAY}(单点及批量阻断)${C_RESET}"
    echo -e "5) 查看已开放端口"
    echo -e "6) 查看端口占用情况"
    echo -e "7) 清除防火墙规则 ${C_YELLOW}⭐${C_RESET}"
    echo -e "8) 切换核心防火墙引擎 ${C_YELLOW}⭐${C_RESET}"
    echo -e "10) 暴力卸载当前防火墙"
    echo -e "98) 刷新当前学习命令 🔄"
    echo -e "99) 查看全部防火墙与网络命令集 📚"
    echo -e "0) 返回上一层"
    echo -e "${LINE_GRAY}"
    
    echo -e "📚 【命令学习群 - 当前应用专供版】:"
    echo -e "$LEARNING_CACHE"
    echo -e "${LINE_GRAY}"

    read -p "请注入操作编号: " FW_OPT

    case $FW_OPT in
        1)
            enforce_ssh_safe
            if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw --force enable
            elif [ "$CURRENT_FW" == "firewalld" ]; then sudo systemctl start firewalld && sudo systemctl enable firewalld
            fi
            echo -e "${C_GREEN}✅ 盾牌升起，防火墙已接管底层路由！${C_RESET}"; sleep 1.5
            ;;
        2)
            enforce_ssh_safe
            if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw disable
            elif [ "$CURRENT_FW" == "firewalld" ]; then sudo systemctl stop firewalld
            fi
            echo -e "${C_GRAY}✅ 防线已撤除，系统处于不设防裸露状态。${C_RESET}"; sleep 1.5
            ;;
        3)
            enforce_ssh_safe
            clear
            echo -e "${C_BLUE}🔑 端口放行高阶策略模块 (基于 $CURRENT_FW)${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) 模式一: 基础单/多端口放行"
            echo -e "   👉 例如: 80 或 80,443"
            echo -e "   💻 实际执行: ${C_CYAN}ufw allow [端口]${C_RESET} 或 ${C_CYAN}firewall-cmd --add-port=[端口]/tcp${C_RESET}"
            echo -e "2) 模式二: 连续范围区间放行"
            echo -e "   👉 例如: 8000:9000 (代表8000到9000全开)"
            echo -e "   💻 实际执行: ${C_CYAN}ufw allow [起始:结束]/tcp${C_RESET}"
            echo -e "3) 模式三: 指定 IP 或网段白名单放行"
            echo -e "   👉 例如: 192.168.1.100 或 10.0.0.0/24"
            echo -e "   💻 实际执行: ${C_CYAN}ufw allow from [目标IP]${C_RESET}"
            echo -e "${LINE_GRAY}"
            read -p "请选择放行模式 [1-3]: " ALLOW_MODE
            
            if [ "$ALLOW_MODE" == "1" ]; then
                read -p "✏️ 请输入拟开放端口 (多端口用英文逗号分隔): " OP_PORTS
                OP_PORTS=$(echo "$OP_PORTS" | tr ',' ' ')
                for p in $OP_PORTS; do
                    if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw allow $p >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "firewalld" ]; then sudo firewall-cmd --add-port=$p/tcp --permanent >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "iptables" ]; then sudo iptables -I INPUT -p tcp --dport $p -j ACCEPT
                    fi
                    echo -e "  🟢 目标点位 $p 贯通"
                done
            elif [ "$ALLOW_MODE" == "2" ]; then
                read -p "✏️ 请输入拟开放范围 (格式 端口:端口): " RANGE_PORT
                if [[ "$RANGE_PORT" == *":"* ]]; then
                    if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw allow $RANGE_PORT/tcp >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "firewalld" ]; then
                        FW_RANGE=$(echo "$RANGE_PORT" | tr ':' '-')
                        sudo firewall-cmd --add-port=$FW_RANGE/tcp --permanent >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "iptables" ]; then sudo iptables -I INPUT -p tcp --dport $RANGE_PORT -j ACCEPT
                    fi
                    echo -e "  🟢 区间集群 $RANGE_PORT 贯通"
                else
                    echo -e "${C_GRAY}❌ 格式错误，请严格使用冒号。${C_RESET}"
                fi
            elif [ "$ALLOW_MODE" == "3" ]; then
                read -p "✏️ 请输入白名单安全源 IP 或 完整网段: " SAFE_IP
                if [ -n "$SAFE_IP" ]; then
                    if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw allow from $SAFE_IP >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "firewalld" ]; then sudo firewall-cmd --add-source=$SAFE_IP --zone=trusted --permanent >/dev/null 2>&1
                    elif [ "$CURRENT_FW" == "iptables" ]; then sudo iptables -I INPUT -s $SAFE_IP -j ACCEPT
                    fi
                    echo -e "  🟢 源安全白名单 $SAFE_IP 已注网"
                fi
            fi
            
            if [ "$CURRENT_FW" == "firewalld" ]; then sudo firewall-cmd --reload >/dev/null 2>&1; fi
            echo -e "${C_GREEN}✅ 放行逻辑部署成功。${C_RESET}"; sleep 1.5
            ;;
        4)
            enforce_ssh_safe
            read -p "请输入您要物理阻断的端口 (多端口逗号分隔): " DEL_PORTS
            if [ -n "$DEL_PORTS" ]; then
                DEL_PORTS=$(echo "$DEL_PORTS" | tr ',' ' ')
                for p in $DEL_PORTS; do
                    if [ "$p" == "$SSH_PORT" ]; then
                        echo -e "  ${C_RED}❌ 警告: 试图切断生命级 SSH 端口 $p，系统已物理回绝！${C_RESET}"
                    else
                        if [ "$CURRENT_FW" == "ufw" ]; then
                            sudo ufw delete allow $p >/dev/null 2>&1
                            sudo ufw delete allow $p/tcp >/dev/null 2>&1
                            sudo ufw deny $p >/dev/null 2>&1
                        elif [ "$CURRENT_FW" == "firewalld" ]; then
                            sudo firewall-cmd --remove-port=$p/tcp --permanent >/dev/null 2>&1
                        elif [ "$CURRENT_FW" == "iptables" ]; then
                            sudo iptables -D INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null
                        fi
                        echo -e "  🔴 目标点位 $p 已物理闭合"
                    fi
                done
                if [ "$CURRENT_FW" == "firewalld" ]; then sudo firewall-cmd --reload >/dev/null 2>&1; fi
                echo -e "${C_GREEN}✅ 阻断逻辑执行完毕。${C_RESET}"
            fi
            sleep 1.5
            ;;
        5)
            enforce_ssh_safe
            clear
            echo -e "${C_BLUE}📋 当前系统防火墙物理穿透大盘: ${C_RESET}"
            echo -e "${LINE_GRAY}"
            if [ "$CURRENT_FW" == "ufw" ]; then sudo ufw status verbose
            elif [ "$CURRENT_FW" == "firewalld" ]; then sudo firewall-cmd --list-all
            elif [ "$CURRENT_FW" == "iptables" ]; then sudo iptables -L INPUT -n -v
            fi
            echo -e "${LINE_GRAY}"
            read -p "按回车键返回..." temp
            ;;
        6)
            clear
            echo -e "${C_CYAN}📋 宿主机网络层监听链路追踪大盘: ${C_RESET}"
            echo -e "${LINE_GRAY}"
            sudo ss -tulnp
            echo -e "${LINE_GRAY}"
            read -p "按回车键返回..." temp
            ;;
        7)
            clear
            echo -e "${C_BLUE}🗑️ 防火墙规则定向清理阵列${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "${C_RED} 9999) 🚨 【高危】彻底核平并抹除所有规则 (将自动保留 SSH)${C_RESET}"
            echo -e "${LINE_GRAY}"
            
            if [ "$CURRENT_FW" == "ufw" ]; then
                sudo ufw status numbered
                read -p "注入拟删除的序列号 (或输入 9999 全清): " D_NUM
                if [ "$D_NUM" == "9999" ]; then
                    sudo ufw --force reset
                    enforce_ssh_safe
                    sudo ufw --force enable >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 已物理核平 UFW 并重铸 SSH 护盾。${C_RESET}"
                elif [[ "$D_NUM" =~ ^[0-9]+$ ]]; then
                    sudo ufw --force delete $D_NUM
                    echo -e "${C_GREEN}✅ 编号 $D_NUM 靶点已被摘除。${C_RESET}"
                fi
            elif [ "$CURRENT_FW" == "iptables" ]; then
                sudo iptables -nL INPUT --line-numbers
                read -p "注入拟删除的链路序列号 (或输入 9999 全清): " D_NUM
                if [ "$D_NUM" == "9999" ]; then
                    sudo iptables -F
                    enforce_ssh_safe
                    echo -e "${C_GREEN}✅ iptables 内存栈已全部出栈并清洗。${C_RESET}"
                elif [[ "$D_NUM" =~ ^[0-9]+$ ]]; then
                    sudo iptables -D INPUT $D_NUM
                    echo -e "${C_GREEN}✅ 底层节点 $D_NUM 已抽离。${C_RESET}"
                fi
            elif [ "$CURRENT_FW" == "firewalld" ]; then
                echo -e "⚠️ Firewalld 不支持直观的序号删除模式。"
                echo -e "请使用主菜单的 ${C_YELLOW}选项 4${C_RESET} 输入具体端口进行关闭。"
                read -p "如果输入 9999 将切断所有额外端口。注入口令: " D_NUM
                if [ "$D_NUM" == "9999" ]; then
                    sudo systemctl restart firewalld
                    sudo firewall-cmd --zone=public --remove-forward-port=all --permanent >/dev/null 2>&1
                    enforce_ssh_safe
                    echo -e "${C_GREEN}✅ 已重启 Firewalld 并尽量回归初始栈。${C_RESET}"
                fi
            fi
            sleep 1.5
            ;;
        8)
            clear
            echo -e "${C_BLUE}⚙️ 核心防火墙引擎切换台${C_RESET}"
            echo -e "${LINE_GRAY}"
            echo -e "1) iptables (复杂底层规则) ⭐"
            echo -e "2) firewalld (CentOS系高级路由) ⭐⭐"
            echo -e "3) UFW (Debian/Ubuntu系, 简单推荐) ⭐⭐⭐"
            echo -e "${LINE_GRAY}"
            read -p "请选择拟装备的核心引擎 [1-3]: " ENGINE_OPT
            
            echo -e "⏳ 正在阻断旧引擎链路并拉取新装甲库..."
            if command -v apt-get &> /dev/null; then PKG_MGR="apt-get"; else PKG_MGR="yum"; fi
            
            if [ "$ENGINE_OPT" == "1" ]; then
                sudo systemctl stop ufw 2>/dev/null; sudo systemctl disable ufw 2>/dev/null
                sudo systemctl stop firewalld 2>/dev/null; sudo systemctl disable firewalld 2>/dev/null
                sudo $PKG_MGR install -y iptables iptables-persistent >/dev/null 2>&1
                echo -e "${C_GREEN}✅ 底层引擎已切换至无干预原生 iptables。${C_RESET}"
            elif [ "$ENGINE_OPT" == "2" ]; then
                sudo systemctl stop ufw 2>/dev/null; sudo systemctl disable ufw 2>/dev/null
                sudo $PKG_MGR install -y firewalld >/dev/null 2>&1
                sudo systemctl enable firewalld >/dev/null 2>&1
                sudo systemctl start firewalld >/dev/null 2>&1
                echo -e "${C_GREEN}✅ Firewalld 高级路由群已接管系统网桥。${C_RESET}"
            elif [ "$ENGINE_OPT" == "3" ]; then
                sudo systemctl stop firewalld 2>/dev/null; sudo systemctl disable firewalld 2>/dev/null
                sudo $PKG_MGR update -y >/dev/null 2>&1; sudo $PKG_MGR install -y ufw >/dev/null 2>&1
                sudo ufw --force enable >/dev/null 2>&1
                echo -e "${C_GREEN}✅ UFW 主流护盾已装填并生效部署。${C_RESET}"
            else
                echo -e "${C_GRAY}❌ 丢弃操作: 未知引擎型号。${C_RESET}"
            fi
            
            # 切换完成后，重新探针防失联并刷新学习库
            get_current_engine
            enforce_ssh_safe
            refresh_learning_cache
            sleep 1.5
            ;;
        10)
            echo -e "${C_RED}🚨 警告: 这将从系统层拔除当前的防火墙组件！${C_RESET}"
            read -p "您确认要执行拔除动作吗？[y/N]: " IS_UNINSTALL
            if [[ "$IS_UNINSTALL" =~ ^[Yy]$ ]]; then
                if command -v apt-get &> /dev/null; then PKG_MGR="apt-get purge"; else PKG_MGR="yum remove"; fi
                
                if [ "$CURRENT_FW" == "ufw" ]; then
                    sudo ufw disable
                    sudo $PKG_MGR -y ufw >/dev/null 2>&1
                elif [ "$CURRENT_FW" == "firewalld" ]; then
                    sudo systemctl stop firewalld
                    sudo $PKG_MGR -y firewalld >/dev/null 2>&1
                fi
                echo -e "${C_GREEN}✅ 当前防火墙已被物理拆卸离线。${C_RESET}"
                get_current_engine
                refresh_learning_cache
            fi
            sleep 1.5
            ;;
        98)
            refresh_learning_cache
            echo -e "${C_GREEN}✅ 学习群已通过源引擎洗牌刷新！${C_RESET}"
            sleep 0.8
            ;;
        99)
            clear
            echo -e "${C_BLUE}📚 全网防火墙与网络底层硬核指令词典${C_RESET}"
            echo -e "${LINE_GRAY}"
            
            echo -e "${C_CYAN}【 UFW 专属指令 】${C_RESET}"
            for cmd in "${CMDS_UFW[@]}"; do echo -e "  👉 $cmd"; done
            echo -e "\n${C_CYAN}【 Firewalld 专属指令 】${C_RESET}"
            for cmd in "${CMDS_FWD[@]}"; do echo -e "  👉 $cmd"; done
            echo -e "\n${C_CYAN}【 iptables 专属指令 】${C_RESET}"
            for cmd in "${CMDS_IPT[@]}"; do echo -e "  👉 $cmd"; done
            echo -e "\n${C_CYAN}【 全局系统网络排障指令 】${C_RESET}"
            for cmd in "${CMDS_NET[@]}"; do echo -e "  👉 $cmd"; done
            
            echo -e "${LINE_GRAY}"
            read -p "请按回车键撤回战术控制台..." temp
            ;;
        0) break ;;
        *)
            echo -e "${C_RED}❌ 无效编号${C_RESET}"
            sleep 1
            ;;
    esac
done

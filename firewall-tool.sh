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

# 50条网络/防火墙学习命令大数组
FW_CMDS=(
    "ufw status # 查看 UFW 防火墙简易状态"
    "ufw status verbose # 查看 UFW 防火墙详细运行状态"
    "ufw status numbered # 查看所有规则并显示编号，方便删除"
    "ufw enable # 开启 UFW 防火墙"
    "ufw disable # 关闭 UFW 防火墙"
    "ufw reload # 重新加载 UFW 配置，不中断现有连接"
    "ufw default deny incoming # 设置默认拒绝所有入站连接"
    "ufw default allow outgoing # 设置默认允许所有出站连接"
    "ufw allow 80/tcp # 允许 80 端口的 TCP 流量"
    "ufw allow 443/tcp # 允许 HTTPS 443 端口流量"
    "ufw deny 3306 # 阻止对 MySQL 默认端口 3306 的访问"
    "ufw delete allow 80/tcp # 删除允许 80 端口入站的规则"
    "ufw delete 3 # 删除 'ufw status numbered' 中显示的第3条规则"
    "ufw allow from 192.168.1.100 # 允许特定 IP 地址的所有流量"
    "ufw deny from 10.0.0.5 # 拒绝来自特定 IP 地址的所有流量"
    "ufw allow from 192.168.1.0/24 # 允许特定网段内的所有机器访问"
    "ufw allow to any port 22 proto tcp # 严格限制只允许访问本地的 tcp 22 端口"
    "ufw limit 22/tcp # 开启 22 端口限流保护，防止暴力破解"
    "ufw reset # 强力重置 UFW，清除所有自定义规则（需谨慎）"
    "ss -tulnp # 查看当前系统所有正在监听的 TCP/UDP 端口"
    "ss -s # 统计当前系统的网络连接总览（Time-wait, Estab等）"
    "ss -ta # 显示所有的 TCP socket 详细连接情况"
    "netstat -anp | grep 80 # 查看 80 端口是否被占用 (需 net-tools)"
    "lsof -i :8080 # 反查出占用 8080 端口的具体进程和 PID"
    "iptables -L -n -v # 查看底层内核的 iptables 详细过滤规则"
    "iptables -F # 清空当前内核中 iptables 的所有过滤规则"
    "iptables -P INPUT DROP # 【危险】设置默认丢弃所有入站包"
    "iptables -A INPUT -p tcp --dport 80 -j ACCEPT # 使用底层命令放行 80 端口"
    "iptables -D INPUT 1 # 删除 INPUT 链的第一条规则"
    "iptables-save > /etc/iptables.rules # 将内存中的规则持久化导出到文件"
    "iptables-restore < /etc/iptables.rules # 从文件中恢复底层防火墙规则"
    "nft list ruleset # 查看最新的 nftables 内核规则集"
    "nft add table inet filter # 针对 nftables 添加一个过滤表"
    "systemctl status ufw # 查看 UFW 的 systemd 服务守护进程状态"
    "firewall-cmd --state # 查看 firewalld 的运行状态 (CentOS常用)"
    "firewall-cmd --list-all # 查看 firewalld 的放行白名单总览"
    "firewall-cmd --zone=public --add-port=80/tcp --permanent # 永久放行 80 端口"
    "firewall-cmd --reload # 重新载入 firewalld 防火墙规则"
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

# 环境依赖监测 (Debian推荐强制使用UFW简化管理)
if ! command -v ufw &> /dev/null; then
    echo -e "${C_CYAN}⏳ 正在为 Debian 部署安全防火墙引擎 (UFW)...${C_RESET}"
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install ufw -y >/dev/null 2>&1
fi

# SSH 防失联保护函数
enforce_ssh_safe() {
    # 动态抓取真实的 SSH 端口
    SSH_PORT=$(ss -tlpn 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F':' '{print $NF}' | sort -nu | head -n 1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    
    # 只要调用了 1~5 菜单的任何操作，都在底层无声补齐一次 SSH 端口的开放指令
    sudo ufw allow $SSH_PORT/tcp >/dev/null 2>&1
}

# 主菜单循环
while true; do
    clear
    
    # 状态检测逻辑
    FW_ENGINE="UFW (Uncomplicated Firewall)"
    UFW_STATUS_RAW=$(sudo ufw status 2>/dev/null)
    
    if echo "$UFW_STATUS_RAW" | grep -q "Status: active"; then
        FW_STATUS="${C_GREEN}已开启 (Active)${C_RESET}"
        IS_ACTIVE="yes"
    else
        FW_STATUS="${C_GRAY}已关闭 (Inactive)${C_RESET}"
        IS_ACTIVE="no"
    fi

    # 动态抓取 SSH 端口
    SSH_PORT=$(ss -tlpn 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F':' '{print $NF}' | sort -nu | head -n 1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    
    # 检测 SSH 端口开放状态
    if [ "$IS_ACTIVE" == "yes" ]; then
        if echo "$UFW_STATUS_RAW" | grep -E -q "^$SSH_PORT(/tcp)? +ALLOW "; then
            SSH_STATUS="${C_GREEN}开放中${C_RESET}"
            SSH_SAFE="yes"
        else
            SSH_STATUS="${C_RED}危险: 未开放!${C_RESET}"
            SSH_SAFE="no"
        fi
    else
        # 防火墙关闭时，端口物理上算开放
        SSH_STATUS="${C_YELLOW}未设防 (防火墙关闭中)${C_RESET}"
        SSH_SAFE="yes"
    fi

    # 面板渲染
    echo -e "${C_BLUE}⚡ 网络防火墙安全调度中心${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e " 🛡️ 防火墙引擎: $FW_ENGINE"
    echo -e " 🚥 当前状况: $FW_STATUS"
    echo -e " 🔑 SSH 使用端口: ${C_CYAN}$SSH_PORT${C_RESET}  状态: $SSH_STATUS"
    echo -e "${LINE_GRAY}"
    
    # 告警拦截机制
    if [ "$SSH_SAFE" == "no" ]; then
        echo -e "${C_RED}🚨 严重警告: 当前防火墙已拦截您的 SSH 端口 ($SSH_PORT)，您可能在退出后失联！${C_RESET}"
        read -p "❓ 是否立即放行 SSH 端口防失联？[Y/n] (回车默认Y): " FIX_SSH
        if [[ -z "$FIX_SSH" || "$FIX_SSH" =~ ^[Yy]$ ]]; then
            sudo ufw allow $SSH_PORT/tcp >/dev/null 2>&1
            echo -e "${C_GREEN}✅ SSH 端口防失联机制已强制触发！${C_RESET}"
            sleep 1
            continue
        fi
    fi

    # 选项输出
    echo -e "1) 开启防火墙"
    echo -e "2) 关闭防火墙"
    echo -e "3) 开放端口 ${C_GRAY}(多个用逗号隔开)${C_RESET}"
    echo -e "4) 关闭端口 ${C_GRAY}(多个用逗号隔开)${C_RESET}"
    echo -e "5) 查看已开放端口"
    echo -e "6) 查看端口占用情况"
    echo -e "7) 清除防火墙规则"
    echo -e "99) 查看防火墙命令集"
    echo -e "0) 返回上一层"
    echo -e "${LINE_GRAY}"
    
    # ==== 学习群模块 (随机抓取 10 条展示) ====
    echo -e "📚 【命令学习群 - 每次随机10条】:"
    if command -v shuf &> /dev/null; then
        shuf -e "${FW_CMDS[@]}" | head -n 10 | sed 's/^/  👉 /'
    else
        # 兼容极低环境无 shuf 的情况
        printf "%s\n" "${FW_CMDS[@]}" | head -n 10 | sed 's/^/  👉 /'
    fi
    echo -e "${LINE_GRAY}"

    read -p "请注入防火墙控制编号 [0-99]: " FW_OPT

    case $FW_OPT in
        1)
            enforce_ssh_safe
            sudo ufw --force enable
            echo -e "${C_GREEN}✅ 防火墙已成功开启！${C_RESET}"
            sleep 1.5
            ;;
        2)
            enforce_ssh_safe
            sudo ufw disable
            echo -e "${C_GRAY}✅ 防火墙已撤国防线停止拦截。${C_RESET}"
            sleep 1.5
            ;;
        3)
            enforce_ssh_safe
            read -p "请输入您要开放的端口 (多个用逗号隔开, 例: 80,443,8080): " OPEN_PORTS
            if [ -n "$OPEN_PORTS" ]; then
                # 把逗号转换成空格用于循环
                OPEN_PORTS=$(echo "$OPEN_PORTS" | tr ',' ' ')
                for p in $OPEN_PORTS; do
                    sudo ufw allow $p >/dev/null 2>&1
                    echo -e "  🟢 端口 $p 已放行"
                done
                echo -e "${C_GREEN}✅ 指定端口批量开放完毕！${C_RESET}"
            fi
            sleep 1.5
            ;;
        4)
            enforce_ssh_safe
            read -p "请输入您要关闭的端口 (多个用逗号隔开, 例: 80,443): " DEL_PORTS
            if [ -n "$DEL_PORTS" ]; then
                DEL_PORTS=$(echo "$DEL_PORTS" | tr ',' ' ')
                for p in $DEL_PORTS; do
                    if [ "$p" == "$SSH_PORT" ]; then
                        echo -e "  ${C_RED}❌ 端口 $p 是当前 SSH 生命线，系统物理拒绝为您关闭！${C_RESET}"
                    else
                        # 清理双通道规则确保切断
                        sudo ufw delete allow $p >/dev/null 2>&1
                        sudo ufw delete allow $p/tcp >/dev/null 2>&1
                        sudo ufw deny $p >/dev/null 2>&1
                        echo -e "  🔴 端口 $p 已物理闭合"
                    fi
                done
                echo -e "${C_GREEN}✅ 端口拦截规则部署完毕！${C_RESET}"
            fi
            sleep 1.5
            ;;
        5)
            enforce_ssh_safe
            clear
            echo -e "${C_BLUE}📋 当前系统入站防火墙规则大盘: ${C_RESET}"
            echo -e "${LINE_GRAY}"
            sudo ufw status numbered
            echo -e "${LINE_GRAY}"
            read -p "按回车键返回上级..." temp
            ;;
        6)
            clear
            echo -e "${C_CYAN}📋 当前机器网络层侦听端口大盘: ${C_RESET}"
            echo -e "${LINE_GRAY}"
            sudo ss -tulnp
            echo -e "${LINE_GRAY}"
            read -p "按回车键返回上级..." temp
            ;;
        7)
            echo -e "${C_YELLOW}🚨 警告：此操作将清空所有放行名单，并立刻拦截全部！${C_RESET}"
            read -p "确认清空吗？[y/N]: " IS_RESET
            if [[ "$IS_RESET" =~ ^[Yy]$ ]]; then
                sudo ufw --force reset
                # 重置后立刻把 SSH 加回来，防止 SSH 断连
                enforce_ssh_safe
                sudo ufw --force enable >/dev/null 2>&1
                echo -e "${C_GREEN}✅ 规则已全面清洗，系统保留了基础 SSH 通道并重启了防线。${C_RESET}"
                sleep 2
            fi
            ;;
        99)
            clear
            echo -e "${C_BLUE}📚 Linux 核心网络防火墙 50 招全览${C_RESET}"
            echo -e "${LINE_GRAY}"
            for cmd in "${FW_CMDS[@]}"; do
                echo -e "  👉 $cmd"
            done
            echo -e "${LINE_GRAY}"
            read -p "请按回车键返回..." temp
            ;;
        0)
            break
            ;;
        *)
            echo "❌ 无效编号"
            sleep 1
            ;;
    esac
done

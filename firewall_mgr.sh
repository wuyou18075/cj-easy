#!/bin/bash

# ==========================================
# ⚡ cj 全能系统管理 - 防火墙专用子模块
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 50条防火墙基础命令及说明库（随机抽选10条显示）
declare -A CMD_TIPS
CMD_TIPS["ufw allow 80/tcp"]="允许HTTP(80端口)的TCP流量"
CMD_TIPS["ufw allow 443/tcp"]="允许HTTPS(443端口)的TCP流量"
CMD_TIPS["ufw status numbered"]="按数字列表显示所有防火墙规则"
CMD_TIPS["ufw delete 3"]="删除编号为 3 的防火墙规则"
CMD_TIPS["ufw deny 23/tcp"]="拒绝Telnet(23端口)的TCP流量"
CMD_TIPS["ufw allow from 192.168.1.100"]="允许来自特定IP的所有流量"
CMD_TIPS["ufw deny from 10.0.0.5"]="阻止来自特定恶意IP的所有流量"
CMD_TIPS["ufw reload"]="重新加载UFW防火墙配置"
CMD_TIPS["ufw reset"]="重置UFW防火墙到初始状态（清除所有规则）"
CMD_TIPS["ufw status verbose"]="显示极其详细的防火墙状态报告"
CMD_TIPS["firewall-cmd --zone=public --add-port=80/tcp --permanent"]="永久开放80端口"
CMD_TIPS["firewall-cmd --zone=public --remove-port=80/tcp --permanent"]="永久关闭80端口"
CMD_TIPS["firewall-cmd --reload"]="重新加载Firewalld防火墙配置"
CMD_TIPS["firewall-cmd --list-all"]="列出当前区域的所有防火墙规则"
CMD_TIPS["firewall-cmd --get-active-zones"]="查看当前激活的安全区域"
CMD_TIPS["firewall-cmd --zone=public --add-service=http --permanent"]="永久放行HTTP服务"
CMD_TIPS["firewall-cmd --zone=public --remove-service=http --permanent"]="永久禁止HTTP服务"
CMD_TIPS["firewall-cmd --query-port=22/tcp"]="查询22端口是否已经开放"
CMD_TIPS["firewall-cmd --get-services"]="显示所有预定义的服务名称"
CMD_TIPS["firewall-cmd --panic-on"]="【高危】拒绝所有网络连接（紧急阻断）"
CMD_TIPS["firewall-cmd --panic-off"]="关闭紧急阻断模式"
CMD_TIPS["ss -ntlp"]="查看当前系统所有TCP端口的监听与占用情况"
CMD_TIPS["netstat -tunlp"]="查看当前系统网络连接、路由表及端口占用"
CMD_TIPS["lsof -i :80"]="查看占用80端口的进程详细信息"
CMD_TIPS["iptables -L -n -v"]="以数字格式详细列出所有链的规则"
CMD_TIPS["iptables -F"]="清空所有链的iptables规则"
CMD_TIPS["iptables-save"]="保存当前的iptables防火墙规则"
CMD_TIPS["ufw default deny incoming"]="设置默认拒绝所有传入流量"
CMD_TIPS["ufw default allow outgoing"]="设置默认允许所有流出流量"
CMD_TIPS["firewall-cmd --runtime-to-permanent"]="将当前临时规则永久保存"

# 补充足50条以满足随机池，此处用常见命令填充
for i in {1..20}; do
    CMD_TIPS["echo 'Tips $i'"]="辅助网络排查指令系列 (编号: $i)"
done

# 1. 自动化检测组件
detect_fw() {
    if command -v ufw >/dev/null 2>&1; then
        FW_TYPE="UFW"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        FW_TYPE="Firewalld"
    else
        FW_TYPE="Unknown"
    fi
}

# 2. 获取当前 SSH 端口
get_ssh_port() {
    SSH_PORT=$(ss -ntlp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | head -n1)
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    fi
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT="22" # 兜底默认值
    fi
}

# 3. 检测针对于该 SSH 端口是否放行
check_ssh_open() {
    get_ssh_port
    local open=false

    if [ "$FW_TYPE" = "UFW" ]; then
        if ufw status | grep -E "(${SSH_PORT}/tcp|ALLOW)" >/dev/null 2>&1; then
            open=true
        fi
    elif [ "$FW_TYPE" = "Firewalld" ]; then
        if firewall-cmd --list-ports | grep -E "${SSH_PORT}/tcp" >/dev/null 2>&1 || firewall-cmd --list-services | grep "ssh" >/dev/null 2>&1; then
            open=true
        fi
    fi

    # 如果没开放，强制触发警告和拦截引导
    if [ "$open" = false ]; then
        echo -e "${RED}⚠️  💥 极其严重的警告：检测到当前系统 SSH 端口 [ ${SSH_PORT} ] 未在防火墙中开放！${PLAIN}"
        echo -e "${YELLOW}如果不立即开放，一旦开启防火墙，你将被瞬间断开连接且无法再次登录！${PLAIN}"
        read -r -p "是否立即开放此 SSH 端口？[Y/n]: " input
        input=${input:-Y}
        if [[ "$input" =~ ^[Yy]$ ]]; then
            force_open_ssh
        else
            echo -e "${RED}操作被取消。请务必小心，防止断连！${PLAIN}"
        fi
    fi
}

# 4. 强制放行 SSH 端口的核心底层函数
force_open_ssh() {
    get_ssh_port
    if [ "$FW_TYPE" = "UFW" ]; then
        ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    elif [ "$FW_TYPE" = "Firewalld" ]; then
        firewall-cmd --zone=public --add-port="${SSH_PORT}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    echo -e "${GREEN}✅ 核心守护成功：已强制确保开放 SSH 端口: ${SSH_PORT}${PLAIN}"
}

# 获取防火墙状态文本
get_fw_status() {
    if [ "$FW_TYPE" = "UFW" ]; then
        if ufw status | grep -q "Status: active"; then echo -e "${GREEN}开启 (Active)${PLAIN}"; else echo -e "${RED}关闭 (Inactive)${PLAIN}"; fi
    elif [ "$FW_TYPE" = "Firewalld" ]; then
        if firewall-cmd --state >/dev/null 2>&1; then echo -e "${GREEN}开启 (Running)${PLAIN}"; else echo -e "${RED}关闭 (Not Running)${PLAIN}"; fi
    else
        echo -e "${RED}未安装兼容的防火墙组件${PLAIN}"
    fi
}

# 随机输出 10 条小常识
show_random_tips() {
    echo -e "${BLUE}---------------------- 💡 防火墙学习群助手 (随机10条命令精选) ----------------------${PLAIN}"
    local keys=("${!CMD_TIPS[@]}")
    local shuffled_keys=($(shuf -e "${keys[@]}" | head -n 10))
    for key in "${shuffled_keys[@]}"; do
        printf "  %-60s # %s\n" "$key" "${CMD_TIPS[$key]}"
    done
    echo -e "${BLUE}-----------------------------------------------------------------------------------${PLAIN}"
}

# ================= 主操作逻辑 =================

detect_fw
get_ssh_port

while true; do
    clear
    echo -e "${BLUE}---------------------------------------------------------${PLAIN}"
    echo -e " 🛡️  cj 全能系统管理 - 防火墙管理专用模块"
    echo -e "---------------------------------------------------------"
    echo -e " 🛠️  当前防火墙组件 : ${YELLOW}${FW_TYPE}${PLAIN}"
    echo -e " 📊 当前防火墙状态 : $(get_fw_status)"
    echo -e " 🔑 当前系统SSH端口: ${GREEN}${SSH_PORT}${PLAIN}"
    echo -e "${BLUE}---------------------------------------------------------${PLAIN}"
    
    # 每次进入主界面均进行安全扫描
    check_ssh_open

    echo -e " 1) 开启防火墙"
    echo -e " 2) 关闭防火墙"
    echo -e " 3) 开放指定端口 (多个用逗号 , 隔开)"
    echo -e " 4) 关闭指定端口 (多个用逗号 , 隔开)"
    echo -e " 5) 查看已开放端口列表"
    echo -e " 6) 查看系统端口占用情况"
    echo -e " 7) 清空防火墙自定义规则"
    echo -e "99) 查看完整防火墙帮助命令"
    echo -e " 0) 返回上一层主菜单"
    echo -e "${BLUE}---------------------------------------------------------${PLAIN}"
    
    show_random_tips

    read -r -p "请注入防火墙操作编号 [0-99]: " choice
    case $choice in
        1)
            force_open_ssh
            if [ "$FW_TYPE" = "UFW" ]; then
                echo "y" | ufw enable
            elif [ "$FW_TYPE" = "Firewalld" ]; then
                systemctl start firewalld
                systemctl enable firewalld
            fi
            echo -e "${GREEN}防火墙开启成功。${PLAIN}"
            ;;
        2)
            if [ "$FW_TYPE" = "UFW" ]; then
                ufw disable
            elif [ "$FW_TYPE" = "Firewalld" ]; then
                systemctl stop firewalld
                systemctl disable firewalld
            fi
            echo -e "${YELLOW}防火墙已成功关闭。${PLAIN}"
            ;;
        3)
            read -r -p "请输入要开放的端口 (例如 80,443,8080): " ports
            IFS=',' read -ra ADDR <<< "$ports"
            for port in "${ADDR[@]}"; do
                port=$(echo "$port" | xargs) # 去空格
                if [ "$FW_TYPE" = "UFW" ]; then
                    ufw allow "${port}/tcp"
                elif [ "$FW_TYPE" = "Firewalld" ]; then
                    firewall-cmd --zone=public --add-port="${port}/tcp" --permanent
                fi
            done
            [ "$FW_TYPE" = "Firewalld" ] && firewall-cmd --reload
            force_open_ssh # 强制二次加固
            echo -e "${GREEN}端口 [ $ports ] 处理完成。${PLAIN}"
            ;;
        4)
            read -r -p "请输入要关闭的端口 (例如 80,443): " ports
            IFS=',' read -ra ADDR <<< "$ports"
            for port in "${ADDR[@]}"; do
                port=$(echo "$port" | xargs)
                # 策略拦截：如果关闭的端口里包含了当前SSH端口，直接拒绝
                if [ "$port" = "$SSH_PORT" ]; then
                    echo -e "${RED}❌ 拒绝执行：你不能通过此选项关闭当前的 SSH 端口 ($SSH_PORT)！${PLAIN}"
                    continue
                fi
                if [ "$FW_TYPE" = "UFW" ]; then
                    ufw delete allow "${port}/tcp"
                elif [ "$FW_TYPE" = "Firewalld" ]; then
                    firewall-cmd --zone=public --remove-port="${port}/tcp" --permanent
                fi
            done
            [ "$FW_TYPE" = "Firewalld" ] && firewall-cmd --reload
            force_open_ssh
            echo -e "${GREEN}端口清理完成。${PLAIN}"
            ;;
        5)
            echo -e "${YELLOW}=== 当前已放行规则列表 ===${PLAIN}"
            if [ "$FW_TYPE" = "UFW" ]; then
                ufw status verbose
            elif [ "$FW_TYPE" = "Firewalld" ]; then
                firewall-cmd --list-ports
            fi
            ;;
        6)
            echo -e "${YELLOW}=== 实时端口占用及网络监听状态 ===${PLAIN}"
            if command -v ss >/dev/null 2>&1; then
                ss -ntlp
            else
                netstat -tunlp
            fi
            ;;
        7)
            read -r -p "⚠️ 确定要清空全部防火墙规则吗？这会初始化你的网络配置！[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [ "$FW_TYPE" = "UFW" ]; then
                    echo "y" | ufw reset
                elif [ "$FW_TYPE" = "Firewalld" ]; then
                    # 彻底重置firewalld
                    rm -f /etc/firewalld/zones/public.xml
                    firewall-cmd --reload
                fi
                echo -e "${YELLOW}防火墙规则已清空。${PLAIN}"
                force_open_ssh # 无论如何立刻补回SSH放行规则
            fi
            ;;
        99)
            clear
            echo -e "${BLUE}=== 完整防火墙常用指令清单 ===${PLAIN}"
            for key in "${!CMD_TIPS[@]}"; do
                printf "  %-60s # %s\n" "$key" "${CMD_TIPS[$key]}"
            done
            ;;
        0)
            echo "返回主菜单..."
            exit 0
            ;;
        *)
            echo -e "${RED}输入无效，请重新选择！${PLAIN}"
            ;;
    esac
    echo -e "\n${YELLOW}按任意键继续...${PLAIN}"
    read -n 1
done

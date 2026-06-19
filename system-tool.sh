#!/bin/bash

C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"
LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

# 核心子任务函数定义
run_tool_installation() {
    local auto_prompt=$1
    local tools_to_check=("sudo" "curl" "git" "tar" "wget" "unzip" "nano")
    local missing_tools=""
    
    for t in "${tools_to_check[@]}"; do
        if ! command -v "$t" &> /dev/null; then
            missing_tools="$missing_tools $t"
        fi
    done
    
    if [ -n "$missing_tools" ]; then
        if [ "$auto_prompt" == "true" ]; then
            echo -e "监测系统未安装以下初始化工具: ${C_YELLOW}${missing_tools}${C_RESET}"
            read -p "全部安装 [y/n] (回车默认 y): " is_install
        else
            is_install="y"
        fi
        
        if [[ -z "$is_install" || "$is_install" =~ ^[Yy]$ ]]; then
            echo -e "${C_CYAN}⏳ 正在自动拉取依赖环境...${C_RESET}"
            apt-get update -y 2>/dev/null || sudo apt-get update -y
            apt-get install -y $missing_tools 2>/dev/null || sudo apt-get install -y $missing_tools
            echo -e "${C_GREEN}✅ 基础工具全部安装完毕！${C_RESET}"
        else
            echo -e "${C_GRAY}已跳过工具安装。${C_RESET}"
        fi
    else
        echo -e "${C_GREEN}✅ 系统所需基础工具均已就绪。${C_RESET}"
    fi
}

run_hostname_change() {
    local auto_prompt=$1
    echo -e "当前主机名称: $(hostname)"
    if [ "$auto_prompt" == "true" ]; then
        read -p "输入主机名 (回车就不改跳过): " NEW_HOSTNAME
    else
        read -p "请输入您拟定设定的全新主机名: " NEW_HOSTNAME
    fi
    
    NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | xargs)
    if [ -n "$NEW_HOSTNAME" ]; then
        if [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] && [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9]$ ]]; then
            echo -e "${C_GRAY}❌ 报错：主机名存在非法字符，已放弃修改！${C_RESET}"
        else
            echo -e "${C_CYAN}⏳ 正在物理锁死系统内核主机名...${C_RESET}"
            sudo sed -i "/127.0.0.1/s/\b$(hostname)\b//g" /etc/hosts 2>/dev/null || sed -i "/127.0.0.1/s/\b$(hostname)\b//g" /etc/hosts
            sudo sed -i "/::1/s/\b$(hostname)\b//g" /etc/hosts 2>/dev/null || sed -i "/::1/s/\b$(hostname)\b//g" /etc/hosts
            echo "127.0.0.1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null 2>&1 || echo "127.0.0.1 $NEW_HOSTNAME" >> /etc/hosts
            echo "::1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null 2>&1 || echo "::1 $NEW_HOSTNAME" >> /etc/hosts
            
            sudo hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || hostnamectl set-hostname "$NEW_HOSTNAME"
            echo -e "${C_GREEN}✅ 主机名已物理修改生效为: $NEW_HOSTNAME${C_RESET}"
        fi
    else
        echo -e "${C_GRAY}跳过主机名修改。${C_RESET}"
    fi
}

run_time_sync() {
    echo -e "${C_CYAN}⏳ 正在应用北京时间...${C_RESET}"
    sudo timedatectl set-timezone Asia/Shanghai 2>/dev/null || timedatectl set-timezone Asia/Shanghai
    
    if command -v apt-get &> /dev/null; then
        apt-get install -y systemd-timesyncd 2>/dev/null || sudo apt-get install -y systemd-timesyncd
        sudo timedatectl set-ntp true 2>/dev/null || timedatectl set-ntp true
        sudo systemctl restart systemd-timesyncd 2>/dev/null || systemctl restart systemd-timesyncd
    elif command -v yum &> /dev/null; then
        sudo yum install -y chrony 2>/dev/null || yum install -y chrony
        sudo systemctl enable --now chronyd 2>/dev/null || systemctl enable --now chronyd
    fi
    echo -e "${C_GREEN}✅ 北京时间校准大功告成！当前时间: $(date "+%Y-%m-%d %H:%M:%S")${C_RESET}"
}

# 菜单主逻辑
while true; do
    clear
    echo -e "${C_BLUE}⚡ 系统信息工具${C_RESET}"
    echo -e "日期: $(date "+%Y-%m-%d %H:%M:%S")"
    echo -e "${LINE_GRAY}"
    echo -e "1) 应用全部"
    echo -e "2) 基础工具安装"
    echo -e "3) 改主机名"
    echo -e "4) 应用北京时间"
    echo -e "0) 返回上一层菜单"
    echo -e "${LINE_GRAY}"
    read -p "请注入系统子项操作编号: " SYS_OPT

    if [ "$SYS_OPT" == "0" ] || [ -z "$SYS_OPT" ]; then
        break
    elif [ "$SYS_OPT" == "1" ]; then
        echo -e "${LINE_GRAY}"
        run_tool_installation "true"
        echo -e "${LINE_GRAY}"
        run_hostname_change "true"
        echo -e "${LINE_GRAY}"
        run_time_sync
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "2" ]; then
        run_tool_installation "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "3" ]; then
        run_hostname_change "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "4" ]; then
        run_time_sync
        read -p "回车返回..." temp
    fi
done

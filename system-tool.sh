#!/bin/bash

C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"
LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

# ========================================
# 核心子任务函数定义
# ========================================

run_tool_installation() {
    local auto_prompt=$1
    local tools_to_check=("sudo" "curl" "git" "tar" "wget" "unzip" "nano" "sshpass")
    local installed_tools=""
    local missing_tools=""
    
    echo -e "${C_CYAN}正在检查系统基础工具...${C_RESET}"
    for t in "${tools_to_check[@]}"; do
        if command -v "$t" &> /dev/null; then
            installed_tools="$installed_tools $t"
        else
            missing_tools="$missing_tools $t"
        fi
    done
    
    echo -e "✅ 已安装工具:${C_GREEN}${installed_tools:- (无)}${C_RESET}"
    
    if [ -z "$missing_tools" ]; then
        echo -e "${C_GREEN}🎉 系统所需基础工具 (包含 nano 等) 均已就绪。${C_RESET}"
        if [ "$auto_prompt" != "true" ]; then
            read -p "按回车键继续..." temp
        fi
        return
    fi

    echo -e "⚠️ 待安装工具:${C_YELLOW}${missing_tools}${C_RESET}"
    
    if [ "$auto_prompt" == "true" ]; then
        is_install="y"
    else
        read -p "是否立即自动安装以上缺失工具? [y/n] (回车默认 y): " is_install
    fi
    
    if [[ -z "$is_install" || "$is_install" =~ ^[Yy]$ ]]; then
        echo -e "${C_CYAN}⏳ 正在自动拉取依赖环境...${C_RESET}"
        apt-get update -y 2>/dev/null || sudo apt-get update -y
        apt-get install -y $missing_tools 2>/dev/null || sudo apt-get install -y $missing_tools
        yum install -y $missing_tools 2>/dev/null || sudo yum install -y $missing_tools
        echo -e "${C_GREEN}✅ 基础工具全部安装完毕！${C_RESET}"
    else
        echo -e "${C_GRAY}已跳过工具安装。${C_RESET}"
    fi
    
    if [ "$auto_prompt" != "true" ]; then
        read -p "按回车键继续..." temp
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
    echo -e "${C_CYAN}⏳ 正在应用北京时间并构筑底层 NTP 同步环...${C_RESET}"
    sudo timedatectl set-timezone Asia/Shanghai 2>/dev/null || timedatectl set-timezone Asia/Shanghai
    
    if command -v apt-get &> /dev/null; then
        apt-get install -y chrony 2>/dev/null || sudo apt-get install -y chrony
        sudo systemctl enable chrony 2>/dev/null || systemctl enable chrony
        sudo systemctl restart chrony 2>/dev/null || systemctl restart chrony
        sudo timedatectl set-ntp true 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        sudo yum install -y chrony 2>/dev/null || yum install -y chrony
        sudo systemctl enable chronyd 2>/dev/null || systemctl enable chronyd
        sudo systemctl restart chronyd 2>/dev/null || systemctl restart chronyd
        sudo timedatectl set-ntp true 2>/dev/null || true
    fi
    echo -e "${C_GREEN}✅ 北京时间校准及 NTP 自动同步引擎大功告成！${C_RESET}"
    echo -e "当前时间: $(date "+%Y-%m-%d %H:%M:%S")"
}

run_swap_check() {
    local auto_prompt=$1
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    
    if [ "$mem_total" -lt 4096 ]; then
        echo -e "监测到物理内存小于 4G (当前: ${mem_total}MB)"
        read -p "是否添加 1G 虚拟内存? [y/n] (回车默认 y): " add_swap
        
        if [[ -z "$add_swap" || "$add_swap" =~ ^[Yy]$ ]]; then
            if ! grep -q "swap" /etc/fstab; then
                echo -e "${C_CYAN}⏳ 正在分配 1GB 虚拟内存区...${C_RESET}"
                fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
                chmod 600 /swapfile
                mkswap /swapfile >/dev/null 2>&1
                swapon /swapfile >/dev/null 2>&1
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
                echo -e "${C_GREEN}✅ 1GB 虚拟内存配置完毕！${C_RESET}"
            else
                echo -e "${C_YELLOW}系统已存在虚拟内存配置，已跳过。${C_RESET}"
            fi
        fi
    else
        echo -e "${C_GREEN}✅ 物理内存大于或等于 4G (${mem_total}MB)，无需配置虚拟内存。${C_RESET}"
    fi
}

run_ssh_port_add() {
    local auto_prompt=$1
    local current_ports=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | paste -sd "," - || echo "22")
    echo -e "当前已监听的 SSH 端口为: ${current_ports}"
    echo -e "${C_YELLOW}💡 提示: 本操作为【追加】新端口，原端口(如22)将同时保留，防止修改失败导致失联。${C_RESET}"
    read -p "请输入要添加的 SSH 新端口号: " new_port

    if [[ -n "$new_port" && "$new_port" =~ ^[0-9]+$ && "$new_port" -le 65535 ]]; then
        echo -e "${C_CYAN}⏳ 正在添加端口并执行防火墙穿透...${C_RESET}"
        
        # 确保原有的默认端口显式存在，以防只留了新端口
        if ! grep -i "^Port 22" /etc/ssh/sshd_config > /dev/null; then
            sed -i '1i Port 22' /etc/ssh/sshd_config
        fi
        
        if ! grep -i "^Port $new_port" /etc/ssh/sshd_config > /dev/null; then
            sed -i "/^Port 22/a Port $new_port" /etc/ssh/sshd_config
        fi
        
        local fw_opened=false
        if command -v ufw &> /dev/null && ufw status | grep -qE "Active|active"; then
            ufw allow "$new_port"/tcp >/dev/null 2>&1
            fw_opened=true
        fi
        if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port="${new_port}/tcp" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            fw_opened=true
        fi
        if command -v iptables &> /dev/null; then
            iptables -I INPUT -p tcp --dport "$new_port" -j ACCEPT >/dev/null 2>&1
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fw_opened=true
        fi

        systemctl restart sshd || systemctl restart ssh
        
        if [ "$fw_opened" = true ]; then
            echo -e "${C_GREEN}✅ SSH 新端口 $new_port 已添加！系统防火墙已自动为您双向放行。可以放心使用新端口尝试登录。${C_RESET}"
        else
            echo -e "${C_GREEN}✅ SSH 新端口 $new_port 已添加！(未检测到运行中的防火墙限制，已放行)。${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}端口输入无效或为空，放弃修改。${C_RESET}"
    fi
}

_create_user_logic() {
    while true; do
        read -p "请输入拟创建的新用户名: " new_user
        if [ -z "$new_user" ]; then continue; fi
        if id "$new_user" &>/dev/null; then
            echo -e "${C_YELLOW}该用户已存在！请换一个名字。${C_RESET}"
            continue
        fi

        read -p "请输入新用户密码 (将明文显示以防写错): " pass1
        read -p "请再次确认密码 (明文): " pass2

        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            useradd -m -s /bin/bash "$new_user"
            echo "$new_user:$pass1" | chpasswd
            
            # 配置免密提权 NOPASSWD
            echo "$new_user ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$new_user"
            chmod 0440 /etc/sudoers.d/"$new_user"
            echo -e "${C_GREEN}✅ 用户 $new_user 创建成功，已配置免密 sudo 权限！连接后输入 'sudo -i' 无需密码即可切换为 root。${C_RESET}"
            break
        else
            echo -e "${C_YELLOW}❌ 密码不匹配或为空，请重新输入！${C_RESET}"
        fi
    done
}

run_user_manage() {
    local users_arr=($(awk -F':' '{ if ($3 == 0 || ($3 >= 1000 && $3 <= 60000 && $1 != "nobody")) print $1 }' /etc/passwd))
    
    echo -e "\n${C_CYAN}当前系统用户列表:${C_RESET}"
    for i in "${!users_arr[@]}"; do
        echo -e "$((i+1))) ${users_arr[$i]}"
    done
    echo -e "${LINE_GRAY}"

    if [ ${#users_arr[@]} -eq 1 ] && [ "${users_arr[0]}" == "root" ]; then
        echo -e "${C_YELLOW}系统中仅存在 root 用户，安全起见，您必须创建一个具有免密 root 权限的个人新用户！${C_RESET}"
        _create_user_logic
    else
        read -p "请选择要操作验证的用户序号: " u_idx
        if [[ ! "$u_idx" =~ ^[0-9]+$ ]] || [ "$u_idx" -lt 1 ] || [ "$u_idx" -gt ${#users_arr[@]} ]; then
            echo -e "${C_YELLOW}输入无效，已退出管理环节。${C_RESET}"
            return
        fi
        
        local selected_user="${users_arr[$((u_idx-1))]}"
        local current_port=$(sshd -T 2>/dev/null | grep -i '^port ' | head -n 1 | awk '{print $2}' || echo "22")
        
        while true; do
            read -p "请输入用户 $selected_user 的密码(明文): " u_pass
            if ! command -v sshpass &> /dev/null; then apt-get install -y sshpass 2>/dev/null || yum install -y sshpass 2>/dev/null; fi
            
            echo -e "${C_CYAN}⏳ 正在发起本地环回登录验证...${C_RESET}"
            if sshpass -p "$u_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$current_port" "$selected_user"@127.0.0.1 "echo 'OK'" 2>/dev/null | grep -q "OK"; then
                echo -e "${C_GREEN}✅ 验证成功！密码完全正确，具备独立 SSH 登录权限。${C_RESET}"
                break
            else
                read -p "❌ 验证失败！是否重试输入密码? (输入 n 为放弃验证直接新建用户) [y/n] (回车默认 y): " retry_opt
                if [[ "$retry_opt" =~ ^[Nn]$ ]]; then
                    _create_user_logic
                    break
                fi
            fi
        done
    fi
}

run_check_ssh_firewall() {
    echo -e "\n${C_CYAN}🔍 当前 SSH 端口监听状态 (/etc/ssh/sshd_config):${C_RESET}"
    grep -i '^Port ' /etc/ssh/sshd_config || echo -e "Port 22 (系统默认隐含配置)"

    echo -e "\n${C_CYAN}🛡️ 当前系统防火墙状态:${C_RESET}"
    local active_fw="none"
    if command -v ufw &> /dev/null && ufw status | grep -qE "Active|active"; then
        active_fw="ufw"
        ufw status | grep -i "Status" || ufw status
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        active_fw="firewalld"
        echo -e "Firewalld 运行状态: $(firewall-cmd --state 2>/dev/null)"
        echo -e "已放行的端口: $(firewall-cmd --list-ports 2>/dev/null)"
    elif command -v iptables &> /dev/null; then
        active_fw="iptables"
        iptables -L INPUT -n | grep dpt || echo "iptables 放行规则如上 (空则表示无特殊拦截)"
    else
        echo -e "未检测到 ufw/firewalld/iptables，系统可能是纯净状态或由云平台安全组进行外部管控。"
    fi

    # 动态非22端口安全查杀与自动修复
    if [ "$active_fw" != "none" ]; then
        echo -e "\n${C_CYAN}🔎 非默认端口防火墙穿透检测:${C_RESET}"
        local ssh_ports=$(grep -i '^Port ' /etc/ssh/sshd_config | awk '{print $2}')
        [ -z "$ssh_ports" ] && ssh_ports="22"

        for port in $ssh_ports; do
            if [ "$port" == "22" ]; then continue; fi
            echo -e "▶ 校验非标准端口 [ ${C_YELLOW}${port}${C_RESET} ] ..."
            local is_open=false

            if [ "$active_fw" == "ufw" ]; then
                if ufw status | grep -qE "^${port}(/tcp)? +ALLOW "; then is_open=true; fi
            elif [ "$active_fw" == "firewalld" ]; then
                if firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then is_open=true; fi
            elif [ "$active_fw" == "iptables" ]; then
                if iptables -L INPUT -n | grep -qE "dpt:${port}\b"; then is_open=true; fi
            fi

            if [ "$is_open" == true ]; then
                echo -e "   ${C_GREEN}✅ 已放开,安全${C_RESET}"
            else
                echo -e "   ${C_YELLOW}⚠️ 监测到端口未放开，现在开始放开...${C_RESET}"
                if [ "$active_fw" == "ufw" ]; then
                    echo -e "   ${C_GRAY}[执行代码] ufw allow ${port}/tcp${C_RESET}"
                    ufw allow "${port}/tcp" >/dev/null 2>&1
                elif [ "$active_fw" == "firewalld" ]; then
                    echo -e "   ${C_GRAY}[执行代码] firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload${C_RESET}"
                    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                    firewall-cmd --reload >/dev/null 2>&1
                elif [ "$active_fw" == "iptables" ]; then
                    echo -e "   ${C_GRAY}[执行代码] iptables -I INPUT -p tcp --dport ${port} -j ACCEPT${C_RESET}"
                    iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                fi
                echo -e "   ${C_GREEN}✅ 验证一下,已放开权限${C_RESET}"
            fi
        done
    fi

    echo -e "\n${C_YELLOW}💡 强烈建议：${C_RESET}"
    echo -e "在执行选项 [20 一键禁用 root 和 22 端口] 之前，请务必【立即开启一个新的 SSH 终端】！"
    echo -e "使用您创建的【非 root 账号】和【新端口】尝试登录。确认连接成功且可以通过 'sudo -i' 提权后，再执行 20 选项。"
    echo -e "${LINE_GRAY}"
    
    read -p "是否立即退出当前 SSH 连接，以便使用非 root 账号重试登录? [y/n] (回车默认 y): " do_exit
    if [[ -z "$do_exit" || "$do_exit" =~ ^[Yy]$ ]]; then
        echo -e "${C_GREEN}⏳ 正在断开连接... 请使用新账号和新端口重新登录服务器！${C_RESET}"
        sleep 1
        kill -9 $PPID
    else
        echo -e "${C_GRAY}已取消退出，请手动验证后再执行 20 选项。${C_RESET}"
    fi
}

run_lockdown() {
    echo -e "\n${C_CYAN}⏳ 正在进行执行环境的安全合规监测...${C_RESET}"
    
    # 提取当前登录发起用户
    local LOGIN_USER=$(logname 2>/dev/null)
    if [ -z "$LOGIN_USER" ]; then
        LOGIN_USER=${SUDO_USER:-$(whoami)}
    fi
    
    # 初始化端口变量
    local CONN_PORT=""

    # 尝试 1：直接从环境变量获取 (兼顾 SSH_CONNECTION 和 SSH_CLIENT)
    local env_conn="${SSH_CONNECTION:-$SSH_CLIENT}"
    if [ -n "$env_conn" ]; then
        # 无论多少个字段，取最后一个字段 ($NF) 必定是服务端接收端口
        CONN_PORT=$(echo "$env_conn" | awk '{print $NF}')
    fi

    # 尝试 2：针对 tmux 虚拟终端的缓存穿透
    if [ -z "$CONN_PORT" ] && [ -n "$TMUX" ] && command -v tmux &> /dev/null; then
        CONN_PORT=$(tmux show-env SSH_CONNECTION 2>/dev/null | grep '^SSH_CONNECTION=' | awk -F'=' '{print $2}' | awk '{print $4}')
    fi

    # 尝试 3：物理映射查杀 (最稳妥的兜底方案)
    # 利用 who -m 提取当前 TTY 接入的真实来源 IP，再用 ss / netstat 反查服务器建立连接的本地监听端口
    if [ -z "$CONN_PORT" ]; then
        local client_ip=$(who -m 2>/dev/null | awk '{print $NF}' | tr -d '()')
        if [ -n "$client_ip" ] && [[ "$client_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$client_ip" =~ : ]]; then
            if command -v ss &> /dev/null; then
                CONN_PORT=$(sudo ss -tn state established 2>/dev/null | grep "$client_ip" | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
            elif command -v netstat &> /dev/null; then
                CONN_PORT=$(sudo netstat -tn 2>/dev/null | grep ESTABLISHED | grep "$client_ip" | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
            fi
        fi
    fi

    # 尝试 4：安全强化的进程树溯源 (彻底修复 integer expression expected 报错)
    if [ -z "$CONN_PORT" ]; then
        local check_pid=$$
        # 强制使用正则校验 pid 必须为纯数字，才能进入内部循环和后续数学比对 (-le 1)
        while [ -n "$check_pid" ] && echo "$check_pid" | grep -qE '^[0-9]+$'; do
            if [ "$check_pid" -le 1 ]; then 
                break 
            fi
            
            local env_port=$(sudo cat /proc/"$check_pid"/environ 2>/dev/null | tr '\0' '\n' | grep '^SSH_CONNECTION=' | head -n 1 | awk '{print $4}')
            if [ -n "$env_port" ]; then
                CONN_PORT="$env_port"
                break
            fi
            
            local next_pid=$(awk '/^[Pp][Pp][Ii][Dd]:/ {print $2}' /proc/"$check_pid"/status 2>/dev/null)
            if [ -z "$next_pid" ] || [ "$next_pid" == "$check_pid" ]; then
                break
            fi
            check_pid="$next_pid"
        done
    fi
    
    local pass_check=true

    echo -e "1. 探测当前操作登录用户: ${C_GREEN}$LOGIN_USER${C_RESET}"
    
    if [ -z "$CONN_PORT" ]; then
        echo -e "2. 探测当前 SSH 登录接收端口: ${C_YELLOW}未知 (无法溯源，可能运行于深层嵌套或特殊子环境中)${C_RESET}"
        echo -e "${C_YELLOW}❌ 监测不通过: 即使强行穿透了进程树仍无法确切获取您的连接端口。保护机制启动，绝不在未知状态下盲目封禁！${C_RESET}"
        pass_check=false
    else
        echo -e "2. 探测当前 SSH 登录接收端口: ${C_GREEN}$CONN_PORT${C_RESET}"
    fi

    if [ "$LOGIN_USER" == "root" ]; then
        echo -e "${C_YELLOW}❌ 监测不通过: 您当前登录的用户身份仍然是 root，为防止失联，禁止操作！${C_RESET}"
        pass_check=false
    fi

    if [ "$CONN_PORT" == "22" ]; then
        echo -e "${C_YELLOW}❌ 监测不通过: 您当前的 SSH 连接仍旧建立在 22 端口上，直接封禁会导致会话断开或失联！${C_RESET}"
        pass_check=false
    fi

    if [ "$pass_check" == "false" ]; then
        echo -e "${C_GRAY}=================================================${C_RESET}"
        echo -e "💡 保护机制已强行熔断: 当前操作已自动中止。"
        echo -e "请您新开一个终端，使用配置好的【新端口】+【新账号】登录进来后，重新运行本脚本再执行 20 项！"
        return
    fi
    
    echo -e "${C_GREEN}✅ 安全验证全面通过！当前已满足禁用 root 用户和 22 端口的安全条件。${C_RESET}"
    read -p "⚠️ 警告：是否确认立即彻底封禁 root 远程登录并抹除 22 端口? [y/n]: " confirm_lock
    
    if [[ "$confirm_lock" =~ ^[Yy]$ ]]; then
        echo -e "${C_CYAN}⏳ 正在吊销特权及擦除高危端口...${C_RESET}"
        
        # 补充必要的 sudo 权限提升，防止普通账号无权修改核心配置
        if grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
            sudo sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        else
            echo "PermitRootLogin no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        fi
        
        # 清理 22 端口
        sudo sed -i '/^Port 22$/d' /etc/ssh/sshd_config
        sudo sed -i '/^#Port 22$/d' /etc/ssh/sshd_config
        
        sudo systemctl restart sshd || sudo systemctl restart ssh
        echo -e "${C_GREEN}🎉 阻断完成！root 直连与 22 端口现已彻底失效，服务器防暴破安全级别已拉满！${C_RESET}"
    else
        echo -e "${C_GRAY}已放弃封禁操作。${C_RESET}"
    fi
}

# ========================================
# 主菜单界面交互逻辑
# ========================================

while true; do
    clear
    echo -e "${C_BLUE}⚡ 系统配置极速工具${C_RESET}"
    echo -e "当前时间: $(date "+%Y-%m-%d %H:%M:%S")"
    echo -e "${LINE_GRAY}"
    echo -e "1) 应用全部防爆破 (1-9)"
    echo -e "2) 基础工具包极速部署"
    echo -e "3) 更改内核主机名"
    echo -e "4) 同步并锁死北京时间"
    echo -e "6) 监测内存不足 4G 自动装载 1G 虚拟内存"
    echo -e "7) 添加 SSH 端口并放行防火墙"
    echo -e "8) 用户管理"
    echo -e "9) 检验 SSH 端口与防火墙状态"
    echo -e "10) 简单初始化环 (2,3,4,6)"
    echo -e "20) 一键禁用 root 和 22端口登录"
    echo -e "0) 退出本脚本"
    echo -e "${LINE_GRAY}"
    read -p "请注入您要执行的系统子项编号: " SYS_OPT

    if [ "$SYS_OPT" == "0" ] || [ -z "$SYS_OPT" ]; then
        echo -e "感谢使用，已安全退出！"
        break
    elif [ "$SYS_OPT" == "1" ]; then
        echo -e "${LINE_GRAY}"
        run_tool_installation "true"
        echo -e "${LINE_GRAY}"
        run_hostname_change "true"
        echo -e "${LINE_GRAY}"
        run_time_sync
        echo -e "${LINE_GRAY}"
        run_swap_check "true"
        echo -e "${LINE_GRAY}"
        run_ssh_port_add "true"
        echo -e "${LINE_GRAY}"
        run_user_manage
        echo -e "${LINE_GRAY}"
        run_check_ssh_firewall
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "2" ]; then
        run_tool_installation "false"
    elif [ "$SYS_OPT" == "3" ]; then
        run_hostname_change "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "4" ]; then
        run_time_sync
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "6" ]; then
        run_swap_check "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "7" ]; then
        run_ssh_port_add "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "8" ]; then
        run_user_manage
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "9" ]; then
        run_check_ssh_firewall
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "10" ]; then
        echo -e "${LINE_GRAY}"
        run_tool_installation "true"
        echo -e "${LINE_GRAY}"
        run_hostname_change "true"
        echo -e "${LINE_GRAY}"
        run_time_sync
        echo -e "${LINE_GRAY}"
        run_swap_check "true"
        echo -e "${LINE_GRAY}"
        echo -e "${C_GREEN}🚀 基础环境初始化 2,3,4,6 步已全部执行完毕！${C_RESET}"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "20" ]; then
        run_lockdown
        read -p "回车返回..." temp
    fi
done
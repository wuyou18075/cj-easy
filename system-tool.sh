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
    local missing_tools=""
    
    for t in "${tools_to_check[@]}"; do
        if ! command -v "$t" &> /dev/null; then
            missing_tools="$missing_tools $t"
        fi
    done
    
    if [ -n "$missing_tools" ]; then
        if [ "$auto_prompt" == "true" ]; then
            echo -e "监测系统未安装以下初始化工具: ${C_YELLOW}${missing_tools}${C_RESET}"
            read -p "全部自动安装 [y/n] (回车默认 y): " is_install
        else
            is_install="y"
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

run_ssh_port_change() {
    local auto_prompt=$1
    if [ "$auto_prompt" == "true" ]; then
        read -p "是否修改 SSH 端口? [y/n] (回车默认 y): " do_port
        if [[ -n "$do_port" && ! "$do_port" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    local current_port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' || echo "22")
    echo -e "当前 SSH 端口为: ${current_port}"
    read -p "请输入新的 SSH 端口号: " new_port

    if [[ -n "$new_port" && "$new_port" =~ ^[0-9]+$ && "$new_port" -le 65535 ]]; then
        echo -e "${C_CYAN}⏳ 正在修改端口并执行防火墙穿透...${C_RESET}"
        sed -i -E "s/^#?Port .*/Port $new_port/" /etc/ssh/sshd_config
        
        local fw_opened=false
        if command -v ufw &> /dev/null && ufw status | grep -q "Active"; then
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
            echo -e "${C_GREEN}✅ SSH 端口已更新为 $new_port，系统防火墙已自动为您放行，可以放心重启！${C_RESET}"
        else
            echo -e "${C_GREEN}✅ SSH 端口已更新为 $new_port (未检测到运行中的防火墙限制，已自动放行，可放心重启)。${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}端口输入无效或为空，放弃修改。${C_RESET}"
    fi
}

run_create_user() {
    local auto_prompt=$1
    
    # 提取所有非系统内置的普通用户 (UID 1000~60000)
    local reg_users=$(awk -F':' -v "min=1000" -v "max=60000" '{ if ( $3 >= min && $3 <= max && $1 != "nobody" ) print $1 }' /etc/passwd)
    local user_count=$(echo "$reg_users" | grep -v "^$" | wc -l)
    local current_port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' || echo "22")

    echo -e "\n${C_CYAN}当前系统有效用户列表:${C_RESET}"
    awk -F':' '{ if ($3 == 0 || ($3 >= 1000 && $3 <= 60000 && $1 != "nobody")) print " - " $1 " (UID: "$3")" }' /etc/passwd
    echo -e "${LINE_GRAY}"

    if [ "$user_count" -eq 0 ]; then
        read -p "当前仅存在 root 及其它系统用户，是否创建一个具有 root 权限的个人新用户? [y/n] (回车默认 y): " do_create
        if [[ -n "$do_create" && ! "$do_create" =~ ^[Yy]$ ]]; then
            return
        fi
    else
        echo -e "${C_YELLOW}检测到存在非 root 普通用户，进入账号遍历管理环节...${C_RESET}"
        for u in $reg_users; do
            if [ -z "$u" ]; then continue; fi
            while true; do
                echo -e "\n针对用户 ${C_GREEN}$u${C_RESET}，请选择操作:"
                echo "1) 验证密码登录状态"
                echo "2) 永久删除该账号及其文件"
                echo "3) 不做处理"
                read -p "请输入操作序号 [1/2/3] (回车默认 3): " u_opt
                
                if [[ -z "$u_opt" || "$u_opt" == "3" ]]; then
                    echo -e "${C_GRAY}已跳过用户 $u。${C_RESET}"
                    break
                elif [ "$u_opt" == "1" ]; then
                    read -p "请输入用户 $u 的密码 (明文): " u_pass
                    # 确保 sshpass 工具就位
                    if ! command -v sshpass &> /dev/null; then apt-get install -y sshpass 2>/dev/null || yum install -y sshpass 2>/dev/null; fi
                    
                    echo -e "${C_CYAN}⏳ 正在发起本地环回登录验证...${C_RESET}"
                    if sshpass -p "$u_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$current_port" "$u"@127.0.0.1 "echo 'OK'" 2>/dev/null | grep -q "OK"; then
                        echo -e "${C_GREEN}✅ 密码完全正确，且具备独立 SSH 登录权限！${C_RESET}"
                    else
                        echo -e "${C_YELLOW}❌ 验证失败！可能是密码错误或账户被禁止 SSH 登录。${C_RESET}"
                    fi
                    # 验证后跳出当前用户的死循环，进入下一个用户
                    break
                elif [ "$u_opt" == "2" ]; then
                    read -p "⚠️ 确认彻底删除用户 $u 及其主目录? [y/n]: " confirm_del
                    if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                        userdel -r "$u" 2>/dev/null
                        echo -e "${C_GREEN}✅ 用户 $u 已被彻底删除！${C_RESET}"
                    fi
                    break
                fi
            done
        done
        
        echo -e "${LINE_GRAY}"
        read -p "管理环节结束，是否需要再创建一个全新具有 root 权限的个人用户? [y/n] (回车默认 y): " do_create
        if [[ -n "$do_create" && ! "$do_create" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    # 新建个人用户逻辑
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
            
            # 赋予 sudo 权限，实现 sudo -i 无缝提权 root
            echo "$new_user ALL=(ALL:ALL) ALL" > /etc/sudoers.d/"$new_user"
            chmod 0440 /etc/sudoers.d/"$new_user"
            echo -e "${C_GREEN}✅ 用户 $new_user 创建成功，连接后可通过 'sudo -i' 直接提权！${C_RESET}"
            break
        else
            echo -e "${C_YELLOW}❌ 密码不匹配或为空，请重新输入！${C_RESET}"
        fi
    done
}

run_disable_root() {
    local auto_prompt=$1
    if [ "$auto_prompt" == "true" ]; then
        read -p "是否禁止 root 远程登录? [y/n] (回车默认 y): " do_disable
        if [[ -n "$do_disable" && ! "$do_disable" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    echo -e "${C_YELLOW}⚠️ 警告：为防止服务器彻底失联，执行剥夺 root 权限前必须前置验证一个非 root 账户的存活情况！${C_RESET}"
    local current_port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' || echo "22")
    
    read -p "请输入一个非 root 用户名用于验证连接: " v_user
    if [ -z "$v_user" ] || [ "$v_user" == "root" ]; then
        echo -e "${C_YELLOW}❌ 用户输入不合法或仍为 root，操作已紧急中止。${C_RESET}"
        return
    fi

    read -p "请输入该用户的密码 (明文): " v_pass
    
    if ! command -v sshpass &> /dev/null; then apt-get install -y sshpass 2>/dev/null || yum install -y sshpass 2>/dev/null; fi

    echo -e "${C_CYAN}⏳ 正在通过 127.0.0.1:$current_port 检测端口通透状态及验证该用户...${C_RESET}"
    if sshpass -p "$v_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$current_port" "$v_user"@127.0.0.1 "echo 'VERIFY_SUCCESS'" 2>/dev/null | grep -q "VERIFY_SUCCESS"; then
        echo -e "${C_GREEN}✅ SSH 端口正常运作，非 root 账号验证通过！${C_RESET}"
        echo -e "${C_CYAN}⏳ 正在剥夺 root 的 SSH 直连权限...${C_RESET}"
        sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
        echo -e "${C_GREEN}✅ root 远程登录已被彻底封死，系统安全性已满配！${C_RESET}"
    else
        echo -e "${C_YELLOW}❌ 防火墙阻断 或 账号/密码严重错误！${C_RESET}"
        echo -e "${C_YELLOW}为防止您被反锁在服务器外，禁止 root 操作已被系统强行熔断并取消！请排查账户问题后再试。${C_RESET}"
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
    echo -e "1) 依次执行应用全部"
    echo -e "2) 基础工具包极速部署 (含 nano、sudo、sshpass 等核心依赖)"
    echo -e "3) 更改内核主机名"
    echo -e "4) 同步并锁死北京时间"
    echo -e "6) 监测内存不足 4G 自动装载 1G 虚拟内存"
    echo -e "7) 更改并放行 SSH 端口"
    echo -e "8) 创建 / 遍历管理个人非 root 用户 (赋予无缝 sudo -i 提权)"
    echo -e "9) 强验证非 root 连接状态并封禁 root 登录直连"
    echo -e "10) 一键应用系统初始化环境 (静默跑通 2、3、4、6 项)"
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
        run_ssh_port_change "true"
        echo -e "${LINE_GRAY}"
        run_create_user "true"
        echo -e "${LINE_GRAY}"
        run_disable_root "true"
        read -p "全部流程结束，按回车返回主菜单..." temp
    elif [ "$SYS_OPT" == "2" ]; then
        run_tool_installation "false"
        read -p "回车返回..." temp
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
        run_ssh_port_change "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "8" ]; then
        run_create_user "false"
        read -p "回车返回..." temp
    elif [ "$SYS_OPT" == "9" ]; then
        run_disable_root "false"
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
        echo -e "${C_GREEN}🚀 基础环境初始化 1-4 步(工具/主机名/时间/Swap)已全部执行完毕！${C_RESET}"
        read -p "回车返回..." temp
    fi
done

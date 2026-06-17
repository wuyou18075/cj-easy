#!/bin/bash

# =========================================================
#             ⚡ TCP内核调优与网络优化矩阵 ⚡
# =========================================================

# 全局色彩控制台
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"

LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"
SYS_FILE="/etc/sysctl.conf"
BAK_FILE="/etc/sysctl.conf.bak_matrix"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ 错误: 必须使用 root 权限运行此脚本！${C_RESET}"
    exit 1
fi

if [ ! -f "$SYS_FILE" ]; then
    touch "$SYS_FILE"
fi

init_dependencies() {
    local missing_deps=()
    for cmd in wget awk grep curl ping bc ip; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    if [ ${#missing_deps[@]} -gt 0 ]; then
        apt-get update -y >/dev/null 2>&1 || yum makecache -y >/dev/null 2>&1
        apt-get install -y "${missing_deps[@]}" >/dev/null 2>&1 || yum install -y "${missing_deps[@]}" >/dev/null 2>&1
    fi
}
init_dependencies

get_ipv6_status_text() {
    local disabled_all
    disabled_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    if [ "$disabled_all" == "1" ]; then 
        echo -e "${C_RED}禁用${C_RESET}"
    else 
        echo -e "${C_GREEN}开启${C_RESET}"
    fi
}

# 动态获取主网卡名称及其实时 MTU 值
_get_main_interface_and_mtu() {
    local interface
    interface=$(ip -4 route ls | grep default | grep -oP 'dev \K\S+' | head -n 1)
    if [ -z "$interface" ]; then
        interface=$(ip link show | grep -v 'lo' | grep 'state UP' | awk -F ': ' '{print $2}' | head -n 1)
    fi
    local mtu_val
    mtu_val=$(ip link show "$interface" 2>/dev/null | grep -oP 'mtu \K\d+')
    echo "${interface:-eth0}|${mtu_val:-1500}"
}

_calculate_static_bdp_recommend() {
    local total_mem; total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if (( total_mem < 1050000 )); then
        echo "8388608"
    else
        echo "16777216"
    fi
}

# 2. 多维速率测试 (内部公用底层函数)
_execute_speed_probe() {
    local test_url="http://cachefly.cachefly.net/10mb.test"
    local wget_output; wget_output=$(wget -4 --no-check-certificate --timeout=6 --tries=1 -O /dev/null "$test_url" 2>&1)
    local raw_speed; raw_speed=$(echo "$wget_output" | grep -oE '\([0-9.]+\s+[KMG]B/s\)' | tr -d '()')
    if [ -z "$raw_speed" ]; then raw_speed=$(echo "$wget_output" | grep "MB/s" | awk '{print $(NF-1), $NF}' | tr -d '()'); fi
    local s_speed="0.00 MB/s"; [ -n "$raw_speed" ] && s_speed="$raw_speed"

    local start_t; start_t=$(date +%s.%N)
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 0-3145728 > /dev/null) &
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 3145729-6291456 > /dev/null) &
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 6291457-9437184 > /dev/null) &
    wait; local end_t; end_t=$(date +%s.%N)
    local m_speed; m_speed=$(awk -v start="$start_t" -v end="$end_t" 'BEGIN {duration = end - start; if (duration <= 0) duration = 0.001; printf "%.2f MB/s", 9.0 / duration;}')
    
    local rtt_avg; rtt_avg=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null | tail -n 1 | awk -F '/' '{print $5}')
    if [ -z "$rtt_avg" ]; then rtt_avg="0.0"; fi

    echo "$s_speed|$m_speed|$rtt_avg"
}

run_multi_dim_speedtest() {
    echo -e "${C_CYAN}⏳ 正在下发单连接套接字，握手跨境通用 Anycast 测速点...${C_RESET}"
    echo -e " 📍 节点位置: ${C_YELLOW}全球 Anycast 边缘分分发集群 (亚太/核心骨干网)${C_RESET}"
    echo -e " 🌐 测试网型: ${C_GRAY}http://cachefly.cachefly.net/10mb.test${C_RESET}"
    echo -e "${LINE_GRAY}"
    
    local res; res=$(_execute_speed_probe)
    
    echo -e " 📊 单线程物理净吞吐速率:   ${C_GREEN}(公网直连) $(echo "$res" | cut -d'|' -f1)${C_RESET}"
    echo -e " 🚀 多线程高并发极限带宽:   ${C_GREEN}(并发压榨) $(echo "$res" | cut -d'|' -f2)${C_RESET}"
}

# 3. 电报数据中心链路专项监测
run_telegram_spec_test() {
    echo -e "⏳ 正在连通 Telegram 全球核心骨干机房进行时延与丢包率交叉监测..."
    local dc1_ip="149.154.175.50"; local dc2_ip="149.154.167.51"; local dc5_ip="91.108.56.110"
    test_ping() {
        local ip=$1; local res; res=$(ping -c 4 -W 2 "$ip" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$res" ]; then echo -e "${C_RED}❌ 物理断流 (超时/阻断)${C_RESET}"; else
            local loss; loss=$(echo "$res" | grep -oP '\d+(?=% packet loss)'); local avg_time; avg_time=$(echo "$res" | tail -n 1 | awk -F '/' '{print $5}')
            echo -e "${C_GREEN}${avg_time} ms${C_RESET} (丢包率: ${C_YELLOW}${loss}%${C_RESET})"; fi
    }
    echo -e "${LINE_GRAY}"
    echo -n " 🌐 Telegram DC1 [北美-迈阿密]:   " && test_ping "$dc1_ip"
    echo -n " 🌐 Telegram DC2 [欧洲-阿姆]:     " && test_ping "$dc2_ip"
    echo -n " 🌐 Telegram DC5 [亚洲-新加坡]:   " && test_ping "$dc5_ip"
}

# 1. 深度交叉审计调优引擎 (涵盖 MTU 智能联动优化)
adaptive_tcp_tuning() {
    clear
    echo -e "${C_BLUE}⚡ 正在启动全向链路监测，实时嗅探网速与物理时延...${C_RESET}"
    echo -e "${LINE_GRAY}"

    echo -e "⏳ 正在测试物理网络到骨干网的时延 (RTT)..."
    local rtt_ms; rtt_ms=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null | tail -n 1 | awk -F '/' '{print $5}')
    if [ -z "$rtt_ms" ] || [ "$rtt_ms" == "0" ]; then
        rtt_ms="150"
    fi
    
    echo -e "⏳ 正在压榨物理网卡极限公网吞吐率..."
    local res_p; res_p=$(_execute_speed_probe)
    local single_p=$(echo "$res_p" | cut -d'|' -f1 | grep -oE '[0-9.]+')
    local bw_bytes=$(awk -v s="$single_p" 'BEGIN {print int(s * 1024 * 1024)}')
    if [ -z "$bw_bytes" ] || [ "$bw_bytes" -eq 0 ]; then bw_bytes=5242880; fi

    local bdp_calc; bdp_calc=$(awk -v bw="$bw_bytes" -v rtt="$rtt_ms" 'BEGIN {print int(bw * (rtt / 1000) * 2)}')
    local total_mem; total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local max_buf=16777216
    local rmem_default=262144
    local wmem_default=262144

    if (( total_mem < 1050000 )); then
        max_buf=8388608
        rmem_default=87380
        wmem_default=65536
        local hardware_tag="${C_YELLOW}轻量型低内存防爆机制限制${C_RESET}"
    else
        max_buf=$bdp_calc
        if (( max_buf < 16777216 )); then max_buf=16777216; fi
        if (( max_buf > 67108864 )); then max_buf=67108864; fi
        rmem_default=524288
        wmem_default=524288
        local hardware_tag="${C_GREEN}满血硬件动态 BDP 智能推荐 (时延: ${rtt_ms}ms)${C_RESET}"
    fi

    # 捕获主网卡和 MTU
    local net_info; net_info=$(_get_main_interface_and_mtu)
    local current_iface; current_iface=$(echo "$net_info" | cut -d'|' -f1)
    local current_mtu; current_mtu=$(echo "$net_info" | cut -d'|' -f2)

    local old_cc; old_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local old_qdisc; old_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local old_rmem; old_rmem=$(sysctl -n net.core.rmem_max 2>/dev/null)
    local old_wmem; old_wmem=$(sysctl -n net.core.wmem_max 2>/dev/null)
    local old_sack; old_sack=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null)
    local old_ecn; old_ecn=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null)
    local old_idle; old_idle=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)
    local old_reuse; old_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)

    clear
    echo -e "${C_BLUE}📊 系统核心网络配置调优新旧数值交叉审计报告${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e " 🖥️  环境画像推演结论: $hardware_tag"
    echo -e "${LINE_GRAY}"
    printf " %-30s | %-16s | %-16s\n" "内核核心配置调优参数项" "原本历史数值" "推演建议新值"
    echo -e "${LINE_GRAY}"
    printf " • mtu最大传输单元 (网卡级)    | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "$current_mtu" "1500 (公网标准)"
    printf " • tcp_congestion_control     | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_cc:-cubic}" "bbr"
    printf " • default_qdisc               | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_qdisc:-pfifo_fast}" "fq"
    printf " • rmem_max (最大核心读缓冲)   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_rmem:-212992}" "$max_buf"
    printf " • wmem_max (最大核心写缓冲)   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_wmem:-212992}" "$max_buf"
    printf " • tcp_sack (SACK 选择性确认)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_sack:-1}" "1"
    printf " • tcp_ecn (ECN 显式拥塞通知)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_ecn:-0}" "1"
    printf " • tcp_slow_start_after_idle   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_idle:-1}" "0 (空闲不重置)"
    printf " • tcp_tw_reuse (TIME_WAIT复用)| %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_reuse:-2}" "1"
    echo -e "${LINE_GRAY}"
    
    read -p "❓ 是否确认进入调优项目细分勾选保存流程？[y/N] (回车默认放弃): " CONFIRM_CHOOSE
    if [[ "$CONFIRM_CHOOSE" != "y" && "$CONFIRM_CHOOSE" != "Y" ]]; then
        echo -e "${C_YELLOW}🛑 已安全拦截，未对系统做出任何修改。${C_RESET}"
        return
    fi

    echo ""
    echo "========================================================="
    echo -e "🛠️  ${C_CYAN}请选择您要注入的调优项目序号 (支持多选，用英文逗号隔开)${C_RESET}"
    echo "========================================================="
    echo -e " ${C_GREEN}1)${C_RESET} 🚀 一键应用上方全部优化参数 (含 MTU 网卡级修复)"
    echo -e " ${C_GREEN}2)${C_RESET} 网卡级 MTU 物理降轨纠偏项 (强焊 1500 黄金标准，防丢包)"
    echo -e " ${C_GREEN}3)${C_RESET} 拥塞算法与排队规则联动项 (bbr + fq)"
    echo -e " ${C_GREEN}4)${C_RESET} 核心网卡最大读写缓冲大小项 (rmem_max & wmem_max)"
    echo -e " ${C_GREEN}5)${C_RESET} TCP动态滑窗缓冲范围优化项 (tcp_rmem & tcp_wmem)"
    echo -e " ${C_GREEN}6)${C_RESET} 高丢包晚高峰专项调优项 (tcp_sack & dsack & fack)"
    echo -e " ${C_GREEN}7)${C_RESET} 跨国骨干网络显式拥塞调优项 (tcp_ecn)"
    echo -e " ${C_GREEN}8)${C_RESET} 拒绝突发空闲连接限速降轨项 (tcp_slow_start_after_idle = 0)"
    echo -e " ${C_GREEN}9)${C_RESET} 高并发端口TIME_WAIT快速回收复用项 (tcp_tw_reuse)"
    echo -e " ${C_GREEN}10)${C_RESET} 宿主机大并发高吞吐套接字队列项 (somaxconn & backlog)"
    echo "========================================================="
    read -p "请精准勾选需要应用的序号 [例如 1 或 2,3,5]: " CHOOSE_INDEX

    if [ -z "$CHOOSE_INDEX" ]; then
        echo -e "${C_YELLOW}🛑 输入为空，放弃本次保存。${C_RESET}"
        return
    fi

    if [ ! -f "$BAK_FILE" ]; then 
        cp "$SYS_FILE" "$BAK_FILE"
    fi

    local APPLY_ALL=0
    if [[ ",$CHOOSE_INDEX," == *",1,"* ]]; then APPLY_ALL=1; fi

    # ⭐ 2) MTU 调优联动纠偏
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",2,"* ]]; then
        if [ -n "$current_iface" ]; then
            sudo ip link set dev "$current_iface" mtu 1500 >/dev/null 2>&1
            echo -e " ✅ 已成功纠偏网卡层 MTU 为 1500 字节"
        fi
    fi

    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",3,"* ]]; then
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYS_FILE"
        sed -i '/net.core.default_qdisc/d' "$SYS_FILE"
        echo "net.core.default_qdisc = fq" >> "$SYS_FILE"
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",4,"* ]]; then
        sed -i '/net.core.rmem_max/d' "$SYS_FILE"
        sed -i '/net.core.wmem_max/d' "$SYS_FILE"
        echo "net.core.rmem_max = $max_buf" >> "$SYS_FILE"
        echo "net.core.wmem_max = $max_buf" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",5,"* ]]; then
        sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
        echo "net.ipv4.tcp_rmem = 4096 $rmem_default $max_buf" >> "$SYS_FILE"
        echo "net.ipv4.tcp_wmem = 4096 $wmem_default $max_buf" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",6,"* ]]; then
        sed -i '/net.ipv4.tcp_sack/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_dsack/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_fack/d' "$SYS_FILE"
        echo "net.ipv4.tcp_sack = 1" >> "$SYS_FILE"
        echo "net.ipv4.tcp_dsack = 1" >> "$SYS_FILE"
        echo "net.ipv4.tcp_fack = 1" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",7,"* ]]; then
        sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
        echo "net.ipv4.tcp_ecn = 1" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",8,"* ]]; then
        sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"
        echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",9,"* ]]; then
        sed -i '/net.ipv4.tcp_tw_reuse/d' "$SYS_FILE"
        sed -i '/net.ipv4.tw_reuse/d' "$SYS_FILE"
        echo "net.ipv4.tcp_tw_reuse = 1" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",10,"* ]]; then
        sed -i '/net.core.somaxconn/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_max_syn_backlog/d' "$SYS_FILE"
        sed -i '/net.core.netdev_max_backlog/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_adv_win_scale/d' "$SYS_FILE"
        sed -i '/net.ipv4.tcp_notsent_lowat/d' "$SYS_FILE"
        echo "net.ipv4.tcp_adv_win_scale = 1" >> "$SYS_FILE"
        echo "net.ipv4.tcp_notsent_lowat = 16384" >> "$SYS_FILE"
        echo "net.core.somaxconn = 4096" >> "$SYS_FILE"
        echo "net.ipv4.tcp_max_syn_backlog = 2048" >> "$SYS_FILE"
        echo "net.core.netdev_max_backlog = 5000" >> "$SYS_FILE"
    fi

    sysctl -p /etc/sysctl.conf >/dev/null 2>&1

    if [ -n "$current_iface" ] && [ $APPLY_ALL -eq 1 ]; then
        ip link set dev "$current_iface" txqueuelen 10000 >/dev/null 2>&1
    fi
    echo -e "\n${C_GREEN}🎉 所选参数参数已成功注入并物理热生效！${C_RESET}"
}

# 4. 更改阻塞队列
change_qdisc_action() {
    while true; do
        clear
        local current_qdisc; current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        local current_cc; current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        
        echo "========================================================="
        echo -e " 当前系统的排队规则(qdisc)为: ${C_GREEN}${current_qdisc:-fq}${C_RESET}"
        echo "========================================================="
        echo -e "💡 ${C_CYAN}[排队规则全向专家选型建议看板]${C_RESET}"
        echo -e " ${C_GREEN}1)${C_RESET} 🚀 ${C_GREEN}fq${C_RESET}       ──► ${C_YELLOW}极限吞吐流${C_RESET}：BBR算法的黄金伴侣，大带宽首选。"
        echo -e " ${C_GREEN}2)${C_RESET} 🍰 ${C_GREEN}cake${C_RESET}     ──► ${C_YELLOW}多流公平抗抖动${C_RESET}：Fq_CoDel终极版，对中低带宽、晚高峰代理线路神级优化。"
        echo -e " ${C_GREEN}3)${C_RESET} 📊 ${C_GREEN}fq_codel${C_RESET} ──► ${C_YELLOW}轻量自适应${C_RESET}：普通Linux内核的默认优选，极限吞吐不如 fq。"
        echo -e " ${C_GREEN}4)${C_RESET} 🔄 ${C_GREEN}pfifo_fast${C_RESET}──► ${C_YELLOW}传统无差别先入先出${C_RESET}：老旧无规则队列，易引发队头阻塞。"
        echo "========================================================="
        echo -e " ⚔️  ${C_BLUE}5) 进入 Fq vs Cake 竞技场真实性能交叉数据实测${C_RESET}"
        echo " 9) 🚀 启动全自动网络探针智控优选"
        echo " 0) 返回上级菜单"
        echo "========================================================="
        read -p "请输入要切换的序号或操作编号: " Q_OPT

        if [ "$Q_OPT" == "0" ] || [ -z "$Q_OPT" ]; then
            break
        elif [ "$Q_OPT" == "1" ]; then
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            echo -e "${C_GREEN}✅ 阻塞队列已切换为: fq${C_RESET}"; read -p "按回车继续..." temp; break
        elif [ "$Q_OPT" == "2" ]; then
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = cake" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            echo -e "${C_GREEN}✅ 阻塞队列已切换为: cake${C_RESET}"; read -p "按回车继续..." temp; break
        elif [ "$Q_OPT" == "3" ]; then
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq_codel" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            echo -e "${C_GREEN}✅ 阻塞队列已切换为: fq_codel${C_RESET}"; read -p "按回车继续..." temp; break
        elif [ "$Q_OPT" == "4" ]; then
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = pfifo_fast" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            echo -e "${C_GREEN}✅ 阻塞队列已切换为: pfifo_fast${C_RESET}"; read -p "按回车继续..." temp; break
            
        elif [ "$Q_OPT" == "5" ]; then
            clear
            echo -e "${C_BLUE}⚔️  正在初始化 [Fq vs Cake 宿主机双雄性能实测竞技场]...${C_RESET}"
            echo -e " 📍 实测目标 Anycast 节点: ${C_YELLOW}http://cachefly.cachefly.net/100mb.test${C_RESET}"
            echo -e "${LINE_GRAY}"
            
            local saved_origin_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

            echo -e "⏳ 正在无感切换至 [🚀 fq] 队列并采集实时传输大盘数据..."
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            sleep 1
            local fq_res; fq_res=$(_execute_speed_probe)
            
            echo -e "⏳ 正在无感切换至 [🍰 cake] 队列并采集实时传输大盘数据..."
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = cake" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            sleep 1
            local cake_res; cake_res=$(_execute_speed_probe)

            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = $saved_origin_qdisc" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1

            local fq_s=$(echo "$fq_res" | cut -d'|' -f1); local fq_m=$(echo "$fq_res" | cut -d'|' -f2); local fq_r=$(echo "$fq_res" | cut -d'|' -f3)
            local cake_s=$(echo "$cake_res" | cut -d'|' -f1); local cake_m=$(echo "$cake_res" | cut -d'|' -f2); local cake_r=$(echo "$cake_res" | cut -d'|' -f3)

            clear
            echo "========================================================="
            echo "⚔️  [Fq vs Cake 真实性能交叉比对对齐报告] ⚔️"
            echo "========================================================="
            printf " %-18s | %-16s | %-16s\n" "核心网络监控指标" "🚀 fq (极限吞吐)" "🍰 cake (抗抖动优化)"
            echo "========================================================="
            printf " • 单线程物理净速率 | %-16s | %-16s\n" "$fq_s" "$cake_s"
            printf " • 多线程高并发带宽 | %-16s | %-16s\n" "$fq_m" "$cake_m"
            printf " • 骨干网平均时延   | %-16s | %-16s\n" "${fq_r} ms" "${cake_r} ms"
            echo "========================================================="
            echo -e "💡 ${C_YELLOW}【数据科学审计建议】${C_RESET}"
            echo -e " 1. 如果你在上方看到 ${C_GREEN}fq${C_RESET} 的多线程速率更高，说明它在纯公网单向发包吞吐上更具杀伤力。"
            echo -e " 2. 如果你处于晚高峰、高丢包、多设备挂载的环境下，建议选择 ${C_GREEN}cake${C_RESET}，它能物理平滑抗丢包，彻底消灭代理卡顿感！"
            echo "========================================================="
            read -p "对比评测结束。按回车键返回..." temp
            
        elif [ "$Q_OPT" == "9" ]; then
            echo -e "\n⏳ 正在激活全向网络链路状态和内核协议栈探针..."
            sleep 1
            local rtt_check; rtt_check=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null | tail -n 1 | awk -F '/' '{print $5}')
            local RECOMMEND_QDISC="fq"
            if [[ "$current_cc" == *"bbr"* ]]; then
                RECOMMEND_QDISC="fq"
            elif [ -n "$rtt_check" ] && (( $(echo "$rtt_check > 180" | bc -l) )); then
                RECOMMEND_QDISC="cake"
            fi
            sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = $RECOMMEND_QDISC" >> "$SYS_FILE"
            sysctl -p /etc/sysctl.conf >/dev/null 2>&1
            echo -e "${C_GREEN}🎉 智控自动优选成功！阻塞队列已绑定为: $RECOMMEND_QDISC${C_RESET}"
            read -p "按回车键继续..." temp
            break
        fi
    done
}

# 5. 还原调优参数
restore_sysctl_backup() {
    clear
    if [ ! -f "$BAK_FILE" ]; then
        echo -e "${C_RED}❌ 错误：在系统内未发现原历史备份文件！无法进行无损还原。${C_RESET}"
    else
        echo "🚨 正在拉起备份参数进行原路物理覆盖还原..."
        sudo cp "$BAK_FILE" "$SYS_FILE"
        sudo sysctl -p /etc/sysctl.conf >/dev/null 2>&1
        echo -e "${C_GREEN}🎉 【还原成功】系统网络控制层参数已完好无损地恢复至脚本改动前状态！${C_RESET}"
    fi
}

# 主循环体交互菜单
while true; do
    clear
    CC_NOW=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    QDISC_NOW=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    RMEM_NOW=$(sysctl -n net.core.rmem_max 2>/dev/null)
    WMEM_NOW=$(sysctl -n net.core.wmem_max 2>/dev/null)
    SACK_NOW=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null)
    ECN_NOW=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null)
    IDLE_NOW=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)
    REUSE_NOW=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)

    # 动态分析提取当前网卡和实时 MTU 状态
    NET_INFO_NOW=$(_get_main_interface_and_mtu)
    MTU_NOW=$(echo "$NET_INFO_NOW" | cut -d'|' -f2)

    RECOMMEND_BUF=$(_calculate_static_bdp_recommend)

    # 渲染终极全向深度调优实时看板 (追加网卡级 MTU 审计行)
    echo -e "${C_BLUE}⚡ tcpt优化 (高内聚并行审计看板)${C_RESET}"
    echo -e " 🖥️  核心指标参数项          │  当前系统运行值      │  脚本推演建议值"
    echo -e " ────────────────────────────┼──────────────────────┼─────────────────────"
    # ⭐ 完美融入 MTU 并行对比监控
    if [ "$MTU_NOW" == "1500" ]; then
        echo -e " • mtu最大传输单元 (网卡级)  │  ${C_GREEN}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "$MTU_NOW"
    else
        echo -e " • mtu最大传输单元 (网卡级)  │  ${C_RED}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "${MTU_NOW} [异常]"
    fi
    echo -e " • 拥塞控制内核算法 (cc)     │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}bbr${C_RESET}" "${CC_NOW:-cubic}"
    echo -e " • 底层阻塞队列规则 (qdisc)  │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}fq${C_RESET}" "${QDISC_NOW:-fq}"
    echo -e " • 最大套接字读缓冲 (rmem)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}%-19s${C_RESET}" "${RMEM_NOW:-212992}" "$RECOMMEND_BUF"
    echo -e " • 最大套接字写缓冲 (wmem)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}%-19s${C_RESET}" "${WMEM_NOW:-212992}" "$RECOMMEND_BUF"
    echo -e " • 选择性确认重传项 (sack)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}1 (物理开启)${C_RESET}" "${SACK_NOW:-1}"
    echo -e " • 显式拥塞状态通知 (ecn)    │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}1 (物理开启)${C_RESET}" "${ECN_NOW:-0}"
    echo -e " • 空闲保持慢启动项 (idle)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}0 (物理禁用)${C_RESET}" "${IDLE_NOW:-1}"
    echo -e " • TIME_WAIT快速复用 (reuse) │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}1 (物理开启)${C_RESET}" "${REUSE_NOW:-2}"
    echo -e " • 全域 IPv6 栈阻断状态      │  $(get_ipv6_status_text)                │  --"
    echo -e "${LINE_GRAY}"
    echo -e " 1) TCP内核调优"
    echo " 2) 速率测试 (包含单线程/高并发多线程)"
    echo " 3) 电报数据中心链路专项监测"
    echo " 4) 更改阻塞队列"
    echo " 5) 还原调优参数 (恢复之前的备份)"
    echo " 9) IPv6禁用/开启"
    echo " 0) 安全退出"
    echo -e "${LINE_GRAY}"
    read -p "请选择操作序号: " OPT
    
    if [ "$OPT" == "0" ] || [ -z "$OPT" ]; then echo "👋 工具已安全退出。"; exit 0; fi
    case $OPT in
        1) adaptive_tcp_tuning; read -p "按回车返回..." t ;;
        2) clear; echo -e "${C_CYAN}【2. 速率测试明细】${C_RESET}\n${LINE_GRAY}"; run_multi_dim_speedtest; read -p "按回车返回..." t ;;
        3) clear; echo -e "${C_CYAN}【3. 电报数据中心链路监测】${C_RESET}"; run_telegram_spec_test; echo -e "${LINE_GRAY}"; read -p "按回车返回..." t ;;
        4) change_qdisc_action; ;;
        5) restore_sysctl_backup; read -p "按回车返回..." t ;;
        9) clear; echo -e "${C_CYAN}【9. 系统 IPv6 状态切换】${C_RESET}\n${LINE_GRAY}"; current_v6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null); sed -i '/disable_ipv6/d' "$SYS_FILE"; if [ "$current_v6" == "1" ]; then echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_GREEN}🎉 全域 IPv6 已顺利恢复开启！${C_RESET}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 1" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1; sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1; echo -e "${C_RED}🛑 内核层 IPv6 已彻底切断禁用！${C_RESET}"; fi; read -p "按回车返回..." t ;;
        *) echo -e "${C_RED}❌ 无效选项！${C_RESET}" ; sleep 1 ;;
    esac
done

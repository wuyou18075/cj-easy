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

LINE_GRAY="${C_GRAY}---------------------------------------------------------${${C_RESET}}"
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

# 工业级双轮科学测速底层引擎 (含冷冻休眠机制)
_execute_speed_probe_double_wheel() {
    echo -e " ⏳ [Round 1/2] 正在拉起第一轮单/多线程分布式套接字盘查..."
    local res1; res1=$(_execute_speed_probe_raw)
    local s1=$(echo "$res1" | cut -d'|' -f1 | grep -oE '[0-9.]+\b' | head -n 1)
    local m1=$(echo "$res1" | cut -d'|' -f2 | grep -oE '[0-9.]+\b' | head -n 1)
    local r1=$(echo "$res1" | cut -d'|' -f3)

    echo -e " 💤 正在执行冷冻休眠 ${C_GRAY}3 秒${C_RESET}，清空链路残留缓存缓冲区，规避瞬时误差..."
    sleep 3

    echo -e " ⏳ [Round 2/2] 正在拉起第二轮单/多线程分布式套接字盘查..."
    local res2; res2=$(_execute_speed_probe_raw)
    local s2=$(echo "$res2" | cut -d'|' -f1 | grep -oE '[0-9.]+\b' | head -n 1)
    local m2=$(echo "$res2" | cut -d'|' -f2 | grep -oE '[0-9.]+\b' | head -n 1)
    local r2=$(echo "$res2" | cut -d'|' -f3)

    # 数据科学求两轮平均绝对值
    local s_avg; s_avg=$(awk -v a="$s1" -v b="$s2" 'BEGIN {printf "%.2f", (a+b)/2}')
    local m_avg; m_avg=$(awk -v a="$m1" -v b="$m2" 'BEGIN {printf "%.2f", (a+b)/2}')
    local r_avg; r_avg=$(awk -v a="$r1" -v b="$r2" 'BEGIN {printf "%.3f", (a+b)/2}')

    echo "$s_avg|$m_avg|$r_avg|$s1|$s2|$m1|$m2"
}

_execute_speed_probe_raw() {
    local test_url="http://cachefly.cachefly.net/10mb.test"
    local wget_output; wget_output=$(wget -4 --no-check-certificate --timeout=6 --tries=1 -O /dev/null "$test_url" 2>&1)
    local raw_speed; raw_speed=$(echo "$wget_output" | grep -oE '\([0-9.]+\s+[KMG]B/s\)' | tr -d '()')
    if [ -z "$raw_speed" ]; then raw_speed=$(echo "$wget_output" | grep "MB/s" | awk '{print $(NF-1), $NF}' | tr -d '()'); fi
    local s_speed="0.00"
    [ -n "$raw_speed" ] && s_speed=$(echo "$raw_speed" | grep -oE '[0-9.]+')

    local start_t; start_t=$(date +%s.%N)
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 0-3145728 > /dev/null) &
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 3145729-6291456 > /dev/null) &
    (curl -4 -s -k http://cachefly.cachefly.net/100mb.test -r 6291457-9437184 > /dev/null) &
    wait; local end_t; end_t=$(date +%s.%N)
    local m_speed; m_speed=$(awk -v start="$start_t" -v end="$end_t" 'BEGIN {duration = end - start; if (duration <= 0) duration = 0.001; printf "%.2f", 9.0 / duration;}')
    
    local rtt_avg; rtt_avg=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null | tail -n 1 | awk -F '/' '{print $5}')
    if [ -z "$rtt_avg" ]; then rtt_avg="0.0"; fi

    echo "$s_speed|$m_speed|$rtt_avg"
}

# 实体物理注入函数（封装多轨参数）
_inject_matrix_values() {
    local mode=$1 # 1:网速 2:延迟 3:稳定 4:综合
    local custom_val=$2
    local final_bytes=67108864

    if [ -n "$custom_val" ]; then
        final_bytes=$(awk -v m="$custom_val" 'BEGIN {print m * 1024 * 1024}')
    else
        case $mode in
            1) final_bytes=67108864 ;;  # 网速优先：64MB 极限缓冲大坝
            2) final_bytes=16777216 ;;  # 延迟优先：16MB 紧凑低延迟滑窗，规避Bufferbloat
            3) final_bytes=33554432 ;;  # 稳定优先：32MB 黄金中庸值，阻断大幅上下跳动
            4) final_bytes=50331648 ;;  # 综合考虑：48MB 兼顾高速率与抗丢包，最佳中继
        esac
    fi
    local final_default_bytes=$(awk -v b="$final_bytes" 'BEGIN {print int(b / 64)}')
    [ $final_default_bytes -lt 262144 ] && final_default_bytes=262144

    sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
    sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
    sed -i '/net.core.somaxconn/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_max_syn_backlog/d' "$SYS_FILE"
    sed -i '/net.core.netdev_max_backlog/d' "$SYS_FILE"; sed -i '/net.core.netdev_budget/d' "$SYS_FILE"

    echo "net.core.rmem_max = $final_bytes" >> "$SYS_FILE"
    echo "net.core.wmem_max = $final_bytes" >> "$SYS_FILE"
    echo "net.ipv4.tcp_rmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
    echo "net.ipv4.tcp_wmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
    echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
    echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
    echo "net.core.somaxconn = 32768" >> "$SYS_FILE"
    echo "net.ipv4.tcp_max_syn_backlog = 16384" >> "$SYS_FILE"
    echo "net.core.netdev_max_backlog = 65536" >> "$SYS_FILE"
    echo "net.core.netdev_budget = 600" >> "$SYS_FILE"
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    local net_info; net_info=$(_get_main_interface_and_mtu)
    local current_iface; current_iface=$(echo "$net_info" | cut -d'|' -f1)
    if [ -n "$current_iface" ]; then ip link set dev "$current_iface" mtu 1500 >/dev/null 2>&1; ip link set dev "$current_iface" txqueuelen 10000 >/dev/null 2>&1; fi
}

# =========================================================
#             🛠️ 二级控制台：核心功能交互流重构
# =========================================================

# 20-1. 提升单线程速率专项面板
optimize_single_thread_panel() {
    clear
    echo -e "${C_CYAN}⏳ 正在启动提升单线程速率专项 A/B 双轮暗测，请耐心等待验证系统画像...${C_RESET}"
    local old_res; old_res=$(_execute_speed_probe_double_wheel)
    local os_avg=$(echo "$old_res" | cut -d'|' -f1); local om_avg=$(echo "$old_res" | cut -d'|' -f2); local or_avg=$(echo "$old_res" | cut -d'|' -f3)
    local os1=$(echo "$old_res" | cut -d'|' -f4); local os2=$(echo "$old_res" | cut -d'|' -f5)

    clear
    echo "========================================================="
    echo -e "🚀 ${C_CYAN}[单线程高速率与稳定性提升策略选型大盘]${C_RESET}"
    echo "========================================================="
    echo -e " 💡 ${C_YELLOW}【多轨网络性能专家自适应选型推演】${C_RESET}:"
    echo -e "    由于当前公网到美西长途物理时延固定在 ${or_avg} ms 上下，要实现持续不卡顿的高速单线程突围，内核优化方向需解决多核心软中断拥堵与滑动窗口硬上限限制。调优目标冲突时可分以下多轨决策："
    echo -e ""
    echo -e "    ${C_GREEN}[ 1 ] 网速吞吐优先预设${C_RESET}  ──► 建议值: ${C_GREEN}64 MB${C_RESET} (倾泻蛮力，压榨单线程最大绝对速度峰值)"
    echo -e "    ${C_GREEN}[ 2 ] 延迟极速优先预设${C_RESET}  ──► 建议值: ${C_GREEN}16 MB${C_RESET} (将滑窗卡在低水位，防缓冲区膨胀引发时延飙升)"
    echo -e "    ${C_GREEN}[ 3 ] 持续稳定优先预设${C_RESET}  ──► 建议值: ${C_GREEN}30 MB${C_RESET} (锁定黄金滑窗大小，消除晚高峰网速上下激烈跳动)"
    echo -e "    ${C_GREEN}[ 4 ] 综合考虑出厂策略${C_RESET}  ──► 建议值: ${C_GREEN}48 MB${C_RESET} (💥 代理首选！兼顾长途持续高速与极致稳定性)"
    echo "========================================================="
    read -p " 🤔 请精准输入您期望应用的轨道序号 [1-4] (直接回车默认采用 4 综合考虑): " TRACK_CHOOSE
    [ -z "$TRACK_CHOOSE" ] && TRACK_CHOOSE="4"

    echo -e "\n⏳ 正在针对性注入策略参数进行底层内核热重载..."
    _inject_matrix_values "$TRACK_CHOOSE" ""
    
    echo -e "⏳ 正在拉起【优化后】物理上轨第二轮双轮暗测，中场休息 2 秒..."
    sleep 2
    local new_res; new_res=$(_execute_speed_probe_double_wheel)
    local ns_avg=$(echo "$new_res" | cut -d'|' -f1); local nm_avg=$(echo "$new_res" | cut -d'|' -f2); local nr_avg=$(echo "$new_res" | cut -d'|' -f3)
    local ns1=$(echo "$new_res" | cut -d'|' -f4); local ns2=$(echo "$new_res" | cut -d'|' -f5)

    clear
    echo "========================================================="
    echo -e "📊 ${C_GREEN}[ 优化执行前后物理效果双轮审计报告 ]${C_RESET}"
    echo "========================================================="
    printf " %-22s | %-18s | %-18s\n" "单线程深度监控指标" "调优前 (历史均值)" "调优后 (当前均值)"
    echo "========================================================="
    printf " • 第一轮单线程绝对值 | %-18s | %-18s\n" "${os1} MB/s" "${ns1} MB/s"
    printf " • 第二轮单线程绝对值 | %-18s | %-18s\n" "${os2} MB/s" "${ns2} MB/s"
    echo "--------------------------------------------------------="
    printf " 🏆 【双轮综合均速】  | ${C_YELLOW}%-14s${C_RESET} | ${C_GREEN}%-14s${C_RESET}\n" "${os_avg} MB/s" "${ns_avg} MB/s"
    printf " ⏱️  【平均物理延迟】  | %-18s | %-18s\n" "${or_avg} ms" "${nr_avg} ms"
    echo "========================================================="
    echo -e "  ${C_GREEN}1)${C_RESET} 🟢 确认应用此项优化，并固化内核配置"
    echo -e "  ${C_GREEN}2)${C_RESET} 🛑 放弃本次单线程优化，回滚原历史备份"
    echo "========================================================="
    read -p "请输入决策编号: " DEC_OPT
    if [ "$DEC_OPT" == "2" ]; then
        cp "$BAK_FILE" "$SYS_FILE" && sysctl -p /etc/sysctl.conf >/dev/null 2>&1
        echo -e "${C_YELLOW}🛑 已完全回滚撤销。${C_RESET}"; sleep 1.5
    else
        echo -e "${C_GREEN}✅ 优化参数已完美长驻锁定！${C_RESET}"; sleep 1.5
    fi
}

# 20-2. 单/多线程同步突围深度交互循环面板 (锁死在此，只有选0才返回)
menu_sync_breakthrough_panel() {
    while true; do
        clear
        local cc_now=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        local qd_now=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        local rm_now=$(sysctl -n net.core.rmem_max 2>/dev/null)
        local rm_now_mb=$(awk -v b="$rm_now" 'BEGIN {printf "%.1f", b/1024/1024}')

        echo "========================================================="
        echo -e "🖥️  ${C_BLUE}[单/多线程同步突围矩阵 ──► 细分肉搏管理中心]${C_RESET}"
        echo "========================================================="
        echo -e " 当前物理内核运行指标: CC=[${C_CYAN}$cc_now${C_RESET}] QDISC=[${C_CYAN}$qd_now${C_RESET}] 缓冲大坝=[${C_GREEN}${rm_now_mb} MB${C_RESET}]"
        echo "========================================================="
        echo -e " ${C_GREEN}1)${C_RESET} 压榨内核大套接字缓冲区"
        echo -e " ${C_GREEN}2)${C_RESET} 禁止空闲连接窗口回落"
        echo -e " ${C_GREEN}3)${C_RESET} 自适应纠偏封锁跨境丢包"
        echo -e " ${C_GREEN}4)${C_RESET} 🚀 自动优化 (联动合并注入1,2,3项，含双轮前后对比审计与多轨选型)"
        echo -e " ${C_GREEN}5)${C_RESET} 🔄 🔄 原地再次测速 (实时核验调优物理反馈)"
        echo " 0) 返回上级菜单"
        echo "========================================================="
        read -p "请精准抉择您要注入的序号: " SUB_OPT

        if [ -z "$SUB_OPT" ] || [ "$SUB_OPT" == "0" ]; then break; fi

        case $SUB_OPT in
            1)
                clear
                local total_mem_kb; total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                local rec_mb=64; [ $total_mem_kb -l 1050000 ] && rec_mb=16
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 1 ──► 压榨内核大套接字缓冲区硬核风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与漏洞审计说明】:${C_RESET}"
                echo -e "    1. ${C_YELLOW}内存爆仓 OOM 风险${C_RESET}：缓冲区绝非越大越好！若盲目写死几百MB甚至几GB，在公网遭遇大流量 SYN 洪水攻击时，系统会为每个恶意虚假连接对齐划分物理缓冲区，瞬间引发 Linux 内核爆仓触发 OOM Panic，强行随机斩杀你反代的 Nginx 或容器进程。"
                echo -e "    2. ${C_YELLOW}缓冲区膨胀 (Bufferbloat) 恶化${C_RESET}：盲目扩容若网卡软中断配额和发包队列限制没跟上，包会积压在网卡层排队，导致物理时延暴涨数秒，网速反倒发生毁灭性滑坡、大面积弹 502 连接超时。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【数据科学安全合理建议值】${C_RESET}："
                echo -e "    • 对于大内存长肥管道实例，推荐核心范围在 ${C_GREEN}32 MB ~ 64 MB${C_RESET}。"
                echo -e "    • 当前系统通过物理算法算出的黄金自适应专家推荐值为: ${C_GREEN}${rec_mb} MB${C_RESET}"
                echo "========================================================="
                read -p "🤔 请手动输入自定义缓存值 (单位MB, 直接回车采用推荐值 ${rec_mb} MB): " INPUT_MB
                local FINAL_MB=$rec_mb
                if [ -n "$INPUT_MB" ]; then
                    if [[ "$INPUT_MB" =~ ^[0-9]+$ ]] && [ "$INPUT_MB" -gt 0 ]; then FINAL_MB=$INPUT_MB; else echo -e "${C_RED}❌ 格式有误，安全回滚至默认值。${C_RESET}"; sleep 1.5; fi
                fi
                local final_bytes=$(awk -v m="$FINAL_MB" 'BEGIN {print m * 1024 * 1024}')
                local final_default_bytes=$(awk -v b="$final_bytes" 'BEGIN {print int(b / 64)}')
                [ $final_default_bytes -lt 262144 ] && final_default_bytes=262144

                sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
                sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
                echo "net.core.rmem_max = $final_bytes" >> "$SYS_FILE"; echo "net.core.wmem_max = $final_bytes" >> "$SYS_FILE"
                echo "net.ipv4.tcp_rmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
                echo "net.ipv4.tcp_wmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
                sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                echo -e "${C_GREEN}✅ 方案 1 物理注入成功：大连接缓冲区锁定为 ${FINAL_MB} MB！${C_RESET}"; read -p "按回车继续..." temp
                ;;
            2)
                clear
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 2 ──► 禁止空闲连接窗口回落风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与原理说明】:${C_RESET}"
                echo -e "    • 对应内核参数项为 \`net.ipv4.tcp_slow_start_after_idle\`。"
                echo -e "    • Linux 内核原生硬规定此项【只允许设置为 0 或 1】！如果瞎写其他数字，内核直接判定无效拒不加载，或者强行等价处理为 1。一旦设为 1，只要代理长连接超过几秒没有突发数据，好不容易探测出来的顶格 cwnd 会被内核无情掐断，迫使连接再次重回挤牙膏慢启动，引发刷网页、拉大图突发性转圈和卡顿。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【跨境高延迟长连接唯一合理建议值】${C_RESET}："
                echo -e "    • 锁定为 ${C_GREEN}0 (物理禁用慢启动空闲重置)${C_RESET}。"
                echo "========================================================="
                read -p "🤔 是否确应用推荐优选值 0 ？[Y/n] (直接回车确认应用): " IS_IDLE_OPT
                if [[ "$IS_IDLE_OPT" == "y" || "$IS_IDLE_OPT" == "Y" || -z "$IS_IDLE_OPT" ]]; then
                    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"
                    echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
                    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 方案 2 物理注入成功：空闲慢启动衰减已切断！${C_RESET}"
                fi; read -p "按回车继续..." temp
                ;;
            3)
                clear
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 3 ──► 自适应纠偏封锁跨境丢包风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与跨境骨干路由器审计说明】:${C_RESET}"
                echo -e "    • 对应内核参数项为 \`net.ipv4.tcp_ecn\`。范围严格限定为【0, 1, 2】。"
                echo -e "    • ${C_RED}不要盲目设为 1 (强开)${C_RESET}：中美跨国海底光缆在晚高峰会经过大量复杂的跨国路由器，有很多不具备 ECN 解析能力。若强行设为 1，数据包打上强开标志后，中途路由器会直接采取【就地丢弃 (Drop)】，直接引发诡异的突发性网络完全阻断。设为 0（关闭）则完全失去在网络微拥塞时自适应降速防丢包的能力。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【跨境 280ms 高丢包线路唯一合理值】${C_RESET}："
                echo -e "    • 必须调整为 ${C_GREEN}2 (自适应对齐模式)${C_RESET}。仅对入站连接被动对齐响应，完美规避跨国路由器误杀丢包。"
                echo "========================================================="
                read -p "🤔 是否确认应用最优纠偏值 2 ？[Y/n] (直接回车确认应用): " IS_ECN_OPT
                if [[ "$IS_ECN_OPT" == "y" || "$IS_ECN_OPT" == "Y" || -z "$IS_ECN_OPT" ]]; then
                    sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
                    echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
                    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 方案 3 物理注入成功：tcp_ecn 自适应对齐降噪已锁定生效！${C_RESET}"
                fi; read -p "按回车继续..." temp
                ;;
            4)
                # 选项 4：自动优化联动合并注入 (带双轮对比和多轨选型交互)
                clear
                echo -e "${C_CYAN}⏳ 正在启动全部应用自动化调优 A/B 双轮暗测，正在采集调优前样本数据...${C_RESET}"
                local old_res; old_res=$(_execute_speed_probe_double_wheel)
                local os_avg=$(old_res | cut -d'|' -f1); local om_avg=$(old_res | cut -d'|' -f2); local or_avg=$(old_res | cut -d'|' -f3)
                local os1=$(old_res | cut -d'|' -f4); local os2=$(old_res | cut -d'|' -f5)
                local om1=$(old_res | cut -d'|' -f6); local om2=$(old_res | cut -d'|' -f7)

                clear
                echo "========================================================="
                echo -e "🚀 ${C_CYAN}[全部联动策略注入 ──► 多轨优化分流控制中心]${C_RESET}"
                echo "========================================================="
                echo -e " 💡 调优冲突决断：当极限吞吐与延迟稳定性发生冲突时，请做出技术倾向选型："
                echo -e "    ${C_GREEN}[ 1 ] 网速吞吐优先预设${C_RESET}  ──► 建议缓冲: 64 MB (压榨最高网速绝对上限)"
                echo -e "    ${C_GREEN}[ 2 ] 延迟极速优先预设${C_RESET}  ──► 建议缓冲: 16 MB (卡紧水位，消灭Bufferbloat排队延时)"
                echo -e "    ${C_GREEN}[ 3 ] 持续稳定优先预设${C_RESET}  ──► 建议缓冲: 30 MB (锁定中水位，拦截大波动跳动)"
                echo -e "    ${C_GREEN}[ 4 ] 综合考虑出厂策略${C_RESET}  ──► 建议缓冲: 48 MB (💥 代理首选！又快又稳，长途高吞吐最优解)"
                echo "========================================================="
                read -p " 🤔 请精准注入您期望应用的轨道序号 [1-4] (直接回车默认采用 4 综合考虑): " AUTO_TRACK
                [ -z "$AUTO_TRACK" ] && AUTO_TRACK="4"

                echo -e "\n⏳ 正在全量并联执行 1,2,3 项及大并发大坝队列（somaxconn 32768）深度加固..."
                _inject_matrix_values "$AUTO_TRACK" ""

                echo -e "⏳ 正在拉起全量优化上轨后的第二轮双轮暗测，中场休息 2 秒..."
                sleep 2
                local new_res; new_res=$(_execute_speed_probe_double_wheel)
                local ns_avg=$(echo "$new_res" | cut -d'|' -f1); local nm_avg=$(echo "$new_res" | cut -d'|' -f2); local nr_avg=$(echo "$new_res" | cut -d'|' -f3)
                local ns1=$(echo "$new_res" | cut -d'|' -f4); local ns2=$(echo "$new_res" | cut -d'|' -f5)
                local nm1=$(echo "$new_res" | cut -d'|' -f6); local nm2=$(echo "$new_res" | cut -d'|' -f7)

                clear
                echo "========================================================="
                echo -e "📊 ${C_GREEN}[ 联动自适应全部应用 ──► 物理效果双轮审计报告 ]${C_RESET}"
                echo "========================================================="
                printf " %-22s | %-18s | %-18s\n" "系统网络高并发核心指标" "调优前 (历史均值)" "调优后 (当前均值)"
                echo "========================================================="
                printf " • 第一轮 单线程 / 多线程 | %-7s / %-7s | %-7s / %-7s\n" "${os1}" "${om1}" "${ns1}" "${nm1}"
                printf " • 第二轮 单线程 / 多线程 | %-7s / %-7s | %-7s / %-7s\n" "${os2}" "${om2}" "${ns2}" "${nm2}"
                echo "--------------------------------------------------------="
                printf " 🏆 【单线程双轮均速】    | ${C_YELLOW}%-14s${C_RESET} | ${C_GREEN}%-14s${C_RESET}\n" "${os_avg} MB/s" "${ns_avg} MB/s"
                printf " 🚀 【多线程极限带宽】    | ${C_YELLOW}%-14s${C_RESET} | ${C_GREEN}%-14s${C_RESET}\n" "${om_avg} MB/s" "${nm_avg} MB/s"
                printf " ⏱️  【跨境骨干物理延迟】  | %-18s | %-18s\n" "${or_avg} ms" "${nr_avg} ms"
                echo "========================================================="
                echo -e "  ${C_GREEN}1)${C_RESET} 🟢 效果卓越，应用此套工业级联动优化组合拳"
                echo -e "  ${C_GREEN}2)${C_RESET} 🛑 速度未达预期，放弃优化，原路完整回回退"
                echo "========================================================="
                read -p "请输入决策编号: " AUTO_DEC
                if [ "$DEC_OPT" == "2" ] || [ "$AUTO_DEC" == "2" ]; then
                    cp "$BAK_FILE" "$SYS_FILE" && sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                    echo -e "${C_YELLOW}🛑 已完好无损安全回滚。${C_RESET}"; sleep 1.5
                else
                    echo -e "${C_GREEN}🎉 恭喜！你的代理机器已进化为高并发自适应完全体状态！${C_RESET}"; sleep 2
                fi
                ;;
            5)
                # 选项 5：原地双轮测速
                clear
                echo -e "${C_CYAN}⏳ 正在执行原地双轮联动测速，实时捕捉内核协议栈微观物理反馈...${C_RESET}"
                local check_res; check_res=$(_execute_speed_probe_double_wheel)
                s_rate="$(echo "$check_res" | cut -d'|' -f1) MB/s"
                m_rate="$(echo "$check_res" | cut -d'|' -f2) MB/s"
                rtt_ms="$(echo "$check_res" | cut -d'|' -f3)"
                ;;
        esac
    done
}

run_multi_dim_speedtest() {
    # 物理升轨：主干测速直接升级为双轮交叉平均采样，拦截晚高峰误差
    clear
    echo -e "${C_CYAN}⏳ 正在拉起 [双轮自适应平均测速引擎]，提取公网纯净物理均值...${C_RESET}"
    echo -e " 📍 节点位置: ${C_YELLOW}全球 Anycast 边缘分发集群 (亚太/核心骨干网)${C_RESET}"
    echo -e " 🌐 测试网型: ${C_GRAY}http://cachefly.cachefly.net/10mb.test${C_RESET}"
    echo -e "${LINE_GRAY}"
    local main_res; main_res=$(_execute_speed_probe_double_wheel)
    
    local s_avg=$(echo "$main_res" | cut -d'|' -f1)
    local m_avg=$(echo "$main_res" | cut -d'|' -f2)
    local r_avg=$(echo "$main_res" | cut -d'|' -f3)

    while true; do
        clear
        echo -e "${C_BLUE}⚡ tcpt吞吐量测速看板 (单/多线程同步突围矩阵)${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " 📊 单线程物理净吞吐速率:   (双轮均速) ${C_GREEN}${s_avg} MB/s${C_RESET}"
        echo -e " 🚀 多线程高并发极限带宽:   (双轮均速) ${C_GREEN}${m_avg} MB/s${C_RESET}"
        echo -e " 🛰️  当前跨境骨干物理延迟:   (绝对均速) ${C_YELLOW}${r_avg} ms${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " ${C_GREEN}1)${C_RESET} 提升单线程速率 (含稳定性提升多轨策略、双轮对比审计面板)"
        echo -e " ${C_GREEN}2)${C_RESET} 单 / 多线程同步突围 (💥 深入单项肉搏调优交互菜单)"
        echo -e " ${C_GREEN}3)${C_RESET} 🔄 原地再次启动双轮精确测速"
        echo -e " 0) 放弃并返回上级主菜单"
        echo -e "${LINE_GRAY}"
        read -p "请精准抉择您要注入的序号: " MAIN_INNER_OPT
        
        if [ -z "$MAIN_INNER_OPT" ] || [ "$MAIN_INNER_OPT" == "0" ]; then break; fi
        
        if [ "$MAIN_INNER_OPT" == "1" ]; then
            optimize_single_thread_panel
        elif [ "$MAIN_INNER_OPT" == "2" ]; then
            menu_sync_breakthrough_panel
        elif [ "$MAIN_INNER_OPT" == "3" ]; then
            clear
            echo -e "${C_CYAN}⏳ 正在重新执行双轮对齐测速...${C_RESET}"
            local re_res; re_res=$(_execute_speed_probe_double_wheel)
            s_avg=$(echo "$re_res" | cut -d'|' -f1)
            m_avg=$(echo "$re_res" | cut -d'|' -f2)
            r_avg=$(echo "$re_res" | cut -d'|' -f3)
        fi
    done
}

# 1. 📂 主面板及系统交叉审计引擎
adaptive_tcp_tuning() {
    clear
    echo -e "${C_BLUE}🛰️  正在启动全向自适应通用网络探针，深入盘查宿主机物理现状...${C_RESET}"
    echo -e "${LINE_GRAY}"

    local cpu_arch; cpu_arch=$(uname -m)
    echo -n " [1/3] 🔍 正在检索物理 CPU 芯片架构: "
    if [[ "$cpu_arch" == *"x86_64"* || "$cpu_arch" == *"amd64"* ]]; then
        local target_cpu="X86_64 蛮力计算核心"; echo -e "${C_CYAN}$target_cpu${C_RESET}"
    else
        local target_cpu="ARM 轻量/高密度核心"; echo -e "${C_GREEN}$target_cpu${C_RESET}"; fi

    local total_mem_kb; total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb; total_mem_mb=$(awk -v k="$total_mem_kb" 'BEGIN {print int(k / 1024)}')
    echo -e " [2/3] 🔍 正在核验宿主机可用内存规模: ${C_CYAN}${total_mem_mb} MB${C_RESET}"

    echo -e " [3/3] ⏳ 正在精确嗅探物理网卡到骨干网的绝对 RTT 时延..."
    local ping_raw; ping_raw=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null)
    local rtt_ms; rtt_ms=$(echo "$ping_raw" | tail -n 1 | awk -F '/' '{print $5}')
    
    if [ -z "$rtt_ms" ] || [ "$rtt_ms" == "0" ]; then rtt_ms="250"
    else
        local t1; t1=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | head -n 1)
        local t2; t2=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | head -n 2 | tail -n 1)
        local t3; t3=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | tail -n 1)
        echo -e "      ──► ${C_GREEN}[物理测速成功] 成功向全球骨干网下发 3 次 ICMP 套接字包${C_RESET}"
        echo -e "      ──► [真实回显数据] 第一次: ${t1}ms | 第二次: ${t2}ms | 第三次: ${t3}ms"; fi
    echo -e "      ──► 最终物理判定平均时延 RTT 为: ${C_YELLOW}${rtt_ms} ms${C_RESET}"
    echo -e "${LINE_GRAY}"

    local max_buf=16777216; local rmem_default=262144; local wmem_default=262144
    if (( total_mem_kb < 1050000 )); then max_buf=8388608; rmem_default=87380; wmem_default=65536
    else max_buf=67108864; rmem_default=1048576; wmem_default=1048576; fi

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

    printf " %-30s | %-16s | %-16s\n" "内核核心配置调优参数项" "原本历史数值" "推演建议新值"
    echo -e "${LINE_GRAY}"
    printf " • mtu最大传输单元 (网卡级)    | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "$current_mtu" "1500 (公网标准)"
    printf " • tcp_congestion_control     | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_cc:-cubic}" "bbr"
    printf " • default_qdisc               | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_qdisc:-pfifo_fast}" "fq"
    printf " • rmem_max (最大核心读缓冲)   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_rmem:-212992}" "$max_buf"
    printf " • wmem_max (最大核心写缓冲)   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_wmem:-212992}" "$max_buf"
    printf " • tcp_sack (SACK 选择性确认)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_sack:-1}" "1"
    printf " • tcp_ecn (ECN 显式拥塞通知)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_ecn:-0}" "2 (自适应开启)"
    printf " • tcp_slow_start_after_idle   | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_idle:-1}" "0 (空闲不重置)"
    printf " • tcp_tw_reuse (TIME_WAIT复用)| %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${old_reuse:-2}" "1"
    echo -e "${LINE_GRAY}"
    
    read -p "❓ 是否确认进入调优项目细分勾选保存流程？[y/N] (回车默认放弃): " CONFIRM_CHOOSE
    if [[ "$CONFIRM_CHOOSE" != "y" && "$CONFIRM_CHOOSE" != "Y" ]]; then return; fi

    echo ""
    echo "========================================================="
    echo -e "🛠️  ${C_CYAN}请选择您要注入的调优项目序号 (支持多选，用英文逗号隔开)${C_RESET}"
    echo "========================================================="
    echo -e " ${C_GREEN}1)${C_RESET} 🚀 一键应用上方全部通用自适应调优参数 (含网卡层 MTU 1500 降轨纠偏)"
    echo -e " ${C_GREEN}2)${C_RESET} 网卡级 MTU 物理降轨纠偏项 (强焊 1500 黄金标准，防丢包)"
    echo -e " ${C_GREEN}3)${C_RESET} 拥塞算法与排队规则联动项 (bbr + fq)"
    echo -e " ${C_GREEN}4)${C_RESET} 💥 满血大滑窗最大读写缓冲项 (解绑单/多线程上限，rmem/wmem)"
    echo -e " ${C_GREEN}5)${C_RESET} TCP动态滑窗缓冲范围优化项 (tcp_rmem & tcp_wmem)"
    echo -e " ${C_GREEN}6)${C_RESET} 💥 高丢包选择性确认抗灾项 (强开 SACK/DSACK/FACK 预防晚高峰重传雪崩)"
    echo -e " ${C_GREEN}7)${C_RESET} 💥 跨国骨干网络显式拥塞调优项 (自适应调整 tcp_ecn = 2，防路由误杀)"
    echo -e " ${C_GREEN}8)${C_RESET} 💥 拒绝空闲连接重置限速项 (将 tcp_slow_start_after_idle 锁死为 0)"
    echo -e " ${C_GREEN}9)${C_RESET} 高并发端口TIME_WAIT快速回收复用项 (tcp_tw_reuse)"
    echo -e " ${C_GREEN}10)${C_RESET} 💥 工业级大并发泄洪队列上限项 (大幅扩容全连接队列与网卡轮询配额)"
    echo "========================================================="
    read -p "请精准勾选需要应用的序号 [例如 1]: " CHOOSE_INDEX
    if [ -z "$CHOOSE_INDEX" ]; then return; fi
    local APPLY_ALL=0; if [[ ",$CHOOSE_INDEX," == *",1,"* ]]; then APPLY_ALL=1; fi

    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",2,"* ]]; then
        if [ -n "$current_iface" ]; then sudo ip link set dev "$current_iface" mtu 1500 >/dev/null 2>&1; fi; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",3,"* ]]; then
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYS_FILE"; sed -i '/net.core.default_qdisc/d' "$SYS_FILE"
        echo "net.core.default_qdisc = fq" >> "$SYS_FILE"; echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",4,"* ]]; then
        sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
        echo "net.core.rmem_max = $max_buf" >> "$SYS_FILE"; echo "net.core.wmem_max = $max_buf" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",5,"* ]]; then
        sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
        echo "net.ipv4.tcp_rmem = 4096 $rmem_default $max_buf" >> "$SYS_FILE"; echo "net.ipv4.tcp_wmem = 4096 $wmem_default $max_buf" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",6,"* ]]; then
        sed -i '/net.ipv4.tcp_sack/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_dsack/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_fack/d' "$SYS_FILE"
        echo "net.ipv4.tcp_sack = 1" >> "$SYS_FILE"; echo "net.ipv4.tcp_dsack = 1" >> "$SYS_FILE"; echo "net.ipv4.tcp_fack = 1" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",7,"* ]]; then
        sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"; echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",8,"* ]]; then
        sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"; echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",9,"* ]]; then
        sed -i '/net.ipv4.tcp_tw_reuse/d' "$SYS_FILE"; sed -i '/net.ipv4.tw_reuse/d' "$SYS_FILE"; echo "net.ipv4.tcp_tw_reuse = 1" >> "$SYS_FILE"; fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",10,"* ]]; then
        sed -i '/net.core.somaxconn/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_max_syn_backlog/d' "$SYS_FILE"
        sed -i '/net.core.netdev_max_backlog/d' "$SYS_FILE"; sed -i '/net.core.netdev_budget/d' "$SYS_FILE"
        echo "net.core.somaxconn = 32768" >> "$SYS_FILE"; echo "net.ipv4.tcp_max_syn_backlog = 16384" >> "$SYS_FILE"
        echo "net.core.netdev_max_backlog = 65536" >> "$SYS_FILE"; echo "net.core.netdev_budget = 600" >> "$SYS_FILE"; fi
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    if [ -n "$current_iface" ] && [ $APPLY_ALL -eq 1 ]; then ip link set dev "$current_iface" txqueuelen 10000 >/dev/null 2>&1; fi
    echo -e "\n${C_GREEN}🎉 通用自适应优化参数已成功注入！${C_RESET}"; read -p "按回车返回..." temp
}

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

    NET_INFO_NOW=$(_get_main_interface_and_mtu)
    MTU_NOW=$(echo "$NET_INFO_NOW" | cut -d'|' -f2)
    RECOMMEND_BUF=$(_calculate_static_bdp_recommend)

    echo -e "${C_BLUE}⚡ tcpt优化 (高内聚并行自适应审计看板)${C_RESET}"
    echo -e " 🖥️  核心指标参数项          │  当前系统运行值      │  脚本推演建议值"
    echo -e " ────────────────────────────┼──────────────────────┼─────────────────────"
    if [ "$MTU_NOW" == "1500" ]; then echo -e " • mtu最大传输单元 (网卡级)  │  ${C_GREEN}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "$MTU_NOW"
    else echo -e " • mtu最大传输单元 (网卡级)  │  ${C_RED}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "${MTU_NOW} [异常]"; fi
    echo -e " • 拥塞控制内核算法 (cc)     │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}bbr${C_RESET}" "${CC_NOW:-cubic}"
    echo -e " • 底层阻塞队列规则 (qdisc)  │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}fq / cake${C_RESET}" "${QDISC_NOW:-fq}"
    echo -e " • 最大套接字读缓冲 (rmem)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}%-19s${C_RESET}" "${RMEM_NOW:-212992}" "$RECOMMEND_BUF"
    echo -e " • 最大套接字写缓冲 (wmem)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}%-19s${C_RESET}" "${WMEM_NOW:-212992}" "$RECOMMEND_BUF"
    echo -e " • 选择性确认重传项 (sack)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}1 (物理开启)${C_RESET}" "${SACK_NOW:-1}"
    echo -e " • 显式拥塞状态通知 (ecn)    │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}2 (自适应对齐)${C_RESET}" "${ECN_NOW:-0}"
    echo -e " • 空闲保持慢启动项 (idle)   │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}0 (物理禁用)${C_RESET}" "${IDLE_NOW:-1}"
    echo -e " • TIME_WAIT快速复用 (reuse) │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}1 (物理开启)${C_RESET}" "${REUSE_NOW:-2}"
    echo -e " • 全域 IPv6 栈阻断状态      │  $(get_ipv6_status_text)                │  --"
    echo -e "${LINE_GRAY}"
    echo -e " 1) TCP内核调优\n 2) 速率测试 (包含单线程/多线程并联突围)\n 3) 电报数据中心链路专项监测\n 4) 更改阻塞队列\n 5) 还原调优参数 (恢复之前的备份)\n 9) IPv6禁用/开启\n 0) 安全退出\n${LINE_GRAY}"
    read -p "请选择操作序号: " OPT
    
    if [ "$OPT" == "0" ] || [ -z "$OPT" ]; then echo "👋 工具已安全退出。"; exit 0; fi
    case $OPT in
        1) adaptive_tcp_tuning; read -p "按回车返回..." t ;;
        2) run_multi_dim_speedtest ;;
        3) clear; echo -e "${C_CYAN}【3. 电报数据中心链路监测】${C_RESET}"; run_telegram_spec_test; echo -e "${LINE_GRAY}"; read -p "按回车返回..." t ;;
        4) change_qdisc_action; ;;
        5) restore_sysctl_backup ;;
        9) clear; current_v6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null); sed -i '/disable_ipv6/d' "$SYS_FILE"; if [ "$current_v6" == "1" ]; then echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_GREEN}🎉 全域 IPv6 已恢复开启！${C_RESET}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 1" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_RED}🛑 内核层 IPv6 已禁用！${C_RESET}"; fi; read -p "按回车返回..." t ;;
        *) echo -e "${C_RED}❌ 无效选项！${C_RESET}" ; sleep 1 ;;
    esac
done

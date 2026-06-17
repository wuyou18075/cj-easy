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

# 20. 速率测试明细二级面板（全新完全体：锁死交互不退回，注入硬核决断警告）
run_multi_dim_speedtest() {
    local s_rate="0.00 MB/s"; local m_rate="0.00 MB/s"; local rtt_ms="250.0"
    local first_run=1

    while true; do
        clear
        if [ $first_run -eq 1 ]; then
            echo -e "${C_CYAN}⏳ 正在下发单连接套接字，握手跨境通用 Anycast 测速点...${C_RESET}"
            echo -e " 📍 节点位置: ${C_YELLOW}全球 Anycast 边缘分分发集群 (亚太/核心骨干网)${C_RESET}"
            echo -e " 🌐 测试网型: ${C_GRAY}http://cachefly.cachefly.net/10mb.test${C_RESET}"
            echo -e "${LINE_GRAY}"
            local res; res=$(_execute_speed_probe)
            s_rate=$(echo "$res" | cut -d'|' -f1)
            m_rate=$(echo "$res" | cut -d'|' -f2)
            rtt_ms=$(echo "$res" | cut -d'|' -f3)
            first_run=0
            clear
        fi

        echo -e "${C_BLUE}⚡ tcpt吞吐量测速看板 (单/多线程同步突围矩阵)${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " 📊 单线程物理净吞吐速率:   (公网直连) ${C_GREEN}${s_rate}${C_RESET}"
        echo -e " 🚀 多线程高并发极限带宽:   (并发压榨) ${C_GREEN}${m_rate}${C_RESET}"
        echo -e " 🛰️  当前跨境骨干物理延迟:   ${C_YELLOW}${rtt_ms} ms${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " ${C_GREEN}1)${C_RESET} 压榨内核大套接字缓冲区"
        echo -e " ${C_GREEN}2)${C_RESET} 禁止空闲连接窗口回落"
        echo -e " ${C_GREEN}3)${C_RESET} 自适应纠偏封锁跨境丢包"
        echo -e " ${C_GREEN}4)${C_RESET} 🚀 全部应用 1, 2, 3 顶级连环策略"
        echo -e " ${C_GREEN}5)${C_RESET} 🔄 原地再次测速 (实时核验调优物理反馈)"
        echo -e " 0) 放弃并返回上级主菜单"
        echo -e "${LINE_GRAY}"
        read -p "请精准抉择您要注入的序号: " BREAK_OPT

        if [ -z "$BREAK_OPT" ] || [ "$BREAK_OPT" == "0" ]; then
            break
        fi

        if [ ! -f "$BAK_FILE" ]; then cp "$SYS_FILE" "$BAK_FILE"; fi

        case $BREAK_OPT in
            1)
                clear
                local total_mem_kb; total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                local rec_mb=64
                if (( total_mem_kb < 1050000 )); then rec_mb=16; else rec_mb=64; fi
                
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 1 ──► 压榨内核大套接字缓冲区硬核风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与漏洞审计说明】:${C_RESET}"
                echo -e "    1. ${C_YELLOW}内存爆仓 OOM 风险${C_RESET}：缓冲区不是越大越好！如果直接写死几百MB甚至几GB，在高并发网络攻击下（如 SYN Flood），系统会为每一个恶意连接强行分配等量的物理内存，瞬间榨干内存触发 Linux OOM 强行随机杀进程（比如杀死你的反代 Nginx 或 Docker 服务）。"
                echo -e "    2. ${C_YELLOW}缓冲区膨胀 (Bufferbloat) 恶化${C_RESET}：盲目改大滑窗如果网卡队列没跟上，会导致海量数据包在队列里产生高达数秒的延迟，速度不升反降，网络变得极度恶劣、弹 502。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【数据科学安全合理值】${C_RESET}："
                echo -e "    • 对于大内存 Intel 机器，建议值为 ${C_GREEN}32 MB ~ 64 MB${C_RESET}（即输入 32 或 64）。"
                echo -e "    • 当前系统通过 BDP 自适应公式算出的出厂推荐值为: ${C_GREEN}${rec_mb} MB${C_RESET}"
                echo "========================================================="
                read -p "🤔 请手动输入自定义缓存值 (单位MB, 直接回车采用推荐值 ${rec_mb} MB): " INPUT_MB
                
                local FINAL_MB=$rec_mb
                if [ -n "$INPUT_MB" ]; then
                    if [[ "$INPUT_MB" =~ ^[0-9]+$ ]] && [ "$INPUT_MB" -gt 0 ]; then
                        FINAL_MB=$INPUT_MB
                    else
                        echo -e "${C_RED}❌ 格式有误，安全回滚至默认推荐建议值。${C_RESET}"; sleep 2; FINAL_MB=$rec_mb
                    fi
                fi
                local final_bytes=$(awk -v m="$FINAL_MB" 'BEGIN {print m * 1024 * 1024}')
                local final_default_bytes=$(awk -v b="$final_bytes" 'BEGIN {print int(b / 64)}')
                [ $final_default_bytes -lt 262144 ] && final_default_bytes=262144

                sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
                sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
                echo "net.core.rmem_max = $final_bytes" >> "$SYS_FILE"
                echo "net.core.wmem_max = $final_bytes" >> "$SYS_FILE"
                echo "net.ipv4.tcp_rmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
                echo "net.ipv4.tcp_wmem = 4096 $final_default_bytes $final_bytes" >> "$SYS_FILE"
                sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                echo -e "${C_GREEN}✅ 方案 1 物理注入成功：大连接滑窗高水位调整为 ${FINAL_MB} MB！${C_RESET}"
                read -p "按回车继续在这个菜单调整其他项目..." temp
                ;;
            2)
                clear
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 2 ──► 禁止空闲连接窗口回落风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与原理说明】:${C_RESET}"
                echo -e "    • 对应内核参数项为 \`net.ipv4.tcp_slow_start_after_idle\`。"
                echo -e "    • 该值在 Linux 原生内核中【只允许设置为 0 或 1】！如果瞎写其他数字，内核直接拒不重载，或者将其等价判定为 1。一旦设为 1，只要连接断流超过几个 RTT，速度就会被强行砍回慢启动初始滑窗状态，看图看视频严重卡顿卡死。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【长肥高延迟链路合理建议值】${C_RESET}："
                echo -e "    • 必须物理封锁此参数，即 ${C_GREEN}0 (空闲不重置窗口)${C_RESET}。"
                echo "========================================================="
                read -p "🤔 是否确应用推荐优选值 0 ？[Y/n] (直接回车确认应用): " IS_IDLE_OPT
                if [[ "$IS_IDLE_OPT" == "y" || "$IS_IDLE_OPT" == "Y" || -z "$IS_IDLE_OPT" ]]; then
                    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"
                    echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
                    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 方案 2 物理注入成功：成功切断空闲慢启动回落衰减！${C_RESET}"
                else
                    echo -e "${C_YELLOW}🛑 放弃注入。${C_RESET}"
                fi
                read -p "按回车继续在这个菜单调整其他项目..." temp
                ;;
            3)
                clear
                echo "========================================================="
                echo -e "📋 ${C_CYAN}[ 选项 3 ──► 自适应纠偏封锁跨境丢包风险决断 ]${C_RESET}"
                echo "========================================================="
                echo -e " ⚠️  ${C_RED}⚠️ 【不准瞎写警告与长途出口路由分析】:${C_RESET}"
                echo -e "    • 对应内核参数为 \`net.ipv4.tcp_ecn\`。范围只允许【0, 1, 2】。"
                echo -e "    • ${C_RED}不要盲目设为 1 (强开)${C_RESET}：中美跨国海底光缆中途经过的海量老旧边缘分发路由器很多都不支持 ECN，一旦包被打了 ECN 强开标志，它们会直接误杀并【就地丢弃 (Drop)】，直接引发诡异的网络断流。也不能设为 0（关闭），那在晚高峰完全失去在拥塞发生前自适应控速的能力。"
                echo -e ""
                echo -e " 💡 ${C_GREEN}【跨境 280ms 高丢包线路唯一合理值】${C_RESET}："
                echo -e "    • 必须设为 ${C_GREEN}2 (自适应对齐模式)${C_RESET}。仅针对对端入站请求开启，彻底避开公网路由器误杀丢包。"
                echo "========================================================="
                read -p "🤔 是否确认应用最优纠偏值 2 ？[Y/n] (直接回车确认应用): " IS_ECN_OPT
                if [[ "$IS_ECN_OPT" == "y" || "$IS_ECY_OPT" == "Y" || -z "$IS_ECN_OPT" ]]; then
                    sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
                    echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
                    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 方案 3 物理注入成功：tcp_ecn 已精准纠偏为 2 自适应防御！${C_RESET}"
                else
                    echo -e "${C_YELLOW}🛑 放弃注入。${C_RESET}"
                fi
                read -p "按回车继续在这个菜单调整其他项目..." temp
                ;;
            4)
                # 一键联动注入全部 1, 2, 3 以及泄洪管道配额
                local total_mem_kb; total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                local final_mb=64; if (( total_mem_kb < 1050000 )); then final_mb=16; fi
                local final_b=$(awk -v m="$final_mb" 'BEGIN {print m * 1024 * 1024}')
                local final_d_b=$(awk -v b="$final_b" 'BEGIN {print int(b / 64)}')
                [ $final_d_b -lt 262144 ] && final_d_b=262144

                sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
                sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
                sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"
                sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
                # 💥 同步注入泄洪大并发大坝配额，防止内存加大后管道却太窄导致丢包！
                sed -i '/net.core.somaxconn/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_max_syn_backlog/d' "$SYS_FILE"
                sed -i '/net.core.netdev_max_backlog/d' "$SYS_FILE"; sed -i '/net.core.netdev_budget/d' "$SYS_FILE"

                echo "net.core.rmem_max = $final_b" >> "$SYS_FILE"
                echo "net.core.wmem_max = $final_b" >> "$SYS_FILE"
                echo "net.ipv4.tcp_rmem = 4096 $final_d_b $final_b" >> "$SYS_FILE"
                echo "net.ipv4.tcp_wmem = 4096 $final_d_b $final_b" >> "$SYS_FILE"
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
                
                echo -e "\n${C_GREEN}🎉 【一键全部突围成功】1,2,3及高并发泄洪大坝队列已完美并联闭合热生效！${C_RESET}"
                read -p "按回车继续..." temp
                ;;
            5)
                first_run=1
                ;;
            *)
                echo -e "${C_RED}❌ 无效编号${C_RESET}"; sleep 1
                ;;
        esac
    done
}

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

# 1. 📂 存量主菜单深度审计
adaptive_tcp_tuning() {
    clear
    echo -e "${C_BLUE}🛰️  正在启动全向自适应通用网络探针，深入盘查宿主机物理现状...${C_RESET}"
    echo -e "${LINE_GRAY}"

    local cpu_arch; cpu_arch=$(uname -m)
    echo -n " [1/3] 🔍 正在检索物理 CPU 芯片架构: "
    if [[ "$cpu_arch" == *"x86_64"* || "$cpu_arch" == *"amd64"* ]]; then
        local target_cpu="X86_64 蛮力计算核心"
        echo -e "${C_CYAN}$target_cpu${C_RESET}"
    else
        local target_cpu="ARM 轻量/高密度核心"
        echo -e "${C_GREEN}$target_cpu${C_RESET}"
    fi

    local total_mem_kb; total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb; total_mem_mb=$(awk -v k="$total_mem_kb" 'BEGIN {print int(k / 1024)}')
    echo -e " [2/3] 🔍 正在核验宿主机可用内存规模: ${C_CYAN}${total_mem_mb} MB${C_RESET}"

    echo -e " [3/3] ⏳ 正在精确嗅探物理网卡到骨干网的绝对 RTT 时延..."
    local ping_raw; ping_raw=$(ping -c 3 -W 2 91.108.56.110 2>/dev/null)
    local rtt_ms; rtt_ms=$(echo "$ping_raw" | tail -n 1 | awk -F '/' '{print $5}')
    
    if [ -z "$rtt_ms" ] || [ "$rtt_ms" == "0" ]; then 
        rtt_ms="250"
        echo -e "      ──► ${C_RED}[测速阻断] 目标节点拒绝 ICMP 握手，触发通用预设。${C_RESET}"
    else
        local t1; t1=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | head -n 1)
        local t2; t2=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | head -n 2 | tail -n 1)
        local t3; t3=$(echo "$ping_raw" | grep "time=" | awk -F 'time=' '{print $2}' | awk '{print $1}' | tail -n 1)
        echo -e "      ──► ${C_GREEN}[物理测速成功] 成功向全球骨干网下发 3 次 ICMP 套接字包${C_RESET}"
        echo -e "      ──► [真实回显数据] 第一次: ${t1}ms | 第二次: ${t2}ms | 第三次: ${t3}ms"
    fi
    echo -e "      ──► 最终物理判定平均时延 RTT 为: ${C_YELLOW}${rtt_ms} ms${C_RESET}"
    
    echo -e "${LINE_GRAY}"
    echo -e "${C_BLUE}⚙️  [全自适应调优引擎分析推演与技术决断报告]${C_RESET}"
    echo -e "${LINE_GRAY}"
    
    local max_buf=16777216; local rmem_default=262144; local wmem_default=262144
    if (( total_mem_kb < 1050000 )); then
        max_buf=8388608; rmem_default=87380; wmem_default=65536
        echo -e " 💡 内存审计决断：由于系统总内存 < 1GB，限制套接字读写滑窗最大边界为 8MB。"
    else
        max_buf=67108864; rmem_default=1048576; wmem_default=1048576
        echo -e " 💡 内存审计决断：宿主机可用物理内存充足。──► 💥 单/多线程并联爆破方案：最大滑窗解绑至 64 MB！"
    fi

    if (( $(echo "$rtt_ms > 150" | bc -l) )); then
        echo -e " 💡 时延链路决断：当前时延高达 $rtt_ms ms，属于典型【跨境超级长肥管道 (LFNs)】。"
        echo -e "               ──► 决断一: 强制将 tcp_slow_start_after_idle 锁死为 0，防止空闲时速率回落。"
        echo -e "               ──► 决断二: 激活多重选择性确认（SACK/DSACK/FACK），封锁晚高峰丢包重传雪崩。"
        echo -e "               ──► 💥 决断三: 调整 tcp_ecn 为 2（自适应对齐模式），彻底解决跨国中途路由误杀丢包。"
    fi
    echo -e "${LINE_GRAY}"

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
        if [ -n "$current_iface" ]; then sudo ip link set dev "$current_iface" mtu 1500 >/dev/null 2>&1; fi
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",3,"* ]]; then
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYS_FILE"; sed -i '/net.core.default_qdisc/d' "$SYS_FILE"
        echo "net.core.default_qdisc = fq" >> "$SYS_FILE"; echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",4,"* ]]; then
        sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
        echo "net.core.rmem_max = $max_buf" >> "$SYS_FILE"; echo "net.core.wmem_max = $max_buf" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",5,"* ]]; then
        sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
        echo "net.ipv4.tcp_rmem = 4096 $rmem_default $max_buf" >> "$SYS_FILE"; echo "net.ipv4.tcp_wmem = 4096 $wmem_default $max_buf" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",6,"* ]]; then
        sed -i '/net.ipv4.tcp_sack/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_dsack/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_fack/d' "$SYS_FILE"
        echo "net.ipv4.tcp_sack = 1" >> "$SYS_FILE"; echo "net.ipv4.tcp_dsack = 1" >> "$SYS_FILE"; echo "net.ipv4.tcp_fack = 1" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",7,"* ]]; then
        sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"; echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",8,"* ]]; then
        sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"; echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",9,"* ]]; then
        sed -i '/net.ipv4.tcp_tw_reuse/d' "$SYS_FILE"; sed -i '/net.ipv4.tw_reuse/d' "$SYS_FILE"; echo "net.ipv4.tcp_tw_reuse = 1" >> "$SYS_FILE"
    fi
    if [ $APPLY_ALL -eq 1 ] || [[ ",$CHOOSE_INDEX," == *",10,"* ]]; then
        sed -i '/net.core.somaxconn/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_max_syn_backlog/d' "$SYS_FILE"
        sed -i '/net.core.netdev_max_backlog/d' "$SYS_FILE"; sed -i '/net.core.netdev_budget/d' "$SYS_FILE"
        echo "net.core.somaxconn = 32768" >> "$SYS_FILE"; echo "net.ipv4.tcp_max_syn_backlog = 16384" >> "$SYS_FILE"
        echo "net.core.netdev_max_backlog = 65536" >> "$SYS_FILE"; echo "net.core.netdev_budget = 600" >> "$SYS_FILE"
    fi
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    if [ -n "$current_iface" ] && [ $APPLY_ALL -eq 1 ]; then ip link set dev "$current_iface" txqueuelen 10000 >/dev/null 2>&1; fi
    echo -e "\n${C_GREEN}🎉 通用自适应优化参数已成功注入！${C_RESET}"; read -p "按回车返回..." temp
}

_execute_arena_and_choose() {
    clear
    echo -e "${C_BLUE}⚔️  正在启动 [Fq vs Cake 宿主机双雄数据实测竞技场]...${C_RESET}"
    echo -e "${C_YELLOW}💡 提示：本测试为硬核 A/B 流量实测，请耐心等待 10 秒钟进行数据建模...${C_RESET}"
    echo -e "${LINE_GRAY}"
    local saved_origin_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; sleep 1
    local fq_res; fq_res=$(_execute_speed_probe)
    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = cake" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; sleep 1
    local cake_res; cake_res=$(_execute_speed_probe)

    local fq_s=$(echo "$fq_res" | cut -d'|' -f1); local fq_m=$(echo "$fq_res" | cut -d'|' -f2); local fq_r=$(echo "$fq_res" | cut -d'|' -f3)
    local cake_s=$(echo "$cake_res" | cut -d'|' -f1); local cake_m=$(echo "$cake_res" | cut -d'|' -f2); local cake_r=$(echo "$cake_res" | cut -d'|' -f3)
    local fq_m_num=$(echo "$fq_m" | grep -oE '[0-9.]+\b' | head -n 1); local cake_m_num=$(echo "$cake_m" | grep -oE '[0-9.]+\b' | head -n 1)
    
    local AUTO_RECOMMEND="fq"; local auto_rec_text="🚀 fq (极限吞吐)"
    if (( $(echo "$cake_m_num > $fq_m_num" | bc -l) )); then AUTO_RECOMMEND="cake"; auto_rec_text="🍰 cake (抗抖动优化)"; fi

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
    echo -e "💡 ${C_YELLOW}【数据科学智控优选大盘推演】${C_RESET}\n 本次实测大数据表明：当前线路上 ${C_GREEN}${auto_rec_text}${C_RESET} 表现更为优异！\n========================================================="
    echo -e " 👈 [ 1 ] 强行注入应用 🚀 fq 阻塞队列\n 👈 [ 2 ] 强行注入应用 🍰 cake 阻塞队列\n 👈 [ 回车 ] 默认应用最优解: ${C_GREEN}${AUTO_RECOMMEND}${C_RESET}\n========================================================="
    read -p "请做出您的选择决策: " ARENA_CHOOSE
    local FINAL_APPLY="$AUTO_RECOMMEND"
    if [ "$ARENA_CHOOSE" == "1" ]; then FINAL_APPLY="fq"; elif [ "$ARENA_CHOOSE" == "2" ]; then FINAL_APPLY="cake"; fi
    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = $FINAL_APPLY" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    echo -e "\n${C_GREEN}🎉 最终阻塞队列已绑定为: $FINAL_APPLY${C_RESET}"; read -p "按回车键继续..." temp
}

change_qdisc_action() {
    while true; do
        clear
        local current_qdisc; current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        echo "========================================================="
        echo -e " 当前系统的排队规则(qdisc)为: ${C_GREEN}${current_qdisc:-fq}${C_RESET}"
        echo "========================================================="
        echo -e "1) 🚀 fq     ──► 极限吞吐流：BBR算法的黄金伴侣，大带宽首选。\n2) 🍰 cake   ──► 多流公平抗抖动：对中低带宽、晚高峰代理线路神级优化。\n3) 📊 fq_codel──► 轻量自适应：普通Linux内核的默认优选。\n4) 🔄 pfifo_fast──► 传统无差别先入先出：老旧无规则队列。\n========================================================="
        echo -e " ⚔️  5) 进入 Fq vs Cake 竞技场真实性能交叉数据实测\n 9) 🚀 启动全自动网络探针智控优选\n 0) 返回上级菜单\n========================================================="
        read -p "请输入操作编号: " Q_OPT
        if [ "$Q_OPT" == "0" ] || [ -z "$Q_OPT" ]; then break; fi
        if [ "$Q_OPT" == "1" ]; then sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo "✅已切换为 fq"; break; fi
        if [ "$Q_OPT" == "2" ]; then sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = cake" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo "✅已切换为 cake"; break; fi
        if [ "$Q_OPT" == "5" ] || [ "$Q_OPT" == "9" ]; then _execute_arena_and_choose; break; fi
    done
}

restore_sysctl_backup() {
    clear
    if [ ! -f "$BAK_FILE" ]; then echo -e "${C_RED}❌ 未发现原历史备份文件！${C_RESET}"; else
        sudo cp "$BAK_FILE" "$SYS_FILE"; sudo sysctl -p /etc/sysctl.conf >/dev/null 2>&1
        echo -e "${C_GREEN}🎉 参数已完好无损地恢复！${C_RESET}"; fi; read -p "按回车返回..." t
}

# =========================================================
#                    ⚙️ 主循环交互体控制
# =========================================================
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
    echo -e " 1) TCP内核调优\n 2) 速率测试 (包含单线程/高并发多线程并联突围)\n 3) 电报数据中心链路专项监测\n 4) 更改阻塞队列\n 5) 还原调优参数 (恢复之前的备份)\n 9) IPv6禁用/开启\n 0) 安全退出\n${LINE_GRAY}"
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

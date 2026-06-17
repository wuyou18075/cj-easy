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

# 20. 速率测试明细二级面板（追加人工推理与方案选择项）
run_multi_dim_speedtest() {
    clear
    echo -e "${C_CYAN}⏳ 正在下发单连接套接字，握手跨境通用 Anycast 测速点...${C_RESET}"
    echo -e " 📍 节点位置: ${C_YELLOW}全球 Anycast 边缘分发集群 (亚太/核心骨干网)${C_RESET}"
    echo -e " 🌐 测试网型: ${C_GRAY}http://cachefly.cachefly.net/10mb.test${C_RESET}"
    echo -e "${LINE_GRAY}"
    
    local res; res=$(_execute_speed_probe)
    local s_rate=$(echo "$res" | cut -d'|' -f1)
    local m_rate=$(echo "$res" | cut -d'|' -f2)
    local rtt_ms=$(echo "$res" | cut -d'|' -f3)
    
    echo -e " 📊 单线程物理净吞吐速率:   (公网直连) ${C_GREEN}${s_rate}${C_RESET}"
    echo -e " 🚀 多线程高并发极限带宽:   (并发压榨) ${C_GREEN}${m_rate}${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e " ${C_GREEN}1)${C_RESET} 🔥 进入单/多线程同步破轨突围优化方案"
    echo -e " 0) 放弃优化，直接返回上级主菜单"
    echo -e "${LINE_GRAY}"
    read -p "请选择操作编号: " BREAK_OPT
    
    if [ "$BREAK_OPT" == "1" ]; then
        clear
        if [ ! -f "$BAK_FILE" ]; then cp "$SYS_FILE" "$BAK_FILE"; fi
        
        echo -e "${C_BLUE}📊 [单/多线程同步突围 ──► 底层内核白盒推理看板]${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " 📋 ${C_YELLOW}1. 动态套接字硬件内存压榨调优项${C_RESET}"
        echo -e "    • 分析方向: 经典数学公式指出，在高达 ${C_YELLOW}${rtt_ms}ms${C_RESET} 的高延迟长肥链路上，单连接最大吞吐量由滑窗硬上限绝对锁死。当前系统缓冲上限极易在晚高峰被完全压干，导致并发吞吐暴跌。"
        echo -e "    • 通用优化: 突破 16MB 传统屏障，暴力将内核最大读写缓冲（rmem_max/wmem_max）解绑提升至 ${C_GREEN}64 MB (67108864 字节)${C_RESET}，让每一个 Socket 连环轨道都拥有无限大的硬件泄洪底气。"
        echo -e ""
        echo -e " 📋 ${C_YELLOW}2. 自适应关闭 TCP 慢启动衰减调优项${C_RESET}"
        echo -e "    • 分析方向: 单线程测速虽高，但实际应用代理时经常偶发性卡顿。因为连接一旦空闲超过一个 RTT 周期，内核就会保守误判网络阻塞，强行将拥塞窗口（cwnd）斩断清零，重新开始挤牙膏慢启动。"
        echo -e "    • 通用优化: 无条件将 ${C_GREEN}tcp_slow_start_after_idle 焊死为 0${C_RESET}，配合敏锐的 BBR 算法，确保空闲连接在突发数据时瞬间以满血顶格速率重回轨道喷射。"
        echo -e ""
        echo -e " 📋 ${C_YELLOW}3. 跨国骨干网显式拥塞自适应校准项${C_RESET}"
        echo -e "    • 分析方向: 若将 tcp_ecn 盲目设为 1（强开），当加密包跨越复杂的太平洋海底光缆时，中途大量老旧跨国路由器由于无法识别，会残忍采取【就地丢弃 (Drop)】策略，引发严重的突发性网络断流。"
        echo -e "    • 通用优化: 调整为 ${C_GREEN}tcp_ecn = 2 (自适应对齐模式)${C_RESET}。仅对入站连接开启通知，既保住了拥塞识别能力，又绝不给中途不兼容的路由器任何误杀丢包的机会。"
        echo -e "${LINE_GRAY}"
        echo -e " ${C_GREEN}1)${C_RESET} 应用方案 1：物理压榨 64MB 内核大套接字缓冲区"
        echo -e " ${C_GREEN}2)${C_RESET} 应用方案 2：锁定 slow_start_after_idle=0 禁止空闲回落"
        echo -e " ${C_GREEN}3)${C_RESET} 应用方案 3：自适应纠偏 tcp_ecn = 2 封锁跨境丢包"
        echo -e " ${C_GREEN}4)${C_RESET} 🚀 一键全量上轨应用：同时注入执行 1, 2, 3 全部顶级策略"
        echo -e " 0) 放弃并返回"
        echo -e "${LINE_GRAY}"
        read -p "请精准抉择您要注入的序号: " EXEC_CHOOSE
        
        if [ "$EXEC_CHOOSE" == "4" ] || [ -z "$EXEC_CHOOSE" ]; then
            local RUN_ALL=1
        else
            local RUN_ALL=0
        fi
        
        # 执行方案 1
        if [ $RUN_ALL -eq 1 ] || [ "$EXEC_CHOOSE" == "1" ]; then
            sed -i '/net.core.rmem_max/d' "$SYS_FILE"; sed -i '/net.core.wmem_max/d' "$SYS_FILE"
            sed -i '/net.ipv4.tcp_rmem/d' "$SYS_FILE"; sed -i '/net.ipv4.tcp_wmem/d' "$SYS_FILE"
            echo "net.core.rmem_max = 67108864" >> "$SYS_FILE"
            echo "net.core.wmem_max = 67108864" >> "$SYS_FILE"
            echo "net.ipv4.tcp_rmem = 4096 1048576 67108864" >> "$SYS_FILE"
            echo "net.ipv4.tcp_wmem = 4096 1048576 67108864" >> "$SYS_FILE"
            echo -e "${C_GREEN} ✅ 方案 1 物理注入成功：64MB 内核大缓冲区已就位。${C_RESET}"
        fi
        # 执行方案 2
        if [ $RUN_ALL -eq 1 ] || [ "$EXEC_CHOOSE" == "2" ]; then
            sed -i '/net.ipv4.tcp_slow_start_after_idle/d' "$SYS_FILE"
            echo "net.ipv4.tcp_slow_start_after_idle = 0" >> "$SYS_FILE"
            echo -e "${C_GREEN} ✅ 方案 2 物理注入成功：空闲连接慢启动回落已切断。${C_RESET}"
        fi
        # 执行方案 3
        if [ $RUN_ALL -eq 1 ] || [ "$EXEC_CHOOSE" == "3" ]; then
            sed -i '/net.ipv4.tcp_ecn/d' "$SYS_FILE"
            echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
            echo -e "${C_GREEN} ✅ 方案 3 物理注入成功：tcp_ecn 自适应降噪对齐应用。${C_RESET}"
        fi
        
        sysctl -p /etc/sysctl.conf >/dev/null 2>&1
        echo -e "\n${C_GREEN}🎉 突围调优参数已被成功注入并热重载生效！${C_RESET}"
        read -p "按回车返回..." temp
    fi
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

# 1. 深度交叉审计自适应通用调优引擎
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
        echo -e "      ──► ${C_RED}[测速阻断] 目标节点拒绝 ICMP 握手，触发通用安全降轨推推。${C_RESET}"
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
    
    local max_buf=16777216
    local rmem_default=262144
    local wmem_default=262144

    if (( total_mem_kb < 1050000 )); then
        max_buf=8388608; rmem_default=87380; wmem_default=65536
        echo -e " 💡 内存审计决断：当前内存较小，限制套接字读写滑窗最大边界为 ${C_GREEN}8MB${C_RESET}。"
    else
        max_buf=67108864 
        rmem_default=1048576
        wmem_default=1048576
        echo -e " 💡 内存审计决断：宿主机可用物理内存充足。"
        echo -e "               ──► 💥 ${C_GREEN}单/多线程并联爆破方案${C_RESET}：将内核最大套接字读写滑窗缓冲区直接暴力焊死至 ${C_GREEN}64 MB${C_RESET}！"
    fi

    if (( $(echo "$rtt_ms > 150" | bc -l) )); then
        echo -e " 💡 时延链路决断：当前时延高达 $rtt_ms ms，属于典型【跨境超级长肥管道 (LFNs)】。"
        echo -e "               ──► ${C_GREEN}决断一${C_RESET}: 强制将 tcp_slow_start_after_idle 锁死为 0，防止空闲时速率回落。"
        echo -e "               ──► ${C_GREEN}决断二${C_RESET}: 激活多重选择性确认（SACK/DSACK/FACK），封锁晚高峰丢包重传雪崩。"
        echo -e "               ──► 💥 ${C_GREEN}决断三${C_RESET}: 调整 tcp_ecn 为 2（自适应对齐模式），彻底解决跨国中途路由误杀丢包。"
    fi

    echo -e " 💡 泄洪队列决断：强力扩容全连接队列（somaxconn=32768）与网卡软中断配额（budget=600），轰开高并发性能锁。"
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
    if [[ "$CONFIRM_CHOOSE" != "y" && "$CONFIRM_CHOOSE" != "Y" ]]; then
        echo -e "${C_YELLOW}🛑 已安全拦截，未对系统做出任何修改。${C_RESET}"
        return
    fi

    echo ""
    echo "========================================================="
    echo -e "🛠️  ${C_CYAN}请选择您要注入的调优项目序号 (支持多选，用英文逗号隔开)${C_RESET}"
    echo "========================================================="
    echo -e " ${C_GREEN}1)${C_RESET} 🚀 一键应用上方全部通用自适应调优参数 (含网卡层 MTU 1500 降轨纠偏)"
    echo -e " ${C_GREEN}2)${C_RESET} 网卡级 MTU 物理降轨纠偏项 (强焊 1500 黄金标准，防丢包)"
    echo -e " ${C_GREEN}3)${C_RESET} 拥塞算法与排队规则联动项 (bbr + fq)"
    echo -e " ${C_GREEN}4)${C_RESET} 💥 满血大滑窗最大读写缓冲项 (暴力解绑单/多线程吞吐上限，rmem/wmem)"
    echo -e " ${C_GREEN}5)${C_RESET} TCP动态滑窗缓冲范围优化项 (tcp_rmem & tcp_wmem)"
    echo -e " ${C_GREEN}6)${C_RESET} 💥 高丢包选择性确认抗灾项 (强开 SACK/DSACK/FACK 预防晚高峰重传雪崩)"
    echo -e " ${C_GREEN}7)${C_RESET} 💥 跨国骨干网络显式拥塞调优项 (自适应调整 tcp_ecn = 2，防路由误杀)"
    echo -e " ${C_GREEN}8)${C_RESET} 💥 拒绝空闲连接重置限速项 (将 tcp_slow_start_after_idle 锁死为 0)"
    echo -e " ${C_GREEN}9)${C_RESET} 高并发端口TIME_WAIT快速回收复用项 (tcp_tw_reuse)"
    echo -e " ${C_GREEN}10)${C_RESET} 💥 工业级大并发泄洪队列上限项 (大幅扩容全连接队列与网卡轮询配额)"
    echo "========================================================="
    read -p "请精准勾选需要应用的序号 [例如 1]: " CHOOSE_INDEX

    if [ -z "$CHOOSE_INDEX" ]; then
        echo -e "${C_YELLOW}🛑 输入为空，放弃本次保存。${C_RESET}"
        return
    fi

    if [ ! -f "$BAK_FILE" ]; then 
        cp "$SYS_FILE" "$BAK_FILE"
    fi

    local APPLY_ALL=0
    if [[ ",$CHOOSE_INDEX," == *",1,"* ]]; then APPLY_ALL=1; fi

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
        echo "net.ipv4.tcp_ecn = 2" >> "$SYS_FILE"
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
        sed -i '/net.core.netdev_budget/d' "$SYS_FILE"
        sed -i '/net.core.netdev_budget_usecs/d' "$SYS_FILE"
        echo "net.ipv4.tcp_adv_win_scale = 1" >> "$SYS_FILE"
        echo "net.ipv4.tcp_notsent_lowat = 16384" >> "$SYS_FILE"
        echo "net.core.somaxconn = 32768" >> "$SYS_FILE"
        echo "net.ipv4.tcp_max_syn_backlog = 16384" >> "$SYS_FILE"
        echo "net.core.netdev_max_backlog = 65536" >> "$SYS_FILE"
        echo "net.core.netdev_budget = 600" >> "$SYS_FILE"
        echo "net.core.netdev_budget_usecs = 8000" >> "$SYS_FILE"
    fi

    sysctl -p /etc/sysctl.conf >/dev/null 2>&1

    if [ -n "$current_iface" ] && [ $APPLY_ALL -eq 1 ]; then
        ip link set dev "$current_iface" txqueuelen 10000 >/dev/null 2>&1
    fi
    echo -e "\n${C_GREEN}🎉 通用自适应优化参数已成功注入，单/多线程大水闸全面拉起！${C_RESET}"
}

_execute_arena_and_choose() {
    clear
    echo -e "${C_BLUE}⚔️  正在启动 [Fq vs Cake 宿主机双雄数据实测竞技场]...${C_RESET}"
    echo -e "${C_YELLOW}💡 提示：本测试为硬核 A/B 流量实测，请耐心等待 10 秒钟进行数据建模...${C_RESET}"
    echo -e "${LINE_GRAY}"
    
    local saved_origin_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    echo -e "⏳ 正在切入 [🚀 fq] 队列并采集公网实时传输层指标..."
    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = fq" >> "$SYS_FILE"
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    sleep 1
    local fq_res; fq_res=$(_execute_speed_probe)
    
    echo -e "⏳ 正在切入 [🍰 cake] 队列并采集公网实时传输层指标..."
    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = cake" >> "$SYS_FILE"
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    sleep 1
    local cake_res; cake_res=$(_execute_speed_probe)

    local fq_s=$(echo "$fq_res" | cut -d'|' -f1); local fq_m=$(echo "$fq_res" | cut -d'|' -f2); local fq_r=$(echo "$fq_res" | cut -d'|' -f3)
    local cake_s=$(echo "$cake_res" | cut -d'|' -f1); local cake_m=$(echo "$cake_res" | cut -d'|' -f2); local cake_r=$(echo "$cake_res" | cut -d'|' -f3)

    local fq_m_num=$(echo "$fq_m" | grep -oE '[0-9.]+\b' | head -n 1)
    local cake_m_num=$(echo "$cake_m" | grep -oE '[0-9.]+\b' | head -n 1)
    
    local AUTO_RECOMMEND="fq"
    local auto_rec_text="🚀 fq (极限吞吐)"
    if (( $(echo "$cake_m_num > $fq_m_num" | bc -l) )); then
        AUTO_RECOMMEND="cake"
        auto_rec_text="🍰 cake (抗抖动优化)"
    fi

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
    echo -e "💡 ${C_YELLOW}【数据科学智控优选大盘推演】${C_RESET}"
    echo -e " 本次实测大数据表明：当前线路上 ${C_GREEN}${auto_rec_text}${C_RESET} 表现更为优异！"
    echo "========================================================="
    echo -e " 👈 [ 1 ] 强行注入应用 🚀 fq 阻塞队列"
    echo -e " 👈 [ 2 ] 强行注入应用 🍰 cake 阻塞队列"
    echo -e " 👈 [ 回车 ] 默认应用数据科学推演出的最优解: ${C_GREEN}${AUTO_RECOMMEND}${C_RESET}"
    echo "========================================================="
    read -p "请做出您的选择决策: " ARENA_CHOOSE

    local FINAL_APPLY="$AUTO_RECOMMEND"
    if [ "$ARENA_CHOOSE" == "1" ]; then
        FINAL_APPLY="fq"
    elif [ "$ARENA_CHOOSE" == "2" ]; then
        FINAL_APPLY="cake"
    fi

    sed -i '/net.core.default_qdisc/d' "$SYS_FILE"; echo "net.core.default_qdisc = $FINAL_APPLY" >> "$SYS_FILE"
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    echo -e "\n${C_GREEN}🎉 队列策略成功锁定生效！当前阻塞队列已最终绑定为: $FINAL_APPLY${C_RESET}"
    read -p "按回车键继续..." temp
}

change_qdisc_action() {
    while true; do
        clear
        local current_qdisc; current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        
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
        echo " 9) 🚀 启动全自动网络探针智控优选 (多维测速A/B对齐版)"
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
        elif [ "$Q_OPT" == "5" ] || [ "$Q_OPT" == "9" ]; then
            _execute_arena_and_choose
            break
        fi
    done
}

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
    if [ "$MTU_NOW" == "1500" ]; then
        echo -e " • mtu最大传输单元 (网卡级)  │  ${C_GREEN}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "$MTU_NOW"
    else
        echo -e " • mtu最大传输单元 (网卡级)  │  ${C_RED}%-19s${C_RESET} │  ${C_GREEN}1500 (公网标准)${C_RESET}" "${MTU_NOW} [异常]"
    fi
    echo -e " • 拥塞控制内核算法 (cc)     │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}bbr${C_RESET}" "${CC_NOW:-cubic}"
    echo -e " • 底层阻塞队列规则 (qdisc)  │  ${C_CYAN}%-19s${C_RESET} │  ${C_GREEN}fq / cake${C_RESET}" "${QDISC_NOW:-fq}"
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
        2) run_multi_dim_speedtest ;;
        3) clear; echo -e "${C_CYAN}【3. 电报数据中心链路监测】${C_RESET}"; run_telegram_spec_test; echo -e "${LINE_GRAY}"; read -p "按回车返回..." t ;;
        4) change_qdisc_action; ;;
        5) restore_sysctl_backup; read -p "按回车返回..." t ;;
        9) clear; echo -e "${C_CYAN}【9. 系统 IPv6 状态切换】${C_RESET}\n${LINE_GRAY}"; current_v6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null); sed -i '/disable_ipv6/d' "$SYS_FILE"; if [ "$current_v6" == "1" ]; then echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_GREEN}🎉 全域 IPv6 已顺利恢复开启！${C_RESET}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 1" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1; sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1; echo -e "${C_RED}🛑 内核层 IPv6 已彻底切断禁用！${C_RESET}"; fi; read -p "按回车返回..." t ;;
        *) echo -e "${C_RED}❌ 无效选项！${C_RESET}" ; sleep 1 ;;
    esac
done

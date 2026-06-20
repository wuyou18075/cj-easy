#!/bin/bash

# =========================================================
#             ⚡ TCP内核调优与智能靶向测速矩阵 ⚡
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
    for cmd in wget awk grep curl ping bc ip python3; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${C_CYAN}⏳ 正在拉取底层探针所需的基础组件 (包含 python3 原生测速核)...${C_RESET}"
        apt-get update -y >/dev/null 2>&1 || yum makecache -y >/dev/null 2>&1
        apt-get install -y "${missing_deps[@]}" >/dev/null 2>&1 || yum install -y "${missing_deps[@]}" >/dev/null 2>&1
    fi
}
init_dependencies

# 核心：自动部署 Speedtest 原生探针核 (轻量化无依赖)
init_speedtest_core() {
    if [ ! -f "/tmp/st_core.py" ]; then
        wget -qO /tmp/st_core.py https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py
        chmod +x /tmp/st_core.py
    fi
}

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
    if (( total_mem < 1050000 )); then echo "8388608"
    else echo "16777216"; fi
}

_inject_matrix_values() {
    local mode=$1 
    local custom_val=$2
    local final_bytes=67108864

    if [ -n "$custom_val" ]; then
        final_bytes=$(awk -v m="$custom_val" 'BEGIN {print m * 1024 * 1024}')
    else
        case $mode in
            1) final_bytes=67108864 ;;  
            2) final_bytes=16777216 ;;  
            3) final_bytes=33554432 ;;  
            4) final_bytes=50331648 ;;  
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
#            ⚙️ 核心模块：智能靶向联动测速引擎
# =========================================================
run_intelligent_speedtest() {
    clear
    init_speedtest_core
    echo -e "${C_BLUE}🛰️ 正在初始化智能网络靶向测速引擎...${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e " 💡 ${C_YELLOW}原理科普：${C_RESET}普通的测速只测机器的【国际骨干带宽】。为了真实反映您的翻墙体感，我们将针对国内三大运营商的核心商业节点（剔除限速的教育网），进行【回国单线程上传】与【并发多线程上传】专项测试。"
    echo -e "${LINE_GRAY}"
    
    local user_ip=""
    local user_isp="默认商业节点随机派发"
    local user_region="中国大陆"
    local p2p_rtt="测速核自适应"
    local p2p_loss="测速核自适应"

    read -p "🎯 请输入您国内本地电脑的公网 IP (用于精准查路由，不输入则智能分配最近节点): " user_ip
    
    if [ -n "$user_ip" ]; then
        echo -e "⏳ 正在通过全球 BGP 路由表反查您的物理归属地..."
        local ip_info; ip_info=$(curl -s -m 3 "http://ip-api.com/json/$user_ip?lang=zh-CN")
        local req_status; req_status=$(echo "$ip_info" | grep -oP '"status":"\K[^"]+')
        
        if [ "$req_status" == "success" ]; then
            user_region=$(echo "$ip_info" | grep -oP '"regionName":"\K[^"]+')
            user_isp=$(echo "$ip_info" | grep -oP '"isp":"\K[^"]+')
            echo -e "✅ 精准锁定本地靶标: ${C_CYAN}$user_region - $user_isp${C_RESET}"
            
            echo -e "⏳ 正在向目标路由发起直连物理 ICMP 探针穿透测试..."
            local ping_res; ping_res=$(ping -c 5 -W 2 "$user_ip" 2>/dev/null)
            if [ $? -eq 0 ]; then
                p2p_loss=$(echo "$ping_res" | grep -oP '\d+(?=% packet loss)' | awk '{print $1}')
                p2p_rtt=$(echo "$ping_res" | tail -n 1 | awk -F '/' '{print $5}')
                echo -e "✅ 端到端物理连通：延迟 ${C_GREEN}${p2p_rtt} ms${C_RESET} | 丢包率 ${C_YELLOW}${p2p_loss}%${C_RESET}"
            else
                echo -e "⚠️ 目标 IP 配置了禁 Ping (ICMP拦截)，物理穿透转交底层测速核接管。"
            fi
        else
            echo -e "❌ IP 解析失败，将使用通用测速大盘。"
        fi
    else
        echo -e "👉 已跳过私有 IP 注入，启用全景随机侦测模式。"
    fi

    echo -e "${LINE_GRAY}"
    echo -e "🚀 正在启动 国际基准 与 国内回程 双轨测速 (大概耗时1~2分钟，请耐心等待)...\n"

    # ================== 测试项 1: 国际控制变量基准 ==================
    echo -e "🌍 ${C_CYAN}[ 测试项 1/2 : 国际骨干网基准 (控制变量) ]${C_RESET}"
    echo -e "   正在测试机器本身物理网卡出口到国际枢纽的极限性能..."
    # --single 测试单线程， 不加测试多线程。用 Cloudflare 等默认节点
    local intl_single; intl_single=$(python3 /tmp/st_core.py --single --secure | grep -E "Download:|Upload:")
    local intl_s_down=$(echo "$intl_single" | grep "Download:" | awk '{printf "%.2f", $2/8}')
    local intl_s_up=$(echo "$intl_single" | grep "Upload:" | awk '{printf "%.2f", $2/8}')
    
    local intl_multi; intl_multi=$(python3 /tmp/st_core.py --secure | grep -E "Download:|Upload:")
    local intl_m_down=$(echo "$intl_multi" | grep "Download:" | awk '{printf "%.2f", $2/8}')
    local intl_m_up=$(echo "$intl_multi" | grep "Upload:" | awk '{printf "%.2f", $2/8}')

    # ================== 测试项 2: 回国真实体感测试 ==================
    echo -e "\n🇨🇳 ${C_CYAN}[ 测试项 2/2 : 中国大陆核心商业节点真实回程 ]${C_RESET}"
    echo -e "   正在拉取国内节点列表，并智能剔除高墙教育网 (CERNET/University)..."
    
    # 获取国内节点，过滤教育网
    local cn_servers; cn_servers=$(python3 /tmp/st_core.py --list | grep -E "China|Shanghai|Beijing|Guangzhou|Shenzhen" | grep -iv -E "University|Edu|CERNET" | head -n 5)
    local target_server_id=""
    
    # 如果用户有输入ISP（比如移动），优先匹配包含该关键字的节点
    if [ -n "$user_ip" ] && [[ "$user_isp" == *"Mobile"* || "$user_isp" == *"移动"* ]]; then
        target_server_id=$(echo "$cn_servers" | grep -i -E "Mobile|移动" | head -n 1 | awk -F')' '{print $1}' | tr -d ' ')
    elif [ -n "$user_ip" ] && [[ "$user_isp" == *"Telecom"* || "$user_isp" == *"电信"* ]]; then
        target_server_id=$(echo "$cn_servers" | grep -i -E "Telecom|电信" | head -n 1 | awk -F')' '{print $1}' | tr -d ' ')
    fi

    # 如果没匹配到，随便抓一个排第一的商业节点
    if [ -z "$target_server_id" ]; then
        target_server_id=$(echo "$cn_servers" | head -n 1 | awk -F')' '{print $1}' | tr -d ' ')
    fi
    local target_server_name=$(echo "$cn_servers" | grep "^ *${target_server_id})" | cut -d')' -f2 | awk -F'[' '{print $1}')

    if [ -n "$target_server_id" ]; then
        echo -e "   🎯 已锁定高质量商业测速靶点: ${C_YELLOW}${target_server_name} (ID: ${target_server_id})${C_RESET}"
        
        local cn_single; cn_single=$(python3 /tmp/st_core.py --server $target_server_id --single --secure 2>/dev/null | grep -E "Download:|Upload:")
        local cn_s_down=$(echo "$cn_single" | grep "Download:" | awk '{printf "%.2f", $2/8}')
        local cn_s_up=$(echo "$cn_single" | grep "Upload:" | awk '{printf "%.2f", $2/8}')

        local cn_multi; cn_multi=$(python3 /tmp/st_core.py --server $target_server_id --secure 2>/dev/null | grep -E "Download:|Upload:")
        local cn_m_down=$(echo "$cn_multi" | grep "Download:" | awk '{printf "%.2f", $2/8}')
        local cn_m_up=$(echo "$cn_multi" | grep "Upload:" | awk '{printf "%.2f", $2/8}')
    else
        echo -e "   ⚠️ 未能成功拉取到国内节点，回国测试项置空。"
        local cn_s_down="0.00"; local cn_s_up="0.00"; local cn_m_down="0.00"; local cn_m_up="0.00"
    fi

    # ================== 渲染最终审计大盘 ==================
    clear
    echo "========================================================="
    echo -e "📊 ${C_GREEN}[ 智能靶向网络链路双轨审计报告 ]${C_RESET}"
    echo "========================================================="
    echo -e " 📍 用户本地网络画像 : ${C_CYAN}${user_region} - ${user_isp}${C_RESET}"
    echo -e " 📍 端到端直连物理探测: 延迟 ${C_YELLOW}${p2p_rtt} ms${C_RESET} | 丢包率 ${C_YELLOW}${p2p_loss}%${C_RESET}"
    echo -e " 📍 国内测速着陆节点 : ${C_CYAN}${target_server_name:-无}${C_RESET}"
    echo "========================================================="
    echo -e " ⚠️ ${C_YELLOW}数据说明${C_RESET}："
    echo -e "   • 测试结果已自动折算为我们日常使用的 ${C_CYAN}MB/s (兆字节每秒)${C_RESET}。"
    echo -e "   • 【机器下载】反映您的代理去抓取外部内容的速度。"
    echo -e "   • ${C_RED}【回国上传】反映的是您在国内用浏览器或软件翻墙时，真实的拉取体感上限！${C_RESET}"
    echo "─────────────────────────────────────────────────────────"
    
    printf " %-20s | %-16s | %-16s\n" "测试维度类别" "国际基准极限带宽" "真实验证回国体感"
    echo "─────────────────────────────────────────────────────────"
    printf " • 单线程下载 (测内核)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${intl_s_down:-0.00} MB/s" "${cn_s_down:-0.00} MB/s"
    printf " • 单线程上传 (测翻墙)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${intl_s_up:-0.00} MB/s" "${cn_s_up:-0.00} MB/s"
    echo "─────────────────────────────────────────────────────────"
    printf " • 多线程下载 (测网卡)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${intl_m_down:-0.00} MB/s" "${cn_m_down:-0.00} MB/s"
    printf " • 多线程上传 (测翻墙)  | %-16s | ${C_GREEN}%-16s${C_RESET}\n" "${intl_m_up:-0.00} MB/s" "${cn_m_up:-0.00} MB/s"
    echo "========================================================="
    read -p "审计完毕，按回车键返回核心调度看板..." temp
}

# =========================================================
#             🌟 主控制面板
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
    echo -e " 1) TCP智能一键网络底层内核调优"
    echo -e " 2) 智能靶向网络链路双轨测速大盘 (区分单/多线程与回国体感) ${C_YELLOW}⭐${C_RESET}"
    echo -e " 3) 还原调优参数 (恢复之前的备份)"
    echo -e " 9) IPv6 禁用/开启切换"
    echo -e " 0) 安全退出"
    echo -e "${LINE_GRAY}"
    read -p "请选择操作序号: " OPT
    
    if [ "$OPT" == "0" ] || [ -z "$OPT" ]; then echo "👋 工具已安全退出。"; exit 0; fi
    case $OPT in
        1) 
            clear; echo -e "${C_CYAN}【1. 正在初始化内核调优预评估...】${C_RESET}"
            _inject_matrix_values "4" "" # 默认使用模式4最优配置
            echo -e "${C_GREEN}✅ 调优完毕！已锁定至跨境大流量全场景最优状态。${C_RESET}"
            read -p "按回车返回..." t ;;
        2) 
            run_intelligent_speedtest ;;
        3) 
            clear; echo -e "${C_CYAN}【3. 正在恢复系统出厂网络默认值...】${C_RESET}"
            if [ -f "$BAK_FILE" ]; then cp "$BAK_FILE" "$SYS_FILE" && sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_GREEN}✅ 恢复成功！${C_RESET}"; else echo -e "${C_RED}❌ 未找到备份文件。${C_RESET}"; fi
            read -p "按回车返回..." t ;;
        9) 
            clear; current_v6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null); sed -i '/disable_ipv6/d' "$SYS_FILE"
            if [ "$current_v6" == "1" ]; then echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_GREEN}🎉 全域 IPv6 已恢复开启！${C_RESET}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYS_FILE"; echo "net.ipv6.conf.default.disable_ipv6 = 1" >> "$SYS_FILE"; sysctl -p /etc/sysctl.conf >/dev/null 2>&1; echo -e "${C_RED}🛑 内核层 IPv6 已禁用！${C_RESET}"; fi
            read -p "按回车返回..." t ;;
        *) echo -e "${C_RED}❌ 无效选项！${C_RESET}" ; sleep 1 ;;
    esac
done

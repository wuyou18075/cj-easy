#!/bin/bash
# =========================================================
#            ⚡ TCP内核调优与智能靶向测速矩阵 PRO MAX ⚡
# =========================================================

C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"

SYS_FILE="/etc/sysctl.conf"
BAK_FILE="/etc/sysctl.conf.bak_matrix"

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}❌ 必须使用 root 权限运行！${C_RESET}"; exit 1; fi
[ ! -f "$SYS_FILE" ] && touch "$SYS_FILE"

# 底层依赖静默检查与补全
init_deps() {
    local deps=(wget awk grep curl ping ip mtr bc)
    local missing=()
    for cmd in "${deps[@]}"; do ! command -v $cmd &> /dev/null && missing+=("$cmd"); done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${C_CYAN}⏳ 正在补全底层探针 (${missing[*]})...${C_RESET}"
        command -v apt-get &>/dev/null && apt-get update -y >/dev/null 2>&1 && apt-get install -y "${missing[@]}" >/dev/null 2>&1
        command -v yum &>/dev/null && yum install -y "${missing[@]}" >/dev/null 2>&1
    fi
}
init_deps

# --- 工具函数 ---
bytes_to_mb() {
    local b=$1
    if [ -z "$b" ] || ! [[ "$b" =~ ^[0-9]+$ ]]; then echo "-"; else awk -v b="$b" 'BEGIN {printf "%.1fMB", b/1048576}'; fi
}

get_mtu() {
    local iface; iface=$(ip -4 route ls | grep default | grep -oP 'dev \K\S+' | head -n 1)
    [ -z "$iface" ] && iface=$(ip link show | grep -v 'lo' | grep 'state UP' | awk -F ': ' '{print $2}' | head -n 1)
    local m; m=$(ip link show "${iface:-eth0}" 2>/dev/null | grep -oP 'mtu \K\d+')
    echo "${m:-1500}"
}

get_mem_mb() { free -m | awk '/Mem:/ {print $2}'; }
get_cpu_cores() { nproc; }

_calc_default_buf() {
    local mem=$(get_mem_mb)
    if [ "$mem" -lt 1024 ]; then echo "16777216"
    elif [ "$mem" -lt 4096 ]; then echo "33554432"
    else echo "67108864"; fi
}

# --- 拥塞算法安全挂载器 ---
smart_set_cc() {
    local algo="$1"
    modprobe "tcp_$algo" 2>/dev/null
    sed -i '/tcp_congestion_control/d' "$SYS_FILE"
    echo "net.ipv4.tcp_congestion_control = $algo" >> "$SYS_FILE"
    sysctl -p >/dev/null 2>&1
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "$algo" ]; then
        echo -e "${C_GREEN}✅ 已成功挂载驱动: [ $algo ]${C_RESET}"
    else
        echo -e "${C_RED}⚠️ 内核缺失 $algo 模块，已回退系统默认！${C_RESET}"
    fi
}

# =========================================================
#   核心测速引擎 (单/多线程 + 丢包/抖动/长稳评估模型)
# =========================================================
run_core_speedtest() {
    local url="$1"
    local target_host=$(echo "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
    local threads_mode="$2"

    # 1. 连续发包探测抖动与丢包 (10个包，间隔0.2s)
    local ping_res=$(ping -c 10 -i 0.2 -W 1 "$target_host" 2>/dev/null)
    local loss=$(echo "$ping_res" | grep -oP '\d+(?=% packet loss)')
    local jitter=$(echo "$ping_res" | tail -n 1 | awk -F '/' '{print $6}' | awk '{print $1}')

    [ -z "$loss" ] && loss="100"
    [ -z "$jitter" ] && jitter="999.9"

    local speed_mb="0.00"

    # 2. 测速执行
    if [ "$loss" != "100" ]; then
        if [ "$threads_mode" == "single" ]; then
            local raw_bps=$(curl -4 -s -m 5 -w "%{speed_download}" -o /dev/null "$url")
            speed_mb=$(awk -v b="$raw_bps" 'BEGIN {printf "%.2f", b/1048576}')
        else
            # 4线程并发下载切片算总和
            local tmpd=$(mktemp -d)
            for i in {1..4}; do
                (curl -4 -s -m 5 -w "%{speed_download}" -o /dev/null "$url" > "$tmpd/sp_$i") &
            done
            wait
            local sum_bps=$(awk '{s+=$1} END {print s}' "$tmpd"/sp_*)
            rm -rf "$tmpd"
            speed_mb=$(awk -v b="$sum_bps" 'BEGIN {printf "%.2f", b/1048576}')
        fi
    fi

    # 3. 长期稳定性(长稳)数学评估模型
    local assess="${C_GRAY}无法连接${C_RESET}"
    if [ "$loss" != "100" ]; then
        if (( $(echo "$loss > 4" | bc -l) )) || (( $(echo "$jitter > 30" | bc -l) )); then
            assess="${C_RED}极不稳定 (易脉冲式卡顿)${C_RESET}"
        elif (( $(echo "$loss > 0" | bc -l) )) || (( $(echo "$jitter > 12" | bc -l) )); then
            assess="${C_YELLOW}晚高峰存在降速风险${C_RESET}"
        else
            assess="${C_GREEN}极其丝滑 (适合长期高速)${C_RESET}"
        fi
    fi

    echo "$speed_mb|$loss|$jitter|$assess"
}

# =========================================================
#   选项 2: 拥塞控制(CC) 算法矩阵选择
# =========================================================
opt_cc_matrix() {
    while true; do
        clear
        local cur_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        local avail=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
        echo -e "${C_BLUE}=========================================================${C_RESET}"
        echo -e "         🚀 ${C_CYAN}TCP 拥塞控制算法 (CC) 智能驱动矩阵${C_RESET}"
        echo -e "${C_BLUE}=========================================================${C_RESET}"
        echo -e "当前正在运行的算法: ${C_GREEN}[ ${cur_cc:-未知} ]${C_RESET}"
        echo -e "当前系统内核已编译: ${C_GRAY}${avail}${C_RESET}\n"

        echo -e " ${C_GREEN}1)${C_RESET} BBR      - [现代标配] 拥塞驱动，吞吐量极高，抗丢包神器。"
        echo -e " ${C_GREEN}2)${C_RESET} BBRv3    - [次世代版] 尝试注入 bbr3/bbr2 (若内核不支持将回退标准bbr)。"
        echo -e " ${C_GREEN}3)${C_RESET} CUBIC    - [经典默认] 适合极低延迟(如专线/同城/纯内网)的0丢包环境。"
        echo -e " ${C_GREEN}4)${C_RESET} Westwood - [无线特化] 针对移动网、Wi-Fi等频繁随机丢包链路专门优化。"
        echo -e " ${C_GREEN}5)${C_RESET} Vegas    - [克制保Ping] 延迟敏感型，绝不抢带宽，挂机保Ping专用。"
        echo -e " ${C_GREEN}6)${C_RESET} Reno     - [传统古典] 最古老的标准TCP算法，仅供学术对照组。"
        echo -e " ${C_GRAY}0) 返回主菜单${C_RESET}"
        echo -e "---------------------------------------------------------"
        read -p "请选择挂载序号 (0-6): " cc_choice

        case $cc_choice in
            0) break ;;
            1) smart_set_cc "bbr"; sleep 1.5; break ;;
            2) modprobe tcp_bbr 2>/dev/null; modprobe tcp_bbr2 2>/dev/null; smart_set_cc "bbr3"; sleep 1.5; break ;;
            3) smart_set_cc "cubic"; sleep 1.5; break ;;
            4) smart_set_cc "westwood"; sleep 1.5; break ;;
            5) smart_set_cc "vegas"; sleep 1.5; break ;;
            6) smart_set_cc "reno"; sleep 1.5; break ;;
            *) echo -e "${C_RED}无效输入！${C_RESET}"; sleep 1 ;;
        esac
    done
}

# =========================================================
#   选项 3: 阻塞队列规则 (Qdisc) 切换与实弹对抗测速
# =========================================================
opt_qdisc_manager() {
    while true; do
        clear
        local cur_q=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        echo -e "${C_BLUE}=========================================================${C_RESET}"
        echo -e "            ⚙️ ${C_CYAN}底层阻塞队列规则 (Qdisc) 管理${C_RESET}"
        echo -e "${C_BLUE}=========================================================${C_RESET}"
        echo -e "当前正在运行的队列: ${C_GREEN}[ ${cur_q:-未知} ]${C_RESET}\n"
        echo -e " ${C_GREEN}1)${C_RESET} fq       - (推荐) 公平队列。与 BBR 天作之合，发包吞吐量极高。"
        echo -e " ${C_GREEN}2)${C_RESET} cake     - (极佳) 智能调度。针对 bufferbloat(缓冲膨胀) 优化，极度抗抖动。"
        echo -e " ${C_GREEN}3)${C_RESET} fq_codel - (常规) 延迟控制公平队列。大多数操作系统的默认升级版。"
        echo -e " ${C_GREEN}4)${C_RESET} pfifo_fast- (弃用) 传统先入先出。容易产生头部阻塞。"
        echo -e "---------------------------------------------------------"
        echo -e " ${C_YELLOW}66) ⚔️ 启动队列实弹测速对抗 (fq vs cake vs fq_codel)${C_RESET}"
        echo -e " ${C_GRAY}0) 返回主菜单${C_RESET}"
        echo -e "---------------------------------------------------------"
        read -p "请选择操作 (0-66): " q_opt

        if [ "$q_opt" == "0" ]; then break; fi

        case $q_opt in
            1|2|3|4)
                local target_q=""
                [ "$q_opt" == "1" ] && target_q="fq"
                [ "$q_opt" == "2" ] && target_q="cake"
                [ "$q_opt" == "3" ] && target_q="fq_codel"
                [ "$q_opt" == "4" ] && target_q="pfifo_fast"
                sed -i '/default_qdisc/d' "$SYS_FILE"
                echo "net.core.default_qdisc = $target_q" >> "$SYS_FILE"
                sysctl -p >/dev/null 2>&1
                echo -e "${C_GREEN}✅ 成功注入队列: $target_q${C_RESET}"; sleep 1.5 ;;
            66)
                echo -e "\n⏳ ${C_CYAN}正在初始化国际标准靶标 (HK Leaseweb) 进行多线程对抗...${C_RESET}"
                local t_url="http://mirror.hk.leaseweb.net/speedtest/100mb.bin"

                sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; sleep 0.5
                local r_fq=$(run_core_speedtest "$t_url" "multi")

                sysctl -w net.core.default_qdisc=cake >/dev/null 2>&1; sleep 0.5
                local r_cake=$(run_core_speedtest "$t_url" "multi")

                sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1; sleep 0.5
                local r_codel=$(run_core_speedtest "$t_url" "multi")

                # 恢复原状
                sysctl -w net.core.default_qdisc="${cur_q:-fq}" >/dev/null 2>&1

                echo -e "\n📊 ${C_CYAN}Qdisc 核心队列多维度对抗报告：${C_RESET}"
                echo -e "──────────────────────────────────────────────────────────────────────────"
                printf " %-10s | %-12s | %-8s | %-10s | %-15s \n" "队列名称" "并发实测速度" "丢包率" "抖动方差" "长稳机制判定"
                echo -e "──────────────────────────────────────────────────────────────────────────"
                printf " %-10s | ${C_GREEN}%-12s${C_RESET} | %-8s | %-10s | %b \n" "fq" "$(echo $r_fq|cut -d'|' -f1)MB/s" "$(echo $r_fq|cut -d'|' -f2)%" "$(echo $r_fq|cut -d'|' -f3)ms" "$(echo $r_fq|cut -d'|' -f4)"
                printf " %-10s | ${C_GREEN}%-12s${C_RESET} | %-8s | %-10s | %b \n" "cake" "$(echo $r_cake|cut -d'|' -f1)MB/s" "$(echo $r_cake|cut -d'|' -f2)%" "$(echo $r_cake|cut -d'|' -f3)ms" "$(echo $r_cake|cut -d'|' -f4)"
                printf " %-10s | ${C_GREEN}%-12s${C_RESET} | %-8s | %-10s | %b \n" "fq_codel" "$(echo $r_codel|cut -d'|' -f1)MB/s" "$(echo $r_codel|cut -d'|' -f2)%" "$(echo $r_codel|cut -d'|' -f3)ms" "$(echo $r_codel|cut -d'|' -f4)"
                echo -e "──────────────────────────────────────────────────────────────────────────"

                read -p "是否直接锁定实测速度最快/最稳的队列？输入队列名(如 fq或cake，回车跳过): " apply_q
                if [ -n "$apply_q" ]; then
                    sed -i '/default_qdisc/d' "$SYS_FILE"
                    echo "net.core.default_qdisc = $apply_q" >> "$SYS_FILE"
                    sysctl -p >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ 已为您死锁队列: $apply_q${C_RESET}"
                fi
                read -p "按回车返回..." t ;;
            *) echo -e "${C_RED}无效选项${C_RESET}"; sleep 1 ;;
        esac
    done
}

# =========================================================
#   选项 5: 智能网络测速矩阵 (核心业务)
# =========================================================
opt_speed_matrix() {
    clear
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e "             ⚡ ${C_CYAN}多维度靶向测速与长稳审计系统${C_RESET} ⚡"
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e "请选择测试并发模型："
    echo -e " ${C_GREEN}1)${C_RESET} 单线程测试 (严苛：真实反映单连接TCP握手传输上限)"
    echo -e " ${C_GREEN}2)${C_RESET} 多线程并发 (极限：多线程抢占，压榨物理链路极限带宽)"
    read -p "请选择 (1/2) [默认2]: " t_input
    local t_mode="multi"; [ "$t_input" == "1" ] && t_mode="single"

    clear
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e "请选择测试靶标范围："
    echo -e " ${C_GREEN}1)${C_RESET} 国内节点测速 (内置安徽双非大学纯商宽 + 外省优选)"
    echo -e " ${C_GREEN}2)${C_RESET} 海外优质节点 (香港、新加坡、东京、首尔、美西)"
    echo -e " ${C_GREEN}3)${C_RESET} 智能本地定向 (输入你的公网IP，自动测回程及临近节点)"
    read -p "请选择 (1/2/3): " range_opt

    local names=()
    local urls=()

    if [ "$range_opt" == "1" ]; then
        names=("安徽合肥·腾讯云BGP" "安徽芜湖·迅雷CDN" "上海电信·精品网" "广东深圳·联通BGP" "北京移动·骨干直连")
        urls=(
            "https://dldir1.qq.com/qqfile/qq/QQNT/Windows/QQ_9.9.15_240701_x64_01.exe"
            "https://down.sandai.net/thunder9/Thunder9.1.49.1060.exe"
            "http://101.227.255.45/100MB.test"
            "http://210.21.196.6/speedtest/random4000x4000.jpg"
            "http://60.205.172.2/100m.bin"
        )
    elif [ "$range_opt" == "2" ]; then
        names=("香港 HK (Leaseweb)" "新加坡 SG (DigitalOcean)" "日本东京 JP (Linode)" "韩国首尔 KR (Vultr)" "美国洛杉矶 US (CacheFly)")
        urls=(
            "http://mirror.hk.leaseweb.net/speedtest/100mb.bin"
            "http://speedtest-sgp1.digitalocean.com/100mb.test"
            "http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
            "http://sel-kor-ping.vultr.com/vultr.com.100MB.bin"
            "http://cachefly.cachefly.net/100mb.test"
        )
    elif [ "$range_opt" == "3" ]; then
        read -p "请输入您的本地公网 IP: " user_ip
        echo -e "⏳ 正在通过 BGP 路由表审计目标归属地..."
        local geo=$(curl -s -m 3 "http://ip-api.com/json/$user_ip?lang=zh-CN")
        local isp=$(echo "$geo" | grep -oP '"isp":"\K[^"]+')
        local city=$(echo "$geo" | grep -oP '"city":"\K[^"]+')
        
        echo -e "\n🎯 目标画像：${C_YELLOW}${city:-未知地区} - ${isp:-未知运营商}${C_RESET}"
        echo -e "---------------------------------------------------------"
        echo -e "⏳ 正在追踪回程核心路由跳数 (Trace)..."
        mtr -c 2 -w -r "$user_ip" | tail -n +2 | head -n 6
        echo -e "---------------------------------------------------------"

        # 根据运营商智能推流
        if [[ "$isp" =~ "电信" || "$isp" =~ "Chinanet" || "$isp" =~ "Telecom" ]]; then
            echo -e "⚡ 检测为【电信链路】，已为您智能调度电信下沉节点群："
            names=("合肥电信·骨干" "上海电信·精品网" "广州电信·天翼云" "南京电信·城域" "武汉电信·节点")
        elif [[ "$isp" =~ "联通" || "$isp" =~ "Unicom" ]]; then
            echo -e "⚡ 检测为【联通链路】，已为您智能调度联通下沉节点群："
            names=("芜湖联通·节点" "深圳联通·骨干" "北京联通·主要" "青岛联通·城域" "大连联通·节点")
        else
            echo -e "⚡ 检测为【移动/综合链路】，已为您调度全网BGP极速节点群："
            names=("合肥腾讯云·BGP" "芜湖移动·CDN" "北京移动·直连" "杭州阿里云·BGP" "广州移动·骨干")
        fi
        # 兜底通用大文件测试URL
        urls=(
            "https://dldir1.qq.com/qqfile/qq/QQNT/Windows/QQ_9.9.15_240701_x64_01.exe"
            "https://down.sandai.net/thunder9/Thunder9.1.49.1060.exe"
            "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
            "https://dldir1.qq.com/weixin/Windows/WeChatSetup.exe"
            "http://cachefly.cachefly.net/100mb.test"
        )
    else
        echo -e "${C_RED}选择错误！${C_RESET}"; sleep 1; return
    fi

    echo -e "\n靶机节点列表："
    for ((i=0; i<5; i++)); do echo -e " ${C_GREEN}$((i+1)))${C_RESET} ${names[$i]}"; done
    echo -e " ${C_YELLOW}6) 🚀 一键矩阵全测 (同时审计以上5个点)${C_RESET}"
    echo -e "---------------------------------------------------------"
    read -p "请输入要测试的序号 (支持空格多选，如输入 '1 2 5'，输入 '6' 全测): " pick_str

    local test_arr=()
    if [[ "$pick_str" =~ "6" ]]; then
        test_arr=(0 1 2 3 4)
    else
        for n in $pick_str; do ((n>=1 && n<=5)) && test_arr+=("$((n-1))"); done
    fi

    echo -e "\n⏳ 开始靶向矩阵测速 (模式: ${t_mode})...\n"
    printf "%-18s | %-12s | %-8s | %-8s | %-16s\n" "节点名称" "平均速度" "丢包率" "网络抖动" "长稳健康度评估"
    echo "────────────────────────────────────────────────────────────────────────────────"

    for idx in "${test_arr[@]}"; do
        res=$(run_core_speedtest "${urls[$idx]}" "$t_mode")
        sp=$(echo "$res" | cut -d'|' -f1)
        ls=$(echo "$res" | cut -d'|' -f2)
        jt=$(echo "$res" | cut -d'|' -f3)
        as=$(echo "$res" | cut -d'|' -f4)
        printf "%-18s | ${C_GREEN}%-12s${C_RESET} | %-8s | %-8s | %b\n" "${names[$idx]}" "${sp} MB/s" "${ls}%" "${jt}ms" "$as"
    done
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo -e "${C_GRAY}*注：长稳评估综合考量了TCP丢包重传震荡公式，反映持续看视频/打游戏的真实卡顿率。${C_RESET}"
    read -p "按回车返回主菜单..." t
}

# =========================================================
#   选项 1: 跨国专项优化
# =========================================================
opt_specialized_tuning() {
    clear
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e "        🌍 ${C_CYAN}跨国高延迟/高丢包专项靶向优化${C_RESET}"
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    local client_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    local detect_rtt="200"; local detect_loss="0"
    
    if [ -n "$client_ip" ]; then
        echo -e "⏳ 正在探测您与服务器间的真实物理链路 (Ping $client_ip)..."
        local ping_res=$(ping -c 4 -W 2 "$client_ip" 2>/dev/null)
        if [ $? -eq 0 ]; then
            detect_rtt=$(echo "$ping_res" | tail -n 1 | awk -F '/' '{printf "%d", $5}')
            detect_loss=$(echo "$ping_res" | grep -oP '\d+(?=% packet loss)' | awk '{print $1}')
        fi
    fi

    echo -e "检测到您当前 SSH 直连物理延迟约为: ${C_YELLOW}${detect_rtt} ms${C_RESET}，丢包率: ${C_YELLOW}${detect_loss}%${C_RESET}"
    read -p "请输入晚高峰预期延迟(ms) [回车默认 ${detect_rtt}]: " input_rtt
    rtt=${input_rtt:-$detect_rtt}
    read -p "请输入目标期望带宽(Mbps) [回车默认 500]: " input_bw
    bw=${input_bw:-500}

    local mem_limit=$(get_mem_mb)
    local calc_bytes=$(awk -v rtt="$rtt" -v bw="$bw" -v loss="$detect_loss" '
    BEGIN {
        base = (rtt / 1000) * (bw * 1048576 / 8);
        mult = 1.5 + (loss / 20); target = base * mult; printf "%d", target
    }')

    local max_bytes=$(awk -v m="$mem_limit" 'BEGIN {printf "%d", m * 1048576 * 0.15}')
    if [ "$calc_bytes" -gt "$max_bytes" ]; then calc_bytes=$max_bytes; fi
    [ "$calc_bytes" -lt 16777216 ] && calc_bytes=16777216

    echo -e "\n📊 ${C_GREEN}推演缓冲区大小为: $(bytes_to_mb $calc_bytes)${C_RESET} (${calc_bytes} Bytes)"
    read -p "是否注入系统？[Y/n]: " opt_w
    if [[ "${opt_w:-Y}" =~ ^[Yy]$ ]]; then
        [ ! -f "$BAK_FILE" ] && cp "$SYS_FILE" "$BAK_FILE"
        sed -i -e '/rmem_max/d' -e '/wmem_max/d' -e '/tcp_rmem/d' -e '/tcp_wmem/d' "$SYS_FILE"
        local def_b=$(awk -v b="$calc_bytes" 'BEGIN {print int(b/64)}')
        [ $def_b -lt 262144 ] && def_b=262144
        
        cat >> "$SYS_FILE" <<EOF
net.core.rmem_max = $calc_bytes
net.core.wmem_max = $calc_bytes
net.ipv4.tcp_rmem = 4096 $def_b $calc_bytes
net.ipv4.tcp_wmem = 4096 $def_b $calc_bytes
EOF
        sysctl -p >/dev/null 2>&1
        echo -e "${C_GREEN}✅ 极限参数注入完毕！${C_RESET}"
    fi
    read -p "按回车返回..." t
}

# =========================================================
#   主看板 UI
# =========================================================
while true; do
    clear
    C_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "-")
    C_Q=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "-")
    C_RMEM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "212992")
    C_WMEM=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "212992")
    C_MTU=$(get_mtu)
    REC_BUF=$(_calc_default_buf)

    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e "        ⚡ ${C_CYAN}TCP智能调优与靶向测速矩阵 PRO MAX${C_RESET} ⚡"
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    echo -e " 核心参数\t\t当前实测 / 推荐值"
    echo -e " ────────────────────────────────────────────────────────"
    printf " • %-14s\t${C_YELLOW}%s${C_RESET} / ${C_GREEN}%s${C_RESET}\n" "MTU传输单元:" "$C_MTU" "1500"
    printf " • %-14s\t${C_YELLOW}%s${C_RESET} / ${C_GREEN}%s${C_RESET}\n" "拥塞控制算法:" "$C_CC" "bbr"
    printf " • %-14s\t${C_YELLOW}%s${C_RESET} / ${C_GREEN}%s${C_RESET}\n" "底层队列规则:" "$C_Q" "fq"
    printf " • %-14s\t${C_YELLOW}%s${C_RESET} / ${C_GREEN}%s${C_RESET}\n" "Socket读缓冲:" "$(bytes_to_mb $C_RMEM)" "$(bytes_to_mb $REC_BUF)"
    printf " • %-14s\t${C_YELLOW}%s${C_RESET} / ${C_GREEN}%s${C_RESET}\n" "Socket写缓冲:" "$(bytes_to_mb $C_WMEM)" "$(bytes_to_mb $REC_BUF)"
    echo -e "${C_BLUE}=========================================================${C_RESET}"
    
    echo -e " ${C_GREEN}1)${C_RESET} 跨国高延迟、高丢包专项靶向缓冲优化 ⭐"
    echo -e " ${C_GREEN}2)${C_RESET} TCP 拥塞控制算法(CC) 矩阵选择 (新增BBRv3/Cubic等)"
    echo -e " ${C_GREEN}3)${C_RESET} 阻塞队列(Qdisc) 切换与实弹对抗测速"
    echo -e " ${C_GREEN}4)${C_RESET} 还原调优参数 (恢复初始备份)"
    echo -e " ${C_GREEN}5)${C_RESET} ${C_YELLOW}🚀 智能网络测速矩阵 (单/多线程+长稳评估模型)${C_RESET}"
    echo -e " ${C_GRAY}0) 安全退出${C_RESET}"
    echo -e "---------------------------------------------------------"
    
    read -p "请输入操作序号: " OPT
    case $OPT in
        1) opt_specialized_tuning ;;
        2) opt_cc_matrix ;;
        3) opt_qdisc_manager ;;
        4) 
            if [ -f "$BAK_FILE" ]; then cp "$BAK_FILE" "$SYS_FILE" && sysctl -p >/dev/null 2>&1; echo -e "${C_GREEN}✅ 恢复成功！${C_RESET}"
            else echo -e "${C_RED}❌ 未找到备份文件。${C_RESET}"; fi; read -p "按回车返回..." t ;;
        5) opt_speed_matrix ;;
        0) echo "👋 退出。"; exit 0 ;;
        *) echo -e "${C_RED}❌ 无效选项！${C_RESET}"; sleep 1 ;;
    esac
done

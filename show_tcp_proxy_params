#!/bin/bash
# show_tcp_proxy_params.sh - 代理节点TCP调优参数（MB单位 + BBR/FQ状态）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "============================================================="
echo -e "${GREEN}         代理节点相关 TCP 内核调优参数（MB 单位）${NC}"
echo "============================================================="
echo ""

# ---------- 1. 核心缓冲区（以MB显示） ----------
echo -e "${YELLOW}--- 核心缓冲区（单位：MB） ---${NC}"
# 字节型参数列表
byte_params=(
    "net.core.rmem_max:接收缓冲区上限"
    "net.core.wmem_max:发送缓冲区上限"
    "net.core.rmem_default:接收缓冲区默认值"
    "net.core.wmem_default:发送缓冲区默认值"
    "net.ipv4.tcp_limit_output_bytes:单次write上限"
)

for item in "${byte_params[@]}"; do
    param="${item%%:*}"
    desc="${item#*:}"
    value=$(sysctl -n "$param" 2>/dev/null)
    if [[ -z "$value" ]]; then
        printf "%-35s %-15s %s\n" "$param:" "N/A" "$desc"
        continue
    fi
    # 使用 awk 计算 MB，保留两位小数
    mb=$(echo "$value 1024 1024" | awk '{printf "%.2f", $1/$2/$3}')
    printf "%-35s %-15s %s\n" "$param:" "${mb} MB" "$desc"
done

# netdev_max_backlog 是个数，不是字节，单独显示
param="net.core.netdev_max_backlog"
value=$(sysctl -n "$param" 2>/dev/null)
if [[ -n "$value" ]]; then
    printf "%-35s %-15s %s\n" "$param:" "$value" "未处理数据包数(个)"
else
    printf "%-35s %-15s %s\n" "$param:" "N/A" "未处理数据包数(个)"
fi

echo ""

# ---------- 2. TCP动态缓冲区范围（rmem/wmem，三个值） ----------
echo -e "${YELLOW}--- TCP 动态缓冲区范围（最小 默认 最大，单位：MB） ---${NC}"
for param in net.ipv4.tcp_rmem net.ipv4.tcp_wmem; do
    value=$(sysctl -n "$param" 2>/dev/null)
    if [[ -n "$value" ]]; then
        read -r min def max <<< "$value"
        min_mb=$(echo "$min 1024 1024" | awk '{printf "%.2f", $1/$2/$3}')
        def_mb=$(echo "$def 1024 1024" | awk '{printf "%.2f", $1/$2/$3}')
        max_mb=$(echo "$max 1024 1024" | awk '{printf "%.2f", $1/$2/$3}')
        printf "%-25s %-10s %-10s %-10s\n" "$param:" "${min_mb}MB" "${def_mb}MB" "${max_mb}MB"
    else
        printf "%-25s %s\n" "$param:" "N/A"
    fi
done
echo ""

# ---------- 3. 其他重要参数（原值显示，非字节） ----------
echo -e "${YELLOW}--- 其他关键参数 ---${NC}"
other_params=(
    "net.ipv4.tcp_window_scaling:窗口缩放(0/1)"
    "net.ipv4.tcp_syncookies:SYN Cookie(0/1)"
    "net.ipv4.tcp_tw_reuse:TIME-WAIT复用(0/1)"
    "net.ipv4.tcp_fin_timeout:FIN-WAIT-2超时(秒)"
    "net.ipv4.tcp_keepalive_time:Keepalive空闲(秒)"
    "net.ipv4.tcp_keepalive_intvl:Keepalive间隔(秒)"
    "net.ipv4.tcp_keepalive_probes:Keepalive探测次数"
    "net.ipv4.ip_local_port_range:本地端口范围"
    "net.ipv4.tcp_max_syn_backlog:SYN队列长度"
    "vm.swappiness:交换倾向(0-100)"
    "fs.file-max:系统最大文件句柄"
)

for item in "${other_params[@]}"; do
    param="${item%%:*}"
    desc="${item#*:}"
    value=$(sysctl -n "$param" 2>/dev/null)
    [[ -z "$value" ]] && value="N/A"
    printf "%-35s %-20s %s\n" "$param:" "$value" "$desc"
done

echo ""

# ---------- 4. 拥塞控制算法 & BBR 状态 ----------
echo -e "${YELLOW}--- 拥塞控制与队列规则 ---${NC}"
cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
echo -n "当前拥塞控制算法: "
if [[ "$cc" == "bbr" ]]; then
    echo -e "${GREEN}$cc${NC}"
else
    echo -e "$cc"
fi

# 检查内核是否支持BBR
if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
    echo -e "BBR 内核支持: ${GREEN}是${NC}"
else
    echo -e "BBR 内核支持: ${RED}否${NC}"
fi

# 检查当前是否使用bbr（如果cc是bbr则说明已启用）
if [[ "$cc" == "bbr" ]]; then
    echo -e "BBR 当前启用: ${GREEN}是${NC}"
else
    echo -e "BBR 当前启用: ${RED}否${NC}"
fi

# 默认qdisc
default_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
echo -n "默认 qdisc: $default_qdisc"

# 获取主要网卡（默认路由接口）的当前qdisc
default_iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
if [[ -n "$default_iface" ]]; then
    qdisc_info=$(tc qdisc show dev "$default_iface" 2>/dev/null | head -1)
    if [[ -n "$qdisc_info" ]]; then
        echo " (接口 $default_iface: $qdisc_info)"
    else
        echo " (无法获取 $default_iface 的qdisc)"
    fi
else
    echo " (无法获取默认接口)"
fi

echo ""
echo "============================================================="
echo -e "${GREEN}说明：${NC}"
echo "  - 缓冲区值已转换为 MB（保留两位小数），非字节参数保持原样"
echo "  - 'N/A' 表示参数不存在或无法读取"
echo "  - BBR 与 FQ 是高性能代理的推荐组合，请确认状态"
echo "  - 修改请编辑 /etc/sysctl.conf 并执行 sysctl -p 生效"
echo "============================================================="

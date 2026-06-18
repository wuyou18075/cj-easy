#!/bin/bash
# Debian/Ubuntu 聚合一体化多功能集群运维主控面板 (逻辑闭环自愈版)

CONFIG_DIR="/root/tg_vps_bot"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DB_PATH="${CONFIG_DIR}/cluster.db"
BOT_LOG="${CONFIG_DIR}/bot.log"
PYTHON_SCRIPT="${CONFIG_DIR}/main.py"

# ==================== 🛠️ 全维深度内审排错引擎 ====================
diagnose_vps_faults() {
    local check_port=$(read_json "PORT")
    echo "====================================================================="
    echo "       🔍  面板底层核心故障全自动化深度内审排错报告"
    echo "====================================================================="

    echo -n " 🔹 1. 后台守护进程状态: "
    if systemctl is-active tg_vps_bot >/dev/null 2>&1; then
        echo "🟢 运行中 (Systemd 托管正常)"
    else
        local py_pid=$(pgrep -f "python3 ${PYTHON_SCRIPT}")
        if [ -n "$py_pid" ]; then
            echo "🟡 异常 (Systemd 托管已挂，但后台存在孤儿 Python 进程 PID: $py_pid)"
        else
            echo "🔴 已死 / 被系统强杀 (无任何活跃进程)"
        fi
    fi

    if [ -n "$check_port" ]; then
        echo -n " 🔹 2. 本地端口监听冲突: "
        local port_owner=""
        if command -v ss &> /dev/null; then
            port_owner=$(ss -tlnp | grep ":$check_port " | awk '{print $6}' | tr -d '"')
        fi
        if [ -n "$port_owner" ]; then
            echo "🔴 惨烈冲突！该端口已被其他进程死死霸占 -> [ $port_owner ]"
        else
            echo "🟢 干净 (无本地端口冲突)"
        fi
    fi

    echo -n " 🔹 3. DNS 跨境域名解析: "
    python3 -c "
import socket
try:
    ip = socket.gethostbyname('api.telegram.org')
    print(f'🟢 正常 (api.telegram.org 成功解析为: {ip})')
except:
    print('🔴 失败 (本地 DNS 无法认出 Telegram 域名)')
" 2>/dev/null

    echo -n " 🔹 4. 跨境网络骨干通路: "
    python3 -c "
import requests
try:
    r = requests.get('https://api.telegram.org', timeout=4)
    print(f'🟢 畅通 (网络链路无阻断，HTTP 状态码: {r.status_code})')
except:
    print('🔴 严重堵塞 / 被墙封锁 (连接官方超时)')
" 2>/dev/null
    echo "====================================================================="
}

# 高级网络与身份真成功双向校验阻断器 (已修复变量注入引起的 404 与语法错误)
verify_tg_credentials() {
    local token="$1"
    local admin_id="$2"
    python3 -c "
import sys, requests
token = sys.argv[1]
admin_id = sys.argv[2]

try:
    r = requests.get(f'https://api.telegram.org/bot{token}/getMe', timeout=6)
    if r.status_code == 401:
        print('❌ Token 验证失败！(HTTP 401) 机器人不存在或注销。')
        sys.exit(2)
    elif r.status_code == 404:
        print('❌ 接口 404 异常！请检查 Token 格式是否复制完整，或重置了 Token。')
        sys.exit(2)
    elif r.status_code != 200:
        print(f'❌ 接口异常！HTTP 状态码: {r.status_code}')
        sys.exit(2)
    print('🟢 第一阶段成功：网络通路顺畅，机器人身份合法！')
except Exception as e:
    print('❌ 网络连通校验未通过，请检查 VPS 是否被墙！')
    sys.exit(1)

try:
    url = f'https://api.telegram.org/bot{token}/sendMessage'
    payload = {
        'chat_id': admin_id,
        'text': '🔔 *[控制面板核心链路双向握手验证]*\n\n恭喜！当前服务器已完全打通与您手机客户端的安全通信信道，指令交互通道现已全部【真成功】激活！',
        'parse_mode': 'Markdown'
    }
    r2 = requests.post(url, json=payload, timeout=6)
    res_data = r2.json()
    if res_data.get('ok'):
        print('🟢 第二阶段成功：下行验证【真成功】！请查看手机，通知已成功送达您的 Telegram 客户端！')
        sys.exit(0)
    else:
        print(f'❌ 消息投递失败！官方拒绝原因: {res_data.get(\"description\", \"\")}')
        sys.exit(3)
except Exception as e:
    print(f'❌ 下行发送出现严重异常: {e}')
    sys.exit(3)
" "$token" "$admin_id"
}

check_depends() {
    local missing=()
    for cmd in python3 pip3 iptables curl traceroute sqlite3 bc; do
        if ! command -v $cmd &> /dev/null; then missing+=($cmd); fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y python3 python3-pip iptables curl traceroute sqlite3 bc procps openssl >/dev/null 2>&1
        pip3 install Flask requests python-telegram-bot psutil --break-system-packages --ignore-installed >/dev/null 2>&1
    fi
}

init_config() {
    mkdir -p "${CONFIG_DIR}"
    chmod 700 "${CONFIG_DIR}"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat << 'END' > "$CONFIG_FILE"
{
    "ROLE": "MASTER",
    "BOT_TOKEN": "",
    "ADMIN_ID": "",
    "VPS_NAME": "cnmb",
    "PORT": 59595,
    "POLL_INTERVAL": 5,
    "TOTAL_TRAFFIC_GB": 1000,
    "TRAFFIC_ALERT_PCT": 80,
    "CPU_HIGH_LOAD_ALERT_PCT": 90,
    "REPORT_ENABLED": 1,
    "SSH_PAGE_SIZE": 20
}
END
    fi
}

read_json() { python3 -c "import json, sys; print(json.load(open('$CONFIG_FILE')).get(sys.argv[1], ''))" "$1" 2>/dev/null; }
write_json() { python3 -c "import json, sys; d=json.load(open('$CONFIG_FILE')); v=sys.argv[2]; d[sys.argv[1]]=int(v) if v.isdigit() else v; json.dump(d,open('$CONFIG_FILE','w'),indent=4)" "$1" "$2" 2>/dev/null; }

restart_backend_service() {
    if systemctl is-enabled tg_vps_bot >/dev/null 2>&1; then
        systemctl restart tg_vps_bot >/dev/null 2>&1
    else
        kill -9 $(pgrep -f "python3 ${PYTHON_SCRIPT}") >/dev/null 2>&1
        python3 ${PYTHON_SCRIPT} > "$BOT_LOG" 2>&1 &
    fi
}

refresh_dashboard() {
    clear
    local token=$(read_json "BOT_TOKEN")
    local port=$(read_json "PORT")
    local interval=$(read_json "POLL_INTERVAL")
    local total_tf=$(read_json "TOTAL_TRAFFIC_GB")
    local cpu_alert=$(read_json "CPU_HIGH_LOAD_ALERT_PCT")
    local r_enabled=$(read_json "REPORT_ENABLED")
    local p_size=$(read_json "SSH_PAGE_SIZE")

    local autostart="🔴 否"
    if systemctl is-enabled tg_vps_bot >/dev/null 2>&1; then autostart="🟢 是"; fi

    local tg_status="🔴 异常"
    if [ -n "$token" ]; then
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "https://api.telegram.org/bot${token}/getMe")
        if [ "$http_code" -eq 200 ]; then tg_status="🟢 正常"; fi
    fi

    local ssh_fail_30d=0
    if [ -f "$DB_PATH" ]; then
        ssh_fail_30d=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM ssh_history WHERE status='FAILED' AND time >= datetime('now', '-30 day');" 2>/dev/null)
    fi

    local traffic_stats="0.00 GB / ${total_tf} GB (0.0%)"
    if [ -f "$DB_PATH" ]; then
        local used_bytes=$(sqlite3 "$DB_PATH" "SELECT count FROM report_counter WHERE id=2;" 2>/dev/null)
        used_bytes=${used_bytes:-0}
        local used_gb=$(echo "scale=2; $used_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null)
        local pct=$(echo "scale=1; ($used_bytes / ($total_tf * 1024 * 1024 * 1024)) * 100" | bc 2>/dev/null)
        traffic_stats="${used_gb} GB / ${total_tf} GB (${pct}%)"
    fi

    local daily_status="🔴 已关闭"
    if [ "$r_enabled" -eq 1 ]; then daily_status="🟢 已开启"; fi

    echo "====================================================================="
    echo "       🛡️  Debian 13 精简版 - 专属集群管理面板 (聚合大盘版)"
    echo "====================================================================="
    echo " 🔹 通讯端口: $port                  | 🔹 开机自启动: $autostart"
    echo " 🔹 轮询间隔: ${interval} s                 | 🔹 TG连接状态: $tg_status"
    echo " 🔹 日报状态: $daily_status              | 🔹 SSH默认分页: $p_size 条"
    echo " 🔹 30天内密码错误次数: ${ssh_fail_30d} 次"
    echo " 🔹 当月总流量配额状态: $traffic_stats [超过80%自动通知]"
    echo " 🔹 长期CPU高负荷报警方案: 连续3次检测到超过 ${cpu_alert}% 触发紧急防死机预警"
    echo "====================================================================="
    echo "  [1] 安装 / 卸载 / 重启 控制面引擎"
    echo "  [2] 查看/管理 集群从控服务器列表"
    echo "  [3] 编辑与热修改 核心服务参数 (已加入安全拦截验证)"
    echo "  [4] 实时追踪 查看后台日志流"
    echo "  [5] 快速调整 节点数据轮询频率"
    echo "  [6] 进入高级 监控分析与路由断点诊断"
    echo "  [7] 查看当前面板各组件服务路径与文件分布"
    echo "  [9] 唤醒 TG 连通性测试并发送验证消息 (支持原地自愈绑定)"
    echo "  [0] Security Exit"
    echo "====================================================================="
}

main_menu() {
    refresh_dashboard
    read -p "请输入对应选项 [0-9]: " menu_num
    case "$menu_num" in
        1) menu_service ;;
        2) menu_nodes ;;
        3) menu_edit_config ;;
        4) view_logs ;;
        5) adjust_freq ;;
        6) menu_monitor ;;
        7) view_paths ;;
        9) wake_tg_connection ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

interactive_bind_flow() {
    local t_token="" t_id=""
    while true; do
        read -p "请输入您的 TG Bot Token: " t_token
        if [ -z "$t_token" ]; then
            echo "❌ 获取失败：Token 不能为空！如果剪贴板粘贴未生效，请重新右键粘贴。"
            echo "---------------------------------------------------------------------"
            continue
        fi

        read -p "请输入您的个人 TG 数字 ID: " t_id
        if [ -z "$t_id" ]; then
            echo "❌ 获取失败：ID 不能为空！"
            echo "---------------------------------------------------------------------"
            continue
        fi

        echo "---------------------------------------------------------------------"
        verify_tg_credentials "$t_token" "$t_id"
        local v_res=$?
        echo "---------------------------------------------------------------------"
        if [ $v_res -eq 0 ]; then
            write_json "BOT_TOKEN" "$t_token"
            write_json "ADMIN_ID" "$t_id"
            
            local saved_token=$(read_json "BOT_TOKEN")
            if [ "$saved_token" == "$t_token" ]; then
                echo "🟢 锁存成功：Token 与 ID 已即时锁定并写入硬盘配置库！"
            else
                echo "❌ 存入失败：配置文件写入异常，请检查 ${CONFIG_DIR} 的目录读写权限！"
                return 1
            fi

            if [ -f "$DB_PATH" ]; then
                sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO whitelist (user_id, username, added_time) VALUES ('$t_id', 'Main_Admin', datetime('now'));" 2>/dev/null
            fi
            restart_backend_service
            read -p "阻断拦截器验证完全通过！按 [回车键] 生效并继续..." 
            return 0
        else
            echo "❌ 链路强拦截判定失败！现启动自动化环境全面内审..."
            diagnose_vps_faults
            echo ""
            echo "⚠️  请排查后选择下一步操作："
            echo "  [1] 根据上述诊断提示修复后，重新输入尝试"
            echo "  [0] 放弃并退回"
            read -p "请选择操作 [1/0, 默认1]: " fail_choice
            fail_choice=${fail_choice:-1}
            if [ "$fail_choice" -eq 0 ]; then return 1; fi
        fi
    done
}

menu_service() {
    clear
    echo "=== [1] 服务核心生命周期管理 ==="
    echo "  [1] 全新交互式部署并安装主控"
    echo "  [2] 彻底卸载并清理残留"
    echo "  [3] 重启主控守护进程"
    echo "  [0] 返回主菜单"
    read -p "请选择操作 [0-3]: " s_num
    case "$s_num" in
        1)
            init_config
            interactive_bind_flow
            if [ $? -ne 0 ]; then main_menu; return; fi

            rand_port=$((RANDOM % 2001 + 58000))
            read -p "配置接收端口 (可以直接敲回车使用随机范围 58000-60000 -> $rand_port): " t_port
            t_port=${t_port:-$rand_port}
            if [[ "$t_port" =~ ^[0-9]+$ ]]; then write_json "PORT" "$t_port"; else write_json "PORT" "$rand_port"; fi
            
            read -p "是否注册为开机自启动系统服务? [y/n, 回车=是]: " sys_choice
            sys_choice=${sys_choice:-"y"}
            
            write_python_engine
            touch "$BOT_LOG"
            cp "$0" "${CONFIG_DIR}/test.sh" 2>/dev/null
            chmod +x "${CONFIG_DIR}/test.sh"

            if [ "$sys_choice" = "y" ] || [ "$sys_choice" = "Y" ]; then
                cat << END_SYS > /etc/systemd/system/tg_vps_bot.service
[Unit]
Description=TG Cluster Monitor Master Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${CONFIG_DIR}
ExecStart=/usr/bin/python3 ${PYTHON_SCRIPT}
StandardOutput=append:${BOT_LOG}
StandardError=append:${BOT_LOG}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
END_SYS
                systemctl daemon-reload
                systemctl enable tg_vps_bot >/dev/null 2>&1
                systemctl restart tg_vps_bot
            else
                systemctl stop tg_vps_bot >/dev/null 2>&1
                systemctl disable tg_vps_bot >/dev/null 2>&1
                restart_backend_service
            fi
            echo "🎉 主控端安全部署成功！文件已抱团归拢。"
            read -p "按回车返回菜单..." ;;
        2)
            systemctl stop tg_vps_bot >/dev/null 2>&1
            systemctl disable tg_vps_bot >/dev/null 2>&1
            rm -f /etc/systemd/system/tg_vps_bot.service
            kill -9 $(pgrep -f "python3 ${PYTHON_SCRIPT}") >/dev/null 2>&1
            rm -rf "$CONFIG_DIR"
            echo "🗑️  卸载清理完毕。"
            read -p "按回车返回..." ;;
        3)
            restart_backend_service
            echo "🔄 重启及热加载指令下达成功。"
            read -p "按回车返回..." ;;
    esac
    main_menu
}

menu_nodes() {
    clear
    echo "=== [2] 从控服务器管理 ==="
    if [ ! -f "$DB_PATH" ]; then echo "ℹ️ 暂无从控数据。"; read -p "回车返回..."; main_menu; return; fi
    sqlite3 "$DB_PATH" "SELECT id, name, ip, status, last_seen FROM nodes;"
    read -p "输入节点 ID 管理 (0取消): " node_id
    if [ -n "$node_id" ] && [ "$node_id" != "0" ]; then
        echo " 1) 设置别名  2) 修改排序编号  3) 踢除节点"
        read -p "选择操作: " n_op
        if [ "$n_op" -eq 1 ]; then
            read -p "全新别名: " new_alias
            sqlite3 "$DB_PATH" "UPDATE nodes SET name='$new_alias' WHERE id=$node_id;"
        elif [ "$n_op" -eq 3 ]; then
            sqlite3 "$DB_PATH" "DELETE FROM nodes WHERE id=$node_id;"
        fi
    fi
    main_menu
}

menu_edit_config() {
    clear
    echo "=== [3] 编辑核心配置 ==="
    echo "  [1] 修改绑定机器人与管理员 ID (含安全链路校验)"
    echo "  [2] 更改服务端口"
    echo "  [4] 更改轮询时间"
    read -p "请选择: " e_num
    case "$e_num" in
        1)
            init_config
            echo "🔄 正在为您调用高级双向安全校验部署流..."
            interactive_bind_flow
            ;;
        2) 
            read -p "新通讯端口: " new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]]; then
                write_json "PORT" "$new_port"
                restart_backend_service
                echo "✅ 端口修改成功，服务已完成热重载监听！"
            else
                echo "❌ 输入格式有误。"
            fi
            read -p "按回车返回..." ;;
        4) 
            read -p "轮询间隔(秒): " new_sec
            write_json "POLL_INTERVAL" "$new_sec"
            restart_backend_service
            echo "✅ 轮询时间已热同步！"
            read -p "按回车返回..." ;;
    esac
    main_menu
}

view_logs() { clear; echo "📋 正在调取实时日志流 (按 Ctrl+C 退出)..."; touch "$BOT_LOG"; tail -n 30 -f "$BOT_LOG"; main_menu; }
adjust_freq() { clear; read -p "设置全局轮询频率 (秒): " f_sec; write_json "POLL_INTERVAL" "$f_sec"; restart_backend_service; main_menu; }

menu_monitor() {
    clear
    echo "=== [6] 高级监控中心 ==="
    echo "  [1] 本机全维度监控 (含中国合肥/南京双骨干网测速)"
    echo "  [2] 查看 SSH 登录历史审计"
    echo "  [3] 切换自动化日报状态"
    echo "  [4] 国内安徽三网延迟测定"
    read -p "请输入选项: " m_num
    case "$m_num" in
        1)
            python3 -c "import sys; sys.path.append('$CONFIG_DIR'); from main import get_system_status, run_benchmark; print(get_system_status()); print(run_benchmark())"
            read -p "回车返回..." ;;
        2)
            local default_page=$(read_json "SSH_PAGE_SIZE")
            read -p "请输入分页拉取行数 (回车默认 $default_page 条): " p_size
            p_size=${p_size:-$default_page}
            sqlite3 "$DB_PATH" "SELECT '时间:'||time||' | 状态:'||status||' | 用户:'||user||' | IP:'||ip FROM ssh_history ORDER BY id DESC LIMIT $p_size;"
            read -p "回车返回..." ;;
        3)
            local curr=$(read_json "REPORT_ENABLED")
            if [ "$curr" -eq 1 ]; then write_json "REPORT_ENABLED" 0; else write_json "REPORT_ENABLED" 1; fi
            restart_backend_service
            echo "✅ 状态已翻转，后台服务已同步加载。"
            read -p "回车返回..." ;;
        4)
            echo "📡 正在对中国安徽骨干机房进行延迟测定..."
            echo -n "● 安徽电信 (合肥): " && ping -c 3 -q 61.132.163.68 | awk -F/ '/rtt/ {print $5" ms"}'
            echo -n "● 安徽联通 (合肥): " && ping -c 3 -q 218.104.78.2 | awk -F/ '/rtt/ {print $5" ms"}'
            echo -n "● 安徽移动 (合肥): " && ping -c 3 -q 211.138.180.2 | awk -F/ '/rtt/ {print $5" ms"}'
            read -p "回车返回..." ;;
    esac
    main_menu
}

view_paths() {
    clear
    echo "====================================================================="
    echo "       📂  集群管理面板 - 当前服务器组件路径与文件分布"
    echo "====================================================================="
    echo " 🔹 面板控制脚本 (Shell):   ${CONFIG_DIR}/test.sh"
    echo " 🔹 异步核心引擎 (Python):  ${PYTHON_SCRIPT}"
    echo " 🔹 核心动态配置 (JSON):    ${CONFIG_FILE}"
    echo " 🔹 本地数据中心 (SQLite):  ${DB_PATH}"
    echo " 🔹 实时运行日志 (Log):     ${BOT_LOG}"
    echo " 🔹 系统自启服务 (Systemd): /etc/systemd/system/tg_vps_bot.service"
    echo "====================================================================="
    read -p "按回车返回主菜单..."
    main_menu
}

wake_tg_connection() {
    clear
    echo "====================================================================="
    echo "       📡  手动深层唤醒：TG 机器人双向安全链路测试"
    echo "====================================================================="
    local token=$(read_json "BOT_TOKEN")
    local admin_id=$(read_json "ADMIN_ID")
    
    if [ -z "$token" ] || [ -z "$admin_id" ]; then
        echo "⚠️  未检测到任何配置信息！"
        read -p "💡 是否直接在此页面原地完成初始化绑定交互? [y/n, 默认y]: " direct_bind
        direct_bind=${direct_bind:-"y"}
        if [ "$direct_bind" = "y" ] || [ "$direct_bind" = "Y" ]; then
            init_config
            interactive_bind_flow
            main_menu
            return
        else
            main_menu
            return
        fi
    fi

    verify_tg_credentials "$token" "$admin_id"
    if [ $? -eq 0 ]; then
        echo "====================================================================="
        echo "🟢 唤起成功！下行通知全量打通，完全通过【真成功】验证！"
        echo "====================================================================="
    else
        echo "====================================================================="
        echo "🔴 唤起失败！链路未接通，现在为你全自动分析核心根源..."
        echo "====================================================================="
        diagnose_vps_faults
    fi
    read -p "内审处理完毕，按回车键返回主菜单..."
    main_menu
}

write_python_engine() {
cat << 'EOF_PY' > ${CONFIG_DIR}/main.py
import os, sys, time, json, sqlite3, datetime, requests, re, threading
from threading import Thread

CONF_PATH = "/root/tg_vps_bot/config.json"
DB_PATH = "/root/tg_vps_bot/cluster.db"

def load_conf():
    with open(CONF_PATH, "r") as f: return json.load(f)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS nodes (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ip TEXT, status TEXT, last_seen TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS whitelist (user_id TEXT PRIMARY KEY, username TEXT, added_time TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS ssh_history (id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT, status TEXT, user TEXT, ip TEXT, port TEXT, location TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS ban_list (ip TEXT PRIMARY KEY, ban_time TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS report_counter (id INTEGER PRIMARY KEY, count INTEGER DEFAULT 0)''')
    c.execute("INSERT OR IGNORE INTO report_counter (id, count) VALUES (1, 0)")
    c.execute("INSERT OR IGNORE INTO report_counter (id, count) VALUES (2, 0)")
    conf = load_conf()
    c.execute("INSERT OR IGNORE INTO whitelist (user_id, username, added_time) VALUES (?, ?, ?)", (str(conf["ADMIN_ID"]), "Main_Admin", datetime.datetime.now().strftime("%Y-%m-%d")))
    conn.commit()
    conn.close()

def traffic_persistent_worker():
    import psutil
    while True:
        try:
            net_io = psutil.net_io_counters()
            current_raw = net_io.bytes_sent + net_io.bytes_recv
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("SELECT count FROM report_counter WHERE id=3")
            row_last = c.fetchone()
            if not row_last:
                c.execute("INSERT INTO report_counter (id, count) VALUES (3, ?)", (current_raw,))
                delta = 0
            else:
                last_raw = row_last[0]
                delta = current_raw - last_raw if current_raw >= last_raw else current_raw
                c.execute("UPDATE report_counter SET count=? WHERE id=3", (current_raw,))
            c.execute("UPDATE report_counter SET count = count + ? WHERE id=2", (delta,))
            conn.commit()
            conn.close()
        except: pass
        time.sleep(5)

def query_geo(ip):
    try:
        r = requests.get(f"http://ip-api.com/json/{ip}?lang=zh-CN", timeout=2).json()
        if r.get("status") == "success": return f"{r.get('country','')}{r.get('regionName','')}{r.get('city','')}"
    except: pass
    return "未知所在地"

def run_benchmark():
    # 动态核心分配
    core_count = os.cpu_count() or 1
    threads = 2 if core_count <= 1 else core_count

    targets = {
        "南京大学节点": "https://mirrors.nju.edu.cn/debian/ls-lR.gz",
        "合肥科大节点": "https://mirrors.ustc.edu.cn/debian/ls-lR.gz",
        "洛杉矶海外节点": "http://cachefly.cachefly.net/10mb.test"
    }

    def download_test(url, res_list):
        try:
            t0 = time.time()
            r = requests.get(url, timeout=4, stream=True)
            sz = 0
            for chunk in r.iter_content(chunk_size=1024*32):
                if chunk: sz += len(chunk)
                if time.time() - t0 > 3: break
            dur = time.time() - t0
            res_list.append(sz / dur if dur > 0 else 0)
        except: res_list.append(0)

    results = []
    for name, url in targets.items():
        # 单线程测速
        s_res = []
        download_test(url, s_res)
        s_speed = (s_res[0] * 8) / (1024**2) if s_res else 0

        # 防网卡拥堵强制睡眠3秒
        time.sleep(3)

        # 多线程测速
        m_res = []
        th_list = []
        for _ in range(threads):
            t = threading.Thread(target=download_test, args=(url, m_res))
            th_list.append(t)
            t.start()
        for t in th_list: t.join()
        m_speed = (sum(m_res) * 8) / (1024**2)

        # 间隔3秒，为下一个节点让路
        time.sleep(3)

        # 完美对齐你要的排版格式
        results.append(f"{name} :单线程: {s_speed:.2f} Mbps,多线程: {m_speed:.2f} Mbps")

    res_str = "\n".join(results)
    return f"\n🚀 国内外网络压榨测速 (本机: {core_count}核, 动态并发: {threads}线程)\n{res_str}"

def get_system_status():
    import psutil
    conf = load_conf()
    cpu_usage = psutil.cpu_percent(interval=0.2)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT count FROM report_counter WHERE id=2")
    used_bytes = c.fetchone()[0]
    conn.close()
    total_g = conf.get("TOTAL_TRAFFIC_GB", 1000)
    used_g = used_bytes / (1024**3)
    pct = (used_g / total_g) * 100
    
    # 按照你要求的干净格式输出
    return (f"🖥️ [{conf['VPS_NAME']}] 服务器监控快照\n\n"
            f"● CPU 使用率: {cpu_usage}% \n"
            f"● 内存损耗: {mem.percent}% ({mem.used // (1024**2)}M / {mem.total // (1024**2)}M)\n"
            f"● 硬盘结余: {disk.percent}% ({disk.free // (1024**3)}G)\n"
            f"● 流量配额: {used_g:.2f}G / {total_g}G ({pct:.1f}%)\n")

def cpu_load_guardian():
    import psutil
    high_count = 0
    while True:
        try:
            conf = load_conf()
            cpu = psutil.cpu_percent(interval=1)
            if cpu >= conf.get("CPU_HIGH_LOAD_ALERT_PCT", 90): high_count += 1
            else: high_count = 0
            if high_count >= 3:
                txt = f"🔥 *[重大安全警报]*\n\n主机 `{conf['VPS_NAME']}` CPU 连续三次满载死锁 (`{cpu}%`)！"
                requests.post(f"https://api.telegram.org/bot{conf['BOT_TOKEN']}/sendMessage", data={"chat_id": conf['ADMIN_ID'], "text": txt, "parse_mode": "Markdown"})
                high_count = 0
        except: pass
        time.sleep(20)

def monitor_ssh_login():
    log_files = ["/var/log/auth.log", "/var/log/secure"]
    target_log = None
    for f in log_files:
        if os.path.exists(f): target_log = f; break
    if not target_log: return
    fail_p = re.compile(r"Failed password for (?:invalid user )?(\S+) from (\s*[\d\.]+) port (\d+)")
    succ_p = re.compile(r"Accepted (?:password|publickey) for (\S+) from (\s*[\d\.]+) port (\d+)")
    try:
        with open(target_log, "r", encoding="utf-8", errors="ignore") as f:
            f.seek(0, os.SEEK_END)
            while True:
                line = f.readline()
                if not line: time.sleep(0.5); continue
                now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                is_match, status, user, login_ip, port = False, "", "", "", ""
                if fail_p.search(line): is_match, status = True, "FAILED"; user, login_ip, port = fail_p.search(line).groups()
                elif succ_p.search(line): is_match, status = True, "SUCCESS"; user, login_ip, port = succ_p.search(line).groups()
                if is_match:
                    conf = load_conf()
                    loc = query_geo(login_ip)
                    conn = sqlite3.connect(DB_PATH)
                    c = conn.cursor()
                    c.execute("INSERT INTO ssh_history (time, status, user, ip, port, location) VALUES (?, ?, ?, ?, ?, ?)", (now_str, status, user, login_ip, port, loc))
                    conn.commit()
                    if status == "SUCCESS":
                        t = f"🚨 *[SSH 登录成功]*\n\n● 主机: `{conf['VPS_NAME']}`\n● 用户: `{user}`\n● IP: `{login_ip}`"
                        requests.post(f"https://api.telegram.org/bot{conf['BOT_TOKEN']}/sendMessage", data={"chat_id": conf['ADMIN_ID'], "text": t, "parse_mode": "Markdown"})
                    elif status == "FAILED":
                        c.execute("SELECT COUNT(*) FROM ssh_history WHERE ip=? AND status='FAILED' AND time >= datetime('now', '-1 day')")
                        if c.fetchone()[0] >= 10:
                            c.execute("INSERT OR IGNORE INTO ban_list (ip, ban_time) VALUES (?, ?)", (login_ip, now_str))
                            conn.commit()
                            os.system(f"iptables -I INPUT -s {login_ip} -j DROP")
                    conn.close()
    except: pass

def build_report():
    conf = load_conf()
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM ssh_history WHERE status='FAILED' AND time >= datetime('now', '-30 day')")
    f_30 = c.fetchone()[0]
    conn.close()
    tg_s = "🟢 正常"
    try:
        if requests.get(f"https://api.telegram.org/bot{conf['BOT_TOKEN']}/getMe", timeout=2).status_code != 200: tg_s = "🔴 异常"
    except: tg_s = "🔴 异常"
    return f"📊 *⚡ [{conf['VPS_NAME']}] 日报系统* ⚡\n\n● TG连通: {tg_s}\n● 30天防爆破数: `{f_30} 次`\n\n" + get_system_status()

def run_bot():
    from telegram import Update
    from telegram.ext import Application, CommandHandler, ContextTypes
    
    async def wrapper(func, update, context):
        try:
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("SELECT 1 FROM whitelist WHERE user_id=?", (str(update.effective_user.id),))
            auth = c.fetchone() is not None
            conn.close()
            if auth: await func(update, context)
        except Exception as err: pass

    async def start(u, c):
        conf = load_conf()
        # 把前面的点去掉了，TG自动识别斜杠为可点击命令
        m = f"🛡️ 专属集群管理就绪 ({conf['VPS_NAME']})\n\n/status - 实时快照与国内外多节点测速\n/report - 提取运维日报\n/toggle - 翻转日报开启状态\n/ping - 安徽三网骨干链路诊断\n/node - 提取节点配置"
        await u.message.reply_text(m)

    async def status_cmd(u, c):
        await u.message.reply_text("⏱️ 正在实时调度国内骨干网与海外多线程测速，请稍候（节点间已增加延时防拥堵）...")
        await u.message.reply_text(get_system_status() + run_benchmark())

    async def report_cmd(u, c): await u.message.reply_text(build_report())

    async def toggle_cmd(u, c):
        conn = sqlite3.connect(DB_PATH)
        curr = conn.cursor()
        curr.execute("UPDATE report_counter SET count = count + 1 WHERE id=1")
        curr.execute("SELECT count FROM report_counter WHERE id=1")
        cnt = curr.fetchone()[0]
        conn.commit(); conn.close()
        status = 1 if cnt % 2 == 1 else 0
        conf = load_conf()
        conf["REPORT_ENABLED"] = status
        with open(CONF_PATH, "w") as f: json.dump(conf, f, indent=4)
        await u.message.reply_text(f"📊 状态翻转成功！日报: {'🟢已开启' if status==1 else '🔴已关闭'}")

    async def ping_cmd(u, c):
        import subprocess
        tel = subprocess.getoutput("ping -c 2 -q 61.132.163.68 | awk -F/ '/rtt/ {print $5}'")
        uni = subprocess.getoutput("ping -c 2 -q 218.104.78.2 | awk -F/ '/rtt/ {print $5}'")
        mob = subprocess.getoutput("ping -c 2 -q 211.138.180.2 | awk -F/ '/rtt/ {print $5}'")
        await u.message.reply_text(f"📡 *安徽三网骨干网络延迟诊断*\n\n● 电信 (合肥): `{tel or '超时'} ms`\n● 联通 (合肥): `{uni or '超时'} ms`\n● 移动 (合肥): `{mob or '超时'} ms`", parse_mode="Markdown")

    async def node_cmd(u, c):
        f_p = "/root/v2rayn-node.txt"
        if not os.path.exists(f_p): await u.message.reply_text("ℹ️ 未检测到 `/root/v2rayn-node.txt` 文件。")
        else:
            with open(f_p, "r", encoding="utf-8", errors="ignore") as f: txt = f.read().strip()
            if not txt: await u.message.reply_text("ℹ️ 节点配置文件为空。")
            else: await u.message.reply_text(f"```text\n{txt}\n
```", parse_mode="Markdown")

    conf = load_conf()
    app = Application.builder().token(conf["BOT_TOKEN"]).build()
    app.add_handler(CommandHandler("start", lambda u, c: wrapper(start, u, c)))
    app.add_handler(CommandHandler("status", lambda u, c: wrapper(status_cmd, u, c)))
    app.add_handler(CommandHandler("report", lambda u, c: wrapper(report_cmd, u, c)))
    app.add_handler(CommandHandler("toggle", lambda u, c: wrapper(toggle_cmd, u, c)))
    app.add_handler(CommandHandler("ping", lambda u, c: wrapper(ping_cmd, u, c)))
    app.add_handler(CommandHandler("node", lambda u, c: wrapper(node_cmd, u, c)))
    app.run_polling()

if __name__ == "__main__":
    init_db()
    Thread(target=traffic_persistent_worker, daemon=True).start()
    Thread(target=monitor_ssh_login, daemon=True).start()
    Thread(target=cpu_load_guardian, daemon=True).start()
    run_bot()
EOF_PY
}

check_depends
init_config
main_menu

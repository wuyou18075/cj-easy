#!/bin/bash

# ==========================================
# 脚本名称: docker-tool-install.sh
# 功能描述: Docker 动态云商店工具箱与全能迁移中心
# ==========================================

# 全局颜色与线框定义
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_RED="\e[31m"
C_GRAY="\e[90m"
C_RESET="\e[0m"
LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

# ==========================================
# 全局目录规则与云端链接定义区
# ==========================================
DOCKER_ROOT="/app/docker"
YAML_FILE="${DOCKER_ROOT}/docker-compose.yml"
YAML_BAK_DIR="${DOCKER_ROOT}/yaml-bak"
REMOTE_TOOLS_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/docker-compose-tools.yml"
# GitHub API 几乎不走 raw CDN 缓存，作为主通道失败时的保底
REMOTE_TOOLS_API_URL="https://api.github.com/repos/wuyou18075/cj-easy/contents/docker-compose-tools.yml?ref=main"
# jsDelivr 镜像备用
REMOTE_TOOLS_CDN_URL="https://cdn.jsdelivr.net/gh/wuyou18075/cj-easy@main/docker-compose-tools.yml"
TEMP_TOOLS="/tmp/remote_docker_tools.yml"

# 初始化环境依赖
mkdir -p "$DOCKER_ROOT"
mkdir -p "$YAML_BAK_DIR"

# ==========================================
# 核心功能: 动态云端应用商店拉取与解析
# ==========================================

# 判定下载内容是否是有效的工具模板（至少含 #NAME: 与 #START）
_is_valid_tools_yml() {
    local f="$1"
    [ -s "$f" ] || return 1
    grep -qE "^#NAME:" "$f" || return 1
    grep -qE "^#START" "$f" || return 1
    # 排除 GitHub 404 HTML / JSON 错误页
    grep -qE "404: Not Found|\"message\": \"Not Found\"" "$f" && return 1
    return 0
}

# 彻底清理本地缓存与 curl 残留，避免读到旧文件
_clear_tools_cache() {
    rm -f "$TEMP_TOOLS" \
          "${TEMP_TOOLS}.tmp" \
          "${TEMP_TOOLS}.api" \
          "${TEMP_TOOLS}.cdn" 2>/dev/null || true
}

# 从 GitHub Contents API 拉文件内容（base64），绕过 raw CDN
_fetch_tools_via_github_api() {
    local out="$1"
    local api_json="${TEMP_TOOLS}.api"
    # API 带时间戳，并声明不要缓存
    if ! curl -fsSL -m 15 \
        -H "Accept: application/vnd.github.raw" \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "${REMOTE_TOOLS_API_URL}&ts=$(date +%s%N)" \
        -o "$out"; then
        # Accept: raw 失败时再走 JSON + base64 解码
        if curl -fsSL -m 15 \
            -H "Accept: application/vnd.github+json" \
            -H "Cache-Control: no-cache, no-store, must-revalidate" \
            -H "Pragma: no-cache" \
            "${REMOTE_TOOLS_API_URL}&ts=$(date +%s%N)" \
            -o "$api_json"; then
            if command -v python3 >/dev/null 2>&1; then
                python3 - "$api_json" "$out" <<'PY'
import base64, json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as f:
    data = json.load(f)
content = data.get("content", "")
if not content:
    sys.exit(1)
with open(dst, "wb") as f:
    f.write(base64.b64decode(content))
PY
            elif command -v jq >/dev/null 2>&1; then
                jq -r '.content' "$api_json" | tr -d '\n' | base64 -d > "$out" 2>/dev/null
            else
                return 1
            fi
        else
            return 1
        fi
    fi
    _is_valid_tools_yml "$out"
}

fetch_remote_tools() {
    echo -e "${C_CYAN}🔄 正在与云端应用库同步数据（强制去缓存）...${C_RESET}"

    # 1) 先删本地缓存，杜绝读旧文件
    _clear_tools_cache

    local bust
    bust="$(date +%s%N 2>/dev/null || date +%s)_$$_${RANDOM}"
    local tmp="${TEMP_TOOLS}.tmp"

    # 2) 主通道：raw + 强去缓存头 + 随机 query
    if curl -fsSL -m 15 \
        --http1.1 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        -H "If-None-Match:" \
        -H "If-Modified-Since:" \
        "${REMOTE_TOOLS_URL}?v=${bust}&nocache=${bust}" \
        -o "$tmp" \
        && _is_valid_tools_yml "$tmp"; then
        mv -f "$tmp" "$TEMP_TOOLS"
        echo -e "${C_GREEN}✅ 已从 raw 源拉取最新工具表${C_RESET}"
        return 0
    fi

    # 3) 备用：GitHub API（基本不受 raw CDN 影响）
    echo -e "${C_YELLOW}⚠️ raw 源异常或疑似缓存，改走 GitHub API...${C_RESET}"
    if _fetch_tools_via_github_api "$tmp"; then
        mv -f "$tmp" "$TEMP_TOOLS"
        echo -e "${C_GREEN}✅ 已从 GitHub API 拉取最新工具表${C_RESET}"
        return 0
    fi

    # 4) 再备用：jsDelivr 镜像
    echo -e "${C_YELLOW}⚠️ GitHub API 也失败，尝试 jsDelivr 镜像...${C_RESET}"
    if curl -fsSL -m 15 \
        -H "Cache-Control: no-cache, no-store, must-revalidate" \
        -H "Pragma: no-cache" \
        "${REMOTE_TOOLS_CDN_URL}?v=${bust}" \
        -o "$tmp" \
        && _is_valid_tools_yml "$tmp"; then
        mv -f "$tmp" "$TEMP_TOOLS"
        echo -e "${C_GREEN}✅ 已从 jsDelivr 拉取工具表${C_RESET}"
        return 0
    fi

    rm -f "$tmp" 2>/dev/null || true
    echo -e "${C_RED}❌ 云端仓库拉取失败（raw / API / CDN 均不可用），请检查 WSL 网络或 GitHub 连通性。${C_RESET}"
    sleep 2
    return 1
}

# 规则: 配置文件自动备份并仅保留最近 10 份
backup_compose_yaml() {
    if [ -f "$YAML_FILE" ]; then
        local BAK_NAME="${YAML_BAK_DIR}/docker-compose-bak-$(date +%Y%m%d%H%M%S).yml"
        cp "$YAML_FILE" "$BAK_NAME"
        ls -t "$YAML_BAK_DIR"/docker-compose-bak-*.yml 2>/dev/null | tail -n +11 | xargs -I {} rm -f "{}"
        echo -e "${C_GRAY}📦 原配置已留存快照: $(basename "$BAK_NAME")${C_RESET}"
    fi
}

# ==========================================
# 核心功能模块: 动态应用安装与生命周期管理
# ==========================================

# 获取公网 IP（强制优先 IPv4；没有 v4 才回退 v6）
_get_public_ip() {
    local ip=""
    local u
    # 1) 强制 IPv4（-4），多源轮询
    for u in \
        "https://api.ipify.org" \
        "https://4.ipw.cn" \
        "https://ipv4.icanhazip.com" \
        "https://v4.ident.me" \
        "https://ifconfig.me/ip" \
        "https://checkip.amazonaws.com" \
        "https://ip.sb"
    do
        ip=$(curl -4 -fsS -m 4 "$u" 2>/dev/null | tr -d '[:space:]\r')
        if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    # 2) 不带 -4 再试，但只接受 IPv4
    for u in \
        "https://api.ipify.org" \
        "https://4.ipw.cn" \
        "https://ifconfig.me/ip" \
        "https://ip.sb" \
        "https://icanhazip.com"
    do
        ip=$(curl -fsS -m 4 "$u" 2>/dev/null | tr -d '[:space:]\r')
        if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    # 3) 本机 IPv4
    ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    # 4) 最后才接受 IPv6（URL 侧会加 []）
    for u in "https://api64.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(curl -fsS -m 3 "$u" 2>/dev/null | tr -d '[:space:]\r')
        if [[ "$ip" == *:* && "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo "127.0.0.1"
}

# 把 host 拼成 URL 可用形式：IPv6 必须加 []
_format_host_for_url() {
    local host="$1"
    if [[ "$host" == *:* && "$host" != \[* ]]; then
        echo "[${host}]"
    else
        echo "$host"
    fi
}

# 读取容器对外映射的主机端口；失败则用默认值
_get_host_port() {
    local cname="$1"
    local container_port="$2"
    local default_port="$3"
    local mapped
    # docker port 输出可能是 0.0.0.0:18317 或 [::]:18317
    mapped=$(docker port "$cname" "$container_port" 2>/dev/null | head -n 1 | sed -E 's/.*:([0-9]+)$/\1/' | tr -d ' \r')
    if [[ "$mapped" =~ ^[0-9]+$ ]]; then
        echo "$mapped"
    else
        echo "$default_port"
    fi
}

# 从模板块中提取全部服务键（支持多服务栈）
_extract_service_keys() {
    echo "$1" | grep -E "^  [a-zA-Z0-9_-]+:" | awk -F':' '{print $1}' | tr -d ' \r'
}

# 保存并打印 CPA+CPAMP 初始化信息（含 CPA 独立访问）
_print_and_save_cpa_stack_info() {
    local admin_key="${1:-}"
    local cpa_mgmt_key="${2:-}"
    local cpa_api_key="${3:-}"
    local cpamp_port_default="${4:-18317}"
    local cpa_port_default="${5:-8317}"

    local PUB_IP PUB_HOST CPAMP_PORT CPA_PORT INFO_FILE
    echo -e "${C_GRAY}🌐 正在获取公网 IP（优先 IPv4）...${C_RESET}"
    PUB_IP=$(_get_public_ip)
    PUB_HOST=$(_format_host_for_url "$PUB_IP")
    CPAMP_PORT=$(_get_host_port "cpa-manager-plus" "18317" "$cpamp_port_default")
    CPA_PORT=$(_get_host_port "cli-proxy-api" "8317" "$cpa_port_default")

    mkdir -p "${DOCKER_ROOT}/cpa-manager-plus" "${DOCKER_ROOT}/cli-proxy-api"
    INFO_FILE="${DOCKER_ROOT}/cpa-manager-plus/INIT_INFO.txt"

    {
        echo "========================================================="
        echo " CPA + CPAMP 初始化信息"
        echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================================="
        echo ""
        echo "【CPAMP 管理面板】（登录 management.html）"
        echo "  面板地址(公网): http://${PUB_HOST}:${CPAMP_PORT}/management.html"
        echo "  面板地址(本机): http://127.0.0.1:${CPAMP_PORT}/management.html"
        echo "  健康检查:       curl http://127.0.0.1:${CPAMP_PORT}/health"
        echo "  登录方式:       管理员密钥（不是用户名密码）"
        echo "  管理员密钥:     ${admin_key:-（未记录，请查 docker logs cpa-manager-plus）}"
        echo ""
        echo "【CPA / CLIProxyAPI 独立访问】"
        echo "  管理面板(公网): http://${PUB_HOST}:${CPA_PORT}/"
        echo "  管理面板(本机): http://127.0.0.1:${CPA_PORT}/"
        echo "  API 地址(公网):  http://${PUB_HOST}:${CPA_PORT}/v1"
        echo "  API 地址(本机):  http://127.0.0.1:${CPA_PORT}/v1"
        echo "  登录/鉴权方式:  Management Key（配置 remote-management.secret-key）"
        echo "  Management Key: ${cpa_mgmt_key:-（未记录）}"
        echo "  说明: CPA 面板没有传统用户名/密码，使用 Management Key 作为管理密钥"
        echo ""
        echo "【CPA 客户端 API（Claude Code / OpenAI 兼容）】"
        echo "  Base URL:       http://${PUB_HOST}:${CPA_PORT}/v1"
        echo "  API Key:        ${cpa_api_key:-（未记录）}"
        echo ""
        echo "【CPAMP Setup 连接 CPA 时填写】"
        echo "  CPA URL(同网):  http://cli-proxy-api:8317"
        echo "  CPA URL(宿主机): http://127.0.0.1:${CPA_PORT}"
        echo "  CPA Management Key: ${cpa_mgmt_key:-（未记录）}"
        echo ""
        echo "【本地文件】"
        echo "  本信息文件:     ${INFO_FILE}"
        echo "  CPA 配置:       ${DOCKER_ROOT}/cli-proxy-api/config.yaml"
        echo "  CPAMP 数据:     ${DOCKER_ROOT}/cpa-manager-plus/data"
        echo "========================================================="
    } | tee "$INFO_FILE"

    {
        echo "CPAMP Admin Key: ${admin_key}"
        echo "CPA Management Key: ${cpa_mgmt_key}"
        echo "CPA Client API Key: ${cpa_api_key}"
        echo "CPAMP Panel: http://${PUB_HOST}:${CPAMP_PORT}/management.html"
        echo "CPA Panel: http://${PUB_HOST}:${CPA_PORT}/"
        echo "CPA API: http://${PUB_HOST}:${CPA_PORT}/v1"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    } > "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt"
    chmod 600 "$INFO_FILE" "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt" 2>/dev/null || true

    echo -e "${C_GRAY}  以上信息已保存，之后可在控制台选【8 查看初始化信息】再次查看。${C_RESET}"
}

# 查看已保存的初始化信息
_show_install_info() {
    local name="$1"
    local raw_block="$2"
    local -a keys=()
    mapfile -t keys < <(_extract_service_keys "$raw_block")
    local info=""

    for cand in \
        "${DOCKER_ROOT}/cpa-manager-plus/INIT_INFO.txt" \
        "${DOCKER_ROOT}/cli-proxy-api/INIT_INFO.txt" \
        "${DOCKER_ROOT}/${keys[0]}/INIT_INFO.txt"
    do
        if [ -f "$cand" ]; then
            info="$cand"
            break
        fi
    done
    if [ -z "$info" ]; then
        for k in "${keys[@]}"; do
            if [ -f "${DOCKER_ROOT}/${k}/INIT_INFO.txt" ]; then
                info="${DOCKER_ROOT}/${k}/INIT_INFO.txt"
                break
            fi
        done
    fi

    clear
    echo -e "${C_BLUE}📄 初始化信息: ${C_YELLOW}${name}${C_RESET}"
    echo -e "${LINE_GRAY}"
    if [ -n "$info" ] && [ -f "$info" ]; then
        echo -e "${C_GRAY}文件: ${info}${C_RESET}"
        echo -e "${LINE_GRAY}"
        cat "$info"
    else
        echo -e "${C_YELLOW}⚠️ 未找到初始化信息文件。${C_RESET}"
        echo "可能原因：安装时未生成，或目录已被抹除。"
        echo "预期路径: ${DOCKER_ROOT}/cpa-manager-plus/INIT_INFO.txt"
        if [ -f "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt" ]; then
            echo -e "${LINE_GRAY}"
            echo -e "${C_CYAN}找到密钥备忘 INSTALL_SECRETS.txt：${C_RESET}"
            cat "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt"
        fi
    fi
    echo -e "${LINE_GRAY}"
    read -p "回车返回..." temp
}

# 为 CPA / CLIProxyAPI 写入官方要求的 config.yaml
# 文档: remote-management.secret-key + allow-remote + usage-statistics-enabled
_write_cpa_config_yaml() {
    local mgmt_key="$1"
    local api_key="$2"
    local conf_dir="${DOCKER_ROOT}/cli-proxy-api"
    local conf_file="${conf_dir}/config.yaml"

    mkdir -p "${conf_dir}/auths" "${conf_dir}/logs" "${DOCKER_ROOT}/cpa-manager-plus/data"

    # 简单转义双引号，避免破坏 YAML
    local esc_mgmt esc_api
    esc_mgmt=$(printf '%s' "$mgmt_key" | sed 's/"/\\"/g')
    esc_api=$(printf '%s' "$api_key" | sed 's/"/\\"/g')

    cat > "$conf_file" <<EOF
host: "0.0.0.0"
port: 8317

remote-management:
  secret-key: "${esc_mgmt}"
  allow-remote: true
  disable-control-panel: false
  disable-auto-update-panel: true
  panel-github-repository: "https://github.com/seakee/CPA-Manager-Plus"

usage-statistics-enabled: true
redis-usage-queue-retention-seconds: 60

auth-dir: "/root/.cli-proxy-api"

api-keys:
  - "${esc_api}"
EOF
    chmod 600 "$conf_file" 2>/dev/null || true

    # 本地留一份密钥备忘（权限收紧）
    local note="${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt"
    {
        echo "CPA Management Key: ${mgmt_key}"
        echo "CPA Client API Key: ${api_key}"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    } > "$note"
    chmod 600 "$note" 2>/dev/null || true

    echo -e "${C_GREEN}✅ 已写入 CPA 配置: ${conf_file}${C_RESET}"
}

_install_service() {
    local NAME="$1"
    local R_BLOCK="$2"
    # 兼容旧调用：第 3 个参数可能是单个 key；优先从块内解析全部 key
    local -a SVC_KEYS=()
    mapfile -t SVC_KEYS < <(_extract_service_keys "$R_BLOCK")
    if [ ${#SVC_KEYS[@]} -eq 0 ] && [ -n "${3:-}" ]; then
        SVC_KEYS=("$3")
    fi
    local PRIMARY_KEY="${SVC_KEYS[0]}"

    clear
    echo -e "${C_CYAN}📥 正在初始化 [ $NAME ] 部署向导...${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "${C_YELLOW}💡 有默认值的项：直接回车 = 使用默认值；输入新值后回车 = 覆盖默认值。${C_RESET}"
    echo -e "${C_YELLOW}💡 无默认值的密钥/密码项：必须手动输入（可自行设定）。${C_RESET}"
    echo -e "${LINE_GRAY}"

    # 动态解析参数，支持 #PARAM_KEY:描述=默认值
    mapfile -t PARAM_LINES < <(echo "$R_BLOCK" | grep -oP "^#PARAM_[a-zA-Z0-9_]+:[^\r\n]+")

    local CONF_BLOCK="$R_BLOCK"
    # 记录关键参数，供安装后提示与 CPA config 生成
    local VAL_ADMIN_KEY="" VAL_CPA_MGMT_KEY="" VAL_CPA_API_KEY="" VAL_CPAMP_PORT="18317" VAL_CPA_PORT="8317"

    for p in "${PARAM_LINES[@]}"; do
        if [ -z "$p" ]; then continue; fi
        local P_KEY
        P_KEY=$(echo "$p" | cut -d':' -f1 | sed 's/^#//')
        local P_FULL
        P_FULL=$(echo "$p" | cut -d':' -f2-)
        local P_DESC="$P_FULL"
        local P_DEFAULT=""
        # 格式: 描述=默认值 （仅第一个 = 分隔）
        if [[ "$P_FULL" == *"="* ]]; then
            P_DESC="${P_FULL%%=*}"
            P_DEFAULT="${P_FULL#*=}"
        fi

        local U_IN=""
        if [ -n "$P_DEFAULT" ]; then
            # 明确展示默认值，并提示回车即用默认
            echo -e "✏️  ${P_DESC}"
            echo -e "   ${C_GREEN}默认值: ${P_DEFAULT}${C_RESET}  ${C_GRAY}(直接回车使用默认值)${C_RESET}"
            read -p "   请输入: " U_IN
            if [ -z "$U_IN" ]; then
                U_IN="$P_DEFAULT"
                echo -e "   ${C_GREEN}→ 已采用默认值: ${P_DEFAULT}${C_RESET}"
            else
                echo -e "   ${C_CYAN}→ 已采用自定义值: ${U_IN}${C_RESET}"
            fi
        else
            # 无默认值：必须手动填写（密钥/密码类）
            echo -e "✏️  ${P_DESC}  ${C_YELLOW}(无默认值，必填，请自行设定)${C_RESET}"
            read -p "   请输入: " U_IN
            while [ -z "$U_IN" ]; do
                echo -e "   ${C_YELLOW}该项无默认值，不能为空，请重新输入。${C_RESET}"
                read -p "   请输入: " U_IN
            done
            echo -e "   ${C_CYAN}→ 已采用: ${U_IN}${C_RESET}"
        fi

        case "$P_KEY" in
            PARAM_ADMIN_KEY) VAL_ADMIN_KEY="$U_IN" ;;
            PARAM_CPA_MGMT_KEY) VAL_CPA_MGMT_KEY="$U_IN" ;;
            PARAM_CPA_API_KEY) VAL_CPA_API_KEY="$U_IN" ;;
            PARAM_CPAMP_PORT|PARAM_PORT) VAL_CPAMP_PORT="$U_IN" ;;
            PARAM_CPA_PORT) VAL_CPA_PORT="$U_IN" ;;
        esac

        # 注入用户输入，使用管道符作为定界符防止路径斜杠干扰
        CONF_BLOCK=$(echo "$CONF_BLOCK" | sed "s|{$P_KEY}|$U_IN|g")
    done

    # 剔除所有的控制标签，生成纯净的 yaml 块
    local CLEAN_BLOCK
    CLEAN_BLOCK=$(echo "$CONF_BLOCK" | grep -vE "^#(START|END|NAME|PARAM_)")

    # CPA 完整栈：安装前写入官方要求的 config.yaml
    if echo "${SVC_KEYS[*]}" | grep -qw "cli-proxy-api"; then
        if [ -z "$VAL_CPA_MGMT_KEY" ]; then
            echo -e "${C_RED}❌ 缺少 CPA Management Key，无法生成 config.yaml${C_RESET}"
            read -p "回车返回..." temp
            return
        fi
        [ -z "$VAL_CPA_API_KEY" ] && VAL_CPA_API_KEY="sk-demo-change-me"
        _write_cpa_config_yaml "$VAL_CPA_MGMT_KEY" "$VAL_CPA_API_KEY"
        # 把管理员密钥也记入备忘
        if [ -n "$VAL_ADMIN_KEY" ]; then
            echo "CPAMP Admin Key: ${VAL_ADMIN_KEY}" >> "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt"
            chmod 600 "${DOCKER_ROOT}/cpa-manager-plus/INSTALL_SECRETS.txt" 2>/dev/null || true
        fi
    fi

    # 配置合并与冲突管控逻辑
    echo -e "${LINE_GRAY}"
    local conflict=0
    for k in "${SVC_KEYS[@]}"; do
        if [ -f "$YAML_FILE" ] && grep -qE "^  ${k}:" "$YAML_FILE"; then
            conflict=1
            break
        fi
    done

    if [ ! -f "$YAML_FILE" ]; then
        echo "version: '3.8'" > "$YAML_FILE"
        echo "" >> "$YAML_FILE"
        echo "services:" >> "$YAML_FILE"
        echo "$CLEAN_BLOCK" >> "$YAML_FILE"
        echo -e "${C_GREEN}✅ 检测到本地为空，已创建根配置并写入模块！${C_RESET}"
    else
        if [ "$conflict" -eq 1 ]; then
            echo -e "${C_YELLOW}⚠️ 警告：检测到本地文件已存在相关服务配置冲突！(${SVC_KEYS[*]})${C_RESET}"
            echo "1) 手动解决 (屏幕将展示新模块，随后自动打开 nano 供您合并)"
            echo "2) 直接丢弃本地配置 (危险：将完全覆盖重写文件，旧有其他服务将被清空！)"
            echo "0) 取消安装"
            echo -e "${LINE_GRAY}"
            read -p "请选择冲突裁决方案 [0-2]: " c_opt

            if [ "$c_opt" == "1" ]; then
                backup_compose_yaml
                clear
                echo -e "${C_CYAN}========== 即将注入的新模块代码 ==========${C_RESET}"
                echo "$CLEAN_BLOCK"
                echo -e "${C_CYAN}==========================================${C_RESET}"
                echo -e "💡 提示：请参考上方的代码，在接下来的编辑器中修改或合并您的本地旧配置。"
                read -p "准备就绪后，按回车键唤醒 nano 编辑器..." temp
                nano "$YAML_FILE"
                echo -e "${C_GREEN}✅ 手动合并结束。${C_RESET}"
            elif [ "$c_opt" == "2" ]; then
                backup_compose_yaml
                echo "version: '3.8'" > "$YAML_FILE"
                echo "" >> "$YAML_FILE"
                echo "services:" >> "$YAML_FILE"
                echo "$CLEAN_BLOCK" >> "$YAML_FILE"
                echo -e "${C_GREEN}✅ 已物理清除旧档案，全新模块写入成功！${C_RESET}"
            else
                echo -e "${C_GRAY}操作已取消。${C_RESET}"
                return
            fi
        else
            backup_compose_yaml
            echo "$CLEAN_BLOCK" >> "$YAML_FILE"
            echo -e "${C_GREEN}✅ 无冲突！已将新模块无缝拼接到本地配置末尾。${C_RESET}"
        fi
    fi

    # 唤醒容器启动流程（支持多服务）
    echo -e "${C_CYAN}🚀 正在调用 Docker 引擎拉起服务: ${SVC_KEYS[*]} ...${C_RESET}"
    cd "$DOCKER_ROOT" || return
    docker compose up -d "${SVC_KEYS[@]}"
    echo -e "${C_GREEN}🎉 部署动作全部完成！${C_RESET}"

    # 个别应用安装后的访问提示
    if echo "${SVC_KEYS[*]}" | grep -qw "cpa-manager-plus"; then
        echo -e "${LINE_GRAY}"
        _print_and_save_cpa_stack_info \
            "${VAL_ADMIN_KEY}" \
            "${VAL_CPA_MGMT_KEY}" \
            "${VAL_CPA_API_KEY}" \
            "${VAL_CPAMP_PORT:-18317}" \
            "${VAL_CPA_PORT:-8317}"
    fi

    read -p "按回车键返回上级菜单..." temp
}

# 从本地 docker-compose.yml 删除指定服务块（顶层 "  key:" 到下一个同级服务前）
_remove_services_from_compose() {
    local yaml="$YAML_FILE"
    if [ ! -f "$yaml" ]; then
        echo -e "${C_GRAY}本地无 compose 文件，跳过 YAML 清理。${C_RESET}"
        return 0
    fi
    if [ "$#" -lt 1 ]; then
        return 0
    fi

    backup_compose_yaml

    # 把服务名列表交给 python 处理（缩进安全、支持多服务）
    local keys_csv
    keys_csv=$(IFS=,; echo "$*")

    if command -v python3 >/dev/null 2>&1; then
        KEYS_CSV="$keys_csv" YAML_PATH="$yaml" python3 - <<'PY'
import os, re
from pathlib import Path

yaml_path = Path(os.environ["YAML_PATH"])
keys = {k.strip() for k in os.environ["KEYS_CSV"].split(",") if k.strip()}
if not keys:
    raise SystemExit(0)

text = yaml_path.read_text(encoding="utf-8", errors="replace")
# 统一换行
lines = text.splitlines(keepends=True)
out = []
i = 0
removed = []
svc_re = re.compile(r"^  ([A-Za-z0-9_-]+):\s*(?:#.*)?\r?\n?$")

while i < len(lines):
    m = svc_re.match(lines[i])
    if m and m.group(1) in keys:
        name = m.group(1)
        removed.append(name)
        i += 1
        # 跳过该服务体：直到下一个「两空格开头且非更多缩进的服务键」或文件顶层非缩进行
        while i < len(lines):
            line = lines[i]
            # 下一个同级服务
            if svc_re.match(line):
                break
            # services: 之外的顶层（极少见）
            if line.startswith("volumes:") or line.startswith("networks:") or (
                line and not line[0].isspace() and not line.startswith("#") and line.strip() != ""
            ):
                # 若是 version/services 头保留；volumes 顶层可能是 compose 的 volumes: 段
                if line.startswith("version:") or line.startswith("services:"):
                    break
                # named volumes 段：若前面服务删完仍可能存在，先停在这里让外层处理
                if line.startswith("volumes:") or line.startswith("networks:"):
                    break
            i += 1
        continue
    out.append(lines[i])
    i += 1

new_text = "".join(out)
# 压缩多余空行
new_text = re.sub(r"\n{3,}", "\n\n", new_text)
yaml_path.write_text(new_text, encoding="utf-8")
print("removed:" + ",".join(removed) if removed else "removed:")
PY
        local py_rc=$?
        if [ $py_rc -eq 0 ]; then
            echo -e "${C_GREEN}✅ 已从 docker-compose.yml 自动清除服务配置: ${keys_csv}${C_RESET}"
            # 若 services 下已无任何服务，保留空壳也可；可选提示
            if ! grep -qE "^  [a-zA-Z0-9_-]+:" "$yaml" 2>/dev/null; then
                echo -e "${C_GRAY}提示: compose 中已无任何服务块（仅剩文件头）。${C_RESET}"
            fi
            return 0
        fi
        echo -e "${C_YELLOW}⚠️ Python 清理失败，尝试 awk 回退...${C_RESET}"
    fi

    # awk 回退：逐个 key 删除
    local tmp="${yaml}.tmp.$$"
    cp "$yaml" "$tmp"
    local k
    for k in "$@"; do
        [ -z "$k" ] && continue
        awk -v key="$k" '
            BEGIN { skip=0 }
            {
                if ($0 ~ ("^  " key ":[[:space:]]*($|#)")) { skip=1; next }
                if (skip) {
                    if ($0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*($|#)/) { skip=0 }
                    else if ($0 ~ /^(version:|services:|volumes:|networks:)/) { skip=0 }
                    else if ($0 ~ /^[^[:space:]#]/ && $0 !~ /^$/) { skip=0 }
                    else next
                }
                if (!skip) print
            }
        ' "$tmp" > "${tmp}.out" && mv "${tmp}.out" "$tmp"
    done
    mv "$tmp" "$yaml"
    echo -e "${C_GREEN}✅ 已从 docker-compose.yml 自动清除服务配置: ${keys_csv}${C_RESET}"
}

manage_service() {
    local SELECTED_NAME="$1"
    # 精准抽取对应的 START 和 END 之间的文本块
    local RAW_BLOCK
    # 用 index 做字面量匹配，避免 NAME 中的 + . * 等破坏正则
    RAW_BLOCK=$(SELECTED_NAME="$SELECTED_NAME" awk '
        BEGIN { target = "#NAME:" ENVIRON["SELECTED_NAME"] }
        /^#START/ { f=1; buf="" }
        f { buf = buf $0 ORS }
        /^#END/ {
            if (f && index(buf, target) > 0) { printf "%s", buf; exit }
            f=0
        }
    ' "$TEMP_TOOLS")

    if [ -z "$RAW_BLOCK" ]; then
        echo -e "${C_RED}❌ 未能从远程模板中解析到该应用数据！${C_RESET}"
        sleep 1; return
    fi

    # 提取全部服务键（多服务栈）
    local -a SVC_KEYS=()
    mapfile -t SVC_KEYS < <(_extract_service_keys "$RAW_BLOCK")
    local SVC_KEY="${SVC_KEYS[0]}"
    local SVC_LABEL
    SVC_LABEL=$(IFS=,; echo "${SVC_KEYS[*]}")

    while true; do
        clear
        echo -e "${C_BLUE}⚡ Docker 矩阵应用控制台: ${C_YELLOW}$SELECTED_NAME${C_RESET}"
        echo -e "   组件映射: ${C_CYAN}${SVC_LABEL}${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo " 1) 安装 (云端参数解析与部署)"
        echo " 2) 更新镜像 (Pull 最新版本并平滑重启)"
        echo " 3) 启动 (Start)"
        echo " 4) 重启 (Restart)"
        echo " 5) 停止 (Stop)"
        echo " 6) 卸载 (仅强制清除容器)"
        echo " 7) 抹除 (深度清除容器、挂载目录与 compose 配置)"
        echo " 8) 查看初始化信息 (登录地址/密钥)"
        echo " 0) 返回上层大厅"
        echo -e "${LINE_GRAY}"
        read -p "请分配操作指令 [0-8]: " SUB_OPT

        case $SUB_OPT in
            1)
                _install_service "$SELECTED_NAME" "$RAW_BLOCK" "$SVC_KEY"
                ;;
            2)
                echo -e "${C_CYAN}🔄 正在追溯最新镜像...${C_RESET}"
                cd "$DOCKER_ROOT" || return
                docker compose pull "${SVC_KEYS[@]}"
                docker compose up -d "${SVC_KEYS[@]}"
                read -p "操作完毕，回车继续..." temp
                ;;
            3)
                cd "$DOCKER_ROOT" || return
                docker compose start "${SVC_KEYS[@]}" 2>/dev/null || docker compose up -d "${SVC_KEYS[@]}"
                read -p "操作完毕，回车继续..." temp
                ;;
            4)
                cd "$DOCKER_ROOT" || return
                docker compose restart "${SVC_KEYS[@]}"
                read -p "操作完毕，回车继续..." temp
                ;;
            5)
                cd "$DOCKER_ROOT" || return
                docker compose stop "${SVC_KEYS[@]}"
                read -p "操作完毕，回车继续..." temp
                ;;
            6)
                echo -e "${C_YELLOW}🗑️ 正在阻断并销毁容器资产...${C_RESET}"
                cd "$DOCKER_ROOT" || return
                docker compose stop "${SVC_KEYS[@]}" 2>/dev/null
                docker compose rm -f -s "${SVC_KEYS[@]}" 2>/dev/null
                echo -e "${C_GREEN}✅ 容器节点已切除（保留 compose 配置与数据目录，便于再启动）。${C_RESET}"
                read -p "回车继续..." temp
                ;;
            7)
                read -p "⚠️ 极危警告：确定要彻底销毁容器、删除挂载数据，并自动清除 docker-compose.yml 中的服务配置吗？[y/N]: " is_del
                if [[ "$is_del" =~ ^[Yy]$ ]]; then
                    cd "$DOCKER_ROOT" || return
                    docker compose stop "${SVC_KEYS[@]}" 2>/dev/null
                    docker compose rm -f -s "${SVC_KEYS[@]}" 2>/dev/null
                    for k in "${SVC_KEYS[@]}"; do
                        if [ -d "${DOCKER_ROOT}/${k}" ]; then
                            sudo rm -rf "${DOCKER_ROOT}/${k}"
                        fi
                    done
                    # CPA 栈额外目录
                    if echo "${SVC_KEYS[*]}" | grep -qw "cli-proxy-api"; then
                        [ -d "${DOCKER_ROOT}/cli-proxy-api" ] && sudo rm -rf "${DOCKER_ROOT}/cli-proxy-api"
                        [ -d "${DOCKER_ROOT}/cpa-manager-plus" ] && sudo rm -rf "${DOCKER_ROOT}/cpa-manager-plus"
                    fi
                    # 自动清理 compose 遗留服务块
                    _remove_services_from_compose "${SVC_KEYS[@]}"
                    echo -e "${C_GREEN}✅ 容器、数据目录与 compose 配置均已清除完毕。${C_RESET}"
                else
                    echo -e "${C_GRAY}数据销毁动作已终止。${C_RESET}"
                fi
                read -p "回车继续..." temp
                ;;
            8)
                _show_install_info "$SELECTED_NAME" "$RAW_BLOCK"
                ;;
            0) break ;;
            *) echo -e "${C_GRAY}❌ 无效代码。${C_RESET}"; sleep 1 ;;
        esac
    done
}


# ==========================================
# 核心功能模块: 跨节点迁移系统 (终极打包与物理装载)
# ==========================================

pack_migration_data() {
    clear
    echo -e "${C_BLUE}⚡ 全能数据打包器 (镜像 + Data挂载)${C_RESET}"
    echo -e "${LINE_GRAY}"
    
    echo -e "活跃服务集群探测:"
    docker ps --format "  🚢 {{.Names}}"
    echo -e "${LINE_GRAY}"
    
    read -p "请输入要打包的服务名(容器名): " SVC_NAME
    if [ -z "$SVC_NAME" ]; then echo -e "${C_RED}❌ 服务名不能为空${C_RESET}"; sleep 1; return; fi

    local SVC_DATA_DIR="${DOCKER_ROOT}/${SVC_NAME}/data"
    local SVC_TAR_DIR="${DOCKER_ROOT}/${SVC_NAME}/tar"
    local TIMESTAMP=$(date +%Y-%m-%d-%s)
    local IMG_TAR="${SVC_NAME}-bak-${TIMESTAMP}.tar"
    local MIGRATE_PKG="${SVC_NAME}-migration-${TIMESTAMP}.tar.gz"
    local STAGE_DIR="/tmp/migration_stage_${TIMESTAMP}"

    mkdir -p "$SVC_TAR_DIR"
    mkdir -p "${STAGE_DIR}/data"

    echo -e "1/3 ${C_CYAN}正在对当前容器进行快照级 Commit...${C_RESET}"
    if ! docker commit "$SVC_NAME" "${SVC_NAME}-mig-temp"; then
        echo -e "${C_RED}❌ 容器打包失败，请检查容器名是否正确！${C_RESET}"; sleep 1.5; return
    fi

    echo -e "2/3 ${C_CYAN}正在将快照导出为物理 .tar 镜像文件...${C_RESET}"
    docker save -o "${STAGE_DIR}/${IMG_TAR}" "${SVC_NAME}-mig-temp"
    docker rmi "${SVC_NAME}-mig-temp" >/dev/null 2>&1

    echo -e "3/3 ${C_CYAN}正在融合挂载数据并生成最终迁移包...${C_RESET}"
    if [ -d "$SVC_DATA_DIR" ]; then
        cp -a "${SVC_DATA_DIR}"/* "${STAGE_DIR}/data/" 2>/dev/null || true
    else
        echo -e "${C_YELLOW}⚠️ 警告: 未检测到标准的 /data 挂载目录，仅打包容器层镜像。${C_RESET}"
    fi

    cd "$STAGE_DIR" || exit
    tar -czvf "${SVC_TAR_DIR}/${MIGRATE_PKG}" . > /dev/null 2>&1
    cd - > /dev/null || exit
    rm -rf "$STAGE_DIR"

    clear
    echo -e "${C_GREEN}🎉 数据无损打包完成！${C_RESET}"
    echo -e "请将以下迁移文件复制并传输到新服务器:"
    echo -e "👉 ${C_YELLOW}${SVC_TAR_DIR}/${MIGRATE_PKG}${C_RESET}"
    read -p "回车继续..." temp
}

load_migration_data() {
    clear
    echo -e "${C_BLUE}⚡ 全能数据装载器 (恢复镜像与挂载)${C_RESET}"
    echo -e "${LINE_GRAY}"
    read -p "📂 请输入迁移文件压缩包的绝对路径 (如 /root/xxx.tar.gz): " PKG_PATH
    
    if [ ! -f "$PKG_PATH" ]; then
        echo -e "${C_RED}❌ 找不到迁移文件，请确认路径正确。${C_RESET}"; sleep 1.5; return
    fi

    read -p "🏷️ 请输入要在本服务器建立的 服务名: " SVC_NAME
    if [ -z "$SVC_NAME" ]; then echo -e "${C_RED}❌ 服务名不能为空${C_RESET}"; sleep 1; return; fi

    local SVC_DATA_DIR="${DOCKER_ROOT}/${SVC_NAME}/data"
    local TIMESTAMP=$(date +%s)
    local STAGE_DIR="/tmp/restore_stage_${TIMESTAMP}"
    
    mkdir -p "$STAGE_DIR"
    mkdir -p "$SVC_DATA_DIR"

    echo -e "1/3 ${C_CYAN}正在解压迁移包...${C_RESET}"
    tar -xzvf "$PKG_PATH" -C "$STAGE_DIR" > /dev/null 2>&1

    echo -e "2/3 ${C_CYAN}正在检索并灌入 Docker 镜像资产...${C_RESET}"
    local IMG_FILE=$(ls "$STAGE_DIR"/*.tar 2>/dev/null | head -n 1)
    if [ -n "$IMG_FILE" ]; then
        docker load -i "$IMG_FILE"
    else
        echo -e "${C_YELLOW}⚠️ 未在压缩包中发现 .tar 镜像文件。${C_RESET}"
    fi

    echo -e "3/3 ${C_CYAN}正在物理映射并恢复数据至宿主机...${C_RESET}"
    if [ -d "${STAGE_DIR}/data" ]; then
        cp -a "${STAGE_DIR}/data"/* "${SVC_DATA_DIR}/" 2>/dev/null || true
    fi
    
    rm -rf "$STAGE_DIR"

    clear
    echo -e "${C_GREEN}🎉 跨节点资产还原完毕！${C_RESET}"
    echo -e "挂载数据已安全恢复至: ${C_YELLOW}${SVC_DATA_DIR}${C_RESET}"
    echo -e "${C_CYAN}💡 下一步操作指引：${C_RESET}"
    echo -e "请在上方选单中选择对应的模块进行【1 安装】，系统会在配置生成后自动拉起您还原好的镜像数据！"
    read -p "回车继续..." temp
}


# ==========================================
# 交互主入口: 动态商店大厅
# ==========================================

while true; do
    # 每次回到大厅都重新拉远端工具表，避免菜单开着期间远端更新后仍显示旧列表
    fetch_remote_tools

    clear
    echo -e "${C_BLUE}⚡ Docker 安全百宝箱 / 动态应用矩阵${C_RESET}"
    echo -e "${LINE_GRAY}"

    # 动态构建云端提取的模块菜单
    mapfile -t TOOL_NAMES < <(grep -oP "^#NAME:\K.*" "$TEMP_TOOLS" | tr -d '\r')

    if [ ${#TOOL_NAMES[@]} -eq 0 ]; then
        echo -e "${C_YELLOW}⚠️ 暂未捕获到任何云端可用组件，请排查模板格式或网络源。${C_RESET}"
    else
        for i in "${!TOOL_NAMES[@]}"; do
            echo -e "$((i+1))) ${TOOL_NAMES[$i]}"
        done
    fi

    echo -e "\n98) 强制刷新云端应用列表"
    echo -e "99) 跨节点迁移：打包导出容器与挂载数据"
    echo -e "100) 跨节点迁移：物理读取装载迁移文件"
    echo -e "0) 返回主环境"
    echo -e "${LINE_GRAY}"
    read -p "请注入工具子项编号: " MAIN_OPT

    if [ "$MAIN_OPT" == "0" ]; then
        echo -e "👋 安全退出百宝箱。"
        exit 0
    elif [ "$MAIN_OPT" == "98" ]; then
        _clear_tools_cache
        echo -e "${C_CYAN}🔄 已清理本地缓存（含临时残留），即将强制重新同步云端应用库...${C_RESET}"
        sleep 1
        continue
    elif [ "$MAIN_OPT" == "99" ]; then
        pack_migration_data
    elif [ "$MAIN_OPT" == "100" ]; then
        load_migration_data
    elif [[ "$MAIN_OPT" =~ ^[0-9]+$ ]] && [ "$MAIN_OPT" -gt 0 ] && [ "$MAIN_OPT" -le "${#TOOL_NAMES[@]}" ]; then
        # 基于用户编号计算数组真实下标并调用管理逻辑
        target_name="${TOOL_NAMES[$((MAIN_OPT-1))]}"
        manage_service "$target_name"
    else
        echo -e "${C_GRAY}❌ 无效的指令输入。${C_RESET}"
        sleep 1
    fi
done
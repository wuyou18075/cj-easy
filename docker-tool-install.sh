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

_install_service() {
    local NAME="$1"
    local R_BLOCK="$2"
    local S_KEY="$3"

    clear
    echo -e "${C_CYAN}📥 正在初始化 [ $NAME ] 部署向导...${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "${C_YELLOW}💡 有默认值的项：直接回车 = 使用默认值；输入新值后回车 = 覆盖默认值。${C_RESET}"
    echo -e "${LINE_GRAY}"

    # 动态解析参数，支持 #PARAM_KEY:描述=默认值
    mapfile -t PARAM_LINES < <(echo "$R_BLOCK" | grep -oP "^#PARAM_[a-zA-Z0-9_]+:[^\r\n]+")

    local CONF_BLOCK="$R_BLOCK"
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
            # 无默认值：必须手动填写
            echo -e "✏️  ${P_DESC}  ${C_YELLOW}(无默认值，必填)${C_RESET}"
            read -p "   请输入: " U_IN
            while [ -z "$U_IN" ]; do
                echo -e "   ${C_YELLOW}该项无默认值，不能为空，请重新输入。${C_RESET}"
                read -p "   请输入: " U_IN
            done
            echo -e "   ${C_CYAN}→ 已采用: ${U_IN}${C_RESET}"
        fi

        # 注入用户输入，使用管道符作为定界符防止路径斜杠干扰
        CONF_BLOCK=$(echo "$CONF_BLOCK" | sed "s|{$P_KEY}|$U_IN|g")
    done

    # 剔除所有的控制标签，生成纯净的 yaml 块
    local CLEAN_BLOCK
    CLEAN_BLOCK=$(echo "$CONF_BLOCK" | grep -vE "^#(START|END|NAME|PARAM_)")

    # 配置合并与冲突管控逻辑
    echo -e "${LINE_GRAY}"
    if [ ! -f "$YAML_FILE" ]; then
        echo "version: '3.8'" > "$YAML_FILE"
        echo "" >> "$YAML_FILE"
        echo "services:" >> "$YAML_FILE"
        echo "$CLEAN_BLOCK" >> "$YAML_FILE"
        echo -e "${C_GREEN}✅ 检测到本地为空，已创建根配置并写入模块！${C_RESET}"
    else
        # 检索服务键值是否已存在于本地 (例如 "  komari:")
        if grep -qE "^  ${S_KEY}:" "$YAML_FILE"; then
            echo -e "${C_YELLOW}⚠️ 警告：检测到本地文件已存在 [ ${S_KEY} ] 服务的配置冲突！${C_RESET}"
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

    # 唤醒容器启动流程
    echo -e "${C_CYAN}🚀 正在调用 Docker 引擎拉起服务...${C_RESET}"
    cd "$DOCKER_ROOT" || return
    docker compose up -d "$S_KEY"
    echo -e "${C_GREEN}🎉 部署动作全部完成！${C_RESET}"

    # 个别应用安装后的访问提示
    if [ "$S_KEY" = "cpa-manager-plus" ]; then
        echo -e "${LINE_GRAY}"
        echo -e "${C_CYAN}📌 CPA Manager Plus 使用提示：${C_RESET}"
        echo -e "  面板地址: ${C_YELLOW}http://<主机IP>:18317/management.html${C_RESET}"
        echo -e "  健康检查: ${C_YELLOW}curl http://127.0.0.1:18317/health${C_RESET}"
        echo -e "  管理员密钥: 首次启动会在日志打印一次 → ${C_YELLOW}docker logs cpa-manager-plus${C_RESET}"
        echo -e "  Setup 时 CPA 在宿主机可填: ${C_YELLOW}http://host.docker.internal:8317${C_RESET}"
    fi

    read -p "按回车键返回上级菜单..." temp
}

manage_service() {
    local SELECTED_NAME="$1"
    # 精准抽取对应的 START 和 END 之间的文本块
    local RAW_BLOCK=$(awk "/#START/{f=1; buf=\"\"} f{buf=buf \$0 ORS} /#END/{if(buf ~ /#NAME:${SELECTED_NAME}/) {print buf; exit} f=0}" "$TEMP_TOOLS")
    
    if [ -z "$RAW_BLOCK" ]; then
        echo -e "${C_RED}❌ 未能从远程模板中解析到该应用数据！${C_RESET}"
        sleep 1; return
    fi

    # 提取 docker-compose 中真实的服务组件标识 (如 "komari")
    local SVC_KEY=$(echo "$RAW_BLOCK" | grep -E "^  [a-zA-Z0-9_-]+:" | head -n 1 | awk -F':' '{print $1}' | tr -d ' \r')

    while true; do
        clear
        echo -e "${C_BLUE}⚡ Docker 矩阵应用控制台: ${C_YELLOW}$SELECTED_NAME${C_RESET} (组件映射: $SVC_KEY)"
        echo -e "${LINE_GRAY}"
        echo " 1) 安装 (云端参数解析与部署)"
        echo " 2) 更新镜像 (Pull 最新版本并平滑重启)"
        echo " 3) 启动 (Start)"
        echo " 4) 重启 (Restart)"
        echo " 5) 停止 (Stop)"
        echo " 6) 卸载 (仅强制清除容器)"
        echo " 7) 抹除 (深度清除容器及本地挂载目录)"
        echo " 0) 返回上层大厅"
        echo -e "${LINE_GRAY}"
        read -p "请分配操作指令 [0-7]: " SUB_OPT

        case $SUB_OPT in
            1)
                _install_service "$SELECTED_NAME" "$RAW_BLOCK" "$SVC_KEY"
                ;;
            2)
                echo -e "${C_CYAN}🔄 正在追溯最新镜像...${C_RESET}"
                cd "$DOCKER_ROOT" || return
                docker compose pull "$SVC_KEY"
                docker compose up -d "$SVC_KEY"
                read -p "操作完毕，回车继续..." temp
                ;;
            3)
                cd "$DOCKER_ROOT" || return
                docker compose start "$SVC_KEY" 2>/dev/null || docker compose up -d "$SVC_KEY"
                read -p "操作完毕，回车继续..." temp
                ;;
            4)
                cd "$DOCKER_ROOT" || return
                docker compose restart "$SVC_KEY"
                read -p "操作完毕，回车继续..." temp
                ;;
            5)
                cd "$DOCKER_ROOT" || return
                docker compose stop "$SVC_KEY"
                read -p "操作完毕，回车继续..." temp
                ;;
            6)
                echo -e "${C_YELLOW}🗑️ 正在阻断并销毁容器资产...${C_RESET}"
                cd "$DOCKER_ROOT" || return
                docker compose stop "$SVC_KEY" 2>/dev/null
                docker compose rm -f -s "$SVC_KEY" 2>/dev/null
                echo -e "${C_GREEN}✅ 容器节点已切除。若需清除底层配置代码，请手动使用 nano 修改 yaml 文件。${C_RESET}"
                read -p "回车继续..." temp
                ;;
            7)
                read -p "⚠️ 极危警告：确定要彻底销毁容器、并强制删除宿主机上的映射数据文件夹吗？[y/N]: " is_del
                if [[ "$is_del" =~ ^[Yy]$ ]]; then
                    cd "$DOCKER_ROOT" || return
                    docker compose stop "$SVC_KEY" 2>/dev/null
                    docker compose rm -f -s "$SVC_KEY" 2>/dev/null
                    
                    # 清扫关联的宿主机目录 (匹配约定规则)
                    if [ -d "${DOCKER_ROOT}/${SVC_KEY}" ]; then
                        sudo rm -rf "${DOCKER_ROOT}/${SVC_KEY}"
                    fi
                    echo -e "${C_GREEN}✅ 容器及物理数据源已被连根拔起！记得清理 docker-compose.yml 遗留代码。${C_RESET}"
                else
                    echo -e "${C_GRAY}数据销毁动作已终止。${C_RESET}"
                fi
                read -p "回车继续..." temp
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
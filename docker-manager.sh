#!/bin/bash

# 全局颜色常量定义
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"

LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"
LOCAL_DP_PATH="/usr/local/bin/dp"
LOCAL_SRC_PATH="/app/docker-manager.sh"
KOMARI_DIR="/cj/dockercompose"
KOMARI_YML_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-compose-tools.yml"

# 精准锁定特定脚本文件的 GitHub Raw 原始文本直链更新源
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/docker-manager.sh"

manage_dp_alias() {
    clear
    if [ -f "$LOCAL_DP_PATH" ]; then
        echo -e "${C_BLUE}⚡ 快捷命令 [dp] 管理面板${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " 1) 🚀 线上热更新 [dp] 核心脚本 (仅拉取独立管理脚本并覆盖)"
        echo -e " 2) 🚨 彻底卸载移除快捷命令 [dp]"
        echo -e " 0) 返回主菜单"
        echo -e "${LINE_GRAY}"
        read -p "请选择操作序号: " ALIAS_OPT
        
        if [ "$ALIAS_OPT" == "1" ]; then
            echo -e "⏳ 正在从您的 GitHub 仓库拉取最新的 docker-manager.sh..."
            local tmp_update="/tmp/dp_git_update.sh"
            
            echo -e "💡 提示执行：${C_CYAN}curl -s -L $SCRIPT_UPDATE_URL > $tmp_update${C_RESET}"
            curl -s -L "$SCRIPT_UPDATE_URL" > "$tmp_update"
            
            if [ -s "$tmp_update" ] && ! grep -q "404:" "$tmp_update"; then
                echo -e "💡 提示执行：${C_CYAN}cp $tmp_update $LOCAL_DP_PATH && cp $tmp_update $LOCAL_SRC_PATH${C_RESET}"
                
                sudo cp "$tmp_update" "$LOCAL_DP_PATH"
                sudo chmod +x "$LOCAL_DP_PATH"
                [ -d "/app" ] && cp "$tmp_update" "$LOCAL_SRC_PATH" 2>/dev/null
                
                echo -e "${C_GREEN}🎉 独立脚本更新大成功！已成功覆盖本地文件并同步刷新全局 dp 命令！${C_RESET}"
                rm -f "$tmp_update"
                sleep 1.5
                
                # 【核心修复】不使用传统的单一 exec，而是强制通过 bash -c 重新拉起新命令，并清除当前命令哈希缓存
                hash -r 2>/dev/null
                exec bash -c "$LOCAL_DP_PATH"
            else
                echo -e "${C_RED}❌ 更新失败：无法连接到 GitHub 或该文件在仓库中不存在！${C_RESET}"
                echo -e "${C_GRAY}💡 请确认您的最新代码已成功提交到 github.com/wuyou18075/cj-easy 仓库的 main 分支中。${C_RESET}"
                rm -f "$tmp_update"
            fi
        elif [ "$ALIAS_OPT" == "2" ]; then
            echo -e "💡 提示执行：${C_CYAN}rm -f $LOCAL_DP_PATH${C_RESET}"
            sudo rm -f "$LOCAL_DP_PATH"
            echo -e "${C_GREEN}✅ 快捷命令 [dp] 已成功从系统物理卸载。${C_RESET}"
            exit 0
        fi
    else
        local current_script=""
        if [ -f "$0" ]; then current_script=$(readlink -f "$0"); else current_script=$(readlink -f "${BASH_SOURCE[0]}"); fi
        if [[ "$current_script" == *"/pipe:"* ]] || [ ! -f "$current_script" ]; then
            sudo cp /proc/$$/exe "$LOCAL_DP_PATH" 2>/dev/null || sudo cp "$0" "$LOCAL_DP_PATH" 2>/dev/null
            if [ ! -s "$LOCAL_DP_PATH" ]; then
                echo -e "💡 提示：请从本地物理文件运行后再注册！"
                return 1
            fi
        else
            echo -e "💡 提示执行：${C_CYAN}cp $current_script $LOCAL_DP_PATH && chmod +x $LOCAL_DP_PATH${C_RESET}"
            sudo cp "$current_script" "$LOCAL_DP_PATH"
        fi
        sudo chmod +x "$LOCAL_DP_PATH"
        echo -e "${C_GREEN}🎉 快捷命令 [dp] 注册成功！可在任意目录直接输入 dp 唤醒。${C_RESET}"
    fi
    sleep 1.5
}

show_short_help() {
    echo -e "${C_BLUE}⚡ dp 命令行快捷脚标帮助${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "  dp -h              👉 显示本帮助单层摘要"
    echo -e "  dp ps              👉 交互式/自适应调阅容器列表"
    echo -e "  dp up -d           👉 智能编排并在后台拉起项目"
    echo -e "  dp down            👉 彻底停止并支持专项点选粉碎数据目录"
    echo -e "  dp logs -f         👉 分层查看容器历史安全日志"
    echo -e "${LINE_GRAY}"
}

find_compose_files() {
    local files=()
    for f in docker-compose* compose*; do
        if [ -f "$f" ] && [[ "$f" == *.yml || "$f" == *.yaml ]]; then files+=("$f"); fi
    done
    echo "${files[@]}"
}

select_yaml_file() {
    local explicit_file=$1
    if [ -n "$explicit_file" ] && [ -f "$explicit_file" ]; then echo "$explicit_file"; return; fi
    local available_files=($(find_compose_files))
    if [ ${#available_files[@]} -eq 0 ]; then echo "";
    elif [ ${#available_files[@]} -eq 1 ]; then echo "${available_files[0]}"; else
        echo -e "${C_CYAN}📋 请选择配置文件序号：${C_RESET}" >&2
        for i in "${!available_files[@]}"; do echo "  $((i+1))) ${available_files[$i]}" >&2; done
        read -p "请输入序号: " file_idx >&2
        if [[ "$file_idx" =~ ^[0-9]+$ ]] && [ "$file_idx" -le "${#available_files[@]}" ] && [ "$file_idx" -gt 0 ]; then
            echo "${available_files[$((file_idx-1))]}"; else echo "${available_files[0]}"; fi
    fi
}

select_container_from_project() {
    local yaml=$1
    local services=($(docker compose -f "$yaml" config --services 2>/dev/null))
    if [ ${#services[@]} -eq 0 ]; then
        services=($(docker compose -f "$yaml" ps --format "{{.Service}}" 2>/dev/null | sort -u))
    fi
    if [ ${#services[@]} -eq 0 ]; then echo "ALL"; return; fi
    echo -e "${C_CYAN}📋 发现当前项目包含以下服务：${C_RESET}" >&2
    for i in "${!services[@]}"; do echo "  $((i+1))) ${services[$i]}" >&2; done
    echo -e "${LINE_GRAY}" >&2
    read -p "请输入服务序号 (直接回车默认全部): " svc_idx >&2
    if [[ "$svc_idx" =~ ^[0-9]+$ ]] && [ "$svc_idx" -le "${#services[@]}" ] && [ "$svc_idx" -gt 0 ]; then
        echo "${services[$((svc_idx-1))]}"; else echo "ALL"; fi
}

handle_args_logic() {
    local safe_action_cmd="$1"
    shift
    if [ "$safe_action_cmd" == "-h" ]; then show_short_help; return; fi

    local yaml_path=""
    local remain_args=()
    while [ $# -gt 0 ]; do
        if [ "$1" == "-f" ]; then yaml_path="$2"; shift 2; else remain_args+=("$1"); shift; fi
    done

    local target_yaml=$(select_yaml_file "$yaml_path")
    if [ -z "$target_yaml" ]; then
        echo -e "${C_RED}❌ 错误：未在当前路径下找到任何配置！${C_RESET}"
        return
    fi

    if [ "$safe_action_cmd" == "ps" ]; then
        echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml ps${C_RESET}"
        docker compose -f "$target_yaml" ps
    elif [ "$safe_action_cmd" == "up" ]; then
        echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml up ${remain_args[*]}${C_RESET}"
        docker compose -f "$target_yaml" up "${remain_args[@]}"
    elif [ "$safe_action_cmd" == "down" ]; then
        local raw_volumes=$(docker compose -f "$target_yaml" config 2>/dev/null | grep -E '\s+-\s+\./|\s+-\s+/[^:]+:[^:]+')
        local v_paths=()
        
        if [ -n "$raw_volumes" ]; then
            while read -r line; do
                local p=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | cut -d':' -f1)
                if [[ "$p" == ./* ]]; then p="$(pwd)/${p#./}"; fi
                if [ -d "$p" ] && [[ "$p" != "/" && "$p" != "/var/lib"* ]]; then v_paths+=("$p"); fi
            done <<< "$raw_volumes"
        fi

        local target_delete_path=""
        if [ ${#v_paths[@]} -gt 0 ]; then
            local clean_paths=($(echo "${v_paths[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
            echo -e "${C_CYAN}📋 检测到本项目包含以下本地挂载数据目录：${C_RESET}"
            for i in "${!clean_paths[@]}"; do
                echo -e "  $((i+1))) ${C_YELLOW}${clean_paths[$i]}${C_RESET}"
            done
            echo -e "${LINE_GRAY}"
            read -p "❓ 请输入你想彻底粉碎删除的数据目录序号 (0或直接回车代表安全退出不删): " del_idx
            
            if [[ "$del_idx" =~ ^[0-9]+$ ]] && [ "$del_idx" -le "${#clean_paths[@]}" ] && [ "$del_idx" -gt 0 ]; then
                target_delete_path="${clean_paths[$((del_idx-1))]}"
                echo -e "${C_RED}🚨 已精准锁定删除目标: $target_delete_path${C_RESET}"
            fi
        fi

        echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml down${C_RESET}"
        docker compose -f "$target_yaml" down

        if [ -n "$target_delete_path" ] && [ -d "$target_delete_path" ]; then
            echo -e "💡 提示执行：${C_RED}rm -rf $target_delete_path${C_RESET}"
            sudo rm -rf "$target_delete_path"
            echo -e "${C_GREEN}💥 专项物理资产已粉碎蒸发完毕。${C_RESET}"
        else
            echo -e "${C_GREEN}✅ 容器已安全关闭，未删除任何本地物理资产目录。${C_RESET}"
        fi
    elif [ "$safe_action_cmd" == "logs" ]; then
        local chosen_svc=$(select_container_from_project "$target_yaml" "logs")
        if [ "$chosen_svc" == "ALL" ]; then
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml logs --tail=300${C_RESET}"
            docker compose -f "$target_yaml" logs --tail=300
        else
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml logs --tail=300 $chosen_svc${C_RESET}"
            docker compose -f "$target_yaml" logs --tail=300 "$chosen_svc"
        fi
    else
        echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml $safe_action_cmd ${remain_args[*]}${C_RESET}"
        docker compose -f "$target_yaml" "$safe_action_cmd" "${remain_args[@]}"
    fi
}

menu_komari_probe() {
    while true; do
        clear
        echo -e "${C_BLUE}⚡ Komari 自动化服务监控面板${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e "1) 一键拉取部署安装"
        echo -e "2) 热拉取最新镜像更新"
        echo -e "3) 阻断并彻底卸载服务"
        echo -e "4) 独立安全归类备份配置文件及项目资产"
        echo -e "0) 返回上一层"
        echo -e "${LINE_GRAY}"
        read -p "选择探针控制令: " KO_OPT
        if [ "$KO_OPT" == "0" ] || [ -z "$KO_OPT" ]; then break; fi
        if [ "$KO_OPT" == "1" ]; then
            echo "⏳ 正在初始化拓扑目录..."
            sudo mkdir -p "$KOMARI_DIR/data"
            curl -s -L "$KOMARI_YML_URL" > "$KOMARI_DIR/docker-compose-tools.yml"
            if [ ! -s "$KOMARI_DIR/docker-compose-tools.yml" ]; then 
                echo "❌ 错误：拉取核心模块失败！"; sleep 2; continue
            fi
            read -p "🔑 设置管理员初始用户名: " KO_USER
            read -p "🔑 设置管理员初始密码: " KO_PASS
            [ -z "$KO_USER" ] && KO_USER="admin"
            [ -z "$KO_PASS" ] && KO_PASS="komari_secure_pwd"
            sed -i "s/ADMIN_USERNAME=.*/ADMIN_USERNAME=$KO_USER/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$KO_PASS/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s|-\s\./komari:|- ./data:|g" "$KOMARI_DIR/docker-compose-tools.yml"
            echo "🚀 正在拉起多路容器群生态..."
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml up -d${C_RESET}"
            docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
            echo -e "${C_GREEN}🎉 安装部署全部完成！${C_RESET}"; sleep 1.5
        elif [ "$KO_OPT" == "2" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml pull && docker compose -f $KOMARI_DIR/docker-compose-tools.yml up -d${C_RESET}"
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" pull
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
                echo -e "${C_GREEN}✅ 探针热升级刷新完成。${C_RESET}"
            else echo "❌ 错误：监控未安装！"; sleep 1.5; fi
        elif [ "$KO_OPT" == "3" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml down -v${C_RESET}"
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" down -v
                sudo rm -f "$KOMARI_DIR/docker-compose-tools.yml"
                echo -e "${C_GREEN}✅ 服务彻底清除销毁。${C_RESET}"
            else echo "❌ 实例不存在。"; sleep 1.5; fi
        elif [ "$KO_OPT" == "4" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo -e "${C_YELLOW}⚠️  安全提示：密码写入文件有泄露风险。${C_RESET}"
                read -p "❓ 是否将凭证写入备份？(回车默认不备份) [y/N]: " IS_PWD_BAK
                [ -z "$IS_PWD_BAK" ] && IS_PWD_BAK="n"
                BACKUP_TAR="/cj/temp/komari_bak_$(date +%Y%m%d%H%M%S).tar.gz"
                sudo mkdir -p /cj/temp
                TMP_BAK_DIR="/tmp/komari_bak_dir"
                sudo rm -rf "$TMP_BAK_DIR" && mkdir -p "$TMP_BAK_DIR"
                if [ "$IS_PWD_BAK" == "y" ] || [ "$IS_PWD_BAK" == "Y" ]; then
                    EXT_USER=$(grep "ADMIN_USERNAME=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    EXT_PASS=$(grep "ADMIN_PASSWORD=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    echo -e "【Komari 凭证】\n用户名: $EXT_USER\n密码: $EXT_PASS" > "$TMP_BAK_DIR/credentials.txt"
                fi
                cp "$KOMARI_DIR/docker-compose-tools.yml" "$TMP_BAK_DIR/"
                cp -r "$KOMARI_DIR/data" "$TMP_BAK_DIR/" 2>/dev/null
                echo -e "💡 提示执行：${C_CYAN}tar -czf $BACKUP_TAR -C $TMP_BAK_DIR .${C_RESET}"
                tar -czf "$BACKUP_TAR" -C "$TMP_BAK_DIR" . 2>/dev/null
                sudo rm -rf "$TMP_BAK_DIR"
                echo -e "${C_GREEN}🎉 备份成功！${C_RESET}\n📦 留存绝对路径: ${C_CYAN}$BACKUP_TAR${C_RESET}"
            else echo "❌ 无法执行备份。"; fi
            read -p "回车继续..." temp
        fi
    done
}

menu_main_logic() {
    while true; do
        if ! command -v docker &> /dev/null; then DOCKER_STATUS_TEXT="${C_RED}未安装${C_RESET}"; else
            if systemctl is-active --quiet docker; then DOCKER_STATUS_TEXT="${C_GREEN}运行${C_RESET}"; else DOCKER_STATUS_TEXT="${C_YELLOW}停止${C_RESET}"; fi
        fi
        if [ -f "$LOCAL_DP_PATH" ]; then DP_SHORT_TEXT=" [ 快捷命令: dp ]"; else DP_SHORT_TEXT=""; fi
        clear
        echo -e "${C_BLUE}⚡ Docker 容器引擎多维调度矩阵${DP_SHORT_TEXT}${C_RESET}"
        echo -e "${LINE_GRAY}"
        echo -e " docker 状态: $DOCKER_STATUS_TEXT"
        echo -e "${LINE_GRAY}"
        echo -e "1) Docker 安装 / 彻底卸载"
        echo -e "2) 当前路径 Docker Compose 容器列表"
        echo -e "3) 全局所有 Docker 容器大盘点"
        echo -e "4) 全局 Docker 虚拟网络集群列表"
        echo -e "5) Docker 高级百宝箱 (占位)"
        echo -e "6) 申请与管理 Komari 探针 ${C_YELLOW}⭐${C_RESET}"
        echo -e "9) 命令行快捷命令使用帮助"
        echo -e "10) 注册 / 更新 / 卸载快捷命令 [dp] ${C_YELLOW}⭐${C_RESET}"
        echo -e "0) 安全退出"
        echo -e "${LINE_GRAY}"
        read -p "请注入主操作编号: " MENU_OPT
        if [ "$MENU_OPT" == "0" ] || [ -z "$MENU_OPT" ]; then echo "👋 安全退出。"; exit 0; fi
        case $MENU_OPT in
            1)
                clear
                echo -e "1) 智能加固安装 Docker & Compose"
                echo -e "2) 完全粉碎卸载 Docker 生态"
                read -p "请选子项: " SUB_D
                if [ "$SUB_D" == "1" ]; then
                    echo -e "💡 提示执行：${C_CYAN}curl -fsSL https://get.docker.com | bash${C_RESET}"
                    curl -fsSL https://get.docker.com | bash
                    sudo systemctl enable docker &>/dev/null
                    sudo systemctl start docker &>/dev/null
                    if command -v docker &> /dev/null; then
                        echo -e "${C_GREEN}🎉 Docker 安装成功！当前版本: $(docker --version)${C_RESET}"
                        read -p "❓ 是否继续安装 Docker Compose 组件？(回车默认安装) [Y/n]: " IS_COMPOSE_INS
                        [ -z "$IS_COMPOSE_INS" ] && IS_COMPOSE_INS="y"
                        if [ "$IS_COMPOSE_INS" == "y" ] || [ "$IS_COMPOSE_INS" == "Y" ]; then
                            echo -e "💡 提示执行：${C_CYAN}apt-get install -y docker-compose-plugin${C_RESET}"
                            if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y docker-compose-plugin
                            elif command -v yum &> /dev/null; then sudo yum install -y docker-compose-plugin; fi
                            echo -e "${C_GREEN}🎉 Compose 挂载配置成功！版本: $(docker compose version)${C_RESET}"
                        fi
                    fi
                elif [ "$SUB_D" == "2" ]; then
                    read -p "确定彻底清洗吗？[y/N]: " IS_RM_CONFIRM
                    if [ "$IS_RM_CONFIRM" == "y" ] || [ "$IS_RM_CONFIRM" == "Y" ]; then
                        echo -e "💡 提示执行：${C_CYAN}apt-get purge -y docker-ce docker-compose-plugin && rm -rf /var/lib/docker${C_RESET}"
                        if command -v apt-get &> /dev/null; then sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && sudo apt-get autoremove -y
                        elif command -v yum &> /dev/null; then sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; fi
                        sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
                        echo -e "${C_GREEN}✅ Docker 彻底卸载。${C_RESET}"
                    fi
                fi
                read -p "按回车继续..." temp ;;
            2)
                local cur_yaml=$(select_yaml_file "")
                if [ -n "$cur_yaml" ]; then
                    echo -e "💡 提示执行：${C_CYAN}docker compose -f $cur_yaml ps -a${C_RESET}"
                    echo -e "${LINE_GRAY}"
                    docker compose -f "$cur_yaml" ps -a
                else echo -e "${C_YELLOW}⚠️  提示：未扫描到符合标准的配置文件。${C_RESET}"; fi
                read -p "按回车继续..." temp ;;
            3)
                echo -e "💡 提示执行：${C_CYAN}docker ps -a --format \"table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}\"${C_RESET}"
                echo -e "${LINE_GRAY}"
                docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
                read -p "按回车继续..." temp ;;
            4)
                echo -e "💡 提示执行：${C_CYAN}docker network ls${C_RESET}"
                echo -e "${LINE_GRAY}"
                docker network ls
                read -p "按回车继续..." temp ;;
            5) echo -e "${C_YELLOW}🚧 占位中...${C_RESET}"; sleep 1.5 ;;
            6) menu_komari_probe ;;
            9) clear; show_short_help; read -p "按回车继续..." temp ;;
            10) manage_dp_alias ;;
            *) echo -e "${C_RED}❌ 无效选项！${C_RESET}"; sleep 1 ;;
        esac
    done
}

if [ $# -eq 0 ]; then
    menu_main_logic
else
    handle_args_logic "$@"
fi

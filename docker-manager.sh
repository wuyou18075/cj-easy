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

# 快捷方式注册与卸载函数
manage_dp_alias() {
    local action=$1
    if [ "$action" == "install" ]; then
        # 获取当前脚本的绝对路径
        local current_script=$(readlink -f "$0")
        echo "#!/bin/bash
$current_script \"\$@\"" | sudo tee "$LOCAL_DP_PATH" > /dev/null
        sudo chmod +x "$LOCAL_DP_PATH"
        echo -e "💡 提示执行：${C_CYAN}echo '#!/bin/bash; $current_script \"\$@\"' > $LOCAL_DP_PATH && chmod +x $LOCAL_DP_PATH${C_RESET}"
        echo -e "${C_GREEN}✅ 快捷方式 [dp] 注册成功！可在任意目录直接输入 dp 唤醒。${C_RESET}"
    else
        sudo rm -f "$LOCAL_DP_PATH"
        echo -e "💡 提示执行：${C_CYAN}rm -f $LOCAL_DP_PATH${C_RESET}"
        echo -e "${C_GREEN}✅ 快捷方式 [dp] 已成功卸载移除。${C_RESET}"
    fi
    sleep 1.5
}

# 快捷命令帮助菜单 (只显示第一层)
show_short_help() {
    echo -e "${C_BLUE}⚡ dp 命令行快捷脚标帮助${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "  dp -h              👉 显示本帮助单层摘要"
    echo -e "  dp ps              👉 交互式/自适应调阅容器列表"
    echo -e "  dp up -d           👉 智能编排并在后台拉起项目"
    echo -e "  dp down            👉 彻底停止并销毁当前项目容器"
    echo -e "  dp logs -f         👉 分层查看容器历史安全日志"
    echo -e "${LINE_GRAY}"
}

# 扫描当前目录下符合条件的 docker-compose 配置文件
find_compose_files() {
    local files=()
    for f in docker-compose* compose*; do
        if [ -f "$f" ] && [[ "$f" == *.yml || "$f" == *.yaml ]]; then
            files+=("$f")
        fi
    done
    echo "${files[@]}"
}

# 智能选择/提炼 YAML 配置文件
select_yaml_file() {
    local explicit_file=$1
    if [ -n "$explicit_file" ] && [ -f "$explicit_file" ]; then
        echo "$explicit_file"
        return
    fi

    local available_files=($(find_compose_files))
    if [ ${#available_files[@]} -eq 0 ]; then
        echo ""
    elif [ ${#available_files[@]} -eq 1 ]; then
        echo "${available_files[0]}"
    else
        # 存在多个文件，引导用户选择
        echo -e "${C_CYAN}📋 检测到当前目录下存在多个 Compose 配置文件：${C_RESET}" >&2
        for i in "${!available_files[@]}"; do
            echo "  $((i+1))) ${available_files[$i]}" >&2
        done
        read -p "请选择需要操作的配置文件序号: " file_idx flocks >&2
        if [[ "$file_idx" =~ ^[0-9]+$ ]] && [ "$file_idx" -le "${#available_files[@]}" ] && [ "$file_idx" -gt 0 ]; then
            echo "${available_files[$((file_idx-1))]}"
        else
            echo "${available_files[0]}"
        fi
    fi
}

# 交互式单选/全选容器处理器
select_container_from_project() {
    local yaml=$1
    local action=$2 # ps, up, down, logs
    
    # 获取 compose 项目中的服务列表
    local services=($(docker compose -f "$yaml" config --services 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        # 如果无法通过 config 解析，尝试用 ps 捞取
        services=($(docker compose -f "$yaml" ps --format "{{.Service}}" 2>/dev/null | sort -u))
    fi

    if [ ${#services[@]} -eq 0 ]; then
        echo "ALL"
        return
    fi

    echo -e "${C_CYAN}📋 发现当前项目包含以下服务：${C_RESET}" >&2
    for i in "${!services[@]}"; do
        echo "  $((i+1))) ${services[$i]}" >&2
    done
    echo -e "${LINE_GRAY}" >&2
    read -p "请输入需要操作的服务序号 (直接回车默认全部): " svc_idx >&2

    if [[ "$svc_idx" =~ ^[0-9]+$ ]] && [ "$svc_idx" -le "${#services[@]}" ] && [ "$svc_idx" -gt 0 ]; then
        echo "${services[$((svc_idx-1))]}"
    else
        echo "ALL"
    fi
}

# 处理带有外置命令参数的极端穿透逻辑
handle_args_logic() {
    local cmd=$1
    shift
    
    # 特殊判读帮助
    if [ "$cmd" == "-h" ]; then
        show_short_help
        return
    fi

    # 提取 -f 后面紧跟的参数，如果存在的话
    local yaml_path=""
    local remain_args=()
    
    while [ $# -gt 0 ]; do
        if [ "$1" == "-f" ]; then
            yaml_path="$2"
            shift 2
        else
            remain_args+=("$1")
            shift
        fi
    done

    # 智能对齐捕获具体的 YAML 文件
    local target_yaml=$(select_yaml_file "$yaml_path")
    if [ -z "$target_yaml" ]; then
        echo -e "${C_RED}❌ 错误：未在当前路径下找到任何符合条件的 docker-compose 配置文件！${C_RESET}"
        return
    fi

    # 根据命令类型进行分流与提示学习
    case "$cmd" in
        ps)
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml ps${C_RESET}"
            docker compose -f "$target_yaml" ps
            ;;
        up)
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml up -d${C_RESET}"
            docker compose -f "$target_yaml" up -d
            ;;
        down)
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml down${C_RESET}"
            docker compose -f "$target_yaml" down
            ;;
        logs)
            local chosen_svc=$(select_container_from_project "$target_yaml" "logs")
            if [ "$chosen_svc" == "ALL" ]; then
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml logs --tail=300${C_RESET}"
                docker compose -f "$target_yaml" logs --tail=300
            else
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml logs --tail=300 $chosen_svc${C_RESET}"
                docker compose -f "$target_yaml" logs --tail=300 "$chosen_svc"
            fi
            ;;
        *)
            # 其他透传命令兼容处理
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml $cmd ${remain_args[*]}${C_RESET}"
            docker compose -f "$target_yaml" "$cmd" "${remain_args[@]}"
            ;;
    esac
}

# =========================================================
#                    主交互菜单逻辑块
# =========================================================
menu_main_logic() {
    while true; do
        # 1. 动态探测并回显 Docker 安装与运行状态
        if ! command -v docker &> /dev/null; then
            DOCKER_STATUS_TEXT="${C_RED}未安装${C_RESET}"
        else
            if systemctl is-active --quiet docker; then
                DOCKER_STATUS_TEXT="${C_GREEN}运行${C_RESET}"
            else
                DOCKER_STATUS_TEXT="${C_YELLOW}停止${C_RESET}"
            fi
        fi

        # 2. 动态探测快捷键状态
        if [ -f "$LOCAL_DP_PATH" ]; then
            DP_SHORT_TEXT=" [ 快捷命令: dp ]"
        else
            DP_SHORT_TEXT=""
        fi

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
        echo -e "9) 命令行快捷命令使用帮助"
        echo -e "10) 注册 / 卸载快捷命令 [dp]"
        echo -e "0) 安全退出"
        echo -e "${LINE_GRAY}"
        read -p "请注入主操作编号: " MENU_OPT

        if [ "$MENU_OPT" == "0" ] || [ -z "$MENU_OPT" ]; then
            echo "👋 安全退出。"; exit 0
        fi

        case $MENU_OPT in
            1)
                clear
                echo -e "1) 智能加固安装 Docker & Compose"
                echo -e "2) 完全粉碎卸载 Docker 生态"
                read -p "请选子项: " SUB_D
                if [ "$SUB_D" == "1" ]; then
                    echo "⏳ 正在同步系统存储库并安全部署 Docker 核心引擎..."
                    echo -e "💡 提示执行：${C_CYAN}curl -fsSL https://get.docker.com | bash${C_RESET}"
                    curl -fsSL https://get.docker.com | bash
                    sudo systemctl enable docker &>/dev/null
                    sudo systemctl start docker &>/dev/null
                    
                    if command -v docker &> /dev/null; then
                        echo -e "${C_GREEN}🎉 Docker 安装成功！当前版本: $(docker --version)${C_RESET}"
                        read -p "❓ 是否继续安装 Docker Compose 组件？(回车默认安装) [Y/n]: " IS_COMPOSE_INS
                        [ -z "$IS_COMPOSE_INS" ] && IS_COMPOSE_INS="y"
                        if [ "$IS_COMPOSE_INS" == "y" ] || [ "$IS_COMPOSE_INS" == "Y" ]; then
                            echo "⏳ 正在下载并配置 Compose 最新二进制核心..."
                            echo -e "💡 提示执行：${C_CYAN}apt-get install -y docker-compose-plugin${C_RESET}"
                            if command -v apt-get &> /dev/null; then
                                sudo apt-get update && sudo apt-get install -y docker-compose-plugin
                            elif command -v yum &> /dev/null; then
                                sudo yum install -y docker-compose-plugin
                            fi
                            echo -e "${C_GREEN}🎉 Compose 挂载配置成功！版本: $(docker compose version)${C_RESET}"
                        fi
                    fi
                elif [ "$SUB_D" == "2" ]; then
                    echo -e "${C_YELLOW}🚨 警报：这将连带删除所有现有的容器、镜像及关联的 Compose 编排文件！${C_RESET}"
                    read -p "确定彻底清洗吗？[y/N]: " IS_RM_CONFIRM
                    if [ "$IS_RM_CONFIRM" == "y" ] || [ "$IS_RM_CONFIRM" == "Y" ]; then
                        echo "⏳ 正在移除系统底层核心组件..."
                        echo -e "💡 提示执行：${C_CYAN}apt-get purge -y docker-ce docker-compose-plugin && rm -rf /var/lib/docker${C_RESET}"
                        if command -v apt-get &> /dev/null; then
                            sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
                            sudo apt-get autoremove -y
                        elif command -v yum &> /dev/null; then
                            sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                        fi
                        sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
                        echo -e "${C_GREEN}✅ Docker 及其全部生态组件已干净移除。${C_RESET}"
                    fi
                fi
                read -p "按回车继续..." temp
                ;;
            2)
                local cur_yaml=$(select_yaml_file "")
                if [ -n "$cur_yaml" ]; then
                    echo -e "💡 提示执行：${C_CYAN}docker compose -f $cur_yaml ps -a${C_RESET}"
                    echo -e "${LINE_GRAY}"
                    docker compose -f "$cur_yaml" ps -a
                else
                    echo -e "${C_YELLOW}⚠️  提示：当前路径下未扫描到符合标准的 docker-compose.yml 配置文件。${C_RESET}"
                fi
                read -p "按回车继续..." temp
                ;;
            3)
                echo -e "💡 提示执行：${C_CYAN}docker ps -a --format \"table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}\"${C_RESET}"
                echo -e "${LINE_GRAY}"
                docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
                read -p "按回车继续..." temp
                ;;
            4)
                echo -e "💡 提示执行：${C_CYAN}docker network ls${C_RESET}"
                echo -e "${LINE_GRAY}"
                docker network ls
                read -p "按回车继续..." temp
                ;;
            5)
                echo -e "${C_YELLOW}🚧 百宝箱高阶模块正在打磨开发中，敬请期待...${C_RESET}"
                sleep 1.5
                ;;
            9)
                clear
                show_short_help
                read -p "按回车继续..." temp
                ;;
            10)
                clear
                if [ -f "$LOCAL_DP_PATH" ]; then
                    read -p "❓ 快捷键当前已处于启用状态，是否确认注销移除？[y/N]: " IS_UNINS
                    [ "$IS_UNINS" == "y" ] || [ "$IS_UNINS" == "Y" ] && manage_dp_alias "uninstall"
                else
                    manage_dp_alias "install"
                fi
                ;;
            *)
                echo -e "${C_RED}❌ 无效选项，请重新输入！${C_RESET}"; sleep 1
                ;;
        esac
    done
}

# =========================================================
#                  脚本生命周期核心总入口
# =========================================================
if [ $# -eq 0 ]; then
    # 没有任何参数传递，优雅切入主交互菜单
    menu_main_logic
else
    # 探测到携带了诸如 dp ps / dp down 等外置命令参数，强力切入快捷透传引擎
    handle_args_logic "$@"
fi

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
KOMARI_DIR="/cj/dockercompose"
KOMARI_YML_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-compose-tools.yml"

# 快捷方式自动固化注册与卸载函数
manage_dp_alias() {
    local action=$1
    if [ "$action" == "install" ]; then
        # 获取当前正在运行的脚本自身的绝对物理路径
        local current_script=$(readlink -f "$0")
        
        # 提示用户即将执行的原生命令
        echo -e "💡 提示执行：${C_CYAN}cp $current_script $LOCAL_DP_PATH && chmod +x $LOCAL_DP_PATH${C_RESET}"
        
        # 强行将当前运行的完整代码复制固化到 /usr/local/bin/dp 中
        sudo cp "$current_script" "$LOCAL_DP_PATH"
        sudo chmod +x "$LOCAL_DP_PATH"
        
        echo -e "${C_GREEN}🎉 快捷命令 [dp] 自动固化注册成功！可在任意目录直接输入 dp 唤醒。${C_RESET}"
    else
        echo -e "💡 提示执行：${C_CYAN}rm -f $LOCAL_DP_PATH${C_RESET}"
        sudo rm -f "$LOCAL_DP_PATH"
        echo -e "${C_GREEN}✅ 快捷命令 [dp] 已成功卸载移除。${C_RESET}"
        exit 0
    fi
    sleep 1.5
}

# 快捷命令帮助菜单
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

# 智能选择 YAML 配置文件
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
        echo -e "${C_CYAN}📋 检测到当前目录下存在多个 Compose 配置文件：${C_RESET}" >&2
        for i in "${!available_files[@]}"; do
            echo "  $((i+1))) ${available_files[$i]}" >&2
        done
        read -p "请选择配置文件序号: " file_idx >&2
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
    local action=$2
    local services=($(docker compose -f "$yaml" config --services 2>/dev/null))
    if [ ${#services[@]} -eq 0 ]; then
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

# 处理带有外置命令参数的强力透传逻辑
handle_args_logic() {
    local cmd=$1
    shift
    if [ "$cmd" == "-h" ]; then
        show_short_help
        return
    fi

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

    local target_yaml=$(select_yaml_file "$yaml_path")
    if [ -z "$target_yaml" ]; then
        echo -e "${C_RED}❌ 错误：未在当前路径下找到任何符合条件的配置！${C_RESET}"
        return
    fi

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
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $target_yaml $cmd ${remain_args[*]}${C_RESET}"
            docker compose -f "$target_yaml" "$cmd" "${remain_args[@]}"
            ;;
    esac
}

# Komari 探针自动化运维子模块
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
            echo "⏳ 正在初始化基础物理拓扑目录..."
            sudo mkdir -p "$KOMARI_DIR/data"
            echo "⏳ 正在同步拉取云端工具库模块..."
            curl -s -L "$KOMARI_YML_URL" > "$KOMARI_DIR/docker-compose-tools.yml"
            
            if [ ! -s "$KOMARI_DIR/docker-compose-tools.yml" ]; then
                echo "❌ 错误：拉取核心模块失败，请检查网络通路！"; sleep 2; continue
            fi

            read -p "🔑 请设置系统管理员初始用户名: " KO_USER
            read -p "🔑 请设置系统管理员初始密码: " KO_PASS
            [ -z "$KO_USER" ] && KO_USER="admin"
            [ -z "$KO_PASS" ] && KO_PASS="komari_secure_pwd"

            sed -i "s/ADMIN_USERNAME=.*/ADMIN_USERNAME=$KO_USER/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$KO_PASS/g" "$KOMARI_DIR/docker-compose-tools.yml"
            sed -i "s|-\s\./komari:|- ./data:|g" "$KOMARI_DIR/docker-compose-tools.yml"

            echo "🚀 正在拉起编排多路容器群生态..."
            echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml up -d${C_RESET}"
            docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
            echo -e "${C_GREEN}🎉 安装部署全部完成！${C_RESET}"; sleep 1.5

        elif [ "$KO_OPT" == "2" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo "⏳ 正在通过容器名 komari 热追踪拉取最新镜像流..."
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml pull && docker compose -f $KOMARI_DIR/docker-compose-tools.yml up -d${C_RESET}"
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" pull
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
                echo -e "${C_GREEN}✅ 探针群落热升级刷新完成。${C_RESET}"
            else
                echo "❌ 错误：未在系统内检索到名为 komari 的活跃容器，请先安装！"
            fi
            sleep 1.5

        elif [ "$KO_OPT" == "3" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo "🚨 正在彻底摧毁并注销该探针服务生态..."
                echo -e "💡 提示执行：${C_CYAN}docker compose -f $KOMARI_DIR/docker-compose-tools.yml down -v && rm -f $KOMARI_DIR/docker-compose-tools.yml${C_RESET}"
                docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" down -v
                sudo rm -f "$KOMARI_DIR/docker-compose-tools.yml"
                echo -e "${C_GREEN}✅ 服务彻底清除销毁。${C_RESET}"
            else
                echo "❌ 系统内未发现运行中的 komari 监控实例。"
            fi
            sleep 1.5

        elif [ "$KO_OPT" == "4" ]; then
            if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
                echo -e "${C_YELLOW}⚠️  安全隐患提示：明文密码备份到本地归档文件中可能存在安全泄露风险。${C_RESET}"
                read -p "❓ 是否确认将当前管理员账号和密码写入备份归档？(回车默认不备份) [y/N]: " IS_PWD_BAK
                [ -z "$IS_PWD_BAK" ] && IS_PWD_BAK="n"

                echo "⏳ 正在通过容器名匹配进行物理集群资产冷备份..."
                BACKUP_TAR="/cj/temp/komari_bak_$(date +%Y%m%d%H%M%S).tar.gz"
                sudo mkdir -p /cj/temp
                
                TMP_BAK_DIR="/tmp/komari_bak_dir"
                sudo rm -rf "$TMP_BAK_DIR" && mkdir -p "$TMP_BAK_DIR"
                
                if [ "$IS_PWD_BAK" == "y" ] || [ "$IS_PWD_BAK" == "Y" ]; then
                    EXT_USER=$(grep "ADMIN_USERNAME=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    EXT_PASS=$(grep "ADMIN_PASSWORD=" "$KOMARI_DIR/docker-compose-tools.yml" | cut -d'=' -f2)
                    echo -e "【Komari 凭证备份】\n用户名: $EXT_USER\n密码: $EXT_PASS" > "$TMP_BAK_DIR/credentials.txt"
                fi

                cp "$KOMARI_DIR/docker-compose-tools.yml" "$TMP_BAK_DIR/"
                cp -r "$KOMARI_DIR/data" "$TMP_BAK_DIR/" 2>/dev/null

                echo -e "💡 提示执行：${C_CYAN}tar -czf $BACKUP_TAR -C $TMP_BAK_DIR .${C_RESET}"
                tar -czf "$BACKUP_TAR" -C "$TMP_BAK_DIR" . 2>/dev/null
                sudo rm -rf "$TMP_BAK_DIR"

                echo -e "${C_GREEN}🎉 备份完全成功！${C_RESET}"
                echo -e "📦 物理打包压缩资产锁留存绝对路径:\n👉 ${C_CYAN}$BACKUP_TAR${C_RESET}"
            else
                echo "❌ 无法执行备份：系统底层未通过容器名检索到活跃的 komari 项目结构。"
            fi
            read -p "回车继续..." temp
        fi
    done
}

# 主交互菜单
menu_main_logic() {
    while true; do
        if ! command -v docker &> /dev/null; then
            DOCKER_STATUS_TEXT="${C_RED}未安装${C_RESET}"
        else
            if systemctl is-active --quiet docker; then
                DOCKER_STATUS_TEXT="${C_GREEN}运行${C_RESET}"
            else
                DOCKER_STATUS_TEXT="${C_YELLOW}停止${C_RESET}"
            fi
        fi

        # 判断是否已经固化到全局路径
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
                            if command -v apt-get &> /dev/null; then
                                sudo apt-get update && sudo apt-get install -y docker-compose-plugin
                            elif command -v yum &> /dev/null; then
                                sudo yum install -y docker-compose-plugin
                            fi
                            echo -e "${C_GREEN}🎉 Compose 挂载配置成功！版本: $(docker compose version)${C_RESET}"
                        fi
                    fi
                elif [ "$SUB_D" == "2" ]; then
                    read -p "确定彻底清洗吗？[y/N]: " IS_RM_CONFIRM
                    if [ "$IS_RM_CONFIRM" == "y" ] || [ "$IS_RM_CONFIRM" == "Y" ]; then
                        echo -e "💡 提示执行：${C_CYAN}apt-get purge -y docker-ce docker-compose-plugin && rm -rf /var/lib/docker${C_RESET}"
                        if command -v apt-get &> /dev/null; then
                            sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                            sudo apt-get autoremove -y
                        elif command -v yum &> /dev/null; then
                            sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                        fi
                        sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
                        echo -e "${C_GREEN}✅ Docker 彻底卸载。${C_RESET}"
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
                    echo -e "${C_YELLOW}⚠️  提示：未扫描到符合标准的 docker-compose 配置文件。${C_RESET}"
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
                echo -e "${C_YELLOW}🚧 占位中...${C_RESET}"; sleep 1.5
                ;;
            9)
                clear; show_short_help; read -p "按回车继续..." temp
                ;;
            10)
                clear
                if [ -f "$LOCAL_DP_PATH" ]; then
                    read -p "❓ 快捷键当前已启用，是否确认卸载移除？[y/N]: " IS_UNINS
                    if [ "$IS_UNINS" == "y" ] || [ "$IS_UNINS" == "Y" ]; then
                        manage_dp_alias "uninstall"
                    fi
                else
                    manage_dp_alias "install"
                fi
                ;;
            *)
                echo -e "${C_RED}❌ 无效选项！${C_RESET}"; sleep 1
                ;;
        esac
    done
}

# 判断带参执行还是进交互菜单
if [ $# -eq 0 ]; then
    menu_main_logic
else
    handle_args_logic "$@"
fi

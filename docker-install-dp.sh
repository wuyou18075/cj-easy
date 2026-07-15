#!/bin/bash

# ==============================================================================
# 脚本名称: docker-install-dp.sh (GitHub 远程专供完整版)
# 系统支持: Debian 13 (Trixie)
# 优化特性: 完美支持远程 bash <(curl ...) 挂载执行，快捷键注册绝不失效
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m错误：请使用 root 权限运行此脚本！\033[0m"
    exit 1
fi

# 检查当前目录下是否存在 compose 配置文件
check_compose_file() {
    if [ -f "docker-compose.yaml" ] || [ -f "docker-compose.yml" ]; then
        echo "true"
    else
        echo "false"
    fi
}

get_docker_status() {
    if ! command -v docker &> /dev/null; then
        echo -e "\033[31m未安装\033[0m"
    else
        if ! systemctl is-active --quiet docker; then
            echo -e "\033[33m未启动(已安装)\033[0m"
        else
            local version
            version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || docker -v | awk '{print $3}' | tr -d ',')
            echo -e "\033[32m正在运行(v${version})\033[0m"
        fi
    fi
}

get_compose_status() {
    if docker compose version &> /dev/null; then
        echo -e "\033[32m已安装($(docker compose version | awk '{print $4}'))\033[0m"
    else
        echo -e "\033[31m未安装\033[0m"
    fi
}

# 50条核心内置命令库
declare -a GLOBAL_CMDS=(
    "docker ps -a                  | 列出本地所有容器（包含运行中和已停止的）"
    "docker images                  | 列出本地所有已下载的镜像及大小"
    "docker logs -f --tail 100 ID  | 动态追踪指定容器最后 100 行日志"
    "docker exec -it ID bash        | 以前提交互模式精准进入容器内部 bash 终端"
    "docker restart ID              | 快速重启指定的容器服务"
    "docker rm -f ID                | 强制删除指定的容器（哪怕它正在运行）"
    "docker rmi ID                  | 删除指定的本地镜像（需先删除相关容器）"
    "docker volume prune            | 清理本地所有未被挂载的孤儿和无用数据卷"
    "docker compose up -d           | 后台静默启动当前路径下的全套编排服务"
    "docker compose down            | 停止并彻底移除当前路径下的全套编排容器与网络"
    "docker info                    | 查看当前 Docker 引擎的系统级别详细配置信息"
    "docker version                 | 查看 Docker 客户端与服务端的版本详细信息"
    "docker inspect ID              | 以 JSON 格式查看容器/镜像的底层元数据详细结构"
    "docker top ID                  | 查看指定容器内部当前正在运行的进程信息"
    "docker stats                   | 实时动态查看所有运行中容器的 CPU、内存及网络 IO 占用"
    "docker port ID                 | 查看指定容器当前映射在宿主机上的实际物理端口"
    "docker network ls              | 列出当前本地所有的 Docker 虚拟网络集群"
    "docker volume ls               | 列出当前本地所有的 Docker 数据卷存储卷"
    "docker system prune -a         | 清理所有未使用的容器、镜像、网络，释放大量磁盘"
    "docker build -t name:v1 .      | 读取当前目录的 Dockerfile 自动化构建新镜像"
    "docker run -d -p 80:80 image  | 后台运行容器并映射宿主机端口到容器内部"
    "docker run --rm image          | 运行一次性容器，容器退出后会自动销毁清空"
    "docker cp path ID:path         | 在宿主机和指定的容器内部之间双向拷贝文件/目录"
    "docker save -o img.tar image  | 将本地镜像打包导出为一个 tar 归档文件"
    "docker load -i img.tar         | 从 tar 归档文件中恢复并加载镜像到本地仓库"
    "docker commit ID name:v1       | 将当前运行的容器连同内部修改提交保存为新镜像"
    "docker diff ID                 | 查看容器启动后，内部文件系统发生了哪些修改变动"
    "docker history image           | 查看指定镜像的构建历史层级和每一步执行的命令"
    "docker login                   | 登录到远程的 Docker Hub 或自建的私有镜像仓库"
    "docker push image:tag          | 将本地打好标签的镜像推送到远程镜像仓库存储"
    "docker search keyword          | 在 Docker Hub 官方公共市场上搜索公开的镜像源"
    "docker pull image:tag          | 从远程仓库拉取指定版本的镜像到本地"
    "docker logs --since 30m ID     | 精准查看指定容器在最近 30 分钟内产生的日志"
    "docker network inspect name    | 查看指定 Docker 虚拟网络集群的内部 IP 分配详情"
    "docker volume inspect name     | 查看指定数据卷在宿主机上的真实物理存储路径"
    "docker pause ID                | 暂停指定容器内的所有进程"
    "docker unpause ID              | 恢复指定容器内被暂停的所有进程"
    "docker kill ID                 | 向容器发送 SIGKILL 信号，强行立刻终止容器"
    "docker wait ID                 | 阻塞并等待指定容器停止运行，并打印其退出状态码"
    "docker rename old new          | 重命名一个已经存在的容器"
    "docker update --cpus 2 ID      | 动态限制和调整正在运行的容器的 CPU 核心配额"
    "docker compose ps              | 列出当前路径下编排服务中所有关联容器的状态"
    "docker compose logs -f         | 动态追踪当前路径编排服务中所有容器的聚合日志"
    "docker compose restart         | 重启当前路径下整套编排服务的所有容器"
    "docker compose stop            | 仅停止当前路径下的编排容器，不进行删除操作"
    "docker compose rm -f           | 强制删除当前路径下已经停止的编排容器"
    "docker compose exec svc bash  | 进入当前路径编排文件中指定服务的容器内部"
    "docker compose config          | 校验并解析当前路径下的编排文件是否配置正确"
    "docker compose pull            | 批量拉取当前路径编排文件中定义的所有镜像"
    "docker image prune             | 清理本地所有虚悬镜像（即标签为 <none> 的镜像）"
)

show_education_commands() {
    echo -e "\n\033[36m💡 每日高频 Docker 命令速学 (随机抽取 5 条):\033[0m"
    local rand_indices
    rand_indices=$(shuf -i 0-49 -n 5)
    
    for idx in $rand_indices; do
        local line="${GLOBAL_CMDS[$idx]}"
        local cmd_part="${line%%|*}"
        local desc_part="${line##*|}"
        printf "  \033[33m%-30s\033[0m | %s\n" "$cmd_part" "$desc_part"
    done
}

list_all_50_commands() {
    clear
    echo "=== 内置 50 条 Docker 命令大盘点 ==="
    echo "--------------------------------------------------------------------------------"
    local count=1
    for line in "${GLOBAL_CMDS[@]}"; do
        local cmd_part="${line%%|*}"
        local desc_part="${line##*|}"
        printf "[%02d] \033[33m%-30s\033[0m | %s\n" $count "$cmd_part" "$desc_part"
        ((count++))
    done
    echo "--------------------------------------------------------------------------------"
}

manage_install_uninstall() {
    clear
    echo "=== Docker Engine & Compose 安装/卸载 ==="
    echo "  1 安装/卸载 Docker 环境"
    echo "  2 彻底卸载并清理残留"
    echo "  0 返回上级"
    echo "----------------------------------------"
    read -r -p "请输入您的选择: " ins_opt
    case $ins_opt in
        1)
            echo "正在同步系统源并安装基础证书依赖..."
            apt-get update -y && apt-get install -y ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            echo "正在安装 Docker 核心组件..."
            apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            systemctl enable --now docker
            echo -e "\033[32m🎉 安装并配置成功！\033[0m"
            ;;
        2)
            read -r -p "⚠️ 警告：确定清除一切吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop docker || true
                apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                rm -rf /var/lib/docker /etc/apt/sources.list.d/docker.list
                echo -e "\033[32m卸载完成。\033[0m"
            else
                echo "操作已安全取消。"
            fi
            ;;
    esac
}

handle_compose_file_mode() {
    if [ "$(check_compose_file)" = "false" ]; then
        echo -e "\033[31m❌ 错误: 当前目录下找不到 docker-compose.yaml 或 docker-compose.yml 文件！\033[0m"
        exit 1
    fi

    local yaml_file="docker-compose.yaml"
    [ ! -f "$yaml_file" ] && yaml_file="docker-compose.yml"

    mapfile -t containers < <(docker compose config --services 2>/dev/null)
    if [ ${#containers[@]} -eq 0 ]; then
        echo -e "\033[31m❌ 错误: 无法从配置文件中解析出有效的服务容器目标。\033[0m"
        exit 1
    fi

    echo "=== 请选择需要操作的容器服务 ==="
    for i in "${!containers[@]}"; do 
        echo "  $((i+1))) ${containers[$i]}"
    done
    echo "  0) 取消并退出"
    echo "----------------------------------------"
    read -r -p "选择目标序号: " idx
    if [ "$idx" == "0" ] || [ -z "$idx" ]; then exit 0; fi

    chosen="${containers[$((idx-1))]}"
    if [ -z "$chosen" ]; then echo "非有效序号！"; exit 1; fi

    clear
    echo "=== 目标容器: $chosen ==="
    echo "  1 重启服务 (Restart)"
    echo "  2 删除容器 (Stop & Remove)"
    echo "  3 查看日志 (Logs)"
    echo "  4 进入内部 (Exec bash/sh)"
    echo "  5 销毁容器及本地挂载目录 (⚠️高危)"
    echo "  0 退出"
    echo "----------------------------------------"
    read -r -p "执行操作: " act
    case $act in
        1) docker compose restart "$chosen" ;;
        2) docker compose stop "$chosen" && docker compose rm -f "$chosen" ;;
        3) 
            read -r -p "是否查看静态300行日志? (回车默认Y/静态, 输入 n 查看动态追踪): " l
            l=${l:-Y}
            if [[ "$l" =~ [Yy] ]]; then
                docker compose logs --tail=300 "$chosen"
            else
                docker compose logs -f --tail=300 "$chosen"
            fi
            ;;
        4) docker compose exec "$chosen" bash || docker compose exec "$chosen" sh ;;
        5)
            volumes=$(docker inspect $(docker compose ps -q "$chosen") --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{end}}{{end}}' 2>/dev/null)
            echo -e "\033[31m即将清空的本地宿主机路径:\033[0m $volumes"
            read -r -p "🔥 确认彻底销毁该容器并物理删除本地挂载目录吗? [y/N] (回车默认N): " confirm
            confirm=${confirm:-N}
            if [[ "$confirm" =~ [Yy] ]]; then
                docker compose stop "$chosen" && docker compose rm -f "$chosen"
                if [ -n "$volumes" ]; then
                    for vol in $volumes; do
                        [ -d "$vol" ] || [ -f "$vol" ] && rm -rf "$vol"
                    done
                fi
                echo -e "\033[32m物理删除完成。\033[0m"
            else
                echo "操作取消。"
            fi
            ;;
    esac
}

SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/main/docker-install-dp.sh"
LOCAL_DP_PATH="/usr/local/bin/dp"

# 在线热更新本脚本：覆盖全局 dp，并立刻用新版本重启当前会话
update_self_script() {
    clear
    echo -e "\033[1;34m🔄 在线更新 Docker 管理脚本\033[0m"
    echo "--------------------------------------------------------------------------------"
    echo -e "\033[36m正在从 GitHub 拉取最新 docker-install-dp.sh ...\033[0m"

    local tmp_update="/tmp/docker-install-dp.update.$$"
    if ! curl -fsSL -m 20 "${SCRIPT_REMOTE_URL}?v=$(date +%s)" -o "$tmp_update"; then
        echo -e "\033[31m❌ 下载失败：无法连接 GitHub 或网络超时。\033[0m"
        rm -f "$tmp_update"
        return 1
    fi

    if [ ! -s "$tmp_update" ] || grep -q "404: Not Found" "$tmp_update"; then
        echo -e "\033[31m❌ 更新失败：远端文件为空或不存在。\033[0m"
        rm -f "$tmp_update"
        return 1
    fi

    # 只要是 bash 脚本就覆盖；兼容 root / 有 sudo 的环境
    if [ -w "$(dirname "$LOCAL_DP_PATH")" ] 2>/dev/null; then
        cp "$tmp_update" "$LOCAL_DP_PATH"
        chmod +x "$LOCAL_DP_PATH"
    else
        sudo cp "$tmp_update" "$LOCAL_DP_PATH"
        sudo chmod +x "$LOCAL_DP_PATH"
    fi
    rm -f "$tmp_update"

    # 清掉百宝箱远端工具表缓存，避免旧菜单残留
    rm -f /tmp/remote_docker_tools.yml

    echo -e "\033[32m🎉 更新成功！已覆盖 ${LOCAL_DP_PATH}，正在重新拉起新版本...\033[0m"
    sleep 1
    hash -r 2>/dev/null
    exec bash "$LOCAL_DP_PATH"
}

if [ "$1" == "-f" ]; then
    handle_compose_file_mode
    exit 0
fi

# 主交互循环
while true; do
    clear
    echo -e "🐳 \033[1;34mDocker 综合管理面板\033[0m"
    echo -e "Docker 状态: $(get_docker_status)\tCompose 状态: $(get_compose_status)"
    echo "--------------------------------------------------------------------------------"
    echo " 1 安装/卸载 Docker环境"
    echo " 2 当前路径 Compose 列表"
    echo " 3 全局所有容器盘点"
    echo " 4 全局虚拟网络集群列表"
    echo " 5 Docker 安全百宝箱"
    echo " 6 注册为全局 dp 快捷键"
    echo " 7 在线更新本脚本 (同步 GitHub 最新版)"
    echo " 9 列出50条内置命令"
    echo " 0 安全退出控制台"
    echo "--------------------------------------------------------------------------------"

    show_education_commands

    echo "--------------------------------------------------------------------------------"
    read -r -p "请选择操作 [0-7, 9]: " m
    case $m in
        1) manage_install_uninstall ;;
        2)
            if [ "$(check_compose_file)" = "false" ]; then
                echo -e "\n\033[31m⚠️ 提示: 当前目录下未检测到任何 docker-compose.yaml/yml 配置文件！\033[0m"
            else
                echo -e "\n--- 当前路径容器状态 ---"
                docker compose ps
            fi
            ;;
        3)
            echo -e "\n--- 全局容器盘点 ---"
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;
        4)
            echo -e "\n--- 全局虚拟网络集群 ---"
            docker network ls
            ;;
        5)
            echo -e "\n\033[36m🔄 正在拉取并执行 Docker 安全百宝箱...\033[0m"
            bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-tool-install.sh?v=$(date +%s)")
            ;;
        6)
            echo "正在通过您的远程链接下载并注册全局快捷键 'dp'..."
            curl -fsSL "${SCRIPT_REMOTE_URL}?v=$(date +%s)" -o "$LOCAL_DP_PATH"
            chmod +x "$LOCAL_DP_PATH"
            echo -e "\n\033[32m🎉 注册并同步成功！以后可在任何路径直接输入 'dp' 或 'dp -f' 运行。\033[0m"
            ;;
        7)
            update_self_script
            ;;
        9)
            list_all_50_commands
            ;;
        0)
            echo "正常退出。"
            exit 0
            ;;
        *)
            echo -e "\033[31m选择无效，请重新选择。\033[0m"
            sleep 0.5
            continue
            ;;
    esac
    echo ""
    read -r -p "回车继续返回主菜单..." tmp
done

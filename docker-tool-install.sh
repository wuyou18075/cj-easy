#!/bin/bash

# ==========================================
# 脚本名称: docker-tool-install.sh
# 功能描述: Docker 综合工具箱与跨节点迁移控制中心
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
# 全局目录规则定义区
# ==========================================
DOCKER_ROOT="/app/docker"
YAML_FILE="${DOCKER_ROOT}/docker-compose.yml"
YAML_BAK_DIR="${DOCKER_ROOT}/yaml-bak"
REMOTE_KOMARI="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-Komari.sh"

# 初始化环境依赖
mkdir -p "$DOCKER_ROOT"
mkdir -p "$YAML_BAK_DIR"

# ==========================================
# 核心功能模块: YAML 规则与冲突管控
# ==========================================

# 规则 1: 配置文件自动备份并仅保留最近 10 份
backup_compose_yaml() {
    if [ -f "$YAML_FILE" ]; then
        local BAK_NAME="${YAML_BAK_DIR}/docker-compose-bak-$(date +%Y%m%d%H%M%S).yml"
        cp "$YAML_FILE" "$BAK_NAME"
        # 强制清理：只保留最新的 10 个备份
        ls -t "$YAML_BAK_DIR"/docker-compose-bak-*.yml 2>/dev/null | tail -n +11 | xargs -I {} rm -f "{}"
        echo -e "${C_CYAN}📦 当前配置已自动备份至: ${BAK_NAME}${C_RESET}"
    fi
}

# 规则 2: 处理远程模块拉取与冲突校验
install_remote_module() {
    clear
    echo -e "${C_BLUE}⚡ 从远程模块安装新服务${C_RESET}"
    echo -e "${LINE_GRAY}"
    read -p "🔗 请输入远程 docker-compose.yml 的直链 URL: " REMOTE_URL
    if [ -z "$REMOTE_URL" ]; then echo -e "${C_RED}❌ URL不能为空${C_RESET}"; sleep 1; return; fi

    local TEMP_YAML="/tmp/docker-compose-remote-temp.yml"
    echo -e "🔄 正在拉取远程配置..."
    curl -sSL "$REMOTE_URL" -o "$TEMP_YAML"
    
    if [ ! -s "$TEMP_YAML" ]; then
        echo -e "${C_RED}❌ 拉取失败，请检查网络或链接。${C_RESET}"; sleep 1.5; return
    fi

    # 如果本地没有任何配置，直接采用
    if [ ! -f "$YAML_FILE" ]; then
        mv "$TEMP_YAML" "$YAML_FILE"
        echo -e "${C_GREEN}✅ 首次部署，已直接写入用户本地配置。${C_RESET}"
        sleep 1.5; return
    fi

    # 存在本地配置，启动冲突检测
    echo -e "🔎 正在与本地配置进行冲突比对..."
    if cmp -s "$TEMP_YAML" "$YAML_FILE"; then
        echo -e "${C_GREEN}✅ 远程配置与本地完全一致，无需合并。${C_RESET}"
        rm -f "$TEMP_YAML"
        sleep 1.5; return
    fi

    # 发生不一致，进入冲突裁决
    clear
    echo -e "${C_YELLOW}⚠️ 警告：检测到本地配置与远程模块存在冲突！${C_RESET}"
    echo -e "${LINE_GRAY}"
    diff -u --color=always "$YAML_FILE" "$TEMP_YAML" | head -n 30
    echo -e "${LINE_GRAY}"
    echo -e "1) 手动解决 (进入编辑器对照合并冲突)"
    echo -e "2) 直接丢弃本地配置 (完全覆盖为远程最新配置)"
    echo -e "0) 取消安装 (退出)"
    echo -e "${LINE_GRAY}"
    read -p "请选择冲突处理方案 [0-2]: " CONFLICT_OPT

    backup_compose_yaml

    if [ "$CONFLICT_OPT" == "1" ]; then
        # 借助 vimdiff 或 nano 手动合并
        echo -e "打开本地配置，请参考刚才的差异日志进行手动添加..."
        sleep 1.5
        nano "$YAML_FILE"
        echo -e "${C_GREEN}✅ 手动合并结束。${C_RESET}"
        rm -f "$TEMP_YAML"
    elif [ "$CONFLICT_OPT" == "2" ]; then
        mv "$TEMP_YAML" "$YAML_FILE"
        echo -e "${C_GREEN}✅ 已直接丢弃旧版本，采用最新远程模块覆盖！${C_RESET}"
    else
        echo -e "操作取消。"
        rm -f "$TEMP_YAML"
    fi
    read -p "回车继续..." temp
}

# ==========================================
# 核心功能模块: 跨节点迁移系统 (打包与装载)
# ==========================================

# 规则 5: 打包当前镜像与挂载数据
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

# 规则 6: 迁移文件还原与挂载建立
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
    echo -e "请使用功能列表中的【模块化安装新服务】拉取或手动编辑 ${YAML_FILE}"
    echo -e "确保已编排此服务的启动参数，随后执行 ${C_YELLOW}docker compose up -d${C_RESET} 即可无缝拉起。 "
    read -p "回车继续..." temp
}


# ==========================================
# 专属业务模块: Komari 探针管理
# ==========================================
menu_komari() {
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
        read -p "选择探针控制令: " K_OPT

        case $K_OPT in
            1)
                clear
                echo -e "${C_BLUE}⚡ 开始初始化 Komari...${C_RESET}"
                if ! command -v curl &> /dev/null; then
                    if command -v apt-get &> /dev/null; then sudo apt-get update -y && sudo apt-get install -y curl; fi
                fi
                bash <(curl -fsSL "${REMOTE_KOMARI}?v=$(date +%s)")
                read -p "按回车键继续..." temp
                ;;
            2)
                clear
                echo -e "${C_CYAN}🔄 正在执行热拉取与平滑重启...${C_RESET}"
                # 此处适配了新的 DOCKER_ROOT 规范
                if [ -d "${DOCKER_ROOT}" ] && [ -f "${YAML_FILE}" ]; then
                    cd "${DOCKER_ROOT}" || exit
                    docker compose pull komari 2>/dev/null || docker compose pull
                    docker compose up -d
                    echo -e "${C_GREEN}✅ 镜像更新并重启完成！${C_RESET}"
                else
                    echo -e "${C_YELLOW}⚠️ 未找到全局 compose 配置文件。${C_RESET}"
                fi
                read -p "按回车键继续..." temp
                ;;
            3)
                clear
                read -p "⚠️ 确认要阻断并彻底清除 Komari 服务吗？[y/N]: " IS_DEL
                if [[ "$IS_DEL" =~ ^[Yy]$ ]]; then
                    docker stop komari 2>/dev/null
                    docker rm -f komari 2>/dev/null
                    echo -e "${C_GREEN}✅ 容器已强力阻断！清理 Compose 配置请移步主菜单的 YAML 配置器。${C_RESET}"
                fi
                read -p "按回车键继续..." temp
                ;;
            4)
                # 复用原有的打包逻辑至新的体系内
                echo -e "${C_CYAN}💡 推荐使用主菜单的【选项 5: 跨节点迁移打包】功能实现完整闭环备份。${C_RESET}"
                read -p "回车继续..." temp
                ;;
            0) break ;;
            *) echo -e "${C_GRAY}❌ 无效选项。${C_RESET}"; sleep 1 ;;
        esac
    done
}


# ==========================================
# 交互主入口: Docker 安全百宝箱
# ==========================================
while true; do
    clear
    echo -e "${C_BLUE}⚡ Docker 安全百宝箱 / 综合工具集${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "1) Komari 探针控制中心"
    echo -e "2) 模块化安装新服务 (YAML 远程拉取/冲突处理)"
    echo -e "3) 功能占位 (待挂载)"
    echo -e "5) 跨节点迁移：打包导出容器与挂载数据"
    echo -e "6) 跨节点迁移：物理读取装载迁移文件"
    echo -e "0) 返回主环境"
    echo -e "${LINE_GRAY}"
    read -p "请注入工具子项编号 [0-6]: " MAIN_OPT

    case $MAIN_OPT in
        1) menu_komari ;;
        2) install_remote_module ;;
        3) echo -e "🚧 对应插槽功能正在开发中..."; sleep 1.5 ;;
        5) pack_migration_data ;;
        6) load_migration_data ;;
        0) echo -e "👋 安全退出百宝箱。"; exit 0 ;;
        *) echo -e "${C_GRAY}❌ 无效的子项编号。${C_RESET}"; sleep 1 ;;
    esac
done

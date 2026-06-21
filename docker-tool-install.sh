#!/bin/bash

# ==========================================
# 脚本名称: docker-tool-install.sh
# 功能描述: Docker 综合工具箱与 Komari 探针面板
# ==========================================

# 全局颜色常量定义
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"

LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

# 动态远程脚本变量
REMOTE_KOMARI="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-Komari.sh"

# 定义 Komari 的本地默认部署路径与备份路径 (可根据实际情况修改)
KOMARI_DIR="/opt/komari"
BACKUP_DIR="/opt/komari_backup"

# Komari 二级管理菜单
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
                echo -e "${C_BLUE}⚡ 开始初始化 Komari 服务可用性探针部署流程...${C_RESET}"
                echo -e "${LINE_GRAY}"

                # 依赖项基础检查：确保 curl 命令存在
                if ! command -v curl &> /dev/null; then
                    echo -e "${C_YELLOW}未检测到 curl 依赖，正在尝试自动补全...${C_RESET}"
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get update -y && sudo apt-get install -y curl
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y curl
                    else
                        echo -e "${C_GRAY}❌ 自动安装 curl 失败，请排查包管理器状态。${C_RESET}"
                        read -p "按回车键继续..." temp
                        continue
                    fi
                fi

                # 拉取并执行核心逻辑，附加时间戳防缓存
                echo -e "${C_CYAN}🔄 正在连接并执行远程探针脚手架...${C_RESET}"
                bash <(curl -fsSL "${REMOTE_KOMARI}?v=$(date +%s)")

                # 执行结果校验
                EXIT_CODE=$?
                if [ $EXIT_CODE -eq 0 ]; then
                    echo -e "${LINE_GRAY}"
                    echo -e "${C_GREEN}🎉 docker-tool-install.sh (Komari探针) 部署脚本执行顺利结束！${C_RESET}"
                else
                    echo -e "${LINE_GRAY}"
                    echo -e "${C_GRAY}❌ 脚本执行发生异常，退出码: ${EXIT_CODE}。请检查网络或远程源状态。${C_RESET}"
                fi
                read -p "按回车键继续..." temp
                ;;
            2)
                clear
                echo -e "${C_CYAN}🔄 正在执行热拉取与平滑重启...${C_RESET}"
                if [ -d "$KOMARI_DIR" ] && [ -f "$KOMARI_DIR/docker-compose.yml" ]; then
                    cd "$KOMARI_DIR" || exit
                    docker compose pull
                    docker compose up -d
                    echo -e "${C_GREEN}✅ 镜像更新并重启完成！${C_RESET}"
                else
                    echo -e "${C_YELLOW}⚠️ 未在 $KOMARI_DIR 找到 docker-compose 配置文件。${C_RESET}"
                    echo -e "如果您使用的是纯 docker run 运行，请尝试手动拉取镜像并重启容器。"
                fi
                read -p "按回车键继续..." temp
                ;;
            3)
                clear
                read -p "⚠️ 危险操作：确认要阻断并彻底清除 Komari 服务及所有数据吗？[y/N]: " IS_DEL
                if [[ "$IS_DEL" =~ ^[Yy]$ ]]; then
                    echo -e "${C_YELLOW}🚨 正在强力阻断并清理资源...${C_RESET}"
                    if [ -d "$KOMARI_DIR" ] && [ -f "$KOMARI_DIR/docker-compose.yml" ]; then
                        cd "$KOMARI_DIR" || exit
                        docker compose down -v
                        cd /
                        sudo rm -rf "$KOMARI_DIR"
                    else
                        # 兼容非 Compose 的强杀模式
                        docker stop komari 2>/dev/null
                        docker rm -f komari 2>/dev/null
                        sudo rm -rf "$KOMARI_DIR"
                    fi
                    echo -e "${C_GREEN}✅ 服务与持久化目录已彻底物理销毁！${C_RESET}"
                else
                    echo -e "${C_GRAY}操作已安全取消。${C_RESET}"
                fi
                read -p "按回车键继续..." temp
                ;;
            4)
                clear
                echo -e "${C_CYAN}📦 正在执行资产独立安全归类...${C_RESET}"
                sudo mkdir -p "$BACKUP_DIR"
                BACKUP_FILE="${BACKUP_DIR}/komari_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
                
                if [ -d "$KOMARI_DIR" ]; then
                    # 仅打包该目录的归属文件
                    sudo tar -czf "$BACKUP_FILE" -C "$(dirname "$KOMARI_DIR")" "$(basename "$KOMARI_DIR")"
                    echo -e "${C_GREEN}✅ 资产冷备份成功！${C_RESET}"
                    echo -e "📁 备份文件已落盘至: ${C_YELLOW}${BACKUP_FILE}${C_RESET}"
                else
                    echo -e "${C_YELLOW}⚠️ 寻址失败：未找到源目录 $KOMARI_DIR ，无法进行打包动作。${C_RESET}"
                fi
                read -p "按回车键继续..." temp
                ;;
            0)
                break
                ;;
            *)
                echo -e "${C_GRAY}❌ 无效的控制令，请重新输入。${C_RESET}"
                sleep 1
                ;;
        esac
    done
}

# 全局工具箱主菜单
while true; do
    clear
    echo -e "${C_BLUE}⚡ Docker 安全百宝箱 / 综合工具集${C_RESET}"
    echo -e "${LINE_GRAY}"
    echo -e "1) Komari 探针控制中心"
    echo -e "2) 功能占位 (待挂载)"
    echo -e "3) 功能占位 (待挂载)"
    echo -e "0) 返回主环境"
    echo -e "${LINE_GRAY}"
    read -p "请注入工具子项编号 [0-3]: " MAIN_OPT

    case $MAIN_OPT in
        1)
            menu_komari
            ;;
        2)
            echo -e "🚧 对应插槽功能正在开发中..."; sleep 1.5
            ;;
        3)
            echo -e "🚧 对应插槽功能正在开发中..."; sleep 1.5
            ;;
        0)
            echo -e "👋 安全退出百宝箱。"
            exit 0
            ;;
        *)
            echo -e "${C_GRAY}❌ 无效的子项编号。${C_RESET}"
            sleep 1
            ;;
    esac
done

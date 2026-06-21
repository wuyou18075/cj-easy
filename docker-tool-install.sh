#!/bin/bash

# ==========================================
# 脚本名称: docker-tool-install.sh
# 功能描述: 独立调用 Komari 服务可用性探针
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
        exit 1
    fi
fi

# 拉取并执行核心逻辑，附加时间戳防缓存
echo -e "${C_CYAN}🔄 正在连接并执行远程探针脚手架...${C_RESET}"
bash <(curl -fsSL "${REMOTE_KOMARI}?v=$(date +%s)")

# 执行结果校验
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${LINE_GRAY}"
    echo -e "${C_GREEN}🎉 docker-tool-install.sh (Komari探针) 执行顺利结束！${C_RESET}"
else
    echo -e "${LINE_GRAY}"
    echo -e "${C_GRAY}❌ 脚本执行发生异常，退出码: ${EXIT_CODE}。请检查网络或远程源状态。${C_RESET}"
    exit $EXIT_CODE
fi

exit 0

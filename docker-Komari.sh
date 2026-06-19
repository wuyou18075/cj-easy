#!/bin/bash

C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GRAY="\e[90m"
C_RESET="\e[0m"
LINE_GRAY="${C_GRAY}---------------------------------------------------------${C_RESET}"

KOMARI_DIR="/cj/dockercompose"
KOMARI_YML_URL="https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-compose-tools.yml"

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
        docker compose -f "$KOMARI_DIR/docker-compose-tools.yml" up -d
        echo -e "${C_GREEN}🎉 安装部署全部完成！${C_RESET}"; sleep 1.5

    elif [ "$KO_OPT" == "2" ]; then
        if [ "$(docker ps -a --filter "name=komari" --format "{{.Names}}")" ]; then
            echo "⏳ 正在通过容器名 komari 热追踪拉取最新镜像流..."
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

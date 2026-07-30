# ⚡ cj-easy 全能系统运维与网络优化矩阵

这是一套专为 Linux 服务器（特别是 ARM/甲骨文云架构）打造的高性能自动化运维管理脚本。

---

## 🚀 核心一键执行命令

请根据需要复制下方对应的命令，在服务器终端（**Root 权限**）直接粘贴执行：

### 1️⃣ cj 全能系统管理与证书脚本（主程序）

> 包含系统状态盘查、原生 Nginx 自动化安装、多分组反向代理管理（支持底层四层 TCP 盲测健康监测）、acme.sh 证书申请与定时自动续签维护。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$(date +%s)")
```

安装后也可使用本机快捷命令（若已写入）：

```bash
cj
```

### 2️⃣ TCP 内核与网卡级深度优化调优

> 包含全球 Anycast 边缘分发节点双向测速推演、BDP 满血硬件级套接字缓冲（rmem/wmem）压榨、新旧配置并行交叉审计、多选/全选智控注入、网卡层 MTU 黄金标准（1500）降轨纠偏以及 Fq vs Cake 真实网络双雄竞技场实测。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/tcp.sh?v=$(date +%s)")
```

### 3️⃣ Docker 容器自动化管理引擎（dp）

> 提供无伤拔除旧残留、一键快速部署、容器依赖加固与生命周期智控管理；并进入「安全百宝箱」动态安装云端应用。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-install-dp.sh?v=$(date +%s)")
```

安装后也可使用本机快捷命令（若已写入）：

```bash
dp
```

### 4️⃣ VPS Telegram Bot 安装

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/vps-tg-bot-install.sh?v=$(date +%s)")
```

---

## 主程序（install.sh / cj）功能范围

入口脚本：[`install.sh`](install.sh)

主程序负责：

- 系统状态相关入口
- 原生 Nginx 安装与多分组反向代理
- 四层 TCP 健康探测相关能力
- acme.sh 证书申请与续签
- 通过远程子脚本进入：系统工具、防火墙、TCP 调优、Docker 面板

主菜单会远程拉取并执行：

| 菜单能力 | 远程脚本 |
|----------|----------|
| 系统工具 | [`system-tool.sh`](system-tool.sh) |
| 防火墙 | [`firewall-tool.sh`](firewall-tool.sh) |
| TCP 调优 | [`tcp.sh`](tcp.sh) |
| Docker 面板 `dp` | [`docker-install-dp.sh`](docker-install-dp.sh) |

Docker **安全百宝箱**（动态应用矩阵）不在 `install.sh` 内写死应用列表，而是由 `docker-install-dp.sh` 再调用 [`docker-tool-install.sh`](docker-tool-install.sh)，并从 [`docker-compose-tools.yml`](docker-compose-tools.yml) 拉取模板。

### 使用建议

1. 用 root 执行
2. 日常运维：跑 `install.sh` / `cj`
3. 只管 Docker：直接跑 `docker-install-dp.sh` 或本机 `dp`
4. 只装某个容器应用：进 Docker 面板 → 安全百宝箱 → 选应用 → 安装

---

## 更多文档

| 文档 | 说明 |
|------|------|
| [Docker工具dp使用说明.md](Docker工具dp使用说明.md) | `dp` 面板与百宝箱操作 |
| [百宝箱配置解析.md](百宝箱配置解析.md) | `#START` / `#NAME` / `#PARAM_*` 模板语法（新增应用必读） |
| [项目文件功能说明.md](项目文件功能说明.md) | 各文件职责与清理记录 |

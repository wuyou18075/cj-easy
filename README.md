# cj-easy

Linux 服务器运维脚本集：系统管理、TCP 调优、Docker 百宝箱。需 **root** 执行。

---

## 一键命令

### 1. 主程序 `cj`

系统状态、Nginx 反向代理、证书（acme.sh）；菜单可进入系统工具 / 防火墙 / TCP / Docker。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$(date +%s)")
```

装好后本机可直接：`cj`

### 2. TCP 调优

内核与网卡参数调优（也可从 `cj` 菜单进入）。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/tcp.sh?v=$(date +%s)")
```

### 3. Docker 面板 `dp`

Docker 安装与容器管理；进入「安全百宝箱」按云端模板安装应用。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-install-dp.sh?v=$(date +%s)")
```

装好后本机可直接：`dp`

---

## 主程序能力

入口：[`install.sh`](install.sh)

| 能力 | 说明 |
|------|------|
| Nginx / 反向代理 | 多分组代理，四层 TCP 健康探测 |
| 证书 | acme.sh 申请与续签 |
| 子菜单 | 远程执行下表脚本 |

| 菜单 | 脚本 |
|------|------|
| 系统工具 | [`system-tool.sh`](system-tool.sh) |
| 防火墙 | [`firewall-tool.sh`](firewall-tool.sh) |
| TCP 调优 | [`tcp.sh`](tcp.sh) |
| Docker `dp` | [`docker-install-dp.sh`](docker-install-dp.sh) |

百宝箱不写死应用列表：`dp` → [`docker-tool-install.sh`](docker-tool-install.sh) → 拉取 [`docker-compose-tools.yml`](docker-compose-tools.yml)。

**建议：** 日常用 `cj`；只管 Docker 用 `dp`；装某个容器进百宝箱选应用安装。

---

## 仓库文件

| 文件 | 作用 |
|------|------|
| [`install.sh`](install.sh) | 主程序 `cj` |
| [`system-tool.sh`](system-tool.sh) | 系统工具（`cj` 远程调用） |
| [`firewall-tool.sh`](firewall-tool.sh) | 防火墙（`cj` 远程调用） |
| [`tcp.sh`](tcp.sh) | TCP 调优（`cj` 调用或独立一键） |
| [`docker-install-dp.sh`](docker-install-dp.sh) | Docker 面板 `dp` |
| [`docker-tool-install.sh`](docker-tool-install.sh) | 安全百宝箱：拉模板、装/卸/迁移 |
| [`docker-compose-tools.yml`](docker-compose-tools.yml) | 百宝箱应用模板（`#START` / `#NAME` / `#PARAM_*` / `#END`） |
| [`LICENSE`](LICENSE) | 许可证 |

### 服务器上的路径（不在仓库）

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/cj` | 主程序本地副本 |
| `/usr/local/bin/dp` | Docker 面板本地副本 |
| `/app/docker/docker-compose.yml` | 百宝箱生成的本机 compose |
| `/app/docker/*` | 各应用数据与备份 |
| `/tmp/remote_docker_tools.yml*` | 模板缓存 |

---

## 更多文档

| 文档 | 说明 |
|------|------|
| [Docker工具dp使用说明.md](Docker工具dp使用说明.md) | `dp` 与百宝箱操作 |
| [百宝箱配置解析.md](百宝箱配置解析.md) | 模板标签语法（新增应用必读） |

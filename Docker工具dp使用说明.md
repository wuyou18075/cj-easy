# Docker 工具 dp 使用说明

核心脚本：

| 脚本 | 作用 |
|------|------|
| [`docker-install-dp.sh`](docker-install-dp.sh) | Docker 主面板（快捷命令常注册为 `dp`） |
| [`docker-tool-install.sh`](docker-tool-install.sh) | 安全百宝箱 / 动态应用矩阵 |
| [`docker-compose-tools.yml`](docker-compose-tools.yml) | 云端应用模板（`#START`…`#END`） |

一键启动面板：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/docker-install-dp.sh?v=$(date +%s)")
```

若已安装快捷命令：

```bash
dp
```

---

## 面板能力概览

`docker-install-dp.sh` 提供：

- Docker / Compose 安装与状态检测
- 高频 Docker 命令速查库
- 容器清单、日志、进入容器、启停删等操作
- 默认路径 Compose 管理（与 `/app/docker` 对齐）
- 入口进入「安全百宝箱」（远程执行 `docker-tool-install.sh`）
- 自更新 `dp` 脚本

百宝箱固定工作目录：

- 根目录：`/app/docker`
- 本机 compose：`/app/docker/docker-compose.yml`
- 各应用数据：`/app/docker/<服务相对路径>`

---

## 安全百宝箱操作

进入后会：

1. 拉取远端 `docker-compose-tools.yml`
2. 按所有 `#NAME:` 生成编号菜单
3. 选中应用后可：安装 / 更新 / 启停 / 卸载 / 抹除 / 查看初始化信息

常用编号：

- `1…N`：各云端应用
- `98`：强制刷新云端列表（清缓存重拉）
- `99`：跨节点导出
- `100`：跨节点导入
- `0`：返回

安装交互规则：

- `#PARAM_KEY:描述=默认` → 回车用默认，输入则覆盖
- `#PARAM_KEY:描述`（无 `=`）→ 必填密钥类，不能为空
- 模板中 `{PARAM_KEY}` 会被替换为最终值

模板语法详见 [百宝箱配置解析.md](百宝箱配置解析.md)。

---

## 安装后常见路径

以 CPA + CPAMP 为例：

- 面板：`http://<主机>:18317/management.html`
- 初始化备忘：`/app/docker/cpa-manager-plus/INIT_INFO.txt`
- 密钥备忘：`/app/docker/cpa-manager-plus/INSTALL_SECRETS.txt`
- 日志：`docker logs cpa-manager-plus` / `docker logs cli-proxy-api`

其它应用同理：端口以安装时填写的 `#PARAM_*` 为准，数据在 `/app/docker` 下对应目录。

---

## 注意

- 改仓库里的 `docker-compose-tools.yml` 后必须 push，服务器再 `98` 刷新
- New API 依赖可用的 Postgres / Redis，并需先建库（安装向导会提示）
- 多服务栈（如 CPA+CPAMP）会按依赖顺序启动

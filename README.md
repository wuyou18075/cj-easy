# ⚡ cj-easy 全能系统运维与网络优化矩阵

这是一套专为 Linux 服务器（特别是 ARM/甲骨文云架构）打造的高性能自动化运维管理脚本。

---

## 🚀 核心一键执行命令

请根据需要复制下方对应的命令，在服务器终端（Root 权限）直接粘贴执行：

### 1️⃣ cj 全能系统管理与证书脚本
> 包含系统状态盘查、原生 Nginx 自动化安装、多分组反向代理管理（支持底层四层 TCP 盲测健康监测）、acme.sh 证书申请与定时自动续签维护。

```bash
bash <(curl -fsSL "[https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$](https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$)(date +%s)")

# ⚡ cj-easy 全能系统运维与网络优化矩阵

这是一套专为 Linux 服务器（特别是 ARM/甲骨文云架构）打造的高性能自动化运维管理脚本。

---

## 🚀 核心一键执行命令

请根据需要复制下方对应的命令，在服务器终端（Root 权限）直接粘贴执行：

### 1️⃣ cj 全能系统管理与证书脚本
> 包含系统状态盘查、原生 Nginx 自动化安装、多分组反向代理管理（支持底层四层 TCP 盲测健康监测）、acme.sh 证书申请与定时自动续签维护。

```bash
bash <(curl -fsSL "[https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$](https://raw.githubusercontent.com/wuyou18075/cj-easy/main/install.sh?v=$)(date +%s)")

### 2️⃣ TCP 内核与网卡级深度优化调优
>包含全球 Anycast 边缘分发节点双向测速推演、BDP 满血硬件级套接字缓冲（rmem/wmem）压榨、新旧配置并行交叉审计、多选/全选智控注入、网卡层 MTU 黄金标准（1500）降轨纠偏以及 Fq vs Cake 真实网络双雄竞技场实测。

```bash
bash <(curl -fsSL "[https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/tcp.sh?v=$](https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/tcp.sh?v=$)(date +%s)")

###3️⃣ Docker 容器自动化管理引擎
>提供无伤拔除旧残留、一键快速部署、容器依赖加固与生命周期智控管理。

```bash
bash <(curl -fsSL "[https://raw.githubusercontent.com/wuyou18075/cj-easy/refs/heads/main/

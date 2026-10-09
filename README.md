> 这是 kejilion 脚本的个人净化版，不是科技Lion原作者的官方发布。
> 相比原版，本版删除了：偷偷把使用记录和 IP 归属地上传给原作者服务器的“报信”功能、VPS 返利广告与站点引流、自带每小时更新的闭源管理面板、会整体覆盖本地文件的“检查更新”功能；下载改为直连原始站点。
> 除上述删减外，其余功能与原版一致，署名与授权以仓库许可文件为准。

<p align="center">
  <img src="https://kejilion.sh/kejilionsh_logo.webp?v=2" alt="KEJILION.SH 科技lion一键脚本工具" width="620">
</p>

<h1 align="center">KEJILION.SH · 科技lion一键脚本工具</h1>

<p align="center">
  面向 Linux 服务器的综合脚本工具箱，集成系统管理、网络测试、Docker、LDNMP 建站、
  备份迁移与安全防护。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg?style=flat-square" alt="Apache-2.0 License"></a>
</p>

<p align="center">
  <a href="#介绍">介绍</a> ·
  <a href="#一键安装">一键安装</a> ·
  <a href="#支持系统">支持系统</a> ·
  <a href="#效果图预览">效果图预览</a> ·
  <a href="#核心功能">核心功能</a> ·
  <a href="#后续事项">后续事项</a> ·
  <a href="#开源许可">开源许可</a>
</p>

## 介绍

科技Lion 的 Shell 脚本工具是一款全能脚本工具箱，专为 Linux 监控、测试和管理而设计。
无论您是初学者还是经验丰富的用户，该工具都能提供便捷的解决方案。脚本集成 Docker
管理、LDNMP 建站、网站优化与防御、备份还原迁移，以及各类系统工具和应用的安装管理，
让服务器维护更加简单。

KejiLion's Shell script is an all-in-one toolbox designed for Linux monitoring, testing, and
server management. It brings together Docker management, LDNMP website deployment, optimization,
protection, backup, restoration, migration, and common server applications in one interactive tool.

## 一键安装

使用 `root` 用户执行以下命令。

```bash
KJ_RAW_URL="https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh"
bash <(curl -sL "$KJ_RAW_URL")
```

这条命令装的是**个人净化版**（脚本从本仓库的 GitHub 直链拉取）；别改成从原作者域名 `kejilion.sh` 拉，那样装回来的是没净化的原版。

首次运行后可按脚本提示设置 `k` 快捷命令，后续直接输入 `k` 即可打开主菜单。

> [!IMPORTANT]
> 脚本包含软件安装、网络、防火墙、磁盘和网站环境等系统级操作。
> 请在执行前阅读终端提示，并提前备份重要网站、数据库、容器和配置。

## 支持系统

<p>
  <img src="https://img.shields.io/badge/Ubuntu-FFB6C1?style=for-the-badge&logo=ubuntu&logoColor=black" alt="Ubuntu">
  <img src="https://img.shields.io/badge/Debian-AFEEEE?style=for-the-badge&logo=debian&logoColor=black" alt="Debian">
  <img src="https://img.shields.io/badge/CentOS-98FB98?style=for-the-badge&logo=centos&logoColor=black" alt="CentOS">
  <img src="https://img.shields.io/badge/Alpine_Linux-ADD8E6?style=for-the-badge&logo=alpinelinux&logoColor=black" alt="Alpine Linux">
  <img src="https://img.shields.io/badge/Kali-D3D3D3?style=for-the-badge&logo=kali-linux&logoColor=black" alt="Kali Linux">
  <img src="https://img.shields.io/badge/Arch-FFFFE0?style=for-the-badge&logo=archlinux&logoColor=black" alt="Arch Linux">
  <img src="https://img.shields.io/badge/Red_Hat-FFE4E1?style=for-the-badge&logo=redhat&logoColor=black" alt="Red Hat">
  <img src="https://img.shields.io/badge/Fedora-FFD700?style=for-the-badge&logo=fedora&logoColor=black" alt="Fedora">
  <img src="https://img.shields.io/badge/AlmaLinux-FFEFD5?style=for-the-badge&logo=almalinux&logoColor=black" alt="AlmaLinux">
  <img src="https://img.shields.io/badge/Rocky_Linux-FFFACD?style=for-the-badge&logo=rocky-linux&logoColor=black" alt="Rocky Linux">
</p>

不同发行版的软件包、网络栈和服务管理方式存在差异，脚本会根据当前系统能力开放对应功能。

## 效果图预览

<p>
  <img src="https://kejilion.sh/img/screenshots/kejilionsh.webp" alt="科技lion一键脚本中文版" width="49%">
  <img src="https://kejilion.sh/img/screenshots/kejilionsh_en.webp" alt="KejiLion Shell Script English Version" width="49%">
</p>

## 核心功能

- **系统信息概览**：快速展示 CPU、内存、磁盘、带宽等运行状态。<br>
  *System status overview: CPU, memory, disk, bandwidth, and more.*
- **网络测试工具**：集成测速、回程、延迟、丢包检测等工具。<br>
  *Network tools: speed tests, route tracing, latency, and packet loss tests.*
- **Docker 容器管理**：提供容器、镜像、网络、存储卷和日志管理。<br>
  *Docker management for containers, images, networks, volumes, and logs.*
- **LDNMP 一键部署**：快速搭建 Nginx、MySQL、PHP、Redis 网站环境。<br>
  *One-click LDNMP stack deployment for Nginx, MySQL, PHP, and Redis.*
- **网站防御与优化**：提供 CC 防护、防爬虫、防火墙和性能优化。<br>
  *Website protection and optimization with anti-CC, anti-crawler, firewall, and tuning tools.*
- **备份与迁移**：支持站点和数据库备份、恢复与远程迁移。<br>
  *Backup and migration for websites, databases, restoration, and remote transfer.*
- **BBR 加速优化**：管理内核加速与网络拥塞控制算法。<br>
  *Network acceleration and TCP congestion control optimization.*

## 项目文档

- [科技lion官方网站](https://kejilion.sh/)

## 使用与安全

- 只从本仓库获取脚本（用上面「一键安装」的命令，或把仓库整个下载到服务器），执行前可先审阅源码。
- 重要网站、数据库、Docker 数据和系统配置应定期备份。
- 生产服务器执行升级、卸载、磁盘或网络操作前，应确认终端显示的影响范围。
- 提交问题时，请隐藏密码、Token、私钥和公网 IP 等敏感信息。

## 后续事项

本次净化只动 `kejilion.sh`（外加删掉的语言资产）。下面这些是**明知没清、但按规格故意留下**的项，
逐条记在这里，等决定要不要单开工单。父议题规格的 Out of Scope 与用户故事 29/30 要求
"其他脚本本次完全不动，剩下的记入后续清单"。

> 从工单 #16 起的后续清理里，"其他文件"已经可以动了：凡是事由已消失的条目，就地标注
> "已随工单 #N 处理"并保留原文作为记录；凡还欠着的，原样留在本节等后面的工单。
> 编号 1~8 保持原样不重排，本轮（工单 #22）的删除清单见本节末尾。

### 1. 登录通知类脚本（每次 SSH 登录查询 IP 与定位）

- **是什么**：`TG-SSH-check-notify.sh` 会在每次 SSH 登录时查你的公网 IP、归属地、登录名和登录地区，
  通过 Telegram 机器人发出去；同目录的 `TG-check-notify.sh` 则每 5 分钟把 CPU/内存/硬盘/流量超阈值
  告警连同 IP 归属地发到同一个机器人。
- **在哪**：仓库根目录 `TG-SSH-check-notify.sh`、`TG-check-notify.sh`。二者都会被净化版脚本在运行时
  从原版仓库下载下来：主菜单 13「系统工具」→ 25「TG-bot系统监控预警」会把它们拉到 `~/` 并用 `nano` 让你填
  Bot Token 和 Chat ID，然后挂进 `@reboot` 定时任务和 `~/.profile`。
- **为什么这次不动**：规格 Out of Scope 原文"其他脚本的任何改动"；用户故事 29 要求改造范围可控。
  这两个脚本不在 `kejilion.sh` 里，删它们不会让净化版少一分报信。
- **建议怎么处理**：单开工单，两个口径分开定——`TG-check-notify.sh` 的告警本体是有用功能（只报本机资源），
  要做的是把消息体里的 `country`/`isp_info`/`masked_ip` 三行摘掉；`TG-SSH-check-notify.sh` 的存在意义
  就是"登录即报地理位置"，要么整个不启用，要么改成只报时间与登录名、不查任何外部定位服务
  （现在它查 `ipinfo.io` 和 `opendata.baidu.com`）。注意它俩是从原版仓库下载来的：只改仓库里的副本，
  对"已经下载过"的机器才有效，要连净化版脚本里的下载地址一起改才彻底（下载地址改指本仓库已列入工单 #23，
  与 `archive.key`、`upgrade_openssh9.8p1.sh` 同一批）。

### 2. 写死地址密码的备份模板

- **是什么**：`beifen.sh` 里硬编码了 `sshpass -p 123456 scp ... root@0.0.0.0:/home/`——密码和地址
  都是看起来像真值的"死值"，靠净化版脚本下载后用 `sed` 替换成用户输入的内容。
- **在哪**：仓库根目录 `beifen.sh`。被 `linux_ldnmp()`（主菜单 10「LDNMP建站」→ 站点远程备份）在
  `kejilion.sh` 第 13493 行从原版仓库下载，随后 `sed` 把 `0.0.0.0` 和 `123456` 换成用户填的 IP 和密码，
  并写进 `crontab` 定时备份。
- **为什么这次不动**：同上，规格把它列为 Out of Scope；它不在 `kejilion.sh` 里。
- **建议怎么处理**：单开工单。最低限度是把仓库里的死值改成一眼看出是占位的字样
  （例如 `sshpass -p '在此填入密码'`、`root@在此填入IP`），避免被人整份复制走直接用；更好的做法是
  改成从环境变量或单独配置文件读凭据，并在文件头写一句"别把真密码写进这里"。

### 3. 示例密码文件等 inert 项

- **是什么**：`archive.key` 是一个 PGP 公钥块（XanMod 内核仓库签名钥），文件名带 `.key`、内容像凭据，
  实际是公开信息，不构成泄露。同类的还有 `cloudflare.conf` 里的 `cftoken = APIKEY00000` 这类占位值。
- **在哪**：仓库根目录 `archive.key`；`kejilion.sh` 第 8326~8327 行会优先从 `dl.xanmod.org` 拉它，
  失败时才退回原版仓库这份副本。
- **为什么这次不动**：规格 Out of Scope 原文"示例密码文件等 inert 项；记入后续清单"。它们不参与报信，
  也不被装到用户机器上，删除反而会让第 8327 行的回退下载失败。
- **建议怎么处理**：单开工单做一次"凭据体检"——用 `grep -rnE 'passwo?rd|secret|token|api[_-]?key'`
  把整个仓库扫一遍，逐条判断是真凭据、占位符还是公开钥：真凭据立刻改掉并轮换；占位符统一改成
  明显是占位的字样；`archive.key` 这类公开钥建议在文件头加一行注释说明"这是公开签名钥，不是私钥"，
  免得将来有人心惊。
- **清点现状（工单 #22 复核）**：这一条涉及的文件清点后是——`archive.key` 仍在仓库根，且它作为
  取内容终局 5 项之一**保留**，下载地址改指本仓库的活归工单 #23；`cloudflare.conf` 仍在仓库根，
  等"凭据体检"那一票；`kejilion_sh_log.txt` 已在此前的工单里连文件带链接一起删除，不再需要处理。

### 4. `CONTRIBUTING.md` 的「KPanel 轻量节点运行时」一节（已随工单 #22 删除）

- **原是什么**：`CONTRIBUTING.md` 开头第 3~10 行整节都在讲"KPanel 轻量节点运行时"的维护规则
  （`KPANEL_NODE_LIFECYCLE` 模板、`KPANEL_NODE_RUNTIME_GENERATION` 版本号、
  `/run/kejilion-node-lifecycle.lock` 锁文件）。它描述的那套运行时已在工单 #6 整块删掉，这一节是悬空文档。
- **为什么拖到工单 #22 才动手**：工单 #6 按"本次不动其他文件"的约定故意留下，
  `docs/kpanel-removal-keep-list.md` 末尾已记了这一笔；那时的工单同样只被允许加"后续事项"这一节。
- **怎么处理的**：工单 #22 按验收第 3 条把整个 `CONTRIBUTING.md` 删掉了——全文只有 10 行，
  唯一一节就是上面那节悬空文档，删掉不损失任何规则。它不是脚本入口，也没有任何测试或构建依赖。
  删除前的内容仍在 git 历史里（`git show 75d4868:CONTRIBUTING.md`），需要时可整份取回。

### 5. `kpanel_backup_center_dispatch()` 调用的 `kejilion-agent`

- **是什么**：净化版脚本保留了 `kpanel_backup_center_dispatch()`（`k backup-center`，Docker/Web 备份菜单
  也会调它）。它会去执行 `/usr/local/libexec/kejilion-agent backup-center ...`——那是**另一个二进制**，
  与工单 #6 删掉的 `kejilion-node` 是两套东西。
- **在哪**：`kejilion.sh` 第 29831~29842 行（函数定义）、第 11148 与 13524 行（两处调用）、
  以及 CLI 分发里的 `backup-center` 分支。
- **为什么这次不动**：工单 #6 的保留清单（`docs/kpanel-removal-keep-list.md`）按边界留下了它：
  本脚本**从不下载**这个二进制（函数注释原文 "No downloaded helper or caller-supplied path"），
  只在机器上已经有人装了匹配版本的 Agent 时才会真的调它；函数开头就校验 root、文件存在且不是符号链接、
  属主为 0、权限不带 group/other 写位、协议版本匹配，任一条不过就报错返回。也就是说它不会偷偷装东西，
  风险只在于"机器上已有这个二进制时仍会调它"。
- **建议怎么处理**：单开工单，先定边界。要彻底断开这次调用，就把 `kpanel_backup_center_dispatch()`
  连同两处调用与 CLI 分支一起删掉，代价是失去"备份中心"这一个入口；要保留功能，就得先把
  `kejilion-agent` 的审计结论写进 `docs/`，明确它是谁提供的、什么许可、本次调用会做什么。
  在那之前，不建议在装了 Agent 的机器上跑 `k backup-center`。

### 6. 一处已经发生的越界删除：`CONTRIBUTING.md` 的「主脚本与中文脚本」同步节

上面几项都是"明知没清、故意留下"的；这一项不一样——它是一次**已经发生、但没人要求过的改动**。

- **是什么**：工单 #10 删七个语言副本目录时，把 `CONTRIBUTING.md` 里"主脚本与中文脚本
  必须同步、提交前跑 `bash tests/test_cn_script_sync.sh`"那一整节（12 行）连带删掉了，
  同一次提交还删掉了该节指向的 `tests/test_cn_script_sync.sh`。
- **为什么不在要求内**：规格 Implementation Decisions 原文是"其余脚本与配置文件本次一律不动"，
  没有任何工单要求改 `CONTRIBUTING.md`。这是范围蔓延。
- **为什么不撤消**：那一节描述的两份脚本在 `cn/` 目录删除后已经不存在，它指向的测试也没了，
  留着它是假话、会误导维护者；撤消它又等于把假话放回去。
- **怎么办**：**不撤消**，由仓库主人决定是否接受。完整背景、为什么删、以及单点回滚方法
  （删除前的内容在 `git show 7e770e8^:CONTRIBUTING.md` 里）详见验收报告第九节 9.2。
  注意：工单 #22 已把 `CONTRIBUTING.md` 整个文件删除（见第 4 条），所以"把那一段按原文贴回去"
  这件事的残响只剩历史记录——真要恢复那一节，现在得连整份文件一起从
  `git show 75d4868:CONTRIBUTING.md` 取回。本条保留为历史披露，不再作为待决事项。

### 7. 游戏开服脚本会把原版 `kejilion.sh` 装回来（重生路径）——已随工单 #22 解决

- **原是什么**：净化版主菜单 16「游戏开服脚本合集」会从**原版仓库**下载并运行另外两个脚本
  （`palworld.sh`、`mc.sh`）；这两个脚本自己的菜单里又各有一个入口（都绑在字母 `k` 上），会把
  **原版未净化的 `kejilion.sh`** 下载到 `~/` 并直接运行。完整路径：
  净化版菜单 → 16「游戏开服脚本合集」→ 幻兽帕鲁 / 我的世界 → `palworld.sh` / `mc.sh`
  → 按 `k` → 下载并运行原版 `kejilion.sh` → **报信复活**。工单 #13 已把 README 的
  一键安装命令改成本仓库 raw 地址，但这条路是从菜单里走的，改 README 拦不住它。
- **当初的位置**（行号为 2026-10-09 逐个核对，随工单 #16 / #22 已全部消失）：

  | 文件 | 行号 | 那一行在做什么 |
  |---|---|---|
  | `kejilion.sh` | 29674 | 菜单 16 → 1「幻兽帕鲁」：从原版仓库拉 `palworld.sh` 并运行 |
  | `kejilion.sh` | 29678 | 菜单 16 → 2「我的世界」：从原版仓库拉 `mc.sh` 并运行 |
  | `palworld.sh` | 419 | 帕鲁菜单按 `k`：从 `https://kejilion.pro/kejilion.sh` 下载原版脚本并立即运行 |
  | `mc.sh` | 416 | MC 菜单按 `k`：同上，从 `https://kejilion.pro/kejilion.sh` 下载原版脚本并立即运行 |

- **怎么解决的**：工单 #16 删掉主菜单 16「游戏开服脚本合集」的渲染行与 `16) games_server_tools`
  分发行；工单 #22 接着把 `games_server_tools()` 函数体整个删掉（它只有 1/2 两个分支，
  都是拉 `palworld.sh` / `mc.sh` 到 `~/` 运行），同时把仓库根这 6 个游戏脚本文件一并删除。
  那两个 `k` 分支干的事只有三样：把 `https://kejilion.pro/kejilion.sh` 拉到 `~/`、加可执行权限、
  立刻运行。文件不在仓库里了，这条路就彻底没有落脚点。
  集群菜单里"安装原作者脚本"那条同源的路也一并掐断：`cluster_python3()` 从原作者
  `python-for-vps` 仓库拉一个安装脚本到用户机器上直接 `python3` 执行，函数体随入口一起退役。
- **结论**：重生路径已清零，`kejilion.sh` 里 `games_server_tools` / `cluster_python3` /
  `python-for-vps` 三项均为零命中。本条改为历史记录，不再作为待办。

### 8. README 的 3 处图片热链与 1 处官网链接（怎么处理待定）

- **是什么**：README 有 4 处把请求发到作者域名 `https://kejilion.sh/`：logo、两张效果图截图
  （都是 `<img src="https://kejilion.sh/...">`）和「科技lion官方网站」链接。任何人在 GitHub 上
  打开这份 README，浏览器加载这三张图时会把查看者的 IP 送到作者的服务器——性质和规格反对的
  报信同源，只是量级小得多（只暴露"谁看过这份 README"）。这 4 处本次**只记账、不改**。
- **在哪**（行号为 2026-10-09 核对）：`README.md` 第 6 行（`/kejilionsh_logo.webp`）、
  第 81 行（`/img/screenshots/kejilionsh.webp`）、第 82 行（`/img/screenshots/kejilionsh_en.webp`）、
  第 109 行（「科技lion官方网站」链接）。
- **为什么这次不动**：怎么处理要仓库主人定——把图片搬进仓库 / 删掉 `<img>` 标签 / 接受现状，
  三种做法代价不同（见下），本工单只被允许记账。
- **建议怎么处理**：单开工单先定方向。推荐"图片搬进仓库 + 删官网链接"：三张图存进 `docs/images/`，
  `<img>` 的 `src` 改成相对路径，README 打开时对作者域名零请求；第 109 行的官网链接若只是想给读者
  一个作者站点参考，可保留文字说明但去掉跳转，或直接删。

### 本轮删除记录（工单 #22）

工单 #22 清掉的是"入口已断的功能本体 + 仓库孤儿"。逐项列出，便于复核：

- **`kejilion.sh` 函数体（2 个）**
  - `games_server_tools()`（38 行，游戏开服）——入口由工单 #16 删除后成孤儿；
  - `cluster_python3()`（6 行，集群菜单"安装原作者脚本"）——同上。
- **仓库根文件（14 个）**
  - 游戏脚本 6 个：`palworld.sh`、`pal_backup.sh`、`pal_log.sh`、`mc.sh`、`mc_backup.sh`、`mc_log.sh`；
  - 真孤儿 5 个（全仓库零引用，`kejilion.sh` 连文件名都不出现）：
    `auto_cert_renewal-1.sh`、`Limiting_Shut_down1.sh`、`check_x86-64_psabi.sh`、`nginx.local`、`valkey.conf`；
  - 内容已被 `kejilion.sh` 内联生成、不经 URL 下发的 2 个仓库副本：
    `Limiting_Shut_down.sh`（脚本本体在 `kpanel_network_operations_build_script()` 的 heredoc 里逐行写死）、
    `sshd.local`（`cat > /etc/fail2ban/jail.d/sshd.local` 的内联 heredoc），功能都完整保留；
  - 悬空文档 1 个：`CONTRIBUTING.md`（见第 4 条）。
- **还欠着、暂时不能删的兄弟文件**（下载点还在 `kejilion.sh` 里，等对应工单先删下载点）
  - LDNMP 建站区，归工单 #20：`auto_cert_renewal.sh`、`beifen.sh`、`CF-Under-Attack.sh`、
    `fail2ban-nginx-cc.conf`、`custom_mysql_config.cnf`、`custom_mysql_config-1.cnf`、
    `optimized_php.ini`、`www.conf`、`www-1.conf`、`ldnmp.sh`；
  - AI 区，归工单 #19：`ai_cli_manager.sh`、`hermes_manager.sh`、`deepseek_harness_manager.sh`；
  - 取内容终局 5 项，URL 改指本仓库，归工单 #23：`TG-check-notify.sh`、`TG-SSH-check-notify.sh`、
    `upgrade_openssh9.8p1.sh`、`archive.key`（第 5 项是 fail2ban SSH 防御配置，落库后同为改指）。

## 开源许可

本项目采用 [Apache License 2.0](LICENSE) 开源。


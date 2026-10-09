> 这是 kejilion 脚本的个人净化版，不是科技Lion原作者的官方发布。
> 相比原版，本版删除了：偷偷把使用记录和 IP 归属地上传给原作者服务器的“报信”功能、VPS 返利广告与站点引流、自带每小时更新的闭源管理面板、会整体覆盖本地文件的“检查更新”功能；下载改为直连原始站点。
> 除上述删减外，其余功能与原版一致，署名与授权以仓库许可文件为准。

<p align="center">
  <img src="https://kejilion.sh/kejilionsh_logo.webp?v=2" alt="KEJILION.SH 科技lion一键脚本工具" width="620">
</p>

<h1 align="center">KEJILION.SH · 科技lion一键脚本工具</h1>

<p align="center">
  面向 Linux 服务器的综合脚本工具箱，集成系统管理、网络测试、Docker
  与安全防护。
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

科技Lion 的 Shell 脚本工具是一款 Linux 服务器脚本工具箱，专为系统监控、测试和运维管理而设计。
无论您是初学者还是经验丰富的用户，该工具都能提供便捷的解决方案。脚本集成 Docker
管理与各类系统工具，
让服务器维护更加简单。

KejiLion's Shell script is a toolbox designed for Linux monitoring, testing, and
server management. It brings together Docker management and system tools
in one interactive tool.

## 一键安装

使用 `root` 用户执行以下命令。

```bash
KJ_RAW_URL="https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh"
bash <(curl -sL "$KJ_RAW_URL")
```

这条命令装的是**个人净化版**（脚本从本仓库的 GitHub 直链拉取）；别改成从原作者域名 `kejilion.sh` 拉，那样装回来的是没净化的原版。

首次运行后可按脚本提示设置 `k` 快捷命令，后续直接输入 `k` 即可打开主菜单。

> [!IMPORTANT]
> 脚本包含软件安装、网络、防火墙、磁盘和容器等系统级操作。
> 请在执行前阅读终端提示，并提前备份重要数据、容器和配置。

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

- **系统信息查询**：快速展示 CPU、内存、磁盘、带宽等运行状态。<br>
  *System status overview: CPU, memory, disk, bandwidth, and more.*
- **系统更新**：更新系统与已安装的组件到当前发行版的最新版本。
- **系统清理**：清理缓存、日志与冗余文件，回收磁盘空间。
- **基础工具**：一键安装 curl、wget、tmux、btop、vim、nano 等常用工具。
- **BBR 管理**：管理内核加速与网络拥塞控制算法。<br>
  *Network acceleration and TCP congestion control optimization.*
- **Docker 管理**：提供容器、镜像、网络、存储卷和日志管理，以及环境备份与还原。<br>
  *Docker management for containers, images, networks, volumes, and logs.*
- **WARP 管理**：管理 Cloudflare WARP 客户端，为出站流量加一层通道。
- **测试脚本合集**：集成测速、回程、延迟、丢包、IP 质量体检等工具。<br>
  *Network tools: speed tests, route tracing, latency, and packet loss tests.*
- **甲骨文云脚本合集**：甲骨文云实例相关的闲置保活、DD 重装、密码登录等运维脚本。
- **后台工作区**：以 tmux 会话承载常驻任务，SSH 掉线后任务继续运行。
- **系统工具**：SSH 端口、DNS、防火墙、fail2ban 防御、硬盘管理、账号管理与定时任务等本机运维项。
- **服务器集群控制**：多台机器的集中管理与批量操作。

## 项目文档

- [科技lion官方网站](https://kejilion.sh/)

## 使用与安全

- 只从本仓库获取脚本（用上面「一键安装」的命令，或把仓库整个下载到服务器），执行前可先审阅源码。
- 重要数据、Docker 数据和系统配置应定期备份。
- 生产服务器执行升级、卸载、磁盘或网络操作前，应确认终端显示的影响范围。
- 提交问题时，请隐藏密码、Token、私钥和公网 IP 等敏感信息。

## 后续事项

规格的初始约定是"只动 `kejilion.sh`"（外加删掉随主脚本退役的语言资产）。从工单 #16
起"其他文件"按事由逐个清理：游戏开服、AI 面板、LDNMP 建站各自带走一批兄弟文件，
又删掉了孤儿文件与整份 `CONTRIBUTING.md`——这些删除的明细见本节末尾的
「本轮删除记录」。下面这些是**明知没清、但按规格故意留下**的项，
逐条记在这里，等决定要不要单开工单。父议题规格的 Out of Scope 与用户故事 29/30 要求
"其他脚本本次完全不动，剩下的记入后续清单"。

> 从工单 #16 起的后续清理里，"其他文件"已经可以动了：凡是事由已消失的条目，就地标注
> "已随工单 #N 处理"并保留原文作为记录；凡还欠着的，原样留在本节等后面的工单。
> 本节编号的完整变迁：**原编号 1~9**（规格初始的后续清单）→ 工单 #20 删掉 LDNMP
> 下载点后，原第 2 条 beifen.sh 事由已消失、随文件一并移出，其后条目顺次上移成
> **1~8** → 工单 #24 补了 `restore_defaults()` 退场（能力减少）与三个零调用方函数
> 两条，恢复成 **1~9**（其余条目原文不动、不重排）。本轮（工单 #22）的删除清单
> 见本节末尾。

### 1. 登录通知类脚本（每次 SSH 登录查询 IP 与定位）

- **是什么**：`TG-SSH-check-notify.sh` 会在每次 SSH 登录时查你的公网 IP、归属地、登录名和登录地区，
  通过 Telegram 机器人发出去；同目录的 `TG-check-notify.sh` 则每 5 分钟把 CPU/内存/硬盘/流量超阈值
  告警连同 IP 归属地发到同一个机器人。
- **在哪**：仓库根目录 `TG-SSH-check-notify.sh`、`TG-check-notify.sh`。二者都会被净化版脚本在运行时
  下载下来：主菜单 13「系统工具」→ 25「TG-bot系统监控预警」会把它们拉到 `~/` 并用 `nano` 让你填
  Bot Token 和 Chat ID，然后挂进 `@reboot` 定时任务和 `~/.profile`。
  **下载地址已改指本仓库**（工单 #23）：原来指向原作者仓库的 raw 地址，现改指
  `https://raw.githubusercontent.com/howi3c/sh/main/…`，与 `archive.key`、`upgrade_openssh9.8p1.sh`
  同一批改完；改完后即便回退也不会从原作者仓库取内容。
- **为什么这次不动**：规格 Out of Scope 原文"其他脚本的任何改动"；用户故事 29 要求改造范围可控。
  这两个脚本不在 `kejilion.sh` 里，删它们不会让净化版少一分报信；改下载地址是取内容收敛（ADR-0002）
  的要求，**不代表脚本内容被审计通过**。
- **建议怎么处理**：单开工单，两个口径分开定——`TG-check-notify.sh` 的告警本体是有用功能（只报本机资源），
  要做的是把消息体里的 `country`/`isp_info`/`masked_ip` 三行摘掉；`TG-SSH-check-notify.sh` 的存在意义
  就是"登录即报地理位置"，要么整个不启用，要么改成只报时间与登录名、不查任何外部定位服务
  （现在它查 `ipinfo.io` 和 `opendata.baidu.com`）。两个脚本的外联清单：
  `TG-check-notify.sh` 查 `ipinfo.io`（归属地）、`ipv4.ip.sb`（本机公网 IPv4）、
  `api.telegram.org`（用户自己的 bot）；`TG-SSH-check-notify.sh` 在此之上另加
  `opendata.baidu.com`（归属地）。这些自带的外联**仍待治理**，URL 改指本仓库
  只解决"从哪取"，不解决"取下来的内容会做什么"。

### 2. 示例密码文件等 inert 项

- **是什么**：`archive.key` 是一个 PGP 公钥块（XanMod 内核仓库签名钥），文件名带 `.key`、内容像凭据，
  实际是公开信息，不构成泄露。同类的还有 `cloudflare.conf` 里的 `cftoken = APIKEY00000` 这类占位值。
- **在哪**：仓库根目录 `archive.key`；`kejilion.sh` 第 3976~3977 行会优先从 `dl.xanmod.org` 拉它，
  失败时才退回本仓库这份副本（工单 #23 已把回退源从原版仓库改指本仓库）。
- **为什么这次不动**：规格 Out of Scope 原文"示例密码文件等 inert 项；记入后续清单"。它们不参与报信，
  也不被装到用户机器上，删除反而会让第 3977 行的回退下载失败。
- **建议怎么处理**：单开工单做一次"凭据体检"——用 `grep -rnE 'passwo?rd|secret|token|api[_-]?key'`
  把整个仓库扫一遍，逐条判断是真凭据、占位符还是公开钥：真凭据立刻改掉并轮换；占位符统一改成
  明显是占位的字样；`archive.key` 这类公开钥建议在文件头加一行注释说明"这是公开签名钥，不是私钥"，
  免得将来有人心惊。
- **清点现状（工单 #23 复核）**：这一条涉及的文件清点后是——`archive.key` 仍在仓库根，作为取内容终局
  5 项之一**保留**，且它的下载地址已在工单 #23 改指本仓库；`cloudflare.conf` 仍在仓库根，
  等"凭据体检"那一票；`kejilion_sh_log.txt` 已在此前的工单里连文件带链接一起删除，不再需要处理。

### 3. `CONTRIBUTING.md` 的「KPanel 轻量节点运行时」一节（已随工单 #22 删除）

- **原是什么**：`CONTRIBUTING.md` 开头第 3~10 行整节都在讲"KPanel 轻量节点运行时"的维护规则
  （`KPANEL_NODE_LIFECYCLE` 模板、`KPANEL_NODE_RUNTIME_GENERATION` 版本号、
  `/run/kejilion-node-lifecycle.lock` 锁文件）。它描述的那套运行时已在工单 #6 整块删掉，这一节是悬空文档。
- **为什么拖到工单 #22 才动手**：工单 #6 按"本次不动其他文件"的约定故意留下，
  工单 #6 的保留清单（`docs/kpanel-removal-keep-list.md`，已随工单 #17 删除，
  原文见 git 历史）末尾已记了这一笔；那时的工单同样只被允许加"后续事项"这一节。
- **怎么处理的**：工单 #22 按验收第 3 条把整个 `CONTRIBUTING.md` 删掉了——全文只有 10 行，
  唯一一节就是上面那节悬空文档，删掉不损失任何规则。它不是脚本入口，也没有任何测试或构建依赖。
  删除前的内容仍在 git 历史里（`git show 75d4868:CONTRIBUTING.md`），需要时可整份取回。

### 4. `kpanel_backup_center_dispatch()` 调用的 `kejilion-agent`

- **是什么**：净化版脚本保留了 `kpanel_backup_center_dispatch()`（`k backup-center`，Docker/Web 备份菜单
  也会调它）。它会去执行 `/usr/local/libexec/kejilion-agent backup-center ...`——那是**另一个二进制**，
  与工单 #6 删掉的 `kejilion-node` 是两套东西。
- **在哪**：`kejilion.sh` 第 13925~13936 行（函数定义）、第 6754 行（Docker 备份/迁移/还原
  工具菜单里的 `5) kpanel_backup_center_dispatch menu docker`）、第 13945~13947 行（CLI
  分发里的 `backup-center` 分支）。这三处行号由工单 #24 于 2026-10-09 重新核对——
  脚本从 30229 行削到 14172 行后集体前移，旧记录里的 29831~29842 / 11148 / 13524 已失效。
- **为什么这次不动**：工单 #6 的保留清单（`docs/kpanel-removal-keep-list.md`，已随工单 #17
  删除，原文见 git 历史）按边界留下了它：
  本脚本**从不下载**这个二进制（函数注释原文 "No downloaded helper or caller-supplied path"），
  只在机器上已经有人装了匹配版本的 Agent 时才会真的调它；函数开头就校验 root、文件存在且不是符号链接、
  属主为 0、权限不带 group/other 写位、协议版本匹配，任一条不过就报错返回。也就是说它不会偷偷装东西，
  风险只在于"机器上已有这个二进制时仍会调它"。
- **建议怎么处理**：单开工单，先定边界。要彻底断开这次调用，就把 `kpanel_backup_center_dispatch()`
  连同两处调用与 CLI 分支一起删掉，代价是失去"备份中心"这一个入口；要保留功能，就得先把
  `kejilion-agent` 的审计结论写进 `docs/`，明确它是谁提供的、什么许可、本次调用会做什么。
  在那之前，不建议在装了 Agent 的机器上跑 `k backup-center`。

### 5. 一处已经发生的越界删除：`CONTRIBUTING.md` 的「主脚本与中文脚本」同步节

上面四项都是"明知没清、故意留下"的；这一项不一样——它是一次**已经发生、但没人要求过的改动**。

- **是什么**：工单 #10 删七个语言副本目录时，把 `CONTRIBUTING.md` 里"主脚本与中文脚本
  必须同步、提交前跑 `bash tests/test_cn_script_sync.sh`"那一整节（12 行）连带删掉了，
  同一次提交还删掉了该节指向的 `tests/test_cn_script_sync.sh`。
- **为什么不在要求内**：规格 Implementation Decisions 原文是"其余脚本与配置文件本次一律不动"，
  没有任何工单要求改 `CONTRIBUTING.md`。这是范围蔓延。
- **为什么不撤消**：那一节描述的两份脚本在 `cn/` 目录删除后已经不存在，它指向的测试也没了，
  留着它是假话、会误导维护者；撤消它又等于把假话放回去。
- **怎么办**：**不撤消**，由仓库主人决定是否接受。完整背景、为什么删、以及单点回滚方法
  （删除前的内容在 `git show 7e770e8^:CONTRIBUTING.md` 里）详见验收报告第九节 9.2。
  注意：工单 #22 已把 `CONTRIBUTING.md` 整个文件删除（见第 3 条），所以"把那一段按原文贴回去"
  这件事的残响只剩历史记录——真要恢复那一节，现在得连整份文件一起从
  `git show 75d4868:CONTRIBUTING.md` 取回。本条保留为历史披露，不再作为待决事项。

### 6. 游戏开服脚本会把原版 `kejilion.sh` 装回来（重生路径）——已随工单 #22 解决

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

### 7. README 的 3 处图片热链与 1 处官网链接（怎么处理待定）

- **是什么**：README 有 4 处把请求发到作者域名 `https://kejilion.sh/`：logo、两张效果图截图
  （都是 `<img src="https://kejilion.sh/...">`）和「科技lion官方网站」链接。任何人在 GitHub 上
  打开这份 README，浏览器加载这三张图时会把查看者的 IP 送到作者的服务器——性质和规格反对的
  报信同源，只是量级小得多（只暴露"谁看过这份 README"）。这 4 处本次**只记账、不改**。
- **在哪**（行号为 2026-10-09 工单 #23 重核，README 能力清单改写后已从 81/82/109 漂移到 78/79/103）：
  `README.md` 第 6 行（`/kejilionsh_logo.webp`）、
  第 78 行（`/img/screenshots/kejilionsh.webp`）、第 79 行（`/img/screenshots/kejilionsh_en.webp`）、
  第 103 行（「科技lion官方网站」链接）。
- **为什么这次不动**：怎么处理要仓库主人定——把图片搬进仓库 / 删掉 `<img>` 标签 / 接受现状，
  三种做法代价不同（见下），本工单只被允许记账；工单 #24（最终验收）已把这一条列为剩余关注点。
- **建议怎么处理**：单开工单先定方向。推荐"图片搬进仓库 + 删官网链接"：三张图存进 `docs/images/`，
  `<img>` 的 `src` 改成相对路径，README 打开时对作者域名零请求；第 103 行的官网链接若只是想给读者
  一个作者站点参考，可保留文字说明但去掉跳转，或直接删。

### 8. 三个零调用方的顶层函数（保留：规格点名，待连"应用编号登记"一起退役时再处理）

- **是什么**：`kejilion.sh` 里有三个顶层函数现在**一个调用方都没有**（工单 #24 于 2026-10-09
  复核）：`remove_app_id()`（应用编号移除）、`kpanel_app_update_marker()`（写
  `/home/docker/appno.txt` 标记文件）、`find_container_by_host_port()`（按宿主端口找容器）。
  其中 `kpanel_app_update_marker` 只被 `remove_app_id` 调用，而 `remove_app_id` 自身无调用方，
  两个是**传递性孤儿**；`find_container_by_host_port` 则是定义即孤儿。
- **在哪**：`kejilion.sh` 第 57 行 `kpanel_app_update_marker()`、第 74 行 `remove_app_id()`、
  第 2524 行 `find_container_by_host_port()`。
- **为什么这次不动**：规格 Implementation Decisions 点名"并发锁基础设施、应用编号登记…
  一律保留"，这条点名压倒了"删除后调用方归零的函数逐一确认后清除"的通用规则。锁四件套
  （`kpanel_app_lock_held` / `kpanel_app_with_lock` 及其 `system` 资源）在保留区有十余处
  调用方（安装、卸载、iptables、防火墙…），`markers` 分支只服务上面那两个孤儿函数，
  `catalog` 分支的调用方（应用市场目录刷新）已随工单 #17 退役——但整套基础设施是一个整体，
  按规格意图保留。
- **建议怎么处理**：将来若决定连"应用编号登记"（`/home/docker/appno.txt` 那套标记机制）
  一起退役，需**同时**收尾三件事：删掉这三个函数；把 `kpanel_app_with_lock` 的资源白名单
  里的 `markers` 与 `catalog` 两个分支一并去掉（第 31 行 `case "$resource" in system|catalog|markers)`）；
  检查还有没有别处读 `/home/docker/appno.txt`。删除守卫
  `tests/test_spec15_slim_down_removed.sh` 已就"这三个函数仍在 + 本条记账在位"设了断言
  （断言 2c），动手时要同步改尺子，不要静默删除。
- **`find_container_by_host_port` 单独说明**：它不属"应用编号登记"那一套（只是 Docker 查询
  辅助），但同为零调用方、同样按上面的理由保留。它体积小、无副作用；若单开工单只清它，
  不牵动锁与标记机制。

### 9. 内核优化菜单的「还原默认设置」能力随工单 #21 消失（保留能力实质减少）

- **是什么**：内核优化菜单（`k nhyh`，系统工具里那一条）原来第 6 项是「还原默认设置：
  将系统设置还原为默认配置」，由 `restore_defaults()` 实现（旧版 `kejilion.sh` 第
  9192~9220 行，29 行函数体，干的是"完全清理"：删掉 `99-kejilion-optimize.conf` 与
  `99-network-optimize.conf` 两个优化配置文件）。工单 #21 删除 `network-optimize.sh`
  外部脚本后，这个函数的调用方归零，被后续的孤儿收敛提交 `f324d6b` 一并清掉。
  现在 `kejilion.sh` 里 `restore_defaults` 与「还原默认设置」字样均为 **0 命中**
  （工单 #24 复核）。
- **为什么这次不动**：规格 Further Notes 把内核调优相关项归入"内核调优剩余项"，判为可接受；
  且规格要求"删除后调用方归零的函数被识别并逐一确认后清除"，`restore_defaults()`
  正是按这条规则走的，不是误删。
- **为什么仍要记账**：这是一次**保留能力的实质减少**——用户原来能把调优改过的系统设置
  一键还原，现在只能手动逐项改回。规格判"可接受"不等于"没有代价"，仓库主人应该知道这事。
- **建议怎么处理**：若要恢复，从 `git show f324d6b^:kejilion.sh` 取回该函数、它的菜单项
  与分发调用三处，重新挂回内核优化菜单；恢复前先确认它引用的调优项编号与现在的菜单
  （一条龙调优已从 12 项变 11 项）还对得上。不恢复也完全说得过去，本条只是把账记下。



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
  - 悬空文档 1 个：`CONTRIBUTING.md`（见第 3 条）。
- **工单 #22 当时还欠着、现已清完的兄弟文件**（下载点随所属板块删除，仓库副本随之消失）
  - LDNMP 建站区，已随工单 #20 删除：`auto_cert_renewal.sh`、`beifen.sh`、`CF-Under-Attack.sh`、
    `fail2ban-nginx-cc.conf`、`custom_mysql_config.cnf`、`custom_mysql_config-1.cnf`、
    `optimized_php.ini`、`www.conf`、`www-1.conf`、`ldnmp.sh`。
    其中 `beifen.sh`（站点远程备份脚本）**事由已消失**——它只服务 LDNMP 建站的站点备份，
    建站整块删除后它连同下载点一起退场，不需要再单开工单治理；
  - AI 区，已随工单 #19 删除：`ai_cli_manager.sh`、`hermes_manager.sh`、`deepseek_harness_manager.sh`；
  - 取内容终局 5 项，已随工单 #23 全部改指本仓库：`TG-check-notify.sh`、`TG-SSH-check-notify.sh`、
    `upgrade_openssh9.8p1.sh`、`archive.key`，以及从 `kejilion/config` 仓收编进来的
    fail2ban SSH 防御配置（仓库内文件名 `fail2ban-ssh.conf`，部署到用户机时仍叫 `centos-ssh.conf`）。

第二轮审查修复（工单 #24 验收报告写完之后）又补删了一个当时漏掉的孤儿：

- **`update_log.sh`**（423 行，原版的脚本更新日志展示脚本）：它符合工单 #22 自己给的判据
  ——`kejilion.sh` 零提及、零下载，全仓库零引用（`grep -rn 'update_log' . --exclude-dir=.git`
  只命中验收报告里一句描述性文字），对应规格用户故事 34「仓库里每个文件都有存在的理由」。
  删除前内容在 git 历史里，删除守卫的孤儿文件黑名单已加上它，今后不得回来。

## 开源许可

本项目采用 [Apache License 2.0](LICENSE) 开源。


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

这一节是**还没解决的待办清单**。凡是已经处置完毕的条目，从这里移出——它们的完整记录
（处置过程、理由、git 提交号）都在 `docs/acceptance-report.md` 里，本节不堆放历史。父议题
规格的 Out of Scope 与用户故事 29/30 要求"其他脚本本次完全不动，剩下的记入后续清单"，
所以每一轮清理都把新发现的欠账记到这里；每解决一条就移出一条，编号顺次前移。

### 1. `TG-SSH-check-notify.sh` 的登录通知：未打码登录 IP + 归属地外联

- **是什么**：每次有人 SSH 登进你的机器，它就查登录方的 IP 与归属地，连同登录名、
  登录时间，通过 Telegram 机器人发一条消息。
- **在哪**：仓库根 `TG-SSH-check-notify.sh`。它由净化版脚本在运行时下载：主菜单 13
  「系统工具」→ 25「TG-bot系统监控预警」会把它拉到 `~/`，用 `nano` 让你填 Bot Token 和
  Chat ID，然后挂进 `@reboot` 定时任务和 `~/.profile`（开机自启、长期在后台跑）。下载地址
  已在工单 #23 改指本仓库（`raw.githubusercontent.com/howi3c/sh/main/…`）。
- **要紧的地方**：消息里"登录机器"那一行的 IP 是**打过码**的（只留后两段），但"登录 IP"
  这一行是**完整未打码**的 `$SSH_CONNECTION` 原值；而且脚本第 18 行会把该 IP 拼进 URL
  查询串发给 `opendata.baidu.com` 换地理位置。也就是说——"谁、什么时间、从哪个 IP、
  用哪个账号、登了你的哪台服务器"这件事，除了进你自己的 Telegram，**登录 IP 和地理位置
  还被送去了百度**。登你机器的人若是同事、朋友、客户，那就是在未经他同意的情况下把他的
  IP 交给第三方。（`ipinfo.io` 查归属地另有一处，属规格明示已接受、不处理的"地区判断端点"。）
- **为什么这次不动**：规格 Out of Scope 原文"其他脚本的任何改动"；用户故事 29 要求改造
  范围可控。这些脚本不在 `kejilion.sh` 里。改下载地址是取内容收敛（ADR-0002）的要求，
  **不代表脚本内容被审计通过**。
- **建议怎么处理**：单开工单。最小改法是把第 18 行整行删掉（连同第 16~17 行注释和第 27 行
  的「登录地区」字段），功能退化成本机 IP + 时间 + 登录名，安全上不再把登录者 IP 送出去；
  要么整个不启用这个脚本。
- **`TG-check-notify.sh` 已评估、不立项**：同目录那个每 5 分钟报一次 CPU/内存/硬盘/流量
  超阈值的脚本，已逐行通读——它采集的**只有本机自己的信息**（`ipinfo.io` 查自己服务器的
  国别与运营商、`ipv4.ip.sb` 取自己服务器的公网 IPv4），发出去的 IP 是打码的 `*.x.x`
  形态，且只发到用户自己填的 bot。它与主脚本里 12 处同类用法同性质，属规格明示已接受、
  不处理的"地区判断端点"，**判定不需要单独立项**，因此不列为本节待办。

### 2. 示例密码文件等 inert 项

- **是什么**：`archive.key` 是一个 PGP 公钥块（XanMod 内核仓库签名钥），文件名带 `.key`、内容像凭据，
  实际是公开信息，不构成泄露。同类的还有 `cloudflare.conf` 里的 `cftoken = APIKEY00000` 这类占位值。
- **在哪**：仓库根目录 `archive.key`；`kejilion.sh` 第 3938~3939 行会优先从 `dl.xanmod.org` 拉它，
  失败时才退回本仓库这份副本（工单 #23 已把回退源从原版仓库改指本仓库）。
- **为什么这次不动**：规格 Out of Scope 原文"示例密码文件等 inert 项；记入后续清单"。它们不参与报信，
  也不被装到用户机器上，删除反而会让第 3939 行的回退下载失败。
- **建议怎么处理**：单开工单做一次"凭据体检"——用 `grep -rnE 'passwo?rd|secret|token|api[_-]?key'`
  把整个仓库扫一遍，逐条判断是真凭据、占位符还是公开钥：真凭据立刻改掉并轮换；占位符统一改成
  明显是占位的字样；`archive.key` 这类公开钥建议在文件头加一行注释说明"这是公开签名钥，不是私钥"，
  免得将来有人心惊。
- **清点现状（工单 #23 复核）**：这一条涉及的文件清点后是——`archive.key` 仍在仓库根，作为取内容终局
  5 项之一**保留**，且它的下载地址已在工单 #23 改指本仓库；`cloudflare.conf` 仍在仓库根，
  等"凭据体检"那一票；`kejilion_sh_log.txt` 已在此前的工单里连文件带链接一起删除，不再需要处理。


### 3. `kpanel_backup_center_dispatch()` 调用的 `kejilion-agent`

- **是什么**：净化版脚本保留了 `kpanel_backup_center_dispatch()`（`k backup-center`，Docker/Web 备份菜单
  也会调它）。它会去执行 `/usr/local/libexec/kejilion-agent backup-center ...`——那是**另一个二进制**，
  与工单 #6 删掉的 `kejilion-node` 是两套东西。
- **在哪**：`kejilion.sh` 第 13887~13898 行（函数定义）、第 6716 行（Docker 备份/迁移/还原
  工具菜单里的 `5) kpanel_backup_center_dispatch menu docker`）、第 13907~13909 行（CLI
  分发里的 `backup-center` 分支）。这三处行号 2026-10-10 由第三轮审查修复重新核对——
  脚本从 30229 行削到 14172 行后集体前移过一次（旧记录里的 29831~29842 / 11148 / 13524
  已失效），第三轮审查（工单 #25）又删了文件头三个零调用方函数（14172 → 14134 行），行号再前移 38 行，
  13925~13936 / 6754 / 13945~13947 又失效，以这里写的为准。
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


### 4. README 的 3 处图片热链与 1 处官网链接（怎么处理待定）

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


### 5. 内核优化菜单的「还原默认设置」能力随工单 #21 消失（保留能力实质减少）

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
  - 悬空文档 1 个：`CONTRIBUTING.md`（删除提交 `80da4de`）。
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

第三轮审查修复（工单 #25，工单 #24 验收报告写完之后）又补删了一个当时漏掉的孤儿：

- **`update_log.sh`**（423 行，原版的脚本更新日志展示脚本）：它符合工单 #22 自己给的判据
  ——`kejilion.sh` 零提及、零下载，全仓库零引用（`grep -rn 'update_log' . --exclude-dir=.git`
  只命中验收报告里一句描述性文字），对应规格用户故事 34「仓库里每个文件都有存在的理由」。
  删除前内容在 git 历史里，删除守卫的孤儿文件黑名单已加上它，今后不得回来。

## 开源许可

本项目采用 [Apache License 2.0](LICENSE) 开源。


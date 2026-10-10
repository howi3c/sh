# 净化原则：取内容只从本仓库

_Status: accepted_

## 关系：本 ADR 是 ADR-0001 的收窄

[ADR-0001](./0001-keep-content-fetching-strip-reporting.md) 定下"**保取内容、灭报信**"——取内容一律保留、报信一律删除，这条边界至今完全成立、本轮一个字都没动。本 ADR 在那基础上再收窄一件事：**取内容的来源**。ADR-0001 回答"要不要发请求"，本 ADR 回答"向谁发"。二者不冲突，是同一条边界线上的前后两道闸门。

## Context

净化版保留的板块（系统信息 / 更新 / 清理 / 基础工具 / BBR / Docker / WARP / 测试脚本 / 甲骨文云 / 后台工作区 / 系统工具 / 集群控制）里，有 5 处取内容是向**原作者名下**发的：

| 文件 | 原 URL | 用途 |
|---|---|---|
| `TG-check-notify.sh` | `raw.githubusercontent.com/kejilion/sh/main/…` | TG 系统监控预警 |
| `TG-SSH-check-notify.sh` | `raw.githubusercontent.com/kejilion/sh/main/…` | SSH 登录通知 |
| `upgrade_openssh9.8p1.sh` | `raw.githubusercontent.com/kejilion/sh/main/…` | OpenSSH 升级 |
| `archive.key` | `raw.githubusercontent.com/kejilion/sh/main/…` | BBRv3 XanMod 签名钥的**回退源**（主用 `dl.xanmod.org`） |
| `centos-ssh.conf` | `raw.githubusercontent.com/kejilion/config/main/fail2ban/…` | fail2ban SSH 防御 jail |

这个问题不是报信——这些请求里**不夹带任何用户信息**，纯粹是拿文件。但它是"净化版仍然依赖原作者服务器"：原作者改一下仓库内容，净化版下发给用户的文件就跟着变；原作者删掉或改动某个文件，净化版的功能就悄悄坏掉。对一个目标是"行为可预期、可审计"的净化版来说，这条隐性依赖说不通。

## Decision

**净化版的取内容只从本仓库 `https://raw.githubusercontent.com/howi3c/sh/main/` 拿。**

具体做法分两类：

1. **现存兄弟文件**（4 个）：仓库里已有副本，逐字节比对确认与原版一致、并通读审计无报信后，把 `kejilion.sh` 里的 URL 改指本仓库。
2. **收编**（1 个）：`centos-ssh.conf` 原来在作者的另一个仓库（`kejilion/config`），把它取回、审计后收进本仓库（仓库内文件名 `fail2ban-ssh.conf`），再把 URL 改指本仓库。

**为什么不连其余原版配置一起收编**：规格 Out of Scope 明确不收编原作者的 nginx 站点配置、docker 编排、`kejilion/config` 里的杂项配置、网站源码与 Python 集群脚本——它们**全部服务于被删除的板块**（LDNMP 建站、网站防御、应用市场、集群安装），随功能删除、一律不收编。`fail2ban-nginx-cc.conf`、`nginx-docker-cc.conf`、`cloudflare-docker.conf` 看起来同属 fail2ban 家族，但它们是 **nginx/CF 的 CC 防护**，不是 SSH 防御，同样随建站退场。唯一例外是这里的 fail2ban **SSH 防御**配置：它服务的"SSH 防御程序"是规格明文保留的功能（主菜单 13→22 与一条龙调优都用它），删掉会让 dnf/yum 系统上的这一项失去配置来源，所以必须收编。

**收编后的两处不对称，是有意保留的**：apt 分支仍不下载它（靠 rsyslog + 默认/内联 sshd jail），与现状一致；`--output centos-ssh.conf`（用户机上的 jail 文件名）不动，改的只是 URL。

## 四个现存兄弟文件的审计结论

工单 #23 的验收要求是"4 个兄弟文件逐字节比对 + 通读审计完成并留有结论记录"。比对结论：四个文件与原版仓库的对应文件**逐字节一致**（`sha256sum` 相同、`cmp` 判定 `IDENTICAL`）——URL 改指本仓库不改变下发内容，只改变"从哪取"。逐文件的通读结论如下（sha256 记前缀，全值可用 `sha256sum <文件>` 复算）：

| 文件 | sha256 前缀 | 审计结论 |
|---|---|---|
| `TG-check-notify.sh` | `8ab9e069…` | TG bot **本机资源告警**：CPU/内存/硬盘/流量超阈值时给用户自己的 bot 发消息。两处凭据（`TELEGRAM_BOT_TOKEN`、`CHAT_ID`）是用户自填的占位符文本（原文写的是"输入TG的机器人API"这类字样），脚本里没有预置任何凭据。外联三处：`ipinfo.io`（取 IP 归属地）、`ipv4.ip.sb`（取本机公网 IPv4）、`api.telegram.org`（用户自己的 bot）。发出去的 IP 是打码的 `*.*.*.*` 形态。无广告、无指向原版仓库的引用、无后门。 |
| `TG-SSH-check-notify.sh` | `61813dc1…` | SSH 登录通知：每次登录给用户自己的 bot 发一条消息。凭据不在文件里，由主脚本 `sed -i "3i…"/"4i…"` 从 `TG-check-notify.sh` 注入（`kejilion.sh` 13255~13256 行，2026-10-10 第三轮审查修复（工单 #25）删除文件头三个零调用方函数后重核）。外联在上一行基础上另加 `opendata.baidu.com`（IP 归属地查询）。**如实记录两点**：登录来源 IP 是**完整未打码**的（`$SSH_CONNECTION` 第一个字段原样发出），IP 归属地经用户的 TG bot 发出——这正是它在术语表口径下仍属报信的原因，当时就此记账于 README「后续事项」第 1 条（该记账节后被仓库主人删除，内容见 git 历史）。按规格 Out of Scope"其他脚本本次不动"，**本次只改 URL，未改一个字的内容**。 |
| `upgrade_openssh9.8p1.sh` | `d366a044…` | OpenSSH 源码编译升级。仅外联 `cdn.openbsd.org`（OpenSSH 官方发布站，取版本列表与源码包），无报信、无后门。另有一行 bilibili 视频链接，是 `echo` 给用户看的说明书，不发请求。 |
| `archive.key` | `f5f465c1…` | `BEGIN PGP PUBLIC KEY BLOCK`，XanMod 内核仓库的签名**公钥**。纯公开信息、无任何网络行为。文件名带 `.key`、内容像凭据，容易让人误会——当时已就这类"inert 项"在 README「后续事项」记账（该节后被仓库主人删除，内容见 git 历史）。 |

**fail2ban SSH 防御配置的收编结论**（另一个文件，收编而非现存，一并记在这里）：sha256 `7248195336a4efb527aa10ac3b489f4850c9d2a6969bdb080d7769ceec343321`，109 字节，全文是一个静态 jail 配置 `[sshd]`（`enabled = true`、`port = ssh`、`logpath = /var/log/secure`、`backend = %(sshd_backend)s`，另有一行注释掉的 `filter`）。**零域名、零 IP、零可执行代码**，取回后原样收编，一个字都没改。它在仓库里叫 `fail2ban-ssh.conf`，下发到用户机时仍叫 `centos-ssh.conf`（见术语表"部署文件名"）。

**这份审计没有覆盖的东西**：两个 TG 通知脚本**运行时**的行为（它们的外联与发送内容，见上表与 ADR-0001 的边界）；以及取内容 URL 之外、文件自身可能携带的第二层依赖。它们当时留给 README「后续事项」第 1 条对应的工单（该节后被仓库主人删除，内容见 git 历史）。

## Considered Options

- **保持指向原作者**：内容不变最省事。否决——上面说的隐性依赖原样存在，净化版的行为仍受原作者单方面改动影响。
- **改指第三方镜像**：换个公共代理。否决——只是把依赖从原作者换成另一个不受我们控制的第三方，问题没有消失。
- **改指本仓库（选定）**：fork 是 one-way 关系，我们从此完全掌控下发内容；配合守门脚本，这条边界可机械验证。
- **全部收编后不再下发、改为脚本内联**：连 URL 一起消灭。否决——工作量大得多，且脚本里塞大段配置/docker 编排可读性差，不划算。

## Consequences

- `kejilion.sh` 里指向原作者域名与作者组织仓库的取内容 URL 清零；留下的 5 个全部形如 `raw.githubusercontent.com/howi3c/sh/main/…`。
- 守门有两处：`tests/test_network_inventory.sh --assert-clean` 新增"原版名下 URL 清零 + 留存 URL 指向本仓库"断言（URL **路径级**判定，因为 `raw.githubusercontent.com` 对 `kejilion/*` 与 `howi3c/*` 是同一主机，只比主机名分不出来源）；`tests/test_spec15_slim_down_removed.sh` 从"已删功能不许回来"的角度守同一批 URL——判据本身只实现一次（在清点检查里），删除守卫直接调用它，不重抄正则与目标清单。
- **两个 TG 脚本自带的外联没有被动过**。它们运行时还会查 `ipinfo.io`、`ipv4.ip.sb`、`opendata.baidu.com`，并把 IP 归属地经用户自己的 TG bot 发出。URL 改指只解决"从哪取"，不解决"取下来的内容会做什么"——当时在 README「后续事项」第 1 条继续记账、等单开工单治理（该节后被仓库主人删除，内容见 git 历史）。这是有意的取舍：规格 Out of Scope 明确"其他脚本本次不动"。
  其中 `TG-check-notify.sh` 已逐行通读并**判定不立项**：它只采集本机自己的信息、发出去的 IP 是打码的，与主脚本里 12 处同类用法同性质；只有 `TG-SSH-check-notify.sh` 留在待办里（它发的是登录方的完整未打码 IP）。

> **2026-10-10 结案（仓库主人裁定，不立项）**：全仓安全审计后，仓库主人明确 `TG-SSH-check-notify.sh` 查询登录 IP 归属地**是功能本意，不是缺陷**——登录通知的意义就在于把"谁、什么时间、从哪个 IP、哪个地区、用哪个账号登了这台机器"送到管理员自己的 Telegram bot；`opendata.baidu.com` 那一跳只是把访客 IP 换成地区文字，送出的对象始终是用户自己的 bot，不构成把机器主人的信息发给第三方。与已判定不立项的 `TG-check-notify.sh` 同性质闭合（残留观察项仅"该接口走明文 HTTP"一层，若接口支持 HTTPS 属零成本加固，不影响本结案）。
- 有人往 `kejilion.sh` 里加回指向 `kejilion/*` 或 `gh/dl/docker.kejilion.pro` 的 URL 时，总门会直接红。
- 仓库净增 1 个文件：`fail2ban-ssh.conf`（部署到用户机时仍叫 `centos-ssh.conf`，见术语表"部署文件名"）。

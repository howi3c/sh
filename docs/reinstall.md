# Debian/Ubuntu 安全重装（#27）

> **这是会覆盖整块磁盘的功能，不是备份工具。** 自动验收使用隔离环境；没有执行真实重装，不能据此承诺不会失联。使用前必须备份，并确认云控制台/救援入口可用。

## 入口与范围

系统工具 → 一键重装系统，或 `k dd` / `k 重装`，仍进入同一菜单。只有 Debian/Ubuntu 改用本仓库的 `reinstall.py` 兄弟文件；其他系统保持既有分发行为，**不在本次安全背书范围**。

主脚本内固定兄弟文件的 Git 提交和 SHA256（文件内容指纹）。只允许验证证书的 HTTPS，不跟随重定向；执行前核对主脚本内的指纹，不从同一响应另取一个可一起替换的校验值。直接运行 `reinstall.py` 相当于信任本地副本；推荐从菜单进入。最初取得的主脚本及正在运行的源系统仍是信任基础，本功能不能修复已被攻陷的源主机。

## 支持矩阵

以下“支持”指实现及离线配置/流程验收范围，不代表真实启动、擦盘或远端 SSH 已实测。

| 目标 | 固定材料 | 维护状态（2026-10-17 核对） | 自动验收 | 真实重装 |
| --- | --- | --- | --- | --- |
| Debian 12 | 12.15，安装器 `20230607+deb12u15` | LTS 至 2028-06；具体软件包依 Debian LTS 覆盖政策 | 隔离环境 | 未执行 |
| Debian 13 | 13.7，安装器 `20250803+deb13u7` | 稳定版、常规安全维护 | 隔离环境 | 未执行 |
| Ubuntu 22.04 LTS | 22.04.5 live-server ISO | 标准维护至 2027-05 | 隔离环境 | 未执行 |
| Ubuntu 24.04 LTS | 24.04.5 live-server ISO | 标准维护至 2029-05 | 隔离环境 | 未执行 |
| Ubuntu 26.04 LTS | 26.04.1 live-server ISO | 已正式发布，标准维护至 2031-05 | 隔离环境 | 未执行 |
| Debian 10/11 | 不提供 | 未收录满足本路径要求的材料及维护方案 | 拒绝用例 | 不适用 |
| Ubuntu 20.04 | 不提供 | 标准维护结束，不自动引入商业扩展维护 | 拒绝用例 | 不适用 |

### 源主机条件

- 源系统：Debian 12/13 或 Ubuntu 22.04/24.04；root 权限，正在使用的真实 SSH 会话（`SSH_CONNECTION`）。
- 架构及引导：amd64，BIOS，已有可直接读取根分区的 GRUB i386-pc，支持 `next_entry` 一次性启动。UEFI、Secure Boot、其他引导器不支持。
- 磁盘：恰好一块非移动磁盘，简单 ext4 根分区，`/boot` 在同一根文件系统；可有 swap，以及（GPT 时）BIOS 嵌入分区。GPT 磁盘没有嵌入分区时，只接受 `/proc/cmdline` 含绝对路径 `BOOT_IMAGE=`（磁盘引导器加载内核的证据；是否 GRUB 由后续引导检查复核）的源主机；无此证据则拒绝。拒绝独立 `/boot`、LVM、RAID、加密根、其他数据分区、多盘及 2 TiB 以上磁盘。**新目标会使用 MBR + ext4 并覆盖整盘。**
- 网络：一块直接连接的 Ethernet 网卡，恰好一个 IPv4 地址、同子网网关、一个默认路由及对应直连路由，1–3 个明确的上游 IPv4 DNS。支持 DHCP 或静态 IPv4；拒绝 /31、/32、特殊主机路由、策略路由、多网卡、隧道/桥接/bond/VLAN、IPv6 管理及带全局 IPv6 的双栈配置。仅有 link-local IPv6 不算可用 IPv6 支持；安装及目标显式禁用 IPv6。
- Debian 至少 1 GiB RAM / 8 GiB 磁盘；Ubuntu 至少 6 GiB RAM / 16 GiB 磁盘，另须满足 **ISO 大小 + 3 GiB** 内存余量；实际材料和启动分区空间也会检查。Ubuntu 的 ISO 必须完全复制到 RAM，解除源盘挂载及 loop 依赖后才可分区。
- 依赖须事先具备：Python 3.9+、curl、gpgv、OpenSSL、ssh-keygen、iproute2、util-linux、GRUB 工具；Ubuntu 另需 xorriso。预检不会自动安装软件或修复引导器。

无法证明上述条件时拒绝，不通过猜磁盘、查公网 IP、改回 22 端口或临时开放所有端口“兼容”。DHCP 保留的是同一 MAC 的申请策略，**不保证新租约、DNS 或公网映射不变**；必须自行核对 DHCP 地址保留、外部 NAT 和云安全组。安装器与目标统一使用 `eth0` 命名参数并按实际 MAC 生成配置。

## 材料认证与运行时规则

本仓库没有收编或执行原先两个外部安装项目的代码；重装策略、配置和启动钩子为本仓库控制的代码，适用根目录 Apache-2.0 许可。Debian/Ubuntu 原生安装器、内核及其中程序保留各自发行版许可证，不在仓库中复制其二进制。

### Debian

认证链：内嵌专用公钥 → `InRelease` 签名 → Release 中固定版本 `images/SHA256SUMS` 的长度和 SHA256 → `netboot/debian-installer/amd64/linux` 与 `initrd.gz`。必须匹配 codename、amd64、审查过的点版本；校验 Release 时间，拒绝过期或超出一年维护窗口的材料。固定版本不再被当前清单覆盖时停止，等待本仓库审查更新，不回退归档。

- 发布入口：`https://deb.debian.org/debian/dists/{bookworm,trixie}/InRelease`。
- Debian 12 主密钥：`B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8`。
- Debian 13 主密钥：`04B54C3CDCA79751B16BC6B5225629DF75B188BD`。
- 独立指纹出处：[Debian 发布密钥](https://ftp-master.debian.org/keys.html)、[12 密钥公告](https://lists.debian.org/debian-devel-announce/2023/03/msg00001.html)、[13 密钥公告](https://lists.debian.org/debian-devel-announce/2025/04/msg00001.html)。专用 keyring 还含这两版 Release 签名钥，以验证同一 Release 的多重签名；不是信任整台主机的任意公钥。

从**已认证的 initrd**保存原生 GNU wget 和 archive keyring；受控 wrapper 限制 HTTPS 主机、证书、超时和重定向。安装组件仍走发行版已签名的 Release/Packages 链；不手动按文件名下载解包额外程序。

原生 bootstrap-base 在 HTTPS 分支可能传 `--no-check-gpg`：分区前加载经过发行版认证的 debootstrap，受控 wrapper 去掉此参数，强制 `--force-check-gpg` 及原生 archive keyring。缺少该能力则停止。第一轮目标 APT 更新前安装 TLS/禁止重定向策略；禁用原生硬编码 HTTP 的 security 源生成器，随后仅加入明确的 HTTPS security/updates 源并执行认证更新。HTTP APT 方法被本路径明确拒绝，HTTPS 保留发行版原生方法；新系统以后更换相关包时应保留 HTTPS 源和策略。

### Ubuntu

认证链：内嵌专用 CD 公钥 → `SHA256SUMS.gpg` → `SHA256SUMS` 中固定 live-server ISO → 从该 ISO 提取 `casper/vmlinuz`、`casper/initrd`。不因 netboot tar 也在发布目录就信任未被签名清单覆盖的材料。

- 发布入口：`https://releases.ubuntu.com/{22.04,24.04,26.04}/`。
- CD 主密钥：`843938DF228D22F7B3742BC0D94AA3F0EFE21092`。
- 独立指纹出处：[Ubuntu 验证教程](https://ubuntu.com/tutorials/how-to-verify-ubuntu)。内嵌公钥去除了不参与身份认证的第三方认证签名，保留主钥、UID 和自签名。

本地 initramfs 钩子把私有自动安装配置带入 live 根系统；不需要远程配置服务器或公开进度页。固定发行版 HTTPS APT 源、证书及签名策略，禁止安装器刷新和额外 snap/驱动/OEM 取内容；live 环境禁用 cloud 数据源探测、外部 NTP、崩溃上报，阻止 geoip 查询，保留 snapd 本地 API 但限制其网络。安装前检查 RAM 中的介质及源盘释放状态；失败仅给控制台诊断，不自动反复重启。

## 账号、确认与撤销

1. 独占锁贯穿流程；只读预检系统、磁盘、引导、实际网络、`sshd -T`、实际监听及当前连接端口。原 helper 的 22 端口回退不是可接受证据。
2. 建立随机、管理员私有的工作目录，不采纳当前目录旧脚本、缓存、上次状态或符号链接。发现旧准备目录/启动项时拒绝自动重入并提示检查。
3. 输入普通管理账号。默认选择公钥方案，核对由 ssh-keygen 解析的指纹并明确确认持有私钥；没有有效公钥则停止。只有明确输入 `PASSWORD` 才进入兼容模式，要求两次输入不少于 16 字符的唯一自设密码。没有公开固定密码，也不把秘密放在命令行参数或普通输出中。
4. 公钥方案禁止密码 SSH，账号用本次生成的不可猜测密码哈希保持可登录状态，为这一个管理员配置免密码 sudo；密码方案按自设密码登录和 sudo。禁止 root SSH。保留实际管理端口，处理 Ubuntu socket activation，检查 SSH 配置、sudoers 与必要的 ufw SSH 放行；不关闭 AppArmor、不清空防火墙、不开放所有端口。
5. 认证和准备后展示版本、磁盘、BIOS、网络、DNS、账号、端口、认证方式和备份/控制台提醒。安装期间 SSH 断开，安装环境本身不开放 SSH。输入 **`ERASE /dev/目标盘`** 才是最终同意；空输入、无效输入、EOF 均不提交。
6. 最终确认后重新检查主机事实，备份 GRUB 配置和环境，创建唯一启动项，检查生成配置，使用 `grub-reboot` 的一次性启动；只有全部成功才请求重启。正常系统的持久默认启动不改成安装器。
7. 失败、取消或可捕获中断撤销本次启动变更并清理私有材料。撤销/清理失败明确警告，并保留恢复备份。SIGKILL、掉电等无法执行清理的情况不冒充已撤销；下次发现遗留状态会拒绝继续。**此时不要盲目重启或删除目录**，按提示用控制台恢复 `grub.cfg.before`、`grubenv.before` 及本次入口，再清理本次目录。

覆盖磁盘之后不能恢复旧系统；安装故障只能通过控制台诊断和救援。重启命令返回成功仅表示已请求启动安装，**不是安装完成、SSH 可用或不会失联的证明**。

## 验证与已知限制

必需自动验收：`bash tests/run_all_checks.sh --no-detail`。新增用例依赖 Python 3、gpgv、ssh-keygen、OpenSSL，全部离线且无需 root。缺少依赖直接报错，不静默跳过。测试从现有菜单进入，替换主机/传输/引导等操作系统边界，使用真正 OpenPGP 签名夹具与 gpgv 校验，并检查生成配置和启动事务；不下载、写真实块设备、改本机网络/SSH/防火墙/引导或重启。合成 ISO 的提取由隔离边界替代，不等同于真实 ISO 启动测试。

补充研究实际验证了当时两个 Debian `InRelease`、其覆盖的 SHA256SUMS 和 netboot 材料，以及三个 Ubuntu SHA256SUMS 签名。此联网研究不是必需自动测试，也未执行任何下载的安装程序。

代码审查分为规范与工单符合度两条线。审查发现并修复了三个真实启动语义问题：保留 `reboot → systemctl` 的调用名、避免覆盖 Debian 13 原生 `bin → usr/bin` 链接、把本次安装条目排在正常 GRUB 条目之后而不改变默认第 0 项。后两项在现有菜单验收中补了先失败再修复通过的回归断言；还对两个已认证的真实 Debian initrd 做了覆盖层路径冲突核对。规范审查的两项非阻断建议（重复 APT 策略、把账号密码哈希与密码登录方式混为一谈）也已收敛。复审未发现新的阻断级问题，但没有验证真实启动时序。

### 本次交付记录（2026-10-17）

- 仓库总验收 **18/18 通过**；新增安全业务验收 12 个测试方法，涵盖多组成功/拒绝/故障场景，另有菜单分发及固定版本启动器验收。
- Python 编译及 Bash 语法检查通过；原有 ShellCheck 输出依仓库既有规则仅报告，不代表全库 lint 清零。
- 主脚本清点：报信 0、作者代理取内容 0；其他系统的分发代码未改。
- 复现命令：`bash tests/run_all_checks.sh --no-detail`（须具备上述依赖）。本开发环境缺少全局 gpgv，因此从发行版软件包提取到私有临时工具目录并通过 PATH 提供，未提权、未安装到宿主系统；必需验收本身完全离线。
- 模块修正版固定于提交 `457f8ca743b5cbc2c8e118ac1f50e2b8d0dba0ef`，SHA256 为 `9565624aff7333fa531b90769a037d638ae8f194c7aa4a8d715591990a177538`。入口提交 `01e5f13` 引用该版本；这些提交须进入本仓库远端后，线上菜单才能取到这份兄弟文件。

**真实重装：未执行，当前环境不具备带控制台、可安全销毁且获授权的隔离虚拟机条件。** 未从独立客户端验证任何版本的真实启动、登录、sudo、端口或网络；所有硬件/云平台、驱动、原生安装器完整启动时序及不同 DHCP 服务行为仍未实测。不会因此要求用户额外试装才能验收，也不能把隔离成功当作端到端可用性保证。

可选补充验证必须使用可销毁虚拟机，保留控制台和独立客户端，记录版本/架构/BIOS/磁盘/网络组合，实际登录并确认 sudo、预定端口和网络。禁止使用开发机或生产 VPS 直接试装。

### 补充修正记录（2026-10-19，工单 #28）

- 真实源机暴露误拒：BIOS 固件 + 单块 GPT 磁盘（一个 ext4 根分区、无 BIOS 嵌入分区），但 `/proc/cmdline` 含 `BOOT_IMAGE=/boot/vmlinuz-…`，即运行内核确由磁盘引导器加载（本实例为磁盘 GRUB）。原检查仅凭“GPT 无嵌入分区”拒绝。现改为：GPT 无嵌入分区时要求 `/proc/cmdline` 含绝对路径 `BOOT_IMAGE=`，无该证据才拒绝；目标盘仍按 MBR 重建，`grub-reboot` 一次性启动路径不变。
- 验收：入口级回归用例新增 1 个（GPT + 磁盘引导器证据 → 走到最终确认并 arm；无证据 → 在下载材料/改动引导前拒绝）；两轴审查跟进再加 2 个生产事实采集测试（`HostFactBoundaryTests`，直接执行 `_storage()`/`inventory()` 钉住新键），`tests/reinstall_acceptance.py` 共 15 个测试方法。`bash tests/run_all_checks.sh --no-detail` **18/18 通过**。
- 审查跟进还包含：提交前复核 `stable` 元组并入 `pttype`/`bios_embedding`/`boot_cmdline`；证据函数改名 `_disk_bootloader_loaded_kernel`（`BOOT_IMAGE=` 只证明磁盘引导器加载，是否 GRUB 由 `_grub()` 复核），文档与提示同步；夹具默认改为“无 `BOOT_IMAGE`、无嵌入分区”，条件写反会红；补最终确认断言；`GLOSSARY.md` 记入模块固定版本、一次性启动、BIOS 嵌入分区。
- 模块修正版固定于提交 `eb6908b90c70ad54978ad1e7e7d09d8a0ebe111f`，SHA256 为 `83bdaebb19243efe55cb573868649dfb817453c410e7155365633366868ad8e5`。入口提交 `5283f9d` 引用该版本，取代 2026-10-17 记录的 `457f8ca`/`01e5f13` 与本日早前的 `613b375`/`4e8e2a7`。
- 真实重装仍未执行；本条修正不改变“重启请求成功 ≠ 安装完成/不会失联”的限定。

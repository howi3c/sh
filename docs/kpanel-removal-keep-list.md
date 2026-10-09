# 工单 #6 记录：闭源面板整块移除（保留清单）

_对应工单：#6（父工单 #1，用户故事 9、10）。原则依据：ADR-0001（保取内容、灭报信）、
GLOSSARY.md（报信 / 取内容 / 净化版 / 原版）。_

「闭源面板」指作者维护的 KPanel 网页管理面板及其核心：一个不在本仓库里的闭源二进制
`kejilion-node`，连同脚本里「下载它、每小时自动更新它、记录每次 SSH 登录」的整套机器。
本工单把这一整块从 `kejilion.sh`（及镜像 `cn/kejilion.sh`）里删掉；用户接受失去该网页面板
功能（用户故事 10），换取整脚本可审计。

> **如果你是因为「KPanel 不是删了吗，为什么 `tests/` 下还有 kpanel 测试」而打开本文档，
> 直接跳到第二节开头的警告框**：`kpanel` 在脚本里有两层含义。守护保留下来那套纯本地
> 适配器的测试已改名 `test_local_adapter_*`；唯一还带 `kpanel` 名的
> `tests/test_kpanel_main_menu_smoke.sh` 是反向守门人，专门盯被删掉的那一层不许回来。

## 一、删除范围（实测基线）

以下数字以集成分支 tip `696b55e` 的 `kejilion.sh`（32465 行）为基线实测得到：

| # | 删掉的块 | 位置（基线行号） | 规模 |
|---|---|---|---|
| 1 | 二进制下载/安装路径：`kpanel_node_*` 函数族 + 内嵌 updater 脚本与全部 unit 模板 | `kpanel_node_paths()`（11489）至 `kpanel_node_dispatch()` 收尾（13456） | 1973 行、78 个函数（52 个 `kpanel_node_*` + 26 个 heredoc 内的嵌套函数）、21 个 heredoc 模板 |
| 2 | 每小时自动更新任务 | `kpanel_node_update_schedule_enable/start/stop/disable()`、`kpanel_node_procd_cron_line()/procd_cron_write()`；updater 与 unit 模板里的 `kejilion-node-update.service/.timer`、`17 * * * * /usr/local/lib/kejilion-node/update-cron.sh` crontab 行、`/etc/periodic/hourly/kejilion-node-update` | 随第 1 项整体消失 |
| 3 | SSH 登录采集服务 | `kejilion-node-ssh-login.service`（systemd）/ `kejilion-node-ssh-login`（OpenRC）/ procd 同名单元的写入代码、`kpanel_node_activate()` 里的 enable/start、`ssh-login-broker` 执行命令与 `/run/kejilion-node-ssh/ssh-login.json` 采集落点 | 随第 1 项整体消失 |
| 4 | 菜单与 CLI 入口 | 主菜单 `kejilion_sh()`：第 17 项「KPanel Web管理面板」两行渲染 + 已安装状态变量 `kpanel_menu_status`（读 `/home/docker/appno.txt`）+ `17) linux_panel kpanel ;;`；`k_info()` 帮助行「KPanel管理 k app kpanel」；`k kpanel` CLI 的 `node` 分支（`join/status/update/uninstall`）与帮助文案里的 `node ...` | 主菜单 8 行 + CLI 3 行 + 帮助 1 行 |
| 5 | 协议门里属于轻节点的那一半 | `KJ_LIGHT_NODE_PROTOCOL` 的设置处（`$1 = kpanel && $2 = node` 时置 1）与 `kpanel_protocol_active()` 里的对应判断 | 5 行 |

删除后脚本里不再出现：`kejilion-node`、`KPanel/releases`、`KPANEL_NODE_`、`kpanel_node_`、
`ssh-login-broker`、`KJ_LIGHT_NODE_PROTOCOL`、`17 * * * *` 的轻节点 crontab 行（测试
`tests/test_kpanel_main_menu_smoke.sh` 逐条断言）。

**新增的两处拒绝（不是功能，是关门）**：`linux_panel()` 入口与交互 `*)` 分支各加一段
「应用编号 kpanel 一律拒绝，退出码 2」。原因：该二进制的真实安装入口不在本仓库，而是
`refresh_apps_catalog()` 从外部应用目录（github.com/kejilion/apps.git）拉下来的
`~/apps/kpanel.conf`——只删菜单项的话，`k app kpanel` 或在应用市场里手输 `kpanel` 仍能把它
装回来。拒绝发生在拉取应用目录之前，不产生任何网络请求。

## 二、保留清单（逐项：留下了什么、为什么它不碰该二进制）

> ### ⚠ 先读这一节：为什么 `tests/` 下既有 `test_local_adapter_*` 又有一个 `test_kpanel_main_menu_smoke.sh`
>
> 因为 `kpanel` 在脚本里是个**有两层含义的名字前缀**，守它们的测试据此分成两类名字：
>
> | 层 | 是什么 | 工单 #6 的处置 | 谁来守 |
> |---|---|---|---|
> | 第一层 | 闭源面板二进制 `kejilion-node`，连同它的网页面板、每小时自更新、SSH 登录采集 | **已删干净** | `tests/test_kpanel_main_menu_smoke.sh`——**反向**守门，断言其痕迹必须为 0 |
> | 第二层 | 一套**纯本地**的非交互适配器，`kejilion.sh` 里函数名仍带 `kpanel_` 前缀 | **按边界保留** | 守护它的测试已改名 `test_local_adapter_*`（工单 #12） |
>
> 第二层是"不弹菜单、一条命令直接调某个系统能力"的命令行接口，例如
> `k kpanel ssh-port 2222` 改 SSH 端口、`k kpanel dns 1.1.1.1` 写
> resolv.conf / systemd-resolved、`k kpanel disk` 管硬盘、`k kpanel f2b` 管 fail2ban。
> 它们只读写本机文件与系统服务，**不下载、不启动、不依赖那个二进制**。
>
> 所以 `tests/` 下那批 `test_local_adapter_*` 测试**不是残留**，删掉它们等于放弃对
> 上述还在用的功能的守护。逐个文件对应的保留能力见下面的 A/B/C 节。（它们的前身叫
> `test_kpanel_*`，文件前缀和被删的二进制撞了名，害得看 `tests/` 的人误会"KPanel 不是删
> 了吗"；工单 [#12](https://github.com/howi3c/sh/issues/12) 已把它们统一改名，git 用
> `mv` 保留历史，行为断言逐条未动。注意：被改的只是**测试文件名**，脚本里 `k kpanel ...`
> 的 CLI 入口与 `kpanel_*` 函数名是仍在运行的接口，一个没改。）
>
> 唯一的例外是 `tests/test_kpanel_main_menu_smoke.sh`：它**反向**断言二进制那一层的
> 痕迹（`kejilion-node`、`kpanel_node_`、`KPanel/releases`、`KJ_LIGHT_NODE_PROTOCOL`、
> 每小时 crontab 行）在脚本里**必须为 0**，是防将来有人把闭源面板加回来的守门人。它的
> 名字恰恰应当带 `kpanel`——这是**唯一**保留 `kpanel` 前缀的测试，专门盯这个名字对应的
> 东西不许回来。

脚本里 `kpanel` 前缀有**两种完全不同的含义**：下面保留的全是第二种——纯本地的系统管理
能力封装，不下载、不启动、不依赖那个闭源二进制；被删的是第一种——二进制本体及其网络界面。

### A. 协议门与非交互适配器（tests/ 下大量测试依赖它们）

| 保留项 | 为什么不碰该二进制 |
|---|---|
| `kpanel_protocol_active()` 及全部 `KJ_*_NONINTERACTIVE=1` 环境变量判断 | 它只是「这次调用是不是适配器协议」的开关，决定脚本跳过首屏副作用；读的都是本地环境变量，不发任何请求 |
| `k kpanel ssh-port / dns / system-resource / disk-management / network-operations / account-management / system-tuning / virus-scan` 七个 CLI 分支 | 对应 `kpanel_ssh_port_noninteractive()`、`kpanel_set_dns_noninteractive()`、`kpanel_dns_*`、`kpanel_system_resource_*`、`kpanel_disk_management_*`、`kpanel_network_operations_*`、`kpanel_account_*`、`kpanel_system_tuning_*`、`kpanel_virus_scan_*`：改 SSH 端口、写 resolv.conf / systemd-resolved、动 hosts/crontab/网卡/防火墙、管 fail2ban、管账号与公钥、病毒扫描，全是本机文件与服务操作 |

### B. 应用市场与 Docker 应用（主菜单 11，用户故事 19）

| 保留项 | 为什么不碰该二进制 |
|---|---|
| `linux_panel()` 无参分支（应用市场菜单、1~122 号内置应用） | 装的是 Docker 应用（portainer、nextcloud、1Panel 等第三方面板），安装时打印该面板自己的官网信息（用户故事 19） |
| `refresh_apps_catalog()`（拉取外部应用目录） | 是应用市场的数据源，对全部 150+ 个应用一视同仁；删了它整个应用市场塌掉 |
| `linux_panel()` 的 `*)` 第三方应用分支（按编号 source `~/apps/*.conf`） | 通用机制；唯一被点名拒绝的是 `kpanel`（见第一节新增拒绝） |
| `kpanel_app_*` / `kpanel_run_docker_app_*` / `kpanel_web_*` / `kpanel_ldnmp_*` 函数族 | Docker 应用的安装/卸载/端口/访问方式/证书/站点封装；`kpanel_web_certificate_*`、`kpanel_app_delete_sites()`、`kpanel_ldnmp_*` 等全是本机 Docker 与 Nginx 操作 |

### C. 本机服务与安全

| 保留项 | 为什么不碰该二进制 |
|---|---|
| `kpanel_f2b_*` / `f2b_install_sshd` / fail2ban 管理 | fail2ban 是本机服务，配置写在 `/etc/fail2ban` |
| `kpanel_dns_*`（含 WSL resolv.conf、`kpanel-wsl-resolvconf.service`） | 写本机 DNS 配置；那个 systemd unit 是「还原 KPanel 管理的 WSL DNS」的本地配置器，与闭源二进制无关 |
| `kpanel_system_tuning_*` | 换源/内核/DNS/防火墙调优；其中确有下载（linuxmirrors.cn 等第三方换源脚本），属取内容，与闭源二进制无关 |
| `kpanel_bbrv3_*`、`kpanel_virus_scan_*`（ClamAV 容器扫描）、`kpanel_test_catalog()` + `kpanel_run_remote_bash()`（测速项目录） | BBRv3、ClamAV、第三方测速脚本都是本机或公开取内容 |

### D. 相关但属于另一套组件的保留项

| 保留项 | 为什么不碰该二进制 |
|---|---|
| `kpanel_backup_center_dispatch()`（`k backup-center`，另被 Docker/Web 备份菜单调用） | 它调用的是 `/usr/local/libexec/kejilion-agent`——另一个二进制，且**本脚本从不下载它**（函数注释原文 "No downloaded helper or caller-supplied path"），与本工单要删的轻量节点是两套东西。若将来要清，应单开工单（符合用户故事 30「记入后续清单」的口径） |
| `kpanel_app_with_lock()` / `kpanel_app_lock_held()` / `kpanel_app_update_marker()` | 应用并行交互的 flock 锁与安装标记文件（`/home/docker/appno.txt`），被主菜单 11 与大量本地适配器复用；删了它们应用市场与适配器一起塌 |
| 文件顶部注释里 "Only the paired KPanel worker enables this protocol" | 描述上述锁协议的历史由来；机制本身已保留 |

## 三、随之删除的测试（守的是被删掉的功能，不留空守）

| 删除的测试 | 原因 |
|---|---|
| `tests/test_kpanel_light_node_smoke.sh` | 测轻节点 updater 内嵌脚本、unit 与服务分发，代码没了 |
| `tests/test_kpanel_light_node_update.py` | 在隔离文件系统里跑权威 updater（含真实下载/校验/回滚路径） |
| `tests/test_kpanel_light_node_dependencies.py` | 在 chroot 里测 join 的依赖 bootstrap |
| `tests/fixtures/kpanel-node-file-2ee9856.service` | 仅被上述 update 测试引用的旧版 unit 夹具 |

改写的尺子：

- `tests/test_kpanel_main_menu_smoke.sh`：从「硬断言 KPanel 入口必须在」改写为「入口必须
  消失 + 保留边界不塌 + 两个行为拒绝在位」；含一个 stub 化 harness，验证 `k app kpanel`
  与应用市场里手输 `kpanel` 都以退出码 2 拒绝且不拉应用目录。
- `tests/test_main_menu_noninteractive_smoke.sh`：仅从 `dispatch_cases` 删 `17` 一条、
  从渲染循环删 `17`（其余条目归其他工单/原样保留）。

## 四、对网络请求清点的影响

`bash tests/test_network_inventory.sh --records kejilion.sh` 的端点三元组
（类别/主机/类型）在删除前后**完全一致**：该二进制的下载地址在脚本里是变量拼接的
（`https://${github_host}/kejilion/KPanel/releases/...`），从未作为字面端点进入清点；
删除后这种拼接口子本身不复存在。基线产物 `tests/fixtures/network_inventory.*` 按约定不
由本工单刷新（等 #6/#7/#8 都落地后由主控统一刷一次）。

## 五、与并行工单的边界

- 主菜单只删属于本工单的行（17 项渲染行 + `kpanel_menu_status` + `17)` 分发行），不给
  别人的菜单项重新编号、不重排 echo。
- `kejilion.sh` 与 `cn/kejilion.sh` 同步改（`test_cn_script_sync.sh` 守）；cn 目录整体
  删除归工单 #10。
- `CONTRIBUTING.md` 里「KPanel 轻量节点运行时」一节描述的是已删除的运行时维护规则，
  本工单按约定不动其他文件，留待文档统一清理时处理。

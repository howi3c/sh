# kejilion.sh 净化版 · 验收报告（工单 #11）

_面向仓库主人。本文只记录**亲手跑出来的**结果；凡是没有跑出来的，一律写进「没验的部分」一节，
不做推测性结论。_

| 项 | 值 |
|---|---|
| 验收对象 | 集成分支 `purify/spec-15-slim-down`（含本轮八个删除工单 #16~#23 与一轮审查修复） |
| 九项检查实跑时的提交 | `7e770e8`（工单 #2~#10 的合并终点） |
| 报告落笔时的提交 | 本工单的三个新增提交（详见第八节）+ 交付前审查修复的一组提交（详见第九节）；全部只动文档与 `tests/` 下的尺子，**不碰 `kejilion.sh` 本体**，因此正文数字对这些提交都成立 |
| 目标脚本 | `kejilion.sh`，14172 行 |
| 单入口验收入口 | `tests/run_all_checks.sh`（本文提交后新增） |
| 判定口径 | `GLOSSARY.md`「报信 / 取内容」+ `docs/adr/0001-keep-content-fetching-strip-reporting.md` |
| 父议题规格 | 议题 #15（规格 #15「净化版瘦身」），其中 Testing Decisions 规定「VPS 冒烟由仓库主人执行，不在代理验收范围内」 |

## 一句话结论

十三项自动检查**全部通过**：报信 0 处、经作者代理的下载 0 处、取内容 107 处、参考链接 10 处，
主菜单 13 个编号入口逐个分派成功、语法合法。本轮（规格 #15）把 `kejilion.sh` 从 30229 行
削到 14172 行、顶层函数从 604 个削到 438 个，删掉的板块一个都没回来。剩下的只有一件事——
**把脚本传上 VPS 人工过目**（操作说明见 `docs/vps-smoke.md`）。

---

## 一、怎么复现

```bash
cd /home/howi/projects/sh
bash tests/run_all_checks.sh
```

这一条命令会依次跑完下面十三项，逐项打印 `PASS`/`FAIL`，最后给总体结论、当前基线数字，
并附上完整的对外端点清点明细。**任何一项失败，整条命令以非零退出**，可以直接当 CI 闸门。

只想看汇总不看清点明细时：

```bash
bash tests/run_all_checks.sh --no-detail
```

> 复现前提：仓库主人拿到的是同一个提交上的同一份 `kejilion.sh`。行号会随后续改动漂移，
> 本文记录的行号以工单 #24 落笔时的 `310f5d2` 为准。

---

## 二、当前基线数字

由 `bash tests/test_network_inventory.sh --summary kejilion.sh` 的同一套分类引擎数出
（`run_all_checks.sh` 只把这四个数读进来打印，不自己写统计逻辑、不改分类规则）：

| 口径 | 数值 | 说明 |
|---|---:|---|
| **报信** | **0 处** | 红线项，必须为 0 |
| 取内容 | 107 处 | 下载安装包、拉测速节点、查公网 IP 归属地；请求里不夹带用户信息 |
| 参考链接 | 10 处 | 脚本只是打印给用户看的链接，并不真发请求 |
| 经作者代理的下载 | 0 处 | 红线项，必须为 0 |

仓库里另固化了一份基线产物 `tests/fixtures/network_inventory.summary.txt`，
数字与上表一致（报信_处数=0、取内容_处数=107、参考链接_处数=10、经作者代理_处数=0），
全量记录在同目录 `network_inventory.records.tsv`（117 行，可直接 diff）。

### 改造前后对照（同一把尺子量的）

下面三列都是工单 #24 用**当前仓库里这一把尺子**（`tests/test_network_inventory.sh --summary`）
在三个版本上重跑的结果，不是抄旧报告：

| 口径 | 原版（`90d1b1f:kejilion.sh`，33125 行） | 净化版 · 本轮前（`4c5e44e`，30229 行） | 净化版 · 本轮后（`310f5d2`，14172 行） |
|---|---:|---:|---:|
| 报信 | 3 处（`api.kejilion.pro` 第 171、16421 两行上报 + `ipinfo.io` 第 166 行喂报信） | **0** | **0** |
| 取内容 | 338 处 | 324 处 | 107 处 |
| 参考链接 | 110 处 | 84 处 | 10 处 |
| 经作者代理的下载 | 142 处 | 0 | 0 |
| 顶层函数 | 689 个 | 604 个 | 438 个 |
| 主菜单编号入口 | 19 个（1–17、00、0） | 16 个（1–14、16、0） | 13 个（1–9、12、13、14、0） |
| `kejilion.sh` 行数 | 33125 | 30229 | 14172 |

> 「本轮后」一列就是本次规格 #15 瘦身后的终态，也就是本报告的验收对象。
> 原版那一列保留作历史对照：它证明尺子量得出报信（不永远是 0），也说明本轮到底削掉了多少。
> 报信那一格，工单 #2 落笔时按当时口径记的是 4 处；现在这把尺子对同一份原版量出 3 处，
> 差的一处是「Python 版附属报信触发点」那一类——那一类的检测随工单 #19 删除 OpenClaw
> 附属报信后一并退役（见清点输出里该分类下的说明）。两个数不矛盾，是判据演进，别混用。

#### 本轮净删除规模（按集成分支的第一父链逐段 diff 数出）

| 板块 | 净删行 | 删掉的顶层函数 |
|---|---:|---:|
| OpenClaw 与三类 AI 面板（工单 #19） | 5613 | 8 |
| 应用市场（工单 #17） | 5008 | 29 |
| LDNMP 建站（工单 #20） | 4289 | 106 |
| FRP 内网穿透（工单 #18） | 860 | 19 |
| 游戏开服与集群安装脚本（工单 #22） | 44 | 2 |
| network-optimize 外部脚本（工单 #21） | 35 | 1 |
| 入口层收敛（工单 #16：菜单、命令行、帮助、协议门） | 180 | 0 |
| 孤儿收敛（`restore_defaults()`，工单 #21 的后续提交 `f324d6b`） | 28 | 1 |
| 取内容收敛与领域资产（工单 #23） | 0 | 0 |
| **合计** | **16057** | **166** |

30229 − 16057 = 14172，与实测行数对得上；604 − 166 = 438，与实测函数数对得上。
规格 Further Notes 预估「删掉 8000 行以上」，实测超出近一倍。

---

## 三、报信十项 grep 级复核

规格要求逐项 grep 复核；下表每条都是在 `kejilion.sh` 上亲手跑过 `grep -c` 的结果
（连注释行一起数，**全部为 0**，因此连"注释里提一句"都没有）：

| # | 特征串 | 含义 | 命中 |
|---|---|---|---:|
| 1 | `send_stats` | 报信主函数及其调用点 | 0 |
| 2 | `ENABLE_STATS` | 报信总开关 | 0 |
| 3 | `api.kejilion.pro` | 作者上报端点 | 0 |
| 4 | `gh.kejilion.pro` | 作者下载代理域名 | 0 |
| 5 | `docker.kejilion.pro` | Docker 镜像里的作者代理 | 0 |
| 6 | `kejilion_Affiliates` | 广告专栏函数/入口/分发 | 0 |
| 7 | `permission_granted` | 首次运行许可状态变量 | 0 |
| 8 | `kejilion_update` | 自更新函数 | 0 |
| 9 | `kejilion-node` | 闭源面板二进制名 | 0 |
| 10 | `gh_proxy` | 作者代理前缀变量 | 0 |

复跑命令（把任一行粘到仓库根目录执行即可）：

```bash
for p in send_stats ENABLE_STATS api.kejilion.pro gh.kejilion.pro \
         docker.kejilion.pro kejilion_Affiliates permission_granted \
         kejilion_update kejilion-node gh_proxy; do
  printf '%-24s %s\n' "$p" "$(grep -c -- "$p" kejilion.sh)"
done
```

另外三项衍生复核，同样为 0：Python 版附属报信函数 `send_stat`、`kejilion_sh_log`（更新日志）、
`kejilion.sh.bak`（自更新前的备份回滚）。
本轮新增两项衍生复核，也都是 0：`restore_defaults` 与「还原默认设置」（内核调优菜单里那一项，
随工单 #21 的孤儿收敛一起退场，见第七节与 README「后续事项」第 9 条）、`cloudflare.conf`
里的凭据体检相关字样尚未扫（见第七节，没跑就不写数）。

> 工单 #2~#10 那十项特征串在「本轮前」的 30229 行版本上同样为 0——本轮删掉的板块
> （游戏、AI 面板、OpenClaw、应用市场、LDNMP、FRP、network-optimize）与报信无关，
> 报信早在工单 #4 就清零了，本节只是证明它没有Regression。

---

## 四、保留项核查（不能删过头的那些）

下表每一项都是工单 #24 亲手数出来的；「已删」一栏写清楚它随哪个板块退场，
免得下次有人再去找一个已经不存在的东西。

| 保留项 | 实测 | 判据 |
|---|---|---|
| fail2ban SSH 防御家族 | 33 个顶层函数（`f2b_*` 6 个 + `kpanel_f2b_*` 27 个），其中 `kpanel_f2b_manager_dispatch()` 等 27 个是工单 #23 收编配置时点名要守的 | 规格 Keep 清单：SSH 防御是保留功能；工单 #23 收编 `fail2ban-ssh.conf`（部署名 `centos-ssh.conf`） |
| 并发锁四件套 | `kpanel_app_lock_held()` 与 `kpanel_app_with_lock()` 各 13 处命中（1 处定义 + 12 处调用），资源白名单 `system\|catalog\|markers` 在 `kejilion.sh` 第 31 行 | 规格 Implementation Decisions 点名"并发锁基础设施一律保留" |
| `KJ_*_NONINTERACTIVE` 纯本地适配器 | 11 个：`KJ_SSH_PORT`、`KJ_DNS`、`KJ_SYSTEM_RESOURCE`、`KJ_DISK_MANAGEMENT`、`KJ_NETWORK_OPERATIONS`、`KJ_ACCOUNT_MANAGEMENT`、`KJ_F2B`、`KJ_SYSTEM_TUNING`、`KJ_VIRUS_SCAN`、`KJ_BBRV3`、`KJ_TEST` | 工单 #6 保留清单：只读本地环境变量，不下载、不依赖闭源二进制 |
| 功能内视频教学链接 | 8 个去重 URL（7 个 bilibili + 1 个 youtu.be） | 用户故事 17：没有文字说明的功能仍有说明书 |
| 「借用的脚本」致谢 | 2 个位置共 5 行：重装系统页第 3598~3600 行三行 + 两处「该功能由jhb大神提供」 | 用户故事 28：署名不是广告 |
| 内核优化菜单入口 | `k nhyh` 帮助行仍在（`k_info()` 里唯一保留的调优面板入口） | 规格「内核调优剩余项」 |
| SSH 防御程序的部署文件名 | `--output centos-ssh.conf` 仍在 | 删除守卫显式断言，见第六节 |
| 取内容 URL 指向本仓库 | 5 处，全部形如 `raw.githubusercontent.com/howi3c/sh/main/…`：`TG-check-notify.sh`、`TG-SSH-check-notify.sh`、`upgrade_openssh9.8p1.sh`、`archive.key`、`fail2ban-ssh.conf` | ADR-0002：取内容只从本仓库 |

随板块退场、已从旧表撤下的项（写在这里备查，**不要再去找**）：

| 原保留项 | 去哪了 |
|---|---|
| `ipinfo.io` 查询 12 处 | 现在 9 处非注释行。少掉的 3 处在已删板块里（应用市场/AI 面板的归属地展示），系统信息查询那一处仍在 |
| 教学视频 11 个 | 现在 8 个。少掉的 3 个是 LDNMP 建站区（Cloudreve、poste.io、雷池 WAF），随工单 #20 退场 |
| 应用市场 122 个内置应用 + `install_panel()` | 随工单 #17 整块删除，主菜单 11 与 `k app` CLI 分支部一并退役 |
| `KJ_WEB` / `KJ_LDNMP` / `KJ_APP` 闸门 | 随工单 #20/#17 退役；`KJ_APP_*` 系列的 `KJ_APP_CONCURRENCY` / `KJ_APP_LOCKS_HELD` 仍在，那是上面那张表的并发锁四件套，与应用市场是两回事 |
| 「官方参考入口（API 厂商推荐列表）8 个」 | 原在 OpenClaw 机器人管理面板里（`主菜单 11 → 114 → 6 → 5`），随工单 #19 整体移除；返利参数清扫仍由 `tests/test_ads_stripped.sh` 自动守着 |

> 顺带一句：`kejilion.sh` 里「隐私」字样现在为 0——工单 #11 那会儿仅剩的 5 处都是应用说明
> 文案（nostr、whisper、searxng、Umami、思源笔记），它们都在应用市场板块里，随工单 #17 走了。

---

## 五、十个工单各自的验收结论

本轮工单按集成分支的合入顺序排；每行的数字都是工单 #24 用 `git diff <merge>^1 <merge>`
（函数数用两棵树的函数名集合差）数出来的，不是抄各工单当时的自述。

| 工单 | 做了什么 | 实测数字 |
|---|---|---|
| #16 入口层收敛 | 菜单渲染与分发行、CLI 分发、`k_info()` 帮助、协议门四个入口层清零已删板块 | 净删 180 行、0 个函数；主菜单 16 → 13 个编号入口（撤下 10 建站、11 应用市场、16 游戏）；`k_info()` 里 `k frps`/`k frpc`/`k web`/`k wp`/`k ssl`/`k app`/`k ldnmp` 全部 0 命中，`k nhyh` 保留 |
| #18 FRP 内网穿透 | 服务端配置生成族 + 增强功能模块 + 仅被它调用的两个端口助手整块删除 | 净删 860 行、19 个函数（`frps` 族 + `frpc_panel`/`configure_frpc` 等）；`frps`/`frpc` 特征串 0 命中 |
| #21 network-optimize | 外部脚本的本体、下载执行它的两个菜单项、钉版本常量与下载函数一并删除 | 净删 35 行、1 个函数；`network-optimize.sh` 文件与 `KPANEL_SYSTEM_TUNING_NETWORK_COMMIT` 常量均 0 命中 |
| #21 后续（孤儿收敛） | 调用方归零的 `restore_defaults()` 被清掉 | 净删 28 行、1 个函数；这是本轮唯一一处**保留能力实质减少**——内核优化菜单的「还原默认设置」不再有，已记入 README「后续事项」第 9 条 |
| #17 应用市场 | Docker 应用助手 23 个函数、面板安装器、yt-dlp 菜单、目录刷新与主菜单入口 | 净删 5008 行、29 个函数；`refresh_apps_catalog`/`应用市场`/`linux_panel` 均 0 命中；退役 6 个专项测试与 `apps/` 目录、1 份保留清单文档 |
| #19 AI 与 OpenClaw | 三类 AI 面板 + OpenClaw 机器人管理整块删除，含 12 个 Python 冒烟测试与矩阵脚本 | 净删 5613 行、8 个函数；`openclaw`/`moltbot`（忽略大小写）0 命中；删除 23 个文件（含 `tests/openclaw/` 12 个） |
| #22 游戏开服、集群项与孤儿文件 | 游戏开服菜单、集群"安装原作者脚本"两项 + 14 个仓库根孤儿文件 | 净删 44 行、2 个函数（`games_server_tools()`、`cluster_python3()`）；`palworld.sh`/`mc.sh` 这种"按 k 把原版脚本装回来"的重生路径彻底没有落脚点；`python-for-vps` 0 命中 |
| #20 LDNMP 建站 | 建站总函数族、证书续签、建站防护、MySQL/PHP 调优配置整块删除 | 净删 4289 行、106 个函数；`linux_ldnmp`/`ldnmp`/`LDNMP` 均 0 命中；删除 20 个文件（含 `ldnmp.sh`、两份 www.conf、两个证书续签夹具） |
| #23 取内容收敛与领域资产 | 5 个兄弟文件 URL 改指本仓库、收编 fail2ban SSH 防御配置、README 能力清单收敛、术语表补两条、发 ADR-0002、新增删除守卫 | `kejilion.sh` 0 增 0 删；新增 3 个文件（`docs/adr/0002-…md`、`fail2ban-ssh.conf`、`tests/test_spec15_slim_down_removed.sh`）；原版名下 URL 清零、留存 5 处全部指向本仓库 raw |
| #24 最终验收与交付（本工单） | 只动文档：验收报告定稿、README 后续事项补账、vps-smoke 通读核对 | `kejilion.sh` 与 `tests/` 一行未改；总门复跑 13/13 全绿，见第六节 |

八个删除工单合计：净删 16057 行、166 个顶层函数、66 个仓库文件；净增 3 个文件。

---

## 六、十三项检查的实跑结果

```text
PASS 1/13  缝 1 · 网络请求清点（报信清零闸门）   ← tests/test_network_inventory.sh --assert-clean
PASS 2/13  缝 2 · 非交互菜单冒烟（主菜单渲染与分发）   ← tests/test_main_menu_noninteractive_smoke.sh
PASS 3/13  缝 3 · 语法检查（bash -n，shellcheck 缺装则跳过）   ← tests/test_kejilion_syntax_check.sh
PASS 4/13  守门 · 广告清扫（工单 #8：返利与推广清空、教学链接/致谢保留）   ← tests/test_ads_stripped.sh
PASS 5/13  守门 · 更新功能整体删除（工单 #7）   ← tests/test_update_removed.sh
PASS 6/13  守门 · 闭源面板痕迹为零 + 本地适配器保留边界（工单 #6，应用市场退场后保留面收窄）   ← tests/test_kpanel_main_menu_smoke.sh
PASS 7/13  守门 · 作者代理拔掉、下载直连（工单 #5）   ← tests/test_direct_downloads.sh
PASS 8/13  守门 · 署名、命名与 README（工单 #9）   ← tests/test_attribution_naming.sh
PASS 9/13  守门 · 语言资产删除（工单 #10）   ← tests/test_language_assets_removed.sh
PASS 10/13  守门 · 测试命名（tests/ 不残留已删闭源面板的 kpanel 前缀，工单 #12）   ← tests/test_local_adapter_naming.sh
PASS 11/13  守门 · README 安装来源（脚本只从本仓库拉，不从作者域名拉回原版，工单 #13）   ← tests/test_readme_install_source.sh
PASS 12/13  守门 · README 不残留原版仓库引用（指向 kejilion/sh 的徽章/问题反馈/更新日志/Star History 与原作者钱包地址，工单 #14）   ← tests/test_readme_no_upstream_refs.sh
PASS 13/13  守门 · 删除守卫（工单 #15：已删功能词汇=0 / 根孤儿文件不存在 / 剩存取内容 URL 指向本仓库 / 与 README 守门交叉确认；工单 #24 起加守规格点名保留的零调用方函数仍在）   ← tests/test_spec15_slim_down_removed.sh

总体结论: 全部通过（13/13 项）
```

`bash tests/run_all_checks.sh` 实跑退出码 **0**；`bash -n kejilion.sh` 无输出（通过）；
`bash tests/test_network_inventory.sh --assert-clean` 两条断言 PASS；
`bash tests/test_spec15_slim_down_removed.sh` 单独跑输出 `spec15-slim-down-removed=pass`。

### 删除守卫的四类断言（`tests/test_spec15_slim_down_removed.sh`）

| 断言 | 名字 | 含义 |
|---|---|---|
| 1 | 已删功能词汇为零 | 20 个固定串 + 2 个忽略大小写串（`openclaw`、`moltbot`），只算非注释行，命中任何一个就 FAIL |
| 2 | 仓库根孤儿文件不存在 | 34 个随板块退役的文件（游戏脚本、AI 面板本体、LDNMP 配置、真孤儿、内联生成的仓库副本、`CONTRIBUTING.md` 等）一个都不许回来 |
| 2b | 保留的兄弟文件一个不少 | 6 个保留文件（两个 TG 通知脚本、`upgrade_openssh9.8p1.sh`、`archive.key`、`fail2ban-ssh.conf`、`cloudflare.conf`）缺任何一个就 FAIL——防删过头 |
| 2c | 规格点名保留的零调用方函数仍在 + README 记着账 | 三个函数（`remove_app_id`、`kpanel_app_update_marker`、`find_container_by_host_port`）定义在位，且 README「后续事项」里有它们与 `markers`、`catalog` 的记账要素 |
| 3 | URL 判据（调用而非重抄） | 直接调 `tests/test_network_inventory.sh --assert-clean`；顺带守 `--output centos-ssh.conf` 这个部署文件名没被改动 |
| 4 | 与 README 守门交叉确认 | 直接调两个 README 守门 + 一条轻量重合点（README 指向本仓库 raw 基址） |

### 反向验证：证明 Guard 真的会叫

在**临时副本**上做了四轮注入，每轮都确认 Guard 以退出码 1 FAIL 并点名，随后还原、复跑回 PASS。
仓库本体自始至终未被改动（`git status --short` 为空）。

| 轮次 | 在副本里做了什么 | Guard 的反应 |
|---|---|---|
| A | 往 `kejilion.sh` 尾部追加 3 行非注释内容，含 `install_moltbot`、`linux_ldnmp()`、`games_server_tools_menu` | FAIL 4 处，逐条带行号（14173/14174/14174/14174） |
| B | 删掉保留的兄弟文件 `TG-check-notify.sh` | FAIL 1 处：「保留的兄弟文件意外缺失: TG-check-notify.sh」 |
| C | 从 `kejilion.sh` 删掉 `remove_app_id()` 整个函数体 | FAIL 1 处：「规格点名保留的零调用方函数不见了: remove_app_id」 |
| D | 把 README「后续事项」节里的三个函数名与 `markers`、`catalog` 抹掉 | FAIL 5 处：「缺少零调用方保留函数的记账要素」逐条点名 |

四轮之后把副本的文件全部换回 `git show HEAD:<文件>`，Guard 回到 `spec15-slim-down-removed=pass`。

---

## 七、没验的部分（明确划界，不做无据结论）

1. **VPS 人工过目**：规格 Testing Decisions 原文规定「净化版上传后打开受影响菜单入口并退出、
   不真装任何东西，由仓库主人执行，不在代理验收范围内」。操作说明见 `docs/vps-smoke.md`。
2. **`shellcheck` lint**：本机未安装，按约定只跳过、不算失败；装上的机器上 lint 仅报告不阻断。
3. **取内容类外部服务的可用性与速度**：规格 Out of Scope 明确排除；大陆网络下直连变慢是已接受取舍。
4. **已安装闭源面板的系统上的清理**：只改脚本，不动任何现存机器状态（规格 Out of Scope）。
5. **两个 TG 脚本自带的外联未治理**：`TG-check-notify.sh`（`ipinfo.io`、`ipv4.ip.sb`、
   `api.telegram.org`）与 `TG-SSH-check-notify.sh`（另加 `opendata.baidu.com`）运行时仍会外联，
   且后者把完整未打码的登录 IP + 归属地经用户自己的 TG bot 发出。工单 #23 只改了 URL 指向，
   **一个字的内容都没动**（规格 Out of Scope）。审计结论见 ADR-0002，记账见 README 第 1 条。
6. **凭据体检没跑**：README 第 2 条建议的 `grep -rnE 'passwo?rd|secret|token|api[_-]?key'`
   全仓扫描本轮**没有执行**，因此这里不给任何"扫出来几条"的数字——要扫请照 README 那条做。
7. **本轮能力减少未做人工确认**：内核优化菜单的「还原默认设置」随工单 #21 消失
   （`restore_defaults()` 调用方归零后被收敛掉）。规格把它归入"内核调优剩余项"、判为可接受，
   但这是保留能力的一次实质减少，本报告只做记录，不替仓库主人判断影响；
   已记入 README「后续事项」第 9 条。

---

## 八、交付物与后续事项

本工单只改文档，未碰 `kejilion.sh` 的任何一行业务逻辑。

### 8.1 本轮净删除规模（工单 #16~#23 + 审查修复，固定点 `4c5e44e` → `310f5d2`）

| 项 | 数值 |
|---|---:|
| `kejilion.sh` 行数 | 30229 → 14172（净删 16057 行） |
| `kejilion.sh` 顶层函数 | 604 → 438（净删 166 个，净增 0） |
| 仓库 tracked 文件数 | 112 → 49（净减 63） |
| 文件级 diff | 新增 3 / 删除 66 / 修改 19 |

### 8.2 仓库文件清点

按 `git diff --name-status 4c5e44e...HEAD` 数出，三类分布：

| 类别 | 个数 | 明细 |
|---|---:|---|
| 新增 | 3 | `docs/adr/0002-content-fetching-only-from-this-repo.md`、`fail2ban-ssh.conf`、`tests/test_spec15_slim_down_removed.sh` |
| 删除 | 66 | 仓库根 33 个、`tests/` 下 32 个、`docs/` 下 1 个 |
| 修改 | 19 | 主脚本 1 个、README/GLOSSARY/验收报告/vps-smoke 4 份文档、总门编排与 11 把尺子、2 份清点夹具 |

删除的 66 个按去向归类：随游戏开服/AI 面板/LDNMP/FRP 退场的兄弟文件与配置 24 个
（`palworld.sh` 等 6 个游戏脚本、3 个 AI 面板脚本、`ldnmp.sh`、两份 www.conf、
两个证书续签夹具、`optimized_php.ini`、`beifen.sh`、`CF-Under-Attack.sh` 等）、
退役的测试与夹具 32 个（含 `tests/openclaw/` 12 个、6 个应用市场专项测试、8 个建站专项测试）、
真孤儿与内联副本 9 个（`Limiting_Shut_down*.sh`、`check_x86-64_psabi.sh`、`nginx.local`、
`valkey.conf`、`sshd.local`、两个 OpenClaw 冒灰脚本）、悬空文档与已退役资产 3 个
（`CONTRIBUTING.md`、`docs/kpanel-removal-keep-list.md`、`apps/README.md`）、
`PandoraNext/` 2 个、`network-optimize.sh` 1 个。仓库根现在剩 12 个文件：
主脚本 + 4 份文档（README/GLOSSARY/LICENSE/AGENTS.md）+ 6 个保留兄弟文件 + `update_log.sh`。

> 与规格 Further Notes 预估「净减约 40 个、净增 1 个」的差异：实测净减 63、净增 3。
> 主要原因是**退役的测试与夹具比预估多得多**——规格只估了"约 20 个"，实际随板块一起
> 退场了 32 个（`tests/openclaw/` 一整个目录 12 个、应用市场 6 个专项测试、
> LDNMP 建站 8 个专项测试、2 个证书续签夹具、4 个应用市场生命周期/镜像更新冒烟等）。
> 净增比预估多 2 个：规格只想到收编 `fail2ban-ssh.conf` 那一个文件，实际还新增了
> 删除守卫这把尺子（`tests/test_spec15_slim_down_removed.sh`，规格用户故事 37 要求）
> 与 ADR-0002 这份决策记录（工单 #23 的领域资产交付物）。

### 8.3 后续事项记账

还有什么没清的，见 `README.md` 的「**后续事项**」一节，共 9 条，每条都写了是什么、在哪、
为什么这次不动、建议怎么处理。本轮（工单 #24）在这 9 条之外没有新增遗漏项，
只做了三件事：第 4 条里 `kejilion-agent` 的行号从 29831~29842 / 11148 / 13524
校正到现在的 13925~13935 / 6754 / 13944（脚本瘦身后行号集体前移）；
第 7 条的四处行号（6 / 78 / 79 / 103）重核后仍准确，未改；
新增第 9 条记录 `restore_defaults()` 退场带来的能力减少。第 5、6 条是历史披露
（越界删除与重生路径），已分别随工单 #10/#22 处置完毕，不再作为待决事项。

本轮审查修复（固定点 `4c5e44e`，两轴共 10 项发现）修的东西见第九节。

---

## 九、两轮交付前审查修复（如实披露）

本轮规格一共做了**两轮**代码审查，两轮都只动文档与 `tests/` 下的尺子，`kejilion.sh` 一行未碰。

### 9.1 第一轮（工单 #11 时代，固定点 `7e770e8`，六项发现）

九项检查在修复前后都是 9/9 全绿、退出码 0；下表每项一个独立提交。

| # | 问题 | 改了什么 | 提交 |
|---|---|---|---|
| 1 | 术语漂移：新写内容里 7 处用错了指代词 | `README.md` 4 处、`docs/acceptance-report.md` 1 处、`tests/test_update_removed.sh` 2 处注释，同文件 `upstream_base` 顺带改名 `orig_base` | `80f3335` |
| 2 | 术语违反：清点检查的内部类型值叫 `telemetry-trigger` | `tests/test_network_inventory.sh` 改名 `report-trigger`，同步注释、awk、人读清单三处筛选、自测断言 | `5201813` |
| 3 | 坏味道：零增益纯转发的 wrapper `ask_assert_clean` | 删掉 wrapper，两处调用点直接调 `assert_clean_impl` | `bf4de13` |
| 4 | 轻度重复：按类别计数 + 经作者代理计数的 awk 写了两遍 | `test_network_inventory.sh` 新增 `emit_summary()` 与 `--summary` 模式；`run_all_checks.sh` 改调它。分类规则一字未动 | `d16e0ee` |
| 5 | 规格半成品：README 还描述已删功能 | 删「English Version」、「自动更新机制」条目、「KPanel Web 管理面板」整节与失效的过时描述附注 | `d9cef37` |
| 6 | 范围蔓延未披露 | 见 9.3 | 本提交 |

修复后自查：术语表口径下那个回避词在 `README.md`、`docs/`、`tests/test_update_removed.sh` 上命中 0；
`grep -rn 't[e]lemetry' tests/` 为 0；总门 9/9 全绿、`--assert-clean` PASS。

### 9.2 第二轮（本轮规格 #15，固定点 `4c5e44e`，两轴 10 项发现）

十三项检查在修复前后都是 13/13 全绿、退出码 0。这一轮由工单 #24 的审查修复分支
`purify/tkt-24-review-fixes` 的六个提交承载：

| 提交 | 修了什么 |
|---|---|
| `b197752` | 术语：清掉文档与测试注释里的回避词字面（上游/遥测），与第一轮修复 1 同一类问题在第二轮的复现 |
| `8f3de8c` | 尺子：URL 清零判据去双写——原先删除守卫抄了第二份同名正则与第二份 5 个取内容目标清单，改成直接调用 `test_network_inventory.sh --assert-clean`；顺带把 `ask_assert_clean` 式 wrapper 清掉 |
| `1c4fff0` | 修复：悬空引用与交叉引用失准——README 第 4 条里 `kejilion-agent` 的行号、第 2 条里 `archive.key` 的行号、术语表举例等随脚本瘦身后集体失效，逐条核对校正 |
| `cd14aa7` | 文档：ADR-0002 补录四个兄弟文件与 fail2ban 配置的审计结论（sha256 前缀 + 逐文件通读结论） |
| `a50d8e9` | 文档：README 补记三个零调用方保留函数（第 8 条）；删除守卫加守断言 2c（函数仍在 + 记账在位两头钉住） |
| `aaa51f1` | 文档：`docs/vps-smoke.md` 同步到终局菜单形态，删掉指向已删功能的核对路径 |

修完总门 13/13 全绿、退出码 0；删除守卫单独跑 `spec15-slim-down-removed=pass`。

### 9.3 第一轮披露的那处越界删除（历史记录）

工单 #10 删除七个语言副本目录的提交 `cb3d460`，把 `CONTRIBUTING.md` 里「主脚本与中文脚本」
整节（12 行）连同它指向的 `tests/test_cn_script_sync.sh` 一起删掉了——没有任何工单要求改
`CONTRIBUTING.md`，这是范围蔓延。当时裁定"不撤消、也不再改它"：那一节描述的两份脚本在
`cn/` 目录删除后已不存在，留着是假话。工单 #22 随后把整个 `CONTRIBUTING.md` 删除
（见 README 第 3 条），这一条的残响只剩历史记录。删除前内容在
`git show 75d4868:CONTRIBUTING.md` 与 `git show 7e770e8^:CONTRIBUTING.md` 都能取回。

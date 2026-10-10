# kejilion.sh 净化版 · 验收报告（工单 #11）

_面向仓库主人。本文只记录**亲手跑出来的**结果；凡是没有跑出来的，一律写进「没验的部分」一节，
不做推测性结论。_

| 项 | 值 |
|---|---|
| 验收对象 | 集成分支 `purify/spec-15-slim-down`（含本轮八个删除工单 #16~#23 与三轮审查修复） |
| 九项检查实跑时的提交 | `7e770e8`（工单 #2~#10 的合并终点） |
| 报告落笔时的提交 | 本工单的三个新增提交（详见第八节）+ 交付前三轮审查修复的一组提交（详见第九节）。前两轮只动文档与 `tests/` 下的尺子；**第三轮按规格判定规则删了 `kejilion.sh` 里三个零调用方函数（38 行）与孤儿文件 `update_log.sh`**，行数/函数数/文件清点等数字已按第三轮后的实测更新 |
| 目标脚本 | `kejilion.sh`，14168 行（第十节「k 快捷命令安装链」增量后；规格 #15 终态为 14134 行） |
| 单入口验收入口 | `tests/run_all_checks.sh`（本文提交后新增） |
| 判定口径 | `GLOSSARY.md`「报信 / 取内容」+ `docs/adr/0001-keep-content-fetching-strip-reporting.md` |
| 父议题规格 | 议题 #15（规格 #15「净化版瘦身」），其中 Testing Decisions 规定「VPS 冒烟由仓库主人执行，不在代理验收范围内」 |

## 一句话结论

十四项自动检查**全部通过**：报信 0 处、经作者代理的下载 0 处、取内容 108 处、参考链接 10 处，
主菜单 13 个编号入口逐个分派成功、语法合法。规格 #15 把 `kejilion.sh` 从 30229 行削到
14134 行、顶层函数从 604 个削到 435 个，删掉的板块一个都没回来；其后「k 快捷命令安装链
自落盘兜底」一项增量（见第十节）再加 34 行、顶层函数净增减 0、1 处取内容 URL，当前 14168 行（另整块删除地区开关死代码，见第十节）。
剩下的只有一件事——**把脚本传上 VPS 人工过目**（操作说明见 `docs/vps-smoke.md`）。

---

## 一、怎么复现

```bash
cd /home/howi/projects/sh
bash tests/run_all_checks.sh
```

这一条命令会依次跑完下面十四项，逐项打印 `PASS`/`FAIL`，最后给总体结论、当前基线数字，
并附上完整的对外端点清点明细。**任何一项失败，整条命令以非零退出**，可以直接当 CI 闸门。

只想看汇总不看清点明细时：

```bash
bash tests/run_all_checks.sh --no-detail
```

> 复现前提：仓库主人拿到的是同一个提交上的同一份 `kejilion.sh`。行号会随后续改动漂移，
> 正文引用的 `kejilion.sh` 行号以第三轮审查修复（工单 #25）后的集成分支 tip 为准；
> 引述历史记录（如 9.x 各轮、反向验证 A 轮）里的行号则是当时的值，按原文保留。

---

## 二、当前基线数字

由 `bash tests/test_network_inventory.sh --summary kejilion.sh` 的同一套分类引擎数出
（`run_all_checks.sh` 只把这四个数读进来打印，不自己写统计逻辑、不改分类规则）：

| 口径 | 数值 | 说明 |
|---|---:|---|
| **报信** | **0 处** | 红线项，必须为 0 |
| 取内容 | 108 处 | 下载安装包、拉测速节点、查公网 IP 归属地；请求里不夹带用户信息 |
| 参考链接 | 10 处 | 脚本只是打印给用户看的链接，并不真发请求 |
| 经作者代理的下载 | 0 处 | 红线项，必须为 0 |

仓库里另固化了一份基线产物 `tests/fixtures/network_inventory.summary.txt`，
数字与上表一致（报信_处数=0、取内容_处数=108、参考链接_处数=10、经作者代理_处数=0），
全量记录在同目录 `network_inventory.records.tsv`（118 行，可直接 diff）。

### 改造前后对照（同一把尺子量的）

下面三列都是工单 #24 用**当前仓库里这一把尺子**（`tests/test_network_inventory.sh --summary`）
在三个版本上重跑的结果，不是抄旧报告：

| 口径 | 原版（`90d1b1f:kejilion.sh`，33125 行） | 净化版 · 本轮前（`4c5e44e`，30229 行） | 净化版 · 本轮后（`310f5d2`，14172 行）+ 第三轮审查修复后（14134 行） |
|---|---:|---:|---:|
| 报信 | 3 处（`api.kejilion.pro` 第 171、16421 两行上报 + `ipinfo.io` 第 166 行喂报信） | **0** | **0** |
| 取内容 | 338 处 | 324 处 | 107 处 |
| 参考链接 | 110 处 | 84 处 | 10 处 |
| 经作者代理的下载 | 142 处 | 0 | 0 |
| 顶层函数 | 689 个 | 604 个 | 438 个 + 第三轮再删 3 个 = **435 个** |
| 主菜单编号入口 | 19 个（1–17、00、0） | 16 个（1–14、16、0） | 13 个（1–9、12、13、14、0） |
| `kejilion.sh` 行数 | 33125 | 30229 | 14172 + 第三轮再删 38 行 = **14134** |

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
第三轮审查修复（工单 #25）按规格判定规则又删了 3 个零调用方函数：14172 − 38 = 14134、
438 − 3 = 435，与当前实测对得上（累计净删 16095 行、166 + 3 = 169 个顶层函数）。
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
随工单 #21 的孤儿收敛一起退场，见第七节；能力减少一事当时记于 README「后续事项」第 5 条，
记账节已删，见 8.3 的现状说明）。原记账里「`cloudflare.conf` 里的凭据体检相关字样尚未扫」
一项，已由 **2026-10-10 的安全审计补做**：全文通读 + 引用检索判定该文件是全仓库零引用的孤儿
（`kejilion.sh` 从不下载它，GLOSSARY「兄弟文件」从未计入它），且 `[Init]` 段的 `cfuser`
是原作者邮箱占位、`cftoken` 是无效占位——已直接删除文件，扫凭据的动机随文件一并消失，
见 8.2 与断言 2b 的相应更新。

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
| 并发锁四件套 | `kpanel_app_lock_held()` 13 处命中（1 处定义 + 12 处调用）、`kpanel_app_with_lock()` 12 处命中（1 处定义 + 11 处调用），资源白名单 `system\|catalog\|markers` 在 `kejilion.sh` 第 31 行 | 规格 Implementation Decisions 点名"并发锁基础设施一律保留"（第三轮删掉 `remove_app_id` 后 `with_lock` 少 1 处调用，`markers`/`catalog` 分支从此无调用方；当时记于 README 第 8 条，该记账节已删） |
| `KJ_*_NONINTERACTIVE` 纯本地适配器 | 11 个：`KJ_SSH_PORT`、`KJ_DNS`、`KJ_SYSTEM_RESOURCE`、`KJ_DISK_MANAGEMENT`、`KJ_NETWORK_OPERATIONS`、`KJ_ACCOUNT_MANAGEMENT`、`KJ_F2B`、`KJ_SYSTEM_TUNING`、`KJ_VIRUS_SCAN`、`KJ_BBRV3`、`KJ_TEST` | 工单 #6 保留清单：只读本地环境变量，不下载、不依赖闭源二进制 |
| 功能内视频教学链接 | 8 个去重 URL（7 个 bilibili + 1 个 youtu.be） | 用户故事 17：没有文字说明的功能仍有说明书 |
| 「借用的脚本」致谢 | 2 个位置共 5 行：重装系统页第 3598~3600 行三行 + 两处「该功能由jhb大神提供」 | 用户故事 28：署名不是广告 |
| 内核优化菜单入口 | `k nhyh` 帮助行仍在（`k_info()` 里唯一保留的调优面板入口） | 规格「内核调优剩余项」 |
| SSH 防御程序的部署文件名 | `--output centos-ssh.conf` 仍在 | 删除守卫显式断言，见第六节 |
| 取内容 URL 指向本仓库 | 6 处，全部形如 `raw.githubusercontent.com/howi3c/sh/main/…`：`TG-check-notify.sh`、`TG-SSH-check-notify.sh`、`upgrade_openssh9.8p1.sh`、`archive.key`、`fail2ban-ssh.conf`、`kejilion.sh`（最后一项是第十节新增的 k 安装链自落盘） | ADR-0002：取内容只从本仓库 |

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
| #21 后续（孤儿收敛） | 调用方归零的 `restore_defaults()` 被清掉 | 净删 28 行、1 个函数；这是本轮唯一一处**保留能力实质减少**——内核优化菜单的「还原默认设置」不再有，当时记入 README「后续事项」第 5 条（该节后被仓库主人删除，见 8.3） |
| #17 应用市场 | Docker 应用助手 23 个函数、面板安装器、yt-dlp 菜单、目录刷新与主菜单入口 | 净删 5008 行、29 个函数；`refresh_apps_catalog`/`应用市场`/`linux_panel` 均 0 命中；退役 6 个专项测试与 `apps/` 目录、1 份保留清单文档 |
| #19 AI 与 OpenClaw | 三类 AI 面板 + OpenClaw 机器人管理整块删除，含 12 个 Python 冒烟测试与矩阵脚本 | 净删 5613 行、8 个函数；`openclaw`/`moltbot`（忽略大小写）0 命中；删除 23 个文件（含 `tests/openclaw/` 12 个） |
| #22 游戏开服、集群项与孤儿文件 | 游戏开服菜单、集群"安装原作者脚本"两项 + 14 个仓库根孤儿文件 | 净删 44 行、2 个函数（`games_server_tools()`、`cluster_python3()`）；`palworld.sh`/`mc.sh` 这种"按 k 把原版脚本装回来"的重生路径彻底没有落脚点；`python-for-vps` 0 命中 |
| #20 LDNMP 建站 | 建站总函数族、证书续签、建站防护、MySQL/PHP 调优配置整块删除 | 净删 4289 行、106 个函数；`linux_ldnmp`/`ldnmp`/`LDNMP` 均 0 命中；删除 20 个文件（含 `ldnmp.sh`、两份 www.conf、两个证书续签夹具） |
| #23 取内容收敛与领域资产 | 5 个兄弟文件 URL 改指本仓库、收编 fail2ban SSH 防御配置、README 能力清单收敛、术语表补两条、发 ADR-0002、新增删除守卫 | `kejilion.sh` 0 增 0 删；新增 3 个文件（`docs/adr/0002-…md`、`fail2ban-ssh.conf`、`tests/test_spec15_slim_down_removed.sh`）；原版名下 URL 清零、留存 5 处全部指向本仓库 raw |
| #24 最终验收与交付（本工单） | 只动文档：验收报告定稿、README 后续事项补账、vps-smoke 通读核对 | `kejilion.sh` 与 `tests/` 一行未改；总门复跑 13/13 全绿，见第六节 |

八个删除工单合计：净删 16057 行、166 个顶层函数、66 个仓库文件；净增 3 个文件。
第三轮审查修复（工单 #25）在此基础上再删 38 行（3 个零调用方函数）与 1 个孤儿文件
（`update_log.sh`），累计净删 16095 行、169 个顶层函数、67 个仓库文件；净增仍为 3 个。

---

## 六、十三项检查的实跑结果

> 本节是工单 #24 交付时的实跑记录（13 项尺子的原文转录），按"引述历史记录按原文保留"
> 的约定不回改；第十节增量后的现行项数以 `tests/run_all_checks.sh` 的 `ITEMS` 清单为准
> （十四项），十四项的实跑结果见第十节。

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
PASS 13/13  守门 · 删除守卫（工单 #15：已删功能词汇=0 / 根孤儿文件不存在 / 剩存取内容 URL 指向本仓库 / 与 README 守门交叉确认；工单 #16 点名自查词 cluster_python3、#22 漏网孤儿 update_log.sh 均在守）   ← tests/test_spec15_slim_down_removed.sh

总体结论: 全部通过（13/13 项）
```

`bash tests/run_all_checks.sh` 实跑退出码 **0**；`bash -n kejilion.sh` 无输出（通过）；
`bash tests/test_network_inventory.sh --assert-clean` 两条断言 PASS；
`bash tests/test_spec15_slim_down_removed.sh` 单独跑输出 `spec15-slim-down-removed=pass`。

### 删除守卫的四类断言（`tests/test_spec15_slim_down_removed.sh`）

| 断言 | 名字 | 含义 |
|---|---|---|
| 1 | 已删功能词汇为零 | 18 个固定串 + 2 个忽略大小写串（`openclaw`、`moltbot`），只算非注释行，命中任何一个就 FAIL（第三轮补入工单 #16 点名自查词 `cluster_python3`） |
| 2 | 仓库根孤儿文件不存在 | 34 个随板块退役的文件（游戏脚本、AI 面板本体、LDNMP 配置、真孤儿、内联生成的仓库副本、`CONTRIBUTING.md`、`update_log.sh` 等）一个都不许回来 |
| 2b | 保留的兄弟文件一个不少 | 原 6 个保留文件（两个 TG 通知脚本、`upgrade_openssh9.8p1.sh`、`archive.key`、`fail2ban-ssh.conf`、`cloudflare.conf`）；2026-10-10 安全审计删除零引用孤儿 `cloudflare.conf`（判定：主脚本从不下载、GLOSSARY「兄弟文件」从未计入、内含原作者邮箱占位；防复活改由断言 2 的 `orphan_files` 守）后为 **5 个**，缺任何一个就 FAIL——防删过头 |
| 2c | （已退役）规格点名保留的零调用方函数仍在 + README 记着账 | 第三轮审查修复按规格判定规则（以 grep 结果为准）删除了这三个函数，本断言随之退役，退役理由写在尺子文件里；README 第 8 条改为"已删 + `kpanel_app_with_lock` 两个空 resource 分支的说明" |
| 3 | URL 判据（调用而非重抄） | 直接调 `tests/test_network_inventory.sh --assert-clean`；顺带守 `--output centos-ssh.conf` 这个部署文件名没被改动 |
| 4 | 与 README 守门交叉确认 | 直接调两个 README 守门 + 一条轻量重合点（README 指向本仓库 raw 基址） |

### 反向验证：证明 Guard 真的会叫

在**临时副本**（或临时改动后还原）上做了六轮注入，每轮都确认 Guard 以退出码 1 FAIL
并点名，随后还原、复跑回 PASS。仓库本体自始至终未被改动（`git status --short` 为空）。

| 轮次 | 在副本里做了什么 | Guard 的反应 |
|---|---|---|
| A | 往 `kejilion.sh` 尾部追加 3 行非注释内容，含 `install_moltbot`、`linux_ldnmp()`、`games_server_tools_menu` | FAIL 4 处，逐条带行号（14173/14174/14174/14174；当时脚本 14172 行） |
| B | 删掉保留的兄弟文件 `TG-check-notify.sh` | FAIL 1 处：「保留的兄弟文件意外缺失: TG-check-notify.sh」 |
| C | 往 `kejilion.sh` 尾部追加 `cluster_python3() { :; }` | FAIL 1 处：「仍含已删功能词汇 [cluster_python3]」（第三轮补的工单 #16 点名自查词） |
| D | 在 CLI 分发块里插入 `cluster) cluster_python3 ;;` 分支 | 冒烟 FAIL 1 处：「CLI 分发块仍通向已退役板块[cluster_python3]」 |
| E | `touch update_log.sh` | FAIL 1 处：「仓库根孤儿文件仍存在: update_log.sh（规格 #15 已删除，不得复活）」 |
| F | 从 `kejilion.sh` 删掉 `kpanel_app_with_lock()` 整个函数体 | 删除守卫与总门 13 项均**不**叫（2c 已退役，没有"函数仍在"类断言为它守）。`tests/` 下另有两把**未挂总门**的行为尺子（磁盘管理 / 网络操作非交互冒烟）的代码路径要经过这个锁，在健康的机器上会把删过头暴露出来；但本机上这两把本来就因环境原因 FAIL（一把缺 `xxd`，一把要 root 级挂载校验），本地实跑分辨不出——按代码路径记录，不冒充本地验证 |

> A、B 两轮是上一轮（固定点 `4c5e44e`）的记录。上一轮还有两轮专项验证断言 2c 的注入
> （删 `remove_app_id()` 函数体、抹 README 记账要素）；本轮删除那三个函数**之前**，先把
> 第一轮复跑确认旧尺子确实见红（FAIL 3 处，逐条点名三个函数），然后才退役 2c——所以 2c
> 当时是真的在守，不是摆设。退役后这两轮不再适用，撤上表。C、D、E 是本轮新增；F 如实
> 记录 2c 退役后留下的空档（删除守卫不再为并发锁四件套守"函数仍在"）。

另附一条与本表相关的既有事实：`tests/` 下还有 15 把尺子没挂总门（各类非交互冒烟），
其中 2 把在本机因环境原因本来就 FAIL（缺 `xxd`、挂载校验要 root），与规格 #15 的改动
无关——在原始提交 `fba891b` 上复跑同样 FAIL。要不要把它们挂进总门或修环境，留给仓库
主人定，本报告只记账。

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
   **一个字的内容都没动**（规格 Out of Scope）。审计结论见 ADR-0002；此事当时记账于 README「后续事项」
   第 1 条（该节已删，内容见 git 历史，见 8.3）。
6. **凭据体检**：原 README「后续事项」第 2 条建议的 `grep -rnE 'passwo?rd|secret|token|api[_-]?key'`
   全仓扫描在报告定稿时**没有执行**，因此定稿版这里不给任何"扫出来几条"的数字。
   **2026-10-10 安全审计已补做**：全仓扫过一遍，命中只有三类——`cloudflare.conf` 的
   `cftoken = APIKEY00000`（无效占位，随该零引用孤儿的删除一并消失，见第三节与 8.2）、
   `archive.key` 的 PGP 公钥块（公开签名钥，不是私钥，ADR-0002 有结论）、
   两个 TG 脚本里的 `TELEGRAM_BOT_TOKEN`/`CHAT_ID`（用户自填占位文本，无预置凭据，
   ADR-0002 有结论）。未发现真凭据；定稿版的"没跑就不写数"划定自本项起作废。
7. **本轮能力减少未做人工确认**：内核优化菜单的「还原默认设置」随工单 #21 消失
   （`restore_defaults()` 调用方归零后被收敛掉）。规格把它归入"内核调优剩余项"、判为可接受，
   但这是保留能力的一次实质减少，本报告只做记录，不替仓库主人判断影响；
   已记入 README「后续事项」第 5 条（该节后被仓库主人删除，见 8.3）。

---

## 八、交付物与后续事项

工单 #16~#23 只改文档与尺子，未碰 `kejilion.sh` 的任何一行业务逻辑；第三轮审查修复
（工单 #25）按规格判定规则从 `kejilion.sh` 删掉了三个零调用方函数（38 行），这是本轮
规格唯一一次改主脚本，删除前的 grep 证据见 9.4 第 9 项与原 README「后续事项」第 8 条（该节已删）。

### 8.1 本轮净删除规模（工单 #16~#23 + 三轮审查修复，固定点 `4c5e44e` → 集成分支 tip）

| 项 | 数值 |
|---|---:|
| `kejilion.sh` 行数 | 30229 → 14134（净删 16095 行；其中第三轮删 38 行） |
| `kejilion.sh` 顶层函数 | 604 → 435（净删 169 个，净增 0；其中第三轮删 3 个） |
| 仓库 tracked 文件数 | 112 → 48（净减 64） |
| 文件级 diff | 新增 3 / 删除 67 / 修改 19 |

### 8.2 仓库文件清点

按 `git diff --name-status 4c5e44e...<集成分支 tip>` 数出，三类分布：

| 类别 | 个数 | 明细 |
|---|---:|---|
| 新增 | 3 | `docs/adr/0002-content-fetching-only-from-this-repo.md`、`fail2ban-ssh.conf`、`tests/test_spec15_slim_down_removed.sh` |
| 删除 | 67 | 仓库根 31 个、`tests/` 下 32 个、`docs/` 下 1 个、`apps/` 下 1 个、`PandoraNext/` 下 2 个 |
| 修改 | 19 | 主脚本 1 个、5 份文档（README/GLOSSARY/验收报告/ADR-0001/vps-smoke）、总门编排 1 个、10 把尺子、2 份清点夹具 |

删除的 67 个按去向归类。**分类互斥、相加必须等于 67**（上一版这里六类相加 71，错在
"随板块退役"类把两个证书续签夹具从 `tests/fixtures/` 重复计了一次——它们属 `tests/` 的
32 个；且各类计数与其自列的明细本身就数不上。本版逐个数过，命名也改成与内容一致）：

| 去向 | 个数 | 明细 |
|---|---:|---|
| 随板块退役的兄弟文件与配置（仓库根） | 20 | 游戏开服 6 个（`palworld.sh`、`pal_backup.sh`、`pal_log.sh`、`mc.sh`、`mc_backup.sh`、`mc_log.sh`）；三类 AI 面板 3 个（`ai_cli_manager.sh`、`hermes_manager.sh`、`deepseek_harness_manager.sh`）；LDNMP 建站 11 个（`ldnmp.sh`、`beifen.sh`、`CF-Under-Attack.sh`、`www.conf`、`www-1.conf`、`optimized_php.ini`、`custom_mysql_config.cnf`、`custom_mysql_config-1.cnf`、`fail2ban-nginx-cc.conf`、`auto_cert_renewal.sh`、`auto_cert_renewal-1.sh`） |
| 退役的测试与夹具（`tests/`） | 32 | `tests/openclaw/` 一整个目录 12 个；应用市场专项 6 个；建站专项 8 个；AI 面板专项 3 个；根目录 OpenClaw 冒烟 1 个（`tests_openclaw_config_path_resolution_smoke.sh`）；证书续签夹具 2 个（`tests/fixtures/`，计入本类、不在上一类重复数） |
| 真孤儿、内联副本与 OpenClaw 冒灰脚本 | 8 | `Limiting_Shut_down.sh`、`Limiting_Shut_down1.sh`、`check_x86-64_psabi.sh`、`nginx.local`、`valkey.conf`、`sshd.local`（后三个内容被主脚本内联生成，不经 URL 下发）、`tests_openclaw_manager_smoke.sh`、`run_openclaw_manager_matrix.sh` |
| 悬空文档与已退役资产 | 3 | `CONTRIBUTING.md`、`docs/kpanel-removal-keep-list.md`、`apps/README.md` |
| `PandoraNext/` 目录 | 2 | 随工单 #19 整目录删除 |
| `network-optimize.sh` | 1 | 工单 #21 点名的外部脚本 |
| `update_log.sh` | 1 | 第三轮审查修复补删的漏网孤儿（工单 #22 判据下的漏网，零引用，见 9.4 第 7 项） |
| **合计** | **67** | 与 `git diff --name-status … --diff-filter=D \| wc -l` 的实测一致 |

仓库根在交付时剩 **11** 个文件：主脚本 + 4 份文档（README/GLOSSARY/LICENSE/AGENTS.md）
+ 6 个保留兄弟文件（`TG-check-notify.sh`、`TG-SSH-check-notify.sh`、
`upgrade_openssh9.8p1.sh`、`archive.key`、`fail2ban-ssh.conf`、`cloudflare.conf`）。

**2026-10-10 安全审计后的现状**：`cloudflare.conf` 经全文通读与引用检索判定为
全仓库零引用的孤儿（`kejilion.sh` 从不下载它；服务的是随 LDNMP 建站删除的 CC 防护；
GLOSSARY「兄弟文件」从未计入它），且 `[Init]` 段 `cfuser` 为原作者邮箱占位、
`cftoken` 为无效占位——已直接删除，仓库根现为 **10** 个文件、保留兄弟文件 **5** 个；
防复活由 `tests/test_spec15_slim_down_removed.sh` 断言 2 的 `orphan_files` 守。

> 与规格 Further Notes 预估「净减约 40 个、净增 1 个」的差异：实测净减 64、净增 3。
> 主要原因是**退役的测试与夹具比预估多得多**——规格只估了"约 20 个"，实际随板块一起
> 退场了 32 个（`tests/openclaw/` 一整个目录 12 个、应用市场专项 6 个、LDNMP 建站
> 专项 8 个、AI 面板专项 3 个、根目录 OpenClaw 冒烟 1 个、证书续签夹具 2 个）。
> 净增比预估多 2 个：规格只想到收编 `fail2ban-ssh.conf` 那一个文件，实际还新增了
> 删除守卫这把尺子（`tests/test_spec15_slim_down_removed.sh`，规格用户故事 37 要求）
> 与 ADR-0002 这份决策记录（工单 #23 的领域资产交付物）。

### 8.3 后续事项记账

**现状说明（2026-10-10，晚于本报告定稿）**：本节原先指向的 `README.md`
「**后续事项**」记账节已由仓库主人**整体删除**。删除前该节共 5 条，每条都写了
是什么、在哪、为什么这次不动、建议怎么处理；删除前一版 README 可用
`git show 9756313^:README.md` 取回。本报告下文里所有"README 第 N 条"
"「后续事项」第 N 条"的引用，均指**那一轮当时**的记账内容，现已不在
`README.md` 里——不要再照着现在的 README 去找。

该节的变迁史（本报告定稿时的记录）：第二轮审查修复之后，这一节又改过一次口径：
仓库主人曾决定「后续事项」只放**还没解决**的待办，已处置完毕的一律移出、记录
归本报告。因此 9 条收缩为 5 条：

| 移出的条目 | 去处 |
|---|---|
| 原第 3 条 `CONTRIBUTING.md` 的 KPanel 悬空文档节 | 文件已随工单 #22 删除，见 8.2 与 9.4 |
| 原第 5 条 `CONTRIBUTING.md` 同步节被越界删除的披露 | 本报告 9.3 |
| 原第 6 条 游戏开服脚本重生路径 | 工单 #22 合并提交 + 本报告第五节 |
| 原第 8 条 三个零调用方函数 | 第三轮审查修复（提交 `dc5bc25`）+ 本报告 9.4 |
| `TG-check-notify.sh` 的外联（原第 1 条的一半） | 判定不立项，逐行通读结论见 ADR-0002；当时记账于 README 第 1 条末尾（该节已删） |

留下的 5 条按原顺序重编为 1~5。**口径变更本身也带来一处尺子退役**：
`tests/test_readme_install_source.sh` 原第 4a 条断言"游戏开服重生路径必须标记为已解决
且 `palworld.sh`/`mc.sh`/`kejilion.pro/kejilion.sh`/`游戏开服脚本合集` 四个要素齐全"，
条目移出 README 后该断言失去目标。该断言防的是"这条路被悄悄加回来"，而这由三层别的
尺子叠加守着（`test_spec15_slim_down_removed.sh` 断言这些词汇在 `kejilion.sh` 里为 0、
`test_update_removed.sh` 判据 6 断言仓库根 6 个游戏脚本不得回来、
`test_kpanel_main_menu_smoke.sh` 的 `retired_entry` 列着它），故退役不削弱防护。

本节此前记的工单 #24 三处修正（`kejilion-agent` 行号、图片热链行号、新增
`restore_defaults` 条）仍成立，只是条目编号已按新口径前移。

> 第 4 条那三处行号此后又错过一次，这里如实记下变迁：工单 #24 校正为
> 13925~13935 / 6754 / 13944，其中两处**没对**（函数定义末行是 13936 不是 13935；
> 13944 是 `backup-center)` 标签行，CLI 分支实为 13945~13947），第三轮审查修复
> （工单 #25）按代码校正为 **13887~13898 / 6716 / 13907~13909**——差异来自工单 #25
> 又删了文件头三个零调用方函数（14172 → 14134 行，行号再前移 38 行）。当时 README 第 4 条
> 与本节现在写的都是 13887~13898 / 6716 / 13907~13909，以代码为准（该记账节现已删除，
>  README 那一份随它不在仓库里）。

第二轮审查修复（固定点 `4c5e44e`，两轴共 10 项发现）与第三轮审查修复（工单 #25，
两轴共 13 项发现，其中 2 项是第二轮自己带出的回归）修的东西分别见 9.2 与 9.4。

---

## 九、三轮交付前审查修复（如实披露）

> **编号口径提醒**：本节与第八节表格里出现的"README「后续事项」第 N 条"，指的是**那一轮
> 当时**的编号。该节后来改为"只放未解决项"，条目已收缩为 5 条，编号前移过一次——
> 新旧编号的对应关系见 8.3 的映射表。**该记账节已于 2026-10-10 由仓库主人整体删除**，
> 这里的引用均为当时口径，取回方式见 8.3 的现状说明。

本轮规格一共做了**三轮**代码审查。前两轮只动文档与 `tests/` 下的尺子，`kejilion.sh`
一行未碰；**第三轮（工单 #25，本轮）破了这个纪录**——按规格判定规则（以 grep 结果为准）
从 `kejilion.sh` 删掉了三个零调用方函数（38 行），并删除漏网的孤儿文件 `update_log.sh`；
其余各项仍是文档与尺子。三轮的提交记录都在分支上，可按表逐条核对。

### 9.1 第一轮（工单 #11 时代，固定点 `7e770e8`，六项发现）

九项检查在修复前后都是 9/9 全绿、退出码 0；下表每项一个独立提交。

| # | 问题 | 改了什么 | 提交 |
|---|---|---|---|
| 1 | 术语漂移：新写内容里 7 处用错了指代词 | `README.md` 4 处、`docs/acceptance-report.md` 1 处、`tests/test_update_removed.sh` 2 处注释，同文件 `upstream_base` 顺带改名 `orig_base` | `80f3335` |
| 2 | 术语违反：清点检查的内部类型值当时叫 [telemetry-trigger]（回避词字面，引述历史） | `tests/test_network_inventory.sh` 改名 `report-trigger`，同步注释、awk、人读清单三处筛选、自测断言 | `5201813` |
| 3 | 坏味道：零增益纯转发的 wrapper `ask_assert_clean` | 删掉 wrapper，两处调用点直接调 `assert_clean_impl` | `bf4de13` |
| 4 | 轻度重复：按类别计数 + 经作者代理计数的 awk 写了两遍 | `test_network_inventory.sh` 新增 `emit_summary()` 与 `--summary` 模式；`run_all_checks.sh` 改调它。分类规则一字未动 | `d16e0ee` |
| 5 | 规格半成品：README 还描述已删功能 | 删「English Version」、「自动更新机制」条目、「KPanel Web 管理面板」整节与失效的过时描述附注 | `d9cef37` |
| 6 | 范围蔓延未披露 | 见 9.3 | 本提交 |

修复后自查：术语表口径下那个回避词在 `README.md`、`docs/`、`tests/test_update_removed.sh` 上命中 0；
`grep -rn 't[e]lemetry' tests/` 为 0；总门 9/9 全绿、`--assert-clean` PASS。

### 9.2 第二轮（本轮规格 #15，固定点 `4c5e44e`，两轴 10 项发现）

> **轮次编号与提交信息后缀的对照**：本报告把仓库历史上**全部**审查世代按顺序编号
> （9.1 是工单 #11 时代那一轮）。因此本节的「第二轮」对应提交信息后缀 `（审查修复）`，
> 9.4 的「第三轮」对应提交信息后缀 `（第二轮审查修复）`——提交后缀只在本规格内计数，
> 报告编号含更早的世代，两者相差一。按提交信息找修复看后缀，按时间线找世代看本节号。

十三项检查在修复前后都是 13/13 全绿、退出码 0。这一轮由工单 #24 的审查修复分支
`purify/tkt-24-review-fixes` 的六个提交承载：

| 提交 | 修了什么 |
|---|---|
| `b197752` | 术语：清掉文档与测试注释里的回避词字面（当时写作 [上游] / [遥测]，见 GLOSSARY 的 _Avoid_ 约定），与第一轮修复 1 同一类问题在第二轮的复现 |
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
（当时见 README 第 3 条，该记账节现已删除），这一条的残响只剩历史记录。删除前内容在
`git show 75d4868:CONTRIBUTING.md` 与 `git show 7e770e8^:CONTRIBUTING.md` 都能取回。
### 9.4 第三轮（工单 #25，固定点 `4c5e44e`，两轴共 13 项发现）

由工单 #25 的审查修复分支 `purify/tkt-25-round3-fixes` 承载，按逻辑单元分提交。十三项
检查在修复前后都是 13/13 全绿、退出码 0。**其中两项是上一轮修复自己带出的回归**（1 与 2），
一项是上一轮裁定的修正（9）。逐项列示：

| # | 问题 | 改了什么 |
|---|---|---|
| 1 | 回归：`test_network_inventory.sh --help` 用法示例被整段截断（上一轮 `8e81e2b` 给文件头加注释，写死的 `sed -n '2,20p'` 跟不上） | 两个入口（本测试与 `run_all_checks.sh`）的 `usage()` 一律改为按锚点 awk 抽取（「用法：」节到第一行非注释代码止），行号再无漂移空间；实跑确认 5 条示例全部输出 |
| 2 | 回归：README 两处现在时引用已删除的 `docs/kpanel-removal-keep-list.md`（悬空引用） | 改为过去时表述（已随工单 #17 删除，原文见 git 历史），不恢复文档 |
| 3 | README 后续事项编号说明过期（写 1~7，实际 1~9） | 补齐完整变迁：原 1~9 → 工单 #20 移出第 2 条后 1~8 → 工单 #24 补两条后 1~9。**该修补后来又被取代**——仓库主人改为"后续事项只放未解决项"，条目收缩为 5 条、不再需要维护编号变迁史，见 8.3 |
| 4 | 幽灵变量 `repo_raw`：注释与报错文案引用一个已从本文件删掉的变量 | 文案改指实际断言的 raw 基址 `https://raw.githubusercontent.com/howi3c/sh/main`，读者不用跳文件 |
| 5 | 行号互掐：报告 8.3 写 `13925~13935 / 13944`，README 与代码实物是 `13925~13936 / 13945~13947`（13944 是 `backup-center)` 标签行） | 以代码为准校正报告与 README 全部 `kejilion.sh` 行号引用；本轮（第三轮）自己删了 38 行造成的连带漂移（`archive.key`、`kejilion-agent`、ADR-0002 的 TG 注入点）一并重核 |
| 6 | 8.2 文件分类账对不上：六类相加 71 ≠ 实测删除 66，且"随板块退役"类把两个证书续签夹具从 `tests/` 重复计了一次 | 重写 8.2 为互斥五类+两项单列，相加等于实测数；本轮又删 `update_log.sh`，账随实数更新 |
| 7 | 工单 #22 漏了一个孤儿文件：`update_log.sh`（423 行，主脚本更新日志展示脚本，全仓库零引用） | 删除；README「本轮删除记录」记账；删除守卫孤儿黑名单加守（反向验证：`touch` 后 FAIL 1 处） |
| 8 | 工单 #16 点名的自查词 `cluster_python3` 没有尺子守（"打不了的勾"） | 删除守卫 `absent_literals` 与冒烟 `retired_entry` 两处都补上；反向验证两处都叫（文件尾注入 → 删除守卫 FAIL；CLI 分发块内注入分支 → 冒烟 FAIL） |
| 9 | 上一轮裁定修正：三个零调用方函数（`remove_app_id` / `kpanel_app_update_marker` / `find_container_by_host_port`）"保留"是错的，规格判定规则以 grep 结果为准，应删 | 删除前先跑旧尺子确认见红（FAIL 3 处，证明它真在守），退役断言 2c 并写明退役理由；README 第 8 条改写为"已删 + `kpanel_app_with_lock` 的 `markers`/`catalog` 分支从此无调用方"；总门第 13 项标签与本节表格同步 |
| 10 | `docs/vps-smoke.md`「一共 9 项」读起来像 9 个待清残项（其中 3 条已自述结案） | 改分层表述：3 条已结案（逐条点名）作为历史记录保留，6 条还欠着（逐条点名），不删已结案条目 |
| 11 | 坏味道：`test_network_inventory.sh` 两处重复 awk（`296~305` 两分支同一 awk 只差 `head -10`；`350~353` 与 `357~360` 同一 awk 两个筛选） | 前者并成一条 awk（前 10 条逐行 + 第 11 行起余量），后者抽成 `summarize_records_by_endpoint()`；**判据强度不变**：用人造样本跑新旧两版，输出逐字节一致 |
| 12 | 脆弱交叉引用：断言 2c 把「第 8 条」写死在注释/报错里 | 随第 9 项退役断言 2c 一并解决 |
| 13 | 术语口径不统一：报告里两处引述历史的旧名（[telemetry-trigger]、[上游]/[遥测]）没跟全文一致用方括号写法 | 引述历史名一律改方括号写法（与该文件既有写法一致）；`test_main_menu_noninteractive_smoke.sh` 的「无遥测版」标题后缀是规格用户故事 15 的特例，按 `test_attribution_naming.sh` 注释的约定**不动** |

修完总门 13/13 全绿、退出码 0；删除守卫单独跑 `spec15-slim-down-removed=pass`；
`bash -n kejilion.sh` 通过；`kejilion.sh` 14172 → 14134 行，仓库文件 49 → 48 个。

> 9.2 表中 `a50d8e9`（README 第 8 条记三个零调用方函数"保留"、守卫加守断言 2c）的裁定
> 已被本轮第 9 项推翻：那三个函数按规格判定规则删除，2c 退役。该提交本身如实记录了
> 当时的行为，保留在表中作为历史。


---

## 十、交付后增量：k 快捷命令安装链自落盘兜底（附：地区开关死代码整块删除）

规格 #25 收尾后，仓库主人按 README 的一键安装命令实装，发现**输入 `k` 没有反应**——
与原版体验不一致。本次增量修复它，如实记录如下。

### 10.1 根因（隔离实验证实，未改代码前先跑尺子见红）

k 命令的安装链原本只有一跳来源：`cp -f ./kejilion.sh ~/kejilion.sh`——「**当前目录**里的
kejilion.sh」。而 README 教的一键安装是 `bash <(curl -sL <本仓库 raw 地址>)`（当时的
命令形态；现已改为先下载再运行，见 10.5）：脚本从
管道流过，`$0` 是 `/dev/fd/N`，硬盘上从来没有 kejilion.sh 这个文件，第一跳就断；且每一跳
的报错都被 `>/dev/null 2>&1` 吞掉——`/usr/local/bin/k` 静默地不存在，用户输入 `k` 只得到
command not found（或一个指向空气的 `/usr/bin/k` 软链报错）。

原版同样断在这一跳，但原版有两条兜底：作者博客教的是「先 `curl -O` 下载再
`./kejilion.sh`」跑法（目录里本来就有文件），且原版的更新功能会把脚本重新落到
`~/kejilion.sh` 再拷成 k。**净化版把更新功能整块删了（工单 #7），兜底没了，坑裸露。**

隔离实验（沙箱模拟两种跑法，不碰真实系统）：管道方式 + 目录里没有脚本文件 →
`~/kejilion.sh` 与 `/usr/local/bin/k` 都没落盘，只剩一个指向空气的软链；目录里有脚本
文件 → 一切正常。

### 10.2 改了什么

| 位置 | 改动 |
|---|---|
| `kejilion.sh` | 安装链收敛为新函数 `kj_install_k_shortcut()`：本体在磁盘上（`./kejilion.sh`、`bash kejilion.sh`、直接跑 `k`）则以 `$0` 为准；本体不在磁盘上（`bash <(curl …)` 管道 / `curl \| bash`）则先从本仓库 raw 地址取一份落到 `~/kejilion.sh` 再接上安装链（地址在代码里写死，不设覆盖开关——取内容来源不可变，与 ADR-0002 的方向一致）。另补三件原版没有的事：落盘后补执行位（curl 下载件默认 644，不补则 k 装上也不能执行）；装不上时清掉指向空气的 `/usr/bin/k` 软链；首次装上屏幕给一句提示（失败兜底助手为 `kj_k_shortcut_failed()`） |
| `kejilion.sh`（同批） | **地区开关死代码整块删除**：`canshu` / `quanju_canshu()` / `canshu_v6()` / `zhushi` 全部移除。删除依据：`canshu` 在净化版里没有任何一处写入（永远是 `default`），`zhushi` 没有任何一处读取（读它的旧门闸 `run_command()` 已不在），`gh_proxy` 分支也随工单 #5 的直连改造消失——开关上下游皆空，留着只会误导。唯一还有用的 `gh_https_url="https://"`（拼 GitHub 展示/取用地址，5 处使用）提为顶层常量保留。原先为 V6 迁移改的调用顺序随之不需要了（迁移的目标本身就是死设置） |
| `README.md` | 一键安装命令改回原版风格单行：`bash <(curl -sL https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh)`；「首次运行后可按脚本提示设置 k」改为与真实行为一致的「首次运行时自动装好 k（屏幕有提示）」——这句话此前并不属实（首次许可流程已在净化时删除，从无提示） |
| `tests/test_k_shortcut_install.sh` | 新增守门尺子（见 10.3），挂上 `tests/run_all_checks.sh` 总门第 12 项；随地区开关删除去掉 V6 迁移场景，截取锚点从 `canshu_v6` 改指 `kj_k_shortcut_failed` |
| `tests/test_direct_downloads.sh` | 第 3 节尺子反转：从「钉着 quanju_canshu 三分支不许退化」改为「`gh_https_url` 前缀常量必须在 + 地区开关不许复活」（注释里提历史名字不算复活，口径同 test_network_inventory.sh 对报信词）；第 6 节里随更新功能（工单 #7）已成死代码的两条 canshu 切换命令断言删除 |
| `GLOSSARY.md` | 新增术语「k 快捷命令」（安装链三跳 + 靠 PATH 命令生效而非 shell 别名的辨析） |
| `docs/vps-smoke.md` | 「自我复制」纪律补一句：用 README 一行命令装也一样，脚本会自己从仓库地址取一份落盘再装 k |
| `tests/fixtures/` | 网络清点基线随改动重生成（见 10.4） |

影响面说明：新 URL 只指向本仓库 raw（ADR-0002「取内容只从本仓库」的方向不变）；
`KJ_LOCAL_BIN_DIR` / `KJ_SYSTEM_BIN_DIR` 两个环境变量注入点默认值即真实路径，
仅为测试沙箱存在，不改变用户机的任何行为。

### 10.3 新尺子守的行为（`tests/test_k_shortcut_install.sh`）

沙箱截取安装链（`kj_k_shortcut_failed` 定义起、`ip_address` 之前止），以两种方式驱动：
`bash <(cat …)`（`$0` 是 `/dev/fd/N`，模拟管道安装）与 `bash` 本地文件（模拟下载后
运行）；curl 换成只写本地夹具的桩（零网络请求）；HOME 与两个 bin 目录全部指进沙箱。
四个场景：

1. **管道安装**：k 装上、可执行、内容正是从仓库取回的本体、软链就位、默认取内容地址
   指向本仓库 raw、首次运行屏幕有提示；二次运行不重复提示、k 仍是仓库本体；
2. **本地文件安装**：k 内容 == 正在运行的那个文件，且全程不调用 curl；
3. **管道安装但 CWD 里躺着别的 kejilion.sh**：仍装从仓库取回的新本体，不装 CWD 里
   那份——防止旧文件/原版文件借尸还魂；
4. **取内容也失败**：不崩、不留指向空气的软链、明确告诉用户「没装上」（静默失败正是
   当年这个坑看不见的原因）。

反向验证（证明尺子真在守，各注入一项倒退后必须见红）：默认地址退回原作者域名 →
场景一红；去掉落盘后的 `chmod +x` → 场景一红（执行位断言）；整块换回老逻辑 →
场景一红（管道安装装不上 k）。正品全绿：`k_shortcut_install=pass`。

同批删除的地区开关另有尺子守（`tests/test_direct_downloads.sh` 第 3 节，原位变异
验证）：代码级注入 `canshu="V6"`、函数级复活 `quanju_canshu()`、删掉 `gh_https_url`
常量，三发全部见红，恢复后 md5 一致、正品通过。

### 10.4 实测结果

`bash tests/run_all_checks.sh`：**14/14 项全部 PASS，退出码 0**（原 13 项 + 本增量
新增第 12 项「k 快捷命令安装链」）。基线数字：报信 0 处（红线）、经作者代理的下载
0 处（红线）、**取内容 108 处**（107 + 本次新增的自落盘取内容）、参考链接 10 处；
原版名下 URL 清零、留存取内容 URL 全部指向本仓库现为 6 处（5 个兄弟文件 +
`kejilion.sh` 自身）。`bash -n kejilion.sh` 通过。`kejilion.sh` 14134 → 14168 行
（净 +34 行；顶层函数净增减 0——新增安装链与失败兜底 2 个，删除地区开关死代码
`quanju_canshu` / `canshu_v6` 2 个）。

> ADR-0002 Consequences 里「留下的 5 个」是工单 #23 时点的快照（5 个兄弟文件），
> 按 ADR 作为决策记录不回改的惯例原文保留；第十节增量后为 6 处（含 `kejilion.sh`
> 自身），以此节为准。

本增量由仓库主人决定直接修复、不开工单；上文各表即为它的验收记录。

### 10.5 一键安装命令改为「先下载再运行」（不再用 `bash <(curl …)`）

仓库主人实跑 README 的一行安装命令时报错，本次做兼容性修正。先在本地做了隔离实验
（不装任何东西、不发请求，把三种跑法的行为摆在一起看）：

| 跑法 | 在 sh 下能否运行 | 脚本内 `read` 交互 |
|---|---|---|
| `bash <(curl …)`（原 README 命令） | **不能**：`sh: 1: Syntax error: "(" unexpected`——`<(...)` 是 bash 专有语法 | 正常 |
| `curl … \| bash` | 能 | **断**：脚本经 stdin 喂入，读完即 EOF，菜单的 `read` 读不到用户输入（实测 `read -p` 得到空值） |
| `curl -fsSL -o /tmp/kejilion.sh … && bash /tmp/kejilion.sh`（新命令） | 能 | 正常 |

另外，原命令的 `-sL` 会把 curl 自己的错误也吞掉——下载失败时用户看到的只是"没反应"；
换成 `-fsSL` 后失败有明确报错，`-f` 还能防止把错误页/重定向页当成脚本执行。

| 位置 | 改动 |
|---|---|
| `README.md` | 「一键安装」命令改为先下载再运行；补两句说明为何不用管道喂法与 `<(...)`（净化的说明句「这是个人净化版、别从原作者域名拉」原样保留） |
| `GLOSSARY.md` | 「k 快捷命令」条目里管道安装的举例补上 `curl \| bash`（与 `kejilion.sh` 内安装链注释口径一致） |
| `docs/vps-smoke.md` | 第三条纪律里 `bash <(curl …)` 的提法改为与新命令形态一致 |
| `tests/test_k_shortcut_install.sh` | 背景注释里 README 命令形态更新（断言不变——管道跑法仍是合法入口，四个场景继续守） |

影响面：新命令仍只从本仓库 raw 取内容（ADR-0002「取内容只从本仓库」方向不变）；
k 安装链走「本体在磁盘上」分支，即场景二（本地文件安装）那条已验证路径；管道跑法
的自落盘兜底不受影响。`bash tests/run_all_checks.sh` 全绿后本表即为验收记录。

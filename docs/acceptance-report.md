# kejilion.sh 净化版 · 验收报告（工单 #11）

_面向仓库主人。本文只记录**亲手跑出来的**结果；凡是没有跑出来的，一律写进「没验的部分」一节，
不做推测性结论。_

| 项 | 值 |
|---|---|
| 验收对象 | 集成分支 `purify/kejilion-telemetry-free` |
| 九项检查实跑时的提交 | `7e770e8`（工单 #2~#10 的合并终点） |
| 报告落笔时的提交 | 本工单的三个新增提交（详见第八节）；它们只新增/修改文档与 `tests/run_all_checks.sh`，**不碰 `kejilion.sh` 本体**，因此正文数字对两者都成立 |
| 目标脚本 | `kejilion.sh`，30229 行 |
| 单入口验收入口 | `tests/run_all_checks.sh`（本文提交后新增） |
| 判定口径 | `GLOSSARY.md`「报信 / 取内容」+ `docs/adr/0001-keep-content-fetching-strip-reporting.md` |
| 父议题规格 | 议题 #1，其中 Testing Decisions 规定「VPS 冒烟由仓库主人执行，不在代理验收范围内」 |

## 一句话结论

九项自动检查**全部通过**：报信 0 处、经作者代理的下载 0 处、取内容 324 处与预期清单一致，
主菜单渲染与分发完好、语法合法。剩下的只有一件事——**把脚本传上 VPS 人工过目**
（操作说明见 `docs/vps-smoke.md`）。

---

## 一、怎么复现

```bash
cd /home/howi/projects/sh
bash tests/run_all_checks.sh
```

这一条命令会依次跑完下面九项，逐项打印 `PASS`/`FAIL`，最后给总体结论、当前基线数字，
并附上完整的对外端点清点明细。**任何一项失败，整条命令以非零退出**，可以直接当 CI 闸门。

只想看汇总不看清点明细时：

```bash
bash tests/run_all_checks.sh --no-detail
```

> 复现前提：仓库主人拿到的是同一个提交上的同一份 `kejilion.sh`。行号会随后续改动漂移，
> 本文记录的行号以 `7e770e8` + 本次新增提交为准。

---

## 二、当前基线数字

由 `bash tests/test_network_inventory.sh --records kejilion.sh` 的同一套分类引擎数出
（`run_all_checks.sh` 只按类别列计数，不改分类规则）：

| 口径 | 数值 | 说明 |
|---|---:|---|
| **报信** | **0 处** | 红线项，必须为 0 |
| 取内容 | 324 处 | 下载安装包、拉测速节点、查公网 IP 归属地；请求里不夹带用户信息 |
| 参考链接 | 84 处 | 脚本只是打印给用户看的链接，并不真发请求 |
| 经作者代理的下载 | 0 处 | 红线项，必须为 0 |

仓库里另固化了一份基线产物 `tests/fixtures/network_inventory.summary.txt`，
数字与上表一致（报信_处数=0、取内容_处数=324、参考链接_处数=84、经作者代理_处数=0），
全量记录在同目录 `network_inventory.records.tsv`（408 行，可直接 diff）。

### 改造前后对照（同一把尺子量的）

| 口径 | 原版（`90d1b1f:kejilion.sh`，33125 行） | 净化版（30229 行） |
|---|---:|---:|
| 报信 | 4 处（`api.kejilion.pro` 两处上报 POST、`ipinfo.io` 一处喂报信、Python 版附属报信一处触发） | **0** |
| 取内容 | 338 处 | 324 |
| 参考链接 | 110 处 | 84 |
| 报信函数相关行 | 545 行提及 / 530 处活跃调用 | 0 |
| `${gh_proxy}` 作者代理取用点 | 161 处 | 0 |
| `gh.kejilion.pro` 字样 | 11 处 | 0 |
| Docker 镜像加速列表 | 17 条（含作者代理 1 条） | 16 条（仅删作者代理那条） |

> 报信「4 处」是**端点级**计数（哪一行把哪个端点发出去了）；规格 Further Notes 里的
> 「543+1+16 处调用点」是**调用点级**口径。两者不矛盾，别混用。

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
`kejilion.sh.bak`（自更新前的备份回滚）。UTC 词频上，脚本里仅剩的 5 处「隐私」字样都是
应用说明文案（nostr、whisper、searxng、Umami、思源笔记），不是隐私开关。

---

## 四、保留项核查（不能删过头的那些）

| 保留项 | 实测 | 判据 |
|---|---:|---|
| `ipinfo.io` 查询处数 | 12 处非注释行 | 用户故事 7/8：国外大型服务、HTTPS 直连、不经作者之手；只服务地区判断与系统信息展示 |
| 功能内视频教学链接 | 12 个去重 URL（11 个 bilibili + 1 个 youtu.be） | 用户故事 17：没有文字说明的功能仍有说明书 |
| 官方参考入口（API 厂商推荐列表） | 8 个 | 用户故事 13：返利入口删掉，不带返利的官网参考链接保留 |
| 「借用的脚本」致谢 | 3 段 4 处（`感谢bin456789…leitbogioro`、`leitbogioro项目地址`、两处`该功能由jhb大神提供`） | 用户故事 28：署名不是广告 |
| `KJ_*_NONINTERACTIVE` 纯本地适配器 | 14 个 | 工单 #6 保留清单：只读本地环境变量，不下载、不依赖闭源二进制 |
| 应用市场（主菜单 11）与面板官网信息 | 内置应用 122 个 + 第三方应用目录机制 + `install_panel()` 打印所装面板自己的官网信息 | 用户故事 19：安装引导完整 |

明细备查：

- **8 个官方参考入口**：`api-docs.deepseek.com`、`openrouter.ai`、`platform.moonshot.cn`（Kimi）、
  `www.scnet.cn`（超算互联网）、`www.minimaxi.com`（MiniMax）、`build.nvidia.com`、`ollama.com`、
  `ai.baishan.com`（白山云）。同页图例只留「● 官方入口」，AFF 标记与返利参数已清空。
- **14 个适配器**：`KJ_SSH_PORT`、`KJ_DNS`、`KJ_SYSTEM_RESOURCE`、`KJ_DISK_MANAGEMENT`、
  `KJ_NETWORK_OPERATIONS`、`KJ_ACCOUNT_MANAGEMENT`、`KJ_F2B`、`KJ_SYSTEM_TUNING`、
  `KJ_VIRUS_SCAN`、`KJ_BBRV3`、`KJ_APP`、`KJ_WEB`、`KJ_LDNMP`、`KJ_TEST`。
- **12 个教学视频**：BV1yMw6e2EwL（FRP 客户端/服务端两处）、BV14K421x7BS（BBR3）、
  BV1mH4y1w7qA（红帽内核）、BV1TqvZe4EQm（ClamAV）、BV1Kb421J7yg（内核调优）、
  BV1wv421C71t（poste.io）、BV13F4m1c7h7（Cloudreve）、BV1mZ421T74c（雷池 WAF）、
  BV1Pm42157cK（Python 版本管理）、BV1mC411j7Qd（限流关机）、BV1ib421E7it（`k_info()`）、
  youtu.be/vLL-eb3Z_TY（TG-bot 预警）。

---

## 五、九个工单各自的验收数字

| 工单 | 验收项 | 实测结果 |
|---|---|---|
| #2 网络请求清点与改造前基线 | 一条命令可跑、按报信/取内容分类输出、原版已知报信集合全部查出、人可读 | 全部满足：`--assert-clean` 闸门在位；自测能在一个"脏"样例上查出全部 4 类报信形态（上报 POST、喂报信数据源、Python 附属触发、代理下载）并正确报点；清单人读可核对 |
| #3 冒烟与语法骨架 | 非交互跑通主菜单、不触发真实安装、语法检查一条命令、失败能点名 | 主菜单 14 个编号入口逐个分派成功且分发后返回菜单（标题渲染 2 次）；输入 `0` 干净退出；`not-a-number`、空输入、`00` 三种无效输入都落到"无效的输入"且不触发副作用；`bash -n` 通过；shellcheck 本机未装，按约定跳过 lint 不算失败 |
| #4 报信连根拔 | 报信类为 0、函数名与调用 grep 级为 0、Python 附属报信消失、冒烟与语法通过、单提交 | 报信 0；十项 grep 复核全 0（见第三节）；`send_stat` 0 命中；冒烟与语法通过；历史提交 `1c365af`/`67bc8fd`/`6f7c052`/`5636ffb` 分四步落地 |
| #5 作者代理拔掉 | 清点无作者代理域名、取内容与更新后清单一致、Docker 列表去掉作者代理其余不变、冒烟语法通过 | `gh_proxy`/`gh.kejilion.pro`/`docker.kejilion.pro` 均 0；Docker 镜像 17→16，只少作者代理那一条；`raw.githubusercontent.com`、`github.com` 直连地址在位；地区开关 `quanju_canshu` 三分支未退化 |
| #6 闭源面板整块移除 | 无下载安装路径、每小时自更新与 SSH 登录采集代码消失、菜单入口消失且冒烟不散、清点中发布源端点消失、保留清单在案、单提交 | `kejilion-node`/`KPanel/releases`/`KPANEL_NODE_`/`kpanel_node_`/`ssh-login-broker`/`KJ_LIGHT_NODE_PROTOCOL` 六项全 0；主菜单 17 消失、冒烟 14 项通过；`kpanel_protocol_active` 与 14 个适配器仍在；保留清单落在 `docs/kpanel-removal-keep-list.md`；`k app kpanel` 与手输 `kpanel` 都以退出码 2 拒绝且不拉应用目录 |
| #7 更新功能整体删除 | 菜单无更新入口、无下载并替换脚本的路径（含定时任务）、冒烟语法通过、单提交 | `kejilion_update` 0；`00` 输入落到无效分支；`kejilion_sh_log`、`kejilion.sh.bak`、`SH_Update_task` 全 0；触到 crontab 且提及 `kejilion.sh` 的行只剩 1 条，且是"卸载时清理用户机器上既存任务"的形态；上游取内容目标 19 个一个不少，只拿掉自更新/自覆盖的 2 个目标（`main/kejilion.sh`、`main/kejilion_sh_log.txt`） |
| #8 广告清扫 | 广告专栏入口与内容消失、厂商列表无返利参数但参考链接保留、首屏协议与首次许可消失、推广 echo 删除而教学/官网/致谢保留、冒烟语法通过 | 30 个应删特征串命中 0（含 `kejilion_Affiliates`、`UserLicenseAgreement`、`permission_granted`、`广告专栏`、`topvps`、6 个 VPS 返利参数、5 个 API 厂商返利参数、`youtube.com/@kejilion`）；6 项保留断言通过（3 个教学视频、`bt.cn` 面板官网、`install_panel()`、3 段致谢）；首屏不再被拦 |
| #9 署名、命名与 README | 标题带无遥测版、关于页一行中性署名、README 顶部三行且与实际一致、冒烟语法通过 | 主菜单标题为「科技lion脚本工具箱 v$sh_v（**无遥测版**）」；`k_info()` 有「本脚本基于 kejilion 脚本修改」一行且不含任何链接；README 顶部三行说明在位（"净化版"、"不是官方发布"、删除项、其余功能与原版一致） |
| #10 语言资产删除 | 无语言副本目录与非简体 README、自动翻译工作流删除或禁用、主脚本无悬空引用、单提交 | `cn en tw kr jp ir ru` 七个目录均不存在；5 个非简体 README 不存在；`.github/workflows/translate.yml` 不存在；根 `translate.py` 不存在；4 类悬空引用模式命中 0 |

---

## 六、九项检查的实跑结果

```text
PASS 1/9  缝 1 · 网络请求清点（报信清零闸门）   ← tests/test_network_inventory.sh --assert-clean
PASS 2/9  缝 2 · 非交互菜单冒烟（主菜单渲染与分发）   ← tests/test_main_menu_noninteractive_smoke.sh
PASS 3/9  缝 3 · 语法检查（bash -n，shellcheck 缺装则跳过）   ← tests/test_kejilion_syntax_check.sh
PASS 4/9  守门 · 广告清扫（工单 #8：返利与推广清空、教学链接/面板官网/致谢保留）   ← tests/test_ads_stripped.sh
PASS 5/9  守门 · 更新功能整体删除（工单 #7）   ← tests/test_update_removed.sh
PASS 6/9  守门 · 闭源面板整块移除（工单 #6）   ← tests/test_kpanel_main_menu_smoke.sh
PASS 7/9  守门 · 作者代理拔掉、下载直连（工单 #5）   ← tests/test_direct_downloads.sh
PASS 8/9  守门 · 署名、命名与 README（工单 #9）   ← tests/test_attribution_naming.sh
PASS 9/9  守门 · 语言资产删除（工单 #10）   ← tests/test_language_assets_removed.sh

总体结论: 全部通过（9/9 项）
```

`bash tests/run_all_checks.sh` 实跑退出码 **0**。

**反向验证过它会叫**（在真实仓库上做，改完原样还原）：把
`tests/test_direct_downloads.sh` 里一个预期镜像地址改成错值，入口立刻以退出码 1 结束，输出：

```text
FAIL 7/9  守门 · 作者代理拔掉、下载直连（工单 #5）   ← tests/test_direct_downloads.sh
      | error: Docker 镜像列表丢了不该丢的镜像: https://docker.1ms.run-TAMPERED
...
总体结论: 未通过（8/9 项 PASS，1 项 FAIL）
```

点名了是哪一项、哪一条对不上，随后 `git checkout --` 还原尺子，重跑恢复 9/9 全绿。
另在临时副本上给 `test_language_assets_removed.sh` 注入一条必败断言，同样以退出码 1 结束并
把行号带出。仓库本体未被改动。

---

## 七、没验的部分（明确划界，不做无据结论）

1. **VPS 人工过目**：规格 Testing Decisions 原文规定「净化版上传后打开受影响菜单入口并退出、
   不真装任何东西，由仓库主人执行，不在代理验收范围内」。操作说明见 `docs/vps-smoke.md`。
2. **`shellcheck` lint**：本机未安装，按约定只跳过、不算失败；装上的机器上 lint 仅报告不阻断。
3. **取内容类外部服务的可用性与速度**：规格 Out of Scope 明确排除；大陆网络下直连变慢是已接受取舍。
4. **已安装闭源面板的系统上的清理**：只改脚本，不动任何现存机器状态（规格 Out of Scope）。
5. **未纳入本次自动验收的其余既有测试**：`tests/` 下还有大量针对其他脚本（OpenClaw 管理、
   ai_cli_manager、deepseek_harness、LDNMP 站点等）的测试，本次改造没碰那些脚本，
   `run_all_checks.sh` 只编排与净化相关的三条缝与六个守门测试。

---

## 八、交付物与后续事项

本次工单只新增/修改四个文件，未碰 `kejilion.sh` 的任何业务逻辑。相对 `7e770e8` 的差异：

| 文件 | 是什么 | 提交 |
|---|---|---|
| `tests/run_all_checks.sh` | 一条命令跑完九项的单入口 | `05ebb63` |
| `docs/acceptance-report.md` | 本报告 | `482d806` |
| `docs/vps-smoke.md` | 给仓库主人的 VPS 冒烟操作说明 | `50da66a` |
| `README.md` | 新增「后续事项」一节（+ 导航链接） | `50da66a` |

还有什么没清的，见 `README.md` 的「**后续事项**」一节：登录通知类脚本、写死地址密码的
备份模板、示例密码文件、`CONTRIBUTING.md` 的悬空一节、`kpanel_backup_center_dispatch()`
调用的 `kejilion-agent`，共 5 项（另有 1 项附注记录 README 自身的过时描述），
每项都写了是什么、在哪、为什么这次不动、建议怎么处理。

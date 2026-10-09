#!/bin/bash
# 规格 #15「净化版瘦身」删除守卫（唯一新增守门文件，用户故事 37）。
#
# 背景：规格 #15 把游戏开服、三类 AI 面板、OpenClaw、应用市场、LDNMP 建站、
# FRP 内网穿透、network-optimize 外部脚本整块删除，取内容收敛到本仓库
# （ADR-0002）。本测试守四类断言，让已删的东西与指向原版名下的 URL
# **永远不会被悄悄加回来**：
#
#   1. 已删功能词汇在主脚本中为零（只算非注释行，说明性注释提一句不算复辟）；
#   2. 仓库根孤儿文件不存在（顺带钉住保留的兄弟文件一个不少）；
#   3. 剩存取内容 URL 全部指向本仓库 raw、指向原版名下的 URL 清零、报信为 0
#      ——调用 tests/test_network_inventory.sh --assert-clean 判定，不重抄判据；
#   4. 与 README 守门交叉确认——直接调用既有两个 README 守门，不重抄它们的逻辑。
#
# 与其它守门的分工（避免重复实现、避免判据漂移）：
#   · 断言 3 的 URL 判据（报信=0 / 原版名下 URL 清零 / 留存 URL 指向本仓库）
#     完全由 tests/test_network_inventory.sh --assert-clean 独揽，本测试只调用它，
#     正则与 5 个取内容目标清单都只有那一份；改判据只需要改一个地方。
#   · test_update_removed.sh 的 expected_targets 守"保留的取内容目标一条不少"，
#     是同一批兄弟文件的另一把尺子（独立基准，只列 4 个目标，见那里的改写说明）。
#   · README 侧"安装来源 / 不残留原版引用"由那两个 README 守门负责，本测试只调用。
#
# 注意：本测试只做静态文本与存在性检查，绝不执行 kejilion.sh、绝不联网。
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_script="${project_root}/kejilion.sh"

fail_count=0
fail() { printf 'FAIL: %s\n' "$*" >&2; fail_count=$((fail_count + 1)); }

[ -f "${main_script}" ] || fail "找不到待测脚本: ${main_script}"

# ===========================================================================
# 断言 1：已删功能词汇在主脚本中为零
#   只列"已删板块特有"的词：函数名 / CLI 标识符 / 菜单文案 / 外部脚本名，
#   不列会撞保留功能的通用词。口径沿用 test_ads_stripped.sh：只算非注释行。
# ===========================================================================
# 固定串（大小写敏感）——逐个核对过只属于已删板块，且删除前确有命中：
#   游戏开服 / AI 面板 / OpenClaw / 应用市场 / LDNMP 建站 / network-optimize
absent_literals=(
	# —— 游戏开服（菜单 16 games_server_tools）——
	'游戏开服脚本合集'              # 菜单 16 渲染文案（删除前 2 行）
	'games_server_tools'            # 游戏菜单函数名 + 16) 分发行（删除前 2 行）
	'palworld.sh'                   # 幻兽帕鲁服务器脚本（删除前 1 行，含后门）
	'mc.sh'                         # 我的世界服务器脚本（删除前 1 行，含后门）
	# —— 三类 AI 面板（编程 CLI / Hermes / DeepSeek Harness）——
	'ai_cli_manager'                # run_ai_cli_manager + 下载地址（删除前 6 行）
	'hermes_manager'                # 应用入口 bash <(curl …/hermes_manager.sh)（删除前 1 行）
	'deepseek_harness_manager'      # 应用入口 bash <(curl …/deepseek_harness_manager.sh)（删除前 1 行）
	# —— 应用市场（菜单 11 linux_panel）——
	'refresh_apps_catalog'          # 应用目录 git clone/pull 驱动函数（删除前 4 行）
	'应用市场'                      # 菜单 11 文案（删除前 4 行）
	'linux_panel'                   # 应用市场分发函数 + 11) 分发行（删除前 4 行）
	# —— LDNMP 建站（菜单 10 linux_ldnmp）——
	'linux_ldnmp'                   # 建站总函数（删除前 6 行）
	'ldnmp'                         # 建站函数族全小写前缀，覆盖 install_ldnmp/ldnmp_v 等（删除前 237 行）
	'LDNMP'                         # 建站文案与 KJ_LDNMP_* 协议门（删除前 48 行）
	# —— network-optimize 外部脚本（系统调优链，工单 #21 删）——
	'network-optimize.sh'           # 钉版本外部脚本（删除前 3 行）
	'KPANEL_SYSTEM_TUNING_NETWORK_COMMIT'  # 其钉版本常量（删除前 2 行）
	# —— FRP 内网穿透（frps/frpc 反向代理）——
	'frps'                          # 服务端配置生成族 generate_frps_config（删除前 33 行）
	'frpc'                          # 增强功能模块 frpc_panel/configure_frpc（删除前 57 行）
)
# 大小写不敏感串——OpenClaw 板块三种写法都出现过，用 -i 一次覆盖
absent_ci_literals=(
	'openclaw'                      # openclaw/OpenClaw/OPENCLAW 全族（删除前小写 654 + 大写 142 + 混合 51 行）
	'moltbot'                       # moltbot_menu/install_moltbot/update_moltbot（删除前 10 行）
)

for pat in "${absent_literals[@]}"; do
	hits="$(grep -nF -- "$pat" "${main_script}" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
	[ -z "${hits}" ] || fail "kejilion.sh 仍含已删功能词汇 [${pat}]（非注释行）: ${hits%%$'\n'*}"
done
for pat in "${absent_ci_literals[@]}"; do
	hits="$(grep -niF -- "$pat" "${main_script}" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
	[ -z "${hits}" ] || fail "kejilion.sh 仍含已删功能词汇（忽略大小写） [${pat}]（非注释行）: ${hits%%$'\n'*}"
done

# ===========================================================================
# 断言 2：仓库根孤儿文件不存在
#   这些文件全部随所属板块在本轮删除；任何一个回来都意味着删掉的板块复活了
#   （其中 mc.sh / palworld.sh 含"按 k 把原版未净化的 kejilion.sh 下载回 ~/ 并
#   直接运行"的后门，仓库副本留着就是报信复活的落脚点）。
#   保留的兄弟文件（TG-*.sh / upgrade_openssh9.8p1.sh / archive.key /
#   fail2ban-ssh.conf）与 cloudflare.conf 一个都不进这个清单，见断言 2b。
# ===========================================================================
orphan_files=(
	# —— 游戏开服本体与其附属脚本（工单 #22）——
	palworld.sh pal_backup.sh pal_log.sh mc.sh mc_backup.sh mc_log.sh
	# —— 三类 AI 面板本体（工单 #19）——
	ai_cli_manager.sh hermes_manager.sh deepseek_harness_manager.sh
	# —— network-optimize 外部脚本（工单 #21）——
	network-optimize.sh
	# —— LDNMP 建站 / 证书续签 / 建站防护（工单 #20）——
	ldnmp.sh auto_cert_renewal.sh auto_cert_renewal-1.sh beifen.sh CF-Under-Attack.sh
	fail2ban-nginx-cc.conf nginx-docker-cc.conf cloudflare-docker.conf
	custom_mysql_config.cnf custom_mysql_config-1.cnf optimized_php.ini www.conf www-1.conf
	# —— 真孤儿 / 内联生成的仓库副本 / OpenClaw 冒灰脚本（工单 #22、#19）——
	Limiting_Shut_down.sh Limiting_Shut_down1.sh check_x86-64_psabi.sh
	sshd.local nginx.local valkey.conf
	tests_openclaw_manager_smoke.sh run_openclaw_manager_matrix.sh
	# —— 更新功能残留（工单 #7）——
	kejilion_sh_log.txt
	# —— 已退役的协作文档（工单 #22）——
	CONTRIBUTING.md
)
for f in "${orphan_files[@]}"; do
	[ ! -e "${project_root}/${f}" ] ||
		fail "仓库根孤儿文件仍存在: ${f}（规格 #15 已删除，不得复活）"
done

# ---- 断言 2b：保留的兄弟文件一个不少（删过头就是事故）----
kept_files=(
	TG-check-notify.sh            # 系统工具 13-25 TG-bot 系统监控预警
	TG-SSH-check-notify.sh        # 系统工具 13-25 SSH 登录通知
	upgrade_openssh9.8p1.sh       # 系统工具 13-26 修复 OpenSSH 高危漏洞
	archive.key                   # BBR 管理 XanMod 签名钥的回退源
	fail2ban-ssh.conf             # 工单 #23 收编的 fail2ban SSH 防御配置
	cloudflare.conf               # 凭据体检占位说明（README 后续事项 #2 记账）
)
for f in "${kept_files[@]}"; do
	[ -e "${project_root}/${f}" ] ||
		fail "保留的兄弟文件意外缺失: ${f}（删过头就是事故，规格 #15 明确保留）"
done

# ===========================================================================
# 断言 3：取内容 URL 只从本仓库
#   3a 正面：留存取内容目标全部以本仓库 raw 形式在位（防靠删 URL 凑清零）；
#   3b 负面：指向原版名下的 URL 清零（URL 路径级，不是主机名级）。
#       raw.githubusercontent.com 对 kejilion/* 与 howi3c/* 是同一直连主机，
#       只比主机名分不出来源，故直接 grep owner/repo 路径段。
#
#   实现：调用 tests/test_network_inventory.sh --assert-clean，不在这里重抄判据。
#   原先本文件抄了第二份同名正则与第二份 5 个取内容目标清单——换一次 raw 基址
#   要动两处，是典型的双写（Duplicated Code）。判据与口径改由那一个脚本独揽，
#   本处只把它的输出原样带出，与断言 4 对 README 守门"调用而非重抄"同一手法。
#   顺带比原先更强：--assert-clean 同时守"报信=0"，这里一并继承。
# ===========================================================================
url_out="$(bash "${project_root}/tests/test_network_inventory.sh" \
	--assert-clean "${main_script}" 2>&1)" || {
	printf '%s\n' "${url_out}" >&2
	fail "取内容 URL 判据未过（报信 / 原版名下 URL 清零 / 留存 URL 指向本仓库），判据由 tests/test_network_inventory.sh --assert-clean 独揽，细节见上面原样带出的输出: ${main_script}"
}
# fail2ban 配置收编后的部署文件名保持不变（用户机 jail 名），这是允许的。
# 这条只有本守卫在守（清点检查只判 URL，不判部署文件名），故留在这里。
grep -qF -- '--output centos-ssh.conf' "${main_script}" ||
	fail "fail2ban SSH 防御配置的部署文件名（--output centos-ssh.conf）不应改动"

# ===========================================================================
# 断言 4：与 README 守门交叉确认（调用而非重抄）
#   本测试断言 1/3 只覆盖主脚本；"用户照 README 能把未净化的原版装回来"是一条
#   只活在 README 的风险，由既有两个守门各守一头。用返回码判定，判据演进时
#   自动跟随，不会两处漂移。
# ===========================================================================
bash "${project_root}/tests/test_readme_install_source.sh" >/dev/null 2>&1 ||
	fail "README 安装来源守门未过（与删除守卫交叉确认失败）：tests/test_readme_install_source.sh"
bash "${project_root}/tests/test_readme_no_upstream_refs.sh" >/dev/null 2>&1 ||
	fail "README 不残留原版引用守门未过（与删除守卫交叉确认失败）：tests/test_readme_no_upstream_refs.sh"
# 一条很轻的护栏重合点：只确认 README 的安装命令与本守卫的 repo_raw 指向同一个
# fork，不复制 install_source 的分节解析逻辑。
grep -Fq 'raw.githubusercontent.com/howi3c/sh' "${project_root}/README.md" ||
	fail "README 未指向本仓库 raw 基址（应与 repo_raw 指向同一个 fork）"

# ===========================================================================
if [ "${fail_count}" -ne 0 ]; then
	printf 'spec15-slim-down-removed: FAIL（%s 处）\n' "${fail_count}" >&2
	exit 1
fi
printf '%s\n' 'spec15-slim-down-removed=pass'

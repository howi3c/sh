#!/bin/bash
# 工单 #7「更新功能整体删除」的验收尺子
#
# 背景（父工单 #1 用户故事 11 / Implementation Decisions）：
#   "更新功能整体删除：检查更新、更新日志、立即更新、自动更新开关与定时任务
#    全部移除。" 核心目的是净化版永远不会被原版整体覆盖、已连根拔掉的报信
#    不会随覆盖复活。
#
# 守的缝（全部是外部行为/不变量，不碰内部实现细节）：
#   1. 自更新函数 kejilion_update() 及其全部引用消失；
#   2. 主菜单不再渲染"脚本更新"项、不再有 00) 分发行
#      （菜单渲染与分发行为由 test_main_menu_noninteractive_smoke.sh 守，
#        这里只做静态存在性判据）；
#   3. 不存在"从原版仓库下载并替换脚本"的代码路径：
#        · main/kejilion.sh 下载地址零命中
#        · 更新日志 kejilion_sh_log.txt 零命中
#        · 更新前的备份/回滚 kejilion.sh.bak 零命中
#   4. 自动更新定时任务的 crontab 写入/清理不存在；唯一允许保留的是
#      "卸载脚本"时清理用户机器上既存任务的辅助代码（纯本地、不下载任何东西，
#        对用户有益）；
#   5. 误删防护：原版仓库里其余取内容目标一个不少（清单取自删除前的原版脚本，
#      属独立基准，不随本次改动推导）。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${project_root}/kejilion.sh"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "${script}" ] || fail "找不到待测脚本: ${script}"

# ---------------------------------------------------------------------------
# 判据 5 的独立基准：改造前的原版脚本从原版仓库取内容的全部目标。
# 删除要拿掉的目标分五类，其余一条都不许少：
#   1. "自更新/自覆盖"目标（kejilion.sh、kejilion_sh_log.txt）；
#   2. network-optimize 外部脚本的两个地址（工单 #21）；
#   3. 应用市场 hermes / deepseek 两个管理器脚本的下载地址（工单 #17）；
#   4. AI 面板 ai_cli_manager 的下载地址（工单 #19）；
#   5. 游戏开服 palworld.sh / mc.sh 两个下载地址（工单 #22）。
#
# 【工单 #21 改写说明】network-optimize 外部脚本不再取内容，那两个地址从清单删掉。
#
# 【工单 #17 改写说明】应用市场整块退场，原 linux_panel 里那两行
#   bash <(curl …/hermes_manager.sh)
#   bash <(curl …/deepseek_harness_manager.sh)
# 随函数体一起消失，这两条下载目标从 kejilion.sh 中清零，清单同步删掉。
#
# 【工单 #19 改写说明】AI 与 OpenClaw 整块删除：run_ai_cli_manager 函数体里的
#   raw…/main/ai_cli_manager.sh
# 一并消失，清单删掉这一条；仓库根的 hermes_manager.sh /
# deepseek_harness_manager.sh / ai_cli_manager.sh 三个文件本体也已在本工单删除。
#
# 【工单 #20 改写说明】LDNMP 建站整块删除，随板块一起消失的取内容目标共 8 条：
#   raw…/main/custom_mysql_config.cnf（变量 ${mysql_source}，nginx_upgrade）
#   raw…/main/www.conf（变量 ${php_fpm_source}，fix_phpfpm_conf）
#   raw…/main/www-1.conf（variables 同 ${php_fpm_source}，php 7.4 分支）
#   raw…/main/custom_mysql_config-1.cnf（update_docker_compose_with_db_creds）
#   raw…/main/optimized_php.ini（web_optimization）
#   raw…/main/auto_cert_renewal.sh（install_certbot）
#   raw…/main/beifen.sh（linux_ldnmp 站点远程备份）
#   raw…/main/CF-Under-Attack.sh（web_security / ldnmp_protection_action_apply）
#   raw…/main/fail2ban-nginx-cc.conf（web_security / ldnmp_protection_action_apply）
# 这些 URL 在 kejilion.sh 里已不存在（删后 grep -F 计数为 0），故从清单删掉。
# 注意 fail2ban-nginx-cc.conf 是 nginx CC 防护配置，随建站退场、不收编；
# fail2ban SSH 防御配置（centos-ssh.conf，f2b_install_sshd 内）不在本清单口径内
# （它取自 kejilion/config 仓，且属 #23 收编范围），不受本次改写影响。
#
# 【工单 #22 追加说明】集群菜单「安装原作者脚本」项（#16 断入口）的函数体
#   cluster_python3() 与游戏开服 games_server_tools() 整函数，随工单 #22
#   一并删除；函数体里那两行
#     curl -sS -O …/kejilion/sh/main/palworld.sh ; ./palworld.sh
#     curl -sS -O …/kejilion/sh/main/mc.sh ; ./mc.sh
#   从 kejilion.sh 中清零，故这两条下载目标移入 removed_targets。这两个游戏
#   脚本按 k 会把原版未净化的 kejilion.sh 下载回 ~/ 并直接运行，是"报信复活"
#   路径；仓库根的本体 palworld.sh / pal_backup.sh / pal_log.sh / mc.sh /
#   mc_backup.sh / mc_log.sh 也随工单 #22 一并删除。
#
# 判据始终只有一条：kejilion.sh 里该 URL 已不存在，不按文件是否存在推导。
#
# 【工单 #23 改写说明】取内容来源收敛到本仓库（ADR-0002）后，判据 5 的 4 个
# 幸存目标仍在 kejilion.sh 里，但 URL 的 owner/repo 从原版 kejilion/sh 改为
# 本仓库 howi3c/sh。本尺子的本意是"误删防护"（保留的取内容目标一条不少），
# 故把 expected_targets 的基准同步为本仓库 raw 基址，继续守这 4 个目标不丢。
# 原版名下的 URL 清零由新增守门 tests/test_spec15_slim_down_removed.sh 负责，
# 那里保留了对 kejilion 组织路径的反向清零断言。
#
# 【工单 #24 改写说明】这 4 个目标是全仓库**第三份**兄弟文件名清单。另两份：
#   · tests/test_network_inventory.sh 的 assert_upstream_urls_impl —— 判据的
#     唯一实现（5 个目标 + 原版 URL 清零正则），删除守卫已改为调用它；
#   · tests/test_spec15_slim_down_removed.sh —— 现在同样调用上面那个函数。
# 本清单**故意**保持独立基准：它是"改造前的原版脚本"推导出来的误删防护口径，
# 只列 4 个目标（不含工单 #23 才收编的 fail2ban-ssh.conf），不从上面那份推导。
# 若将来第 5 个兄弟文件也要进这份误删防护，改这里即可，但要同时核对其余两处
# 的说明是否还成立。
# ---------------------------------------------------------------------------
repo_base='raw.githubusercontent.com/howi3c/sh'
expected_targets=(
	"${repo_base}/main/archive.key"
	"${repo_base}/main/TG-check-notify.sh"
	"${repo_base}/main/TG-SSH-check-notify.sh"
	"${repo_base}/main/upgrade_openssh9.8p1.sh"
)
# 本次删除要拿掉的自更新目标（基准仍是原版仓库地址，判据是"这些 URL 已不存在"）
orig_base='raw.githubusercontent.com/kejilion/sh'
removed_targets=(
	"${orig_base}/main/kejilion.sh"
	"${orig_base}/main/kejilion_sh_log.txt"
	"${orig_base}/refs/heads/main/network-optimize.sh"
	"${orig_base}/main/mc.sh"
	"${orig_base}/main/palworld.sh"
	"${orig_base}/main/\${mysql_source}"
	"${orig_base}/main/\${php_fpm_source}"
	"${orig_base}/main/auto_cert_renewal.sh"
	"${orig_base}/main/beifen.sh"
	"${orig_base}/main/CF-Under-Attack.sh"
	"${orig_base}/main/custom_mysql_config-1.cnf"
	"${orig_base}/main/fail2ban-nginx-cc.conf"
	"${orig_base}/main/optimized_php.ini"
)

check_one_script() {
	local f="$1" label="$2"
	[ -f "${f}" ] || fail "${label}: 文件不存在"

	# ---- 判据 1：自更新函数本体与全部引用 ----
	local update_hits
	update_hits="$(grep -n 'kejilion_update' "${f}" || true)"
	[ -z "${update_hits}" ] || fail "${label}: 仍存在 kejilion_update 引用:
${update_hits}"

	# ---- 判据 2：主菜单"脚本更新"渲染行 + 00 分发行 ----
	local menu_hits
	menu_hits="$(grep -n '脚本更新\|00)[[:space:]]*kejilion_update' "${f}" || true)"
	[ -z "${menu_hits}" ] || fail "${label}: 仍存在通向更新功能的菜单入口:
${menu_hits}"

	# ---- 判据 3：下载并替换脚本的路径 / 更新日志 / 备份回滚 ----
	local pattern hits
	for pattern in 'kejilion_sh_log' 'kejilion\.sh\.bak' 'SH_Update_task'; do
		hits="$(grep -nE "${pattern}" "${f}" || true)"
		[ -z "${hits}" ] || fail "${label}: 仍存在更新功能残留(${pattern}):
${hits}"
	done
	local target
	for target in "${removed_targets[@]}"; do
		hits="$(grep -nF "${target}" "${f}" || true)"
		[ -z "${hits}" ] || fail "${label}: 仍存在从原版仓库下载脚本的地址(${target}):
${hits}"
	done

	# ---- 判据 4：crontab 里只剩"卸载时清理用户机器上既存任务"的那一条 ----
	local cron_hits cron_count
	cron_hits="$(grep -n 'crontab' "${f}" | grep 'kejilion\.sh' || true)"
	cron_count="$(printf '%s\n' "${cron_hits}" | grep -c . || true)"
	[ "${cron_count}" -eq 1 ] ||
		fail "${label}: 触到 crontab 且提及 kejilion.sh 的行应有 1 条（卸载清理），实为 ${cron_count}:
${cron_hits}"
	printf '%s\n' "${cron_hits}" | grep -Fq 'grep -v "kejilion.sh"' ||
		fail "${label}: 剩下的那条 crontab 行不是"卸载时清理旧任务"的形态:
${cron_hits}"
	printf '%s\n' "${cron_hits}" | grep -Eq 'curl|wget|download|kejilion\.sh\.bak|SH_Update_task' &&
		fail "${label}: 剩下的清理行里夹带了下载/备份逻辑:
${cron_hits}"

	# ---- 判据 5：误删防护，其余取内容目标一条不少 ----
	local missing=""
	for target in "${expected_targets[@]}"; do
		grep -qF "${target}" "${f}" || missing="${missing} ${target}"
	done
	[ -z "${missing}" ] || fail "${label}: 误删了取内容目标:${missing}"
}

# ---------------------------------------------------------------------------
# 判据 6：游戏开服的 6 个仓库根脚本不得再回到仓库里
#   工单 #22 删的不只是 kejilion.sh 里的下载行，还有仓库根的本体——
#   palworld.sh:419 与 mc.sh:416 的 k 分支会把原版未净化的 kejilion.sh
#   下载到 ~/ 并直接运行，文件留着就是"报信复活"的落脚点。
# ---------------------------------------------------------------------------
for f in palworld.sh pal_backup.sh pal_log.sh mc.sh mc_backup.sh mc_log.sh; do
	[ -e "${project_root}/${f}" ] && fail "${f} 又回到了仓库（游戏开服脚本，工单 #22 已删除，含按 k 下载原版 kejilion.sh 的后门）"
done

check_one_script "${script}" "kejilion.sh"

printf '%s\n' "update-removed=pass"

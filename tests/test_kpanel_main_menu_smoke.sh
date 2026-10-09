#!/bin/bash
set -euo pipefail

# 工单 #6「闭源面板整块移除」的守门尺子。
#
# 【命名例外 · 工单 #12】tests/ 下其余本地系统适配器测试已把 kpanel 前缀改掉——kpanel
# 在脚本里有两层含义：一层是给二进制那一层（kejilion-node 那套闭源面板）起的名字，
# 已整块移除；另一层是纯本地系统工具适配器（system-resource / disk-management 等），
# 仍在服务。唯独本测试保留 kpanel 之名：它是这个被删名字的**反向守门人**，逐条断言
# 二进制那一层的痕迹（kejilion-node、kpanel_node_、KPanel/releases、
# KJ_LIGHT_NODE_PROTOCOL、每小时 crontab 行）必须为 0。名字恰带 kpanel，
# 后来者一眼就知它在盯"kpanel 那一层不许回来"，故不改。
#
# 【工单 #17 改写说明】应用市场板块整块退场（工单 #17）后，本尺子的职责收窄，
# 现在只守两件事：
#   1. 闭源面板二进制那一层的痕迹为零（kejilion-node / KPanel/releases /
#      KPANEL_NODE_ / kpanel_node_ / KJ_LIGHT_NODE_PROTOCOL / ssh-login-broker /
#      每小时自更新 crontab 行 / 主菜单第 17 项 / k_info 帮助行 / CLI node 分支）；
#   2. 纯本地系统工具适配器一条不少（协议门变量与各自的 dispatch 函数族）。
# 随板块退役、本文件不再断言的内容：
#   · 原「保留边界」里的 linux_panel() 与 refresh_apps_catalog —— 二者是应用市场
#     本体，已整体删除，保留清单反转为"只剩系统工具适配器"；
#   · 原两个行为场景（linux_panel kpanel 拒绝、应用市场里手输 kpanel 拒绝）——
#     拒绝逻辑本就在 linux_panel 函数体开头，随函数体一起退役。工单 #17 验收第 2 条
#     明确"不保留防已删之物的代码"，行为断言与它守护的函数同生共死。
#     linux_panel 已不存在，再驱动它只会测一个空壳，故 harness 一并退役。
#
# 守的缝（都是外部行为与不变量，不碰内部实现细节）：
#   1. 主菜单里「KPanel Web管理面板」入口整体消失：已安装状态变量、两行渲染
#      文本、17) linux_panel kpanel 分发行，一个都不许回来；
#   2. k_info() 帮助里的 KPanel管理 一行消失；k kpanel CLI 的 node 分支消失，
#      纯本地适配器分支（system-resource / disk-management / network-operations /
#      account-management / system-tuning / virus-scan）一条不少；
#   3. 脚本里不再有该闭源二进制的任何痕迹：kejilion-node 本体、KPanel releases
#      下载地址、KPANEL_NODE_* 常量与 kpanel_node_* 函数族、每小时自更新
#      （kejilion-node-update.timer / 17 * * * * crontab 行 / periodic/hourly）、
#      SSH 登录采集服务（kejilion-node-ssh-login）、KJ_LIGHT_NODE_PROTOCOL 协议门；
#   4. 保留边界不塌：协议门 kpanel_protocol_active 与本地适配器函数族原样在。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

for script_path in "${project_root}/kejilion.sh"; do
	[ -f "${script_path}" ] || fail "找不到待测脚本: ${script_path}"
	bash -n "${script_path}" || fail "语法检查未通过: ${script_path}"

	menu_body="$(
		awk '
			/^kejilion_sh\(\) \{/ { capture=1 }
			capture { print }
			capture && /^}$/ { exit }
		' "${script_path}"
	)"
	[ -n "${menu_body}" ] || fail "未能截取 kejilion_sh() 主菜单: ${script_path}"

	# ---- 删除面一：主菜单第 17 项「KPanel Web管理面板」整体消失 ----
	for gone in \
		'kpanel_menu_status' \
		'grep -qxF "kpanel" /home/docker/appno.txt' \
		'KPanel Web管理面板' \
		'kejilion.sh 的现代化网页管理界面' \
		'17) linux_panel kpanel ;;'
	do
		if grep -Fq "${gone}" <<<"${menu_body}"; then
			fail "主菜单仍残留 KPanel 入口痕迹[${gone}]: ${script_path}"
		fi
	done

	# ---- 删除面二：帮助行、CLI node 分支、二进制与它的周边机器 ----
	for gone in \
		'KPanel管理          k app kpanel' \
		'kpanel_node_dispatch' \
		'kejilion-node' \
		'KPanel/releases' \
		'KPANEL_NODE_' \
		'kpanel_node_' \
		'KJ_LIGHT_NODE_PROTOCOL' \
		'ssh-login-broker' \
		'17 * * * * /usr/local/lib/kejilion-node/update-cron.sh'
	do
		if grep -Fq "${gone}" "${script_path}"; then
			fail "脚本仍残留闭源面板痕迹[${gone}]: ${script_path}"
		fi
	done

	# ---- 删除面二·补：应用市场整块退役后，k app 这条 CLI 入口也不许回来 ----
	# 为什么这里要守 k app：命令行是菜单之外的第二条入口。应用市场（工单 #17）
	# 整块退役后，"k app"若还通向 linux_panel，等于闭源面板从命令行复活——
	# 菜单里看不到了，用命令照样能调出来。linux_panel() 的函数体归工单 #17 删除，
	# 这里只守"命令行不再分发到它"。
	cli_dispatch_body="$(
		awk '
			/^[[:space:]]*case \$1 in[[:space:]]*$/ { capture=1 }
			capture { print }
			capture && /^[[:space:]]*esac[[:space:]]*$/ { exit }
		' "${script_path}"
	)"
	[ -n "${cli_dispatch_body}" ] || fail "未能截取 case \$1 in CLI 分发块: ${script_path}"
	for retired_entry in \
		'linux_panel' \
		'games_server_tools' \
		'linux_ldnmp' \
		'frps_panel' \
		'frpc_panel' \
		'moltbot_menu'
	do
		if grep -Fq "${retired_entry}" <<<"${cli_dispatch_body}"; then
			fail "CLI 分发块仍通向已退役板块[${retired_entry}]: ${script_path}"
		fi
	done
	if grep -Eq '^[[:space:]]*app\)[[:space:]]*$' <<<"${cli_dispatch_body}"; then
		fail "CLI 分发块仍残留 app) 分支（应用市场已随工单 #15/#17 退役）: ${script_path}"
	fi

	# node 分支从 k kpanel 的分发段里消失，本地适配器分支一条不少
	kpanel_cli_body="$(
		awk '
			/^[[:space:]]*kpanel\)[[:space:]]*$/ { capture=1 }
			capture { print }
			capture && /^[[:space:]]*;;[[:space:]]*$/ { exit }
		' "${script_path}"
	)"
	[ -n "${kpanel_cli_body}" ] || fail "未能截取 k kpanel CLI 分发段: ${script_path}"
	for adapter in \
		'system-resource' \
		'disk-management' \
		'network-operations' \
		'account-management' \
		'system-tuning' \
		'virus-scan'
	do
		grep -Fq "${adapter}" <<<"${kpanel_cli_body}" ||
			fail "k kpanel CLI 丢了纯本地适配器分支[${adapter}]: ${script_path}"
	done
	if grep -Fqw 'node' <<<"${kpanel_cli_body}"; then
		fail "k kpanel CLI 仍残留 node 分支: ${script_path}"
	fi

	# ---- 保留边界：协议门与本地适配器函数族原样在 ----
	# 工单 #17 起收窄：应用市场（linux_panel / refresh_apps_catalog）已整块
	# 退场，保留清单反转为"只剩系统工具适配器"——上面删除面一/二的零痕迹
	# 断言继续守"闭源二进制不许回来"，这里守"留存能力不许被误伤"。
	for kept in \
		'kpanel_protocol_active() {' \
		'kpanel_ssh_port_noninteractive() {' \
		'kpanel_set_dns_noninteractive() {' \
		'kpanel_f2b_manager_dispatch() {' \
		'kpanel_system_tuning_dispatch() {' \
		'kpanel_virus_scan_dispatch() {' \
		'kpanel_account_dispatch() {' \
		'kpanel_disk_management_dispatch() {' \
		'kpanel_network_operations_dispatch() {' \
		'kpanel_system_resource_dispatch() {'
	do
		grep -Fq "${kept}" "${script_path}" ||
			fail "保留边界被误伤[${kept}]: ${script_path}"
	done

	# 协议门仍认全部保留板块的本地适配器环境变量。
	# 工单 #15/#16：应用市场与建站的非交互闸门随板块退役，KJ_APP_* /
	# KJ_WEB_* / KJ_LDNMP_NONINTERACTIVE 五个变量已从闸门移除；系统工具、
	# 系统调优、集群控制、BBRv3、测试合集的闸门一律保留（下面逐条反向断言）。
	protocol_body="$(
		awk '
			/^kpanel_protocol_active\(\) \{/ { capture=1 }
			capture { print }
			capture && /^}$/ { exit }
		' "${script_path}"
	)"
	[ -n "${protocol_body}" ] || fail "未能截取 kpanel_protocol_active(): ${script_path}"
	for variable in \
		'KJ_SSH_PORT_NONINTERACTIVE' \
		'KJ_DNS_NONINTERACTIVE' \
		'KJ_SYSTEM_RESOURCE_NONINTERACTIVE' \
		'KJ_DISK_MANAGEMENT_NONINTERACTIVE' \
		'KJ_NETWORK_OPERATIONS_NONINTERACTIVE' \
		'KJ_ACCOUNT_MANAGEMENT_NONINTERACTIVE' \
		'KJ_F2B_NONINTERACTIVE' \
		'KJ_SYSTEM_TUNING_NONINTERACTIVE' \
		'KJ_VIRUS_SCAN_NONINTERACTIVE' \
		'KJ_TEST_NONINTERACTIVE'
	do
		grep -Fq "${variable}" <<<"${protocol_body}" ||
			fail "协议门丢了本地适配器环境变量[${variable}]: ${script_path}"
	done

	# 反向：随应用市场 / 建站退役的五个闸门变量不许回来。
	# （只在协议门函数体内断言——这些变量在被删板块的函数体里还有残留，
	#   那些函数体归工单 #17/#20，不在本守门的射程内。）
	for retired_variable in \
		'KJ_APP_NONINTERACTIVE' \
		'KJ_APP_INTERACTIVE' \
		'KJ_WEB_NONINTERACTIVE' \
		'KJ_WEB_INTERACTIVE' \
		'KJ_LDNMP_NONINTERACTIVE'
	do
		if grep -Fq "${retired_variable}" <<<"${protocol_body}"; then
			fail "协议门仍残留随板块退役的闸门变量[${retired_variable}]: ${script_path}"
		fi
	done
done

printf '%s\n' 'PASS: KPanel 闭源面板痕迹为零、纯本地适配器保留边界未塌'

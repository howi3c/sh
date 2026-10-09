#!/bin/bash
set -euo pipefail

# 工单 #6「闭源面板整块移除」的守门尺子。
#
# 【命名例外 · 工单 #12】tests/ 下其余本地系统适配器测试已把 kpanel 前缀改掉——kpanel
# 在脚本里有两层含义，见 docs/kpanel-removal-keep-list.md 第二节。唯独本测试保留 kpanel
# 之名：它是这个被删名字的**反向守门人**，逐条断言二进制那一层的痕迹（kejilion-node、
# kpanel_node_、KPanel/releases、KJ_LIGHT_NODE_PROTOCOL、每小时 crontab 行）必须为 0。
# 名字恰带 kpanel，后来者一眼就知它在盯"kpanel 那一层不许回来"，故不改。
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
#   4. 保留边界不塌：应用市场（linux_panel 无参 + 第三方应用目录机制）、协议门
#      kpanel_protocol_active 与 KJ_*_NONINTERACTIVE 本地适配器函数族原样在；
#   5. 行为断言：应用编号 kpanel（k app kpanel 与交互菜单里手输）一律拒绝，
#      且拒绝发生在拉取第三方应用目录之前——不存在再把它装回来的代码路径。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

behavior_root="$(mktemp -d)"
cleanup() { rm -rf -- "${behavior_root}"; }
trap cleanup EXIT

# 截取入口分发块之前的全部函数定义，供 harness 直接驱动 linux_panel。
# 手法与 tests/test_main_menu_noninteractive_smoke.sh 同源：stub 掉全部副作用，
# 借用 KJ_TEST_NONINTERACTIVE=1 跳过 source 期间的真实副作用。
prepare_functions_only() { # $1=待测脚本
	awk '/^if \[ "\$#" -eq 0 \]; then$/ { exit } { print }' "$1" \
		>"${behavior_root}/functions_only.sh"
	bash -n "${behavior_root}/functions_only.sh" || fail "截取出的函数定义部分语法不合法: $1"
}

cat >"${behavior_root}/run.sh" <<'HARNESS'
#!/bin/bash
set -u
KJ_TEST_NONINTERACTIVE=1
source "${HARNESS_FUNCTIONS}"

# source 之后再定义 stub：后定义者优先（与主菜单冒烟同一手法）。
# 分发目标与副作用命令只记录不执行，绝不碰网络与真实系统状态。
record() { printf '%s\n' "$*" >>"${HARNESS_DISPATCH_LOG}"; }
clear() { :; }
break_end() { :; }
refresh_apps_catalog() { record "refresh_apps_catalog"; return 0; }
kejilion() { record "kejilion"; exit 0; }
kejilion_sh() { record "kejilion_sh"; exit 0; }
# 拒绝必须发生在渲染应用市场、等待输入之前；真走到交互 read 说明拒绝失效。
if [ "${HARNESS_STUB_READ:-0}" = "1" ]; then
	read() { printf 'linux_panel 走到了交互 read（应用市场菜单）\n' >&2; exit 42; }
fi
linux_panel "$@"
HARNESS

# run_linux_panel <喂给 read 的输入> [传给 linux_panel 的参数...]
# 结果写进 behavior_status / behavior_output / ${behavior_root}/dispatch.log
run_linux_panel() {
	local feed="$1"
	shift
	: >"${behavior_root}/dispatch.log"
	behavior_status=0
	behavior_output="$(
		printf '%s\n' "${feed}" |
			HARNESS_DISPATCH_LOG="${behavior_root}/dispatch.log" \
				HARNESS_FUNCTIONS="${behavior_root}/functions_only.sh" \
				HARNESS_STUB_READ=1 \
				HOME="${behavior_root}/home" \
				bash "${behavior_root}/run.sh" "$@" 2>&1
	)" || behavior_status=$?
}

mkdir -p "${behavior_root}/home"

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
	# （notes/02-entry-points.md 第 6 节：应用市场删除后需补"k app 亦不存在"。
	#   linux_panel() 的函数体归工单 #17，这里只守"命令行不再分发到它"。）
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

	# ---- 保留边界：应用市场、协议门、本地适配器函数族原样在 ----
	for kept in \
		'linux_panel() {' \
		'refresh_apps_catalog || return 1' \
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

	# ---- 行为断言：应用编号 kpanel 一律拒绝，且拒绝前不拉第三方应用目录 ----
	prepare_functions_only "${script_path}"

	# 场景一：k app kpanel（原主菜单 17 与 CLI 走的同一条路）。
	# 拒绝发生在最前面：不刷新应用目录、不渲染菜单、不等待输入。
	run_linux_panel '' kpanel
	[ "${behavior_status}" -eq 2 ] ||
		fail "linux_panel kpanel 未以退出码 2 拒绝（实际 ${behavior_status}）: ${behavior_output}"
	grep -Fq '闭源面板已从本脚本移除' <<<"${behavior_output}" ||
		fail "linux_panel kpanel 拒绝时未说明原因: ${behavior_output}"
	if grep -Fq 'refresh_apps_catalog' "${behavior_root}/dispatch.log"; then
		fail "linux_panel kpanel 拒绝前仍拉取了第三方应用目录: ${script_path}"
	fi

	# 场景二：应用市场里手动输入 kpanel（第三方应用列表的选中路径）。
	# 这里 refresh_apps_catalog 会被调用一次（应用市场本就先拉目录），
	# 但选中 kpanel 必须被拒绝，而不是去 source 该二进制的外部安装配置。
	: >"${behavior_root}/dispatch.log"
	behavior_status=0
	behavior_output="$(
		printf '%s\n' 'kpanel
0' |
			HARNESS_DISPATCH_LOG="${behavior_root}/dispatch.log" \
				HARNESS_FUNCTIONS="${behavior_root}/functions_only.sh" \
				HARNESS_STUB_READ=0 \
				HOME="${behavior_root}/home" \
				bash "${behavior_root}/run.sh" "" 2>&1
	)" || behavior_status=$?
	[ "${behavior_status}" -eq 2 ] ||
		fail "应用市场里输入 kpanel 未以退出码 2 拒绝（实际 ${behavior_status}）: ${behavior_output}"
	grep -Fq '闭源面板已从本脚本移除' <<<"${behavior_output}" ||
		fail "应用市场里输入 kpanel 拒绝时未说明原因: ${behavior_output}"
	if grep -Fq '未找到编号为' <<<"${behavior_output}"; then
		fail "应用市场里输入 kpanel 走了第三方应用配置查找: ${behavior_output}"
	fi
done

printf '%s\n' 'PASS: KPanel 闭源面板入口已移除、纯本地适配器与行为拒绝均在位'

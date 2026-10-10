#!/bin/bash
set -euo pipefail

# 缝 2 · 非交互主菜单冒烟。
#
# 目的：后续每一项清洗（删报信、拆面板、清广告、删更新……）都可能动到
# kejilion_sh() 主菜单及其分发目标。本测试是回归尺子：不改任何系统状态，
# 验证主菜单仍能完整渲染、每个编号入口仍能分派到目标函数、且分发后能回到菜单。
#
# 手法（沿用 tests/ 下既有冒烟测试的做法）：
#   1. 截取脚本里“入口分发块”之前的全部内容（含全部函数定义）到临时副本，
#      这样可以在测试进程里 source 之后自己驱动 kejilion_sh，而不是跑整脚本。
#   2. source 之前把 sed/cp/ln 等写系统的命令换成记录型 stub——即使将来
#      顶部“复制到 /usr/local/bin/k、写 ~/.bashrc”那段副作用块改头换面，
#      冒烟也绝不会真的改到开发机；真有调用会写进分发日志并被断言拦下。
#   3. 借用脚本自己的 KJ_*_NONINTERACTIVE=1 协议，让 source 时跳过首屏
#      许可弹窗与别名安装等真实副作用。
#   4. source 之后再定义 stub：后定义者优先，菜单分发目标（linux_info 等）
#      与副作用命令（install/curl/wget/systemctl/send_stats 等）全部只记录
#      不执行，从而逐个入口验证分发且不触发任何真实安装。
#
# 菜单编号→目标的映射表是“当前版本”的快照：后续工单若有意增删菜单项，
# 同步更新 dispatch_cases，尺子会明确指出是哪一项对不上。
#
# 工单 #15/#16「净化版瘦身」：建站(10)、应用市场(11)、游戏开服(16) 三块整块退役，
# 编号按“菜单空号策略”留空不重排，终局渲染集合为 1–9、12、13、14、0。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
dispatch_log="${test_root}/dispatch.log"
: >"${dispatch_log}"

fail() {
	echo "$*" >&2
	exit 1
}

[ -f "${script_path}" ] || fail "找不到待测脚本: ${script_path}"

# 入口分发块的锚点必须存在且唯一：锚点消失说明脚本结构变了，
# 此时绝不能把整份脚本 source 进 harness（那会在 source 期间就跑起菜单）。
anchor_count="$(grep -c '^if \[ "\$#" -eq 0 \]; then$' "${script_path}")"
[ "${anchor_count}" -eq 1 ] ||
	fail "${script_path} 里入口分发块锚点不唯一或不存在（共 ${anchor_count} 处），脚本结构已变，需同步维护本冒烟"

# 截到“有参数就跑分发”的入口块为止，只保留函数定义，供 harness 驱动。
awk '/^if \[ "\$#" -eq 0 \]; then$/ { exit } { print }' "${script_path}" >"${test_root}/functions_only.sh"
test -s "${test_root}/functions_only.sh" || fail "未能从 ${script_path} 截取函数定义部分（找不到入口分发块）"
bash -n "${test_root}/functions_only.sh" || fail "截取出的函数定义部分语法不合法"

# 非交互 harness：source 函数定义，stub 掉全部副作用，然后驱动主菜单。
cat >"${test_root}/run.sh" <<'HARNESS'
#!/bin/bash
set -u
test_root="$1"
dispatch_log="${test_root}/dispatch.log"

# source 之前：先把会写系统的命令换成只记录的 stub（纵深防御，
# 正常情况下这些 stub 一次都不该被触发；被触发说明副作用漏进了冒烟）。
log_stub_call() { printf '%s\n' "$*" >>"${dispatch_log}"; }
sed() { log_stub_call "sed $*"; return 99; }
cp() { log_stub_call "cp $*"; return 99; }
mv() { log_stub_call "mv $*"; return 99; }
ln() { log_stub_call "ln $*"; return 99; }

# 借用脚本自己的非交互协议，跳过 source 时的真实副作用。
KJ_TEST_NONINTERACTIVE=1
source "${test_root}/functions_only.sh"

# source 之后：后定义的函数优先，分发目标与副作用命令只记录不执行。
record() { printf '%s\n' "$*" >>"${dispatch_log}"; }
clear() { :; }
break_end() { :; }
send_stats() { record "send_stats $*"; }
install() { record "install $*"; return 99; }
remove() { record "remove $*"; return 99; }
apt() { record "apt $*"; return 99; }
yum() { record "yum $*"; return 99; }
dnf() { record "dnf $*"; return 99; }
systemctl() { record "systemctl $*"; return 99; }
curl() { record "curl $*"; return 99; }
wget() { record "wget $*"; return 99; }

linux_info() { record "dispatch linux_info${*:+ $*}"; }
linux_update() { record "dispatch linux_update${*:+ $*}"; }
linux_clean() { record "dispatch linux_clean${*:+ $*}"; }
linux_tools() { record "dispatch linux_tools${*:+ $*}"; }
linux_bbr() { record "dispatch linux_bbr${*:+ $*}"; }
linux_docker() { record "dispatch linux_docker${*:+ $*}"; }
linux_test() { record "dispatch linux_test${*:+ $*}"; }
linux_work() { record "dispatch linux_work${*:+ $*}"; }
linux_Settings() { record "dispatch linux_Settings${*:+ $*}"; }
linux_cluster() { record "dispatch linux_cluster${*:+ $*}"; }

# 固定工作目录，避免分支里的裸文件名（如 WARP 的 menu.sh）意外命中真实文件。
cd "${test_root}"
kejilion_sh
HARNESS

# 输入是纯管道（read -e 在非终端下退化为普通 read），无需 PTY。
drive_menu() { # $1=输入给 read 的一行选择
	printf '%s\n0\n' "$1" | bash "${test_root}/run.sh" "${test_root}" 2>&1
}

strip_ansi() {
	sed -e $'s/\033\\[[0-9;]*m//g'
}

# ---- 断言一：主菜单能完整渲染（每个编号都画出来且带文字标签）----
if ! render_output="$(drive_menu '0')"; then
	printf '%s\n' "${render_output}" >&2
	fail "主菜单渲染后未能以 0 干净退出"
fi
render_plain="$(printf '%s\n' "${render_output}" | strip_ansi)"
printf '%s\n' "${render_plain}" | grep -Fq '科技lion脚本工具箱' ||
	fail "主菜单未渲染标题"
# 工单 #9：主菜单标题须在原菜单名后带"无遥测版"后缀，让人一眼认出净化版。
# 原名"科技lion脚本工具箱"必须原样保留（上面的断言已守），这里只要求它同时带无遥测版标识。
printf '%s\n' "${render_plain}" | grep -F '科技lion脚本工具箱' | grep -Fq '无遥测版' ||
	fail "主菜单标题缺少'无遥测版'后缀（工单 #9：原名 + 无遥测版标识）"
# 附带小修：合并工单 #6/#7/#8 后主菜单出现过两条挨着的 '-----' 空分隔线。
# 这里守住"渲染结果里不得出现连续两行纯分隔线"，防止双线复辟。
if printf '%s\n' "${render_plain}" | awk '/^-{3,}$/{if(prev)exit 1; prev=1; next}{prev=0}'; then
	:
else
	fail "主菜单出现两条连续的 '-----' 分隔线（本工单附带小修：应收敛为一条）"
fi
for option in 1 2 3 4 5 6 7 8 9 10 11 0; do
	printf '%s\n' "${render_plain}" | grep -Eq "^${option}\.[[:space:]]+[^[:space:]]" ||
		fail "主菜单未渲染编号 ${option} 的菜单项（渲染与分发缝被破坏）"
done
# 工单 #25：甲骨文云整块退役；主菜单告别空号策略，紧凑顺排为 1-11。
# 反向断言旧编号 12、13、14、16 及甲骨文云不再被渲染（原 10/11 现已复用为系统工具与集群控制）。
for retired in 12 13 14 16; do
	if printf '%s\n' "${render_plain}" | grep -Eq "^${retired}\.[[:space:]]+[^[:space:]]"; then
		fail "主菜单仍渲染已退役的编号 ${retired}（工单 #25：主菜单紧凑顺排为 1-11，超出 11 的旧编号不得渲染）"
	fi
done
if printf '%s\n' "${render_plain}" | grep -Fq '甲骨文云脚本合集'; then
	fail "主菜单仍渲染甲骨文云脚本合集（工单 #25 应整块删除）"
fi
[ ! -s "${dispatch_log}" ] || {
	cat "${dispatch_log}" >&2
	fail "仅看菜单（输入 0）就触发了分发或副作用记录"
}

# ---- 断言一·补：广告专栏入口已从菜单与脚本中移除（工单 #8「广告清扫」）----
# 后续工单各自拆 17（KPanel）/00（更新），本守卫只盯工单 #8 的广告专栏。
if printf '%s\n' "${render_plain}" | grep -Fq '广告专栏'; then
	fail "主菜单仍渲染广告专栏（工单 #8 应删除菜单第 15 项 kejilion_Affiliates）"
fi
if grep -Fq 'kejilion_Affiliates' "${script_path}"; then
	fail "kejilion.sh 仍定义或引用 kejilion_Affiliates（工单 #8 应整块删除广告专栏）"
fi

# ---- 断言一·补二：已退役板块的主菜单分发行一条不许回来（工单 #15/#16/#25）----
# 只删掉上面的正向断言拦不住复辟，这里用精确字符串把已退役的分发行钉死。
for gone in \
	'9) linux_Oracle' \
	'10) linux_ldnmp' \
	'11) linux_panel' \
	'12) linux_work' \
	'13) linux_Settings' \
	'14) linux_cluster' \
	'16) games_server_tools'
do
	if grep -Fq "${gone}" "${script_path}"; then
		fail "主菜单仍残留已退役板块的分发行[${gone}]"
	fi
done

# ---- 断言二：每个编号入口按预期分派，且分发后菜单继续渲染 ----
# 形式：编号|分发日志里应出现的行|放行的记录正则（完整分组内容，
# 即“允许出现哪些 stub 记录”；未出现在白名单里的记录一律视为越权）
dispatch_cases=(
	'1|dispatch linux_info|dispatch |send_stats '
	'2|dispatch linux_update|dispatch |send_stats '
	'3|dispatch linux_clean|dispatch |send_stats '
	'4|dispatch linux_tools|dispatch |send_stats '
	'5|dispatch linux_bbr|dispatch |send_stats '
	'6|dispatch linux_docker|dispatch |send_stats '
	'7|install wget|dispatch |send_stats |install |wget '
	'8|dispatch linux_test|dispatch |send_stats '
	'9|dispatch linux_work|dispatch |send_stats '
	'10|dispatch linux_Settings|dispatch |send_stats '
	'11|dispatch linux_cluster|dispatch |send_stats '
)
for dispatch_case in "${dispatch_cases[@]}"; do
	choice="${dispatch_case%%|*}"
	remainder="${dispatch_case#*|}"
	marker="${remainder%%|*}"
	allowed="${remainder#*|}"
	: >"${dispatch_log}"
	if ! entry_output="$(drive_menu "${choice}")"; then
		printf '%s\n' "${entry_output}" >&2
		fail "主菜单入口 ${choice} 运行后未以 0 干净退出"
	fi
	grep -Fqx "${marker}" "${dispatch_log}" || {
		echo "入口 ${choice} 的实际分发日志：" >&2
		cat "${dispatch_log}" >&2
		fail "主菜单入口 ${choice} 未分派到预期目标（期望日志行 '${marker}'）"
	}
	render_count="$(printf '%s\n' "${entry_output}" | strip_ansi | grep -Fc '科技lion脚本工具箱' || true)"
	[ "${render_count}" -eq 2 ] ||
		fail "主菜单入口 ${choice} 分发后未返回菜单（标题渲染 ${render_count} 次，应为 2）"
	violations="$(grep -Ev "^(${allowed})" "${dispatch_log}" || true)"
	[ -z "${violations}" ] || {
		echo "入口 ${choice} 的越权记录：" >&2
		printf '%s\n' "${violations}" >&2
		fail "主菜单入口 ${choice} 触发了白名单之外的副作用（install/curl/wget/systemctl/写系统命令只应被 stub 记录）"
	}
done

# ---- 断言三：退出项与无效输入分支 ----
: >"${dispatch_log}"
if ! exit_output="$(drive_menu '0')"; then
	printf '%s\n' "${exit_output}" >&2
	fail "主菜单退出项 0 运行后异常"
fi
[ ! -s "${dispatch_log}" ] || {
	cat "${dispatch_log}" >&2
	fail "主菜单退出项 0 触发了分发或副作用记录"
}
render_count="$(printf '%s\n' "${exit_output}" | strip_ansi | grep -Fc '科技lion脚本工具箱' || true)"
[ "${render_count}" -eq 1 ] ||
	fail "主菜单退出项 0 未直接退出（标题渲染 ${render_count} 次，应为 1）"

# '00' 曾是"脚本更新"入口（工单 #7 整体删除更新功能）；旧编号 12/13/14 现已退役。
for invalid_input in 'not-a-number' '' '00' '12' '13' '14'; do
	: >"${dispatch_log}"
	if ! invalid_output="$(drive_menu "${invalid_input}")"; then
		printf '%s\n' "${invalid_output}" >&2
		fail "主菜单无效输入分支运行后异常"
	fi
	printf '%s\n' "${invalid_output}" | grep -Fq '无效的输入' ||
		fail "主菜单无效输入 '${invalid_input}' 未提示无效输入"
	[ ! -s "${dispatch_log}" ] || {
		cat "${dispatch_log}" >&2
		fail "主菜单无效输入 '${invalid_input}' 触发了分发或副作用记录"
	}
	render_count="$(printf '%s\n' "${invalid_output}" | strip_ansi | grep -Fc '科技lion脚本工具箱' || true)"
	[ "${render_count}" -eq 2 ] ||
		fail "主菜单无效输入后未返回菜单（标题渲染 ${render_count} 次，应为 2）"
done

printf '%s\n' "main_menu_noninteractive_smoke=pass"

#!/bin/bash
# k 快捷命令安装链 · 守门测试。
#
# 背景（为什么要有本测试）：
#   脚本把 k 命令装上去的链条原本只有一跳来源——
#       cp -f ./kejilion.sh ~/kejilion.sh
#   ——「当前目录里的 kejilion.sh」。README 的一键安装现为「先下载再运行」（本体
#   在磁盘上）；但管道跑法——bash <(curl …)（$0 是 /dev/fd/N）与 curl | bash
#   （$0 不是文件）——仍是常见入口，脚本本体同样从不在磁盘上，第一跳照样断。
#   脚本从管道流过，硬盘上从来没有 kejilion.sh 这个文件，第一跳就断；且每一跳的
#   报错都被 >/dev/null 2>&1 吞掉，/usr/local/bin/k 静默地不存在，用户输入 k 只得到
#   command not found（或一个指向空气的 /usr/bin/k 软链报错）。
#   原版同样断在这一跳，但原版有两条兜底：作者博客教的是「先 curl -O 下载再
#   ./kejilion.sh」跑法（目录里本来就有文件），且原版的更新功能会把脚本重新落到
#   ~/kejilion.sh 再拷成 k。净化版把更新功能整块删了（工单 #7），兜底没了，坑裸露。
#
# 本次修复后被固化的行为（本测试只黑盒断言结果，不碰内部实现）：
#   1. 跑的是磁盘上的脚本文件（./kejilion.sh、bash kejilion.sh、直接跑 k）→ 装那份文件；
#   2. 脚本本体不在磁盘上（bash <(curl …) 管道 / curl | bash）→ 先从本仓库 raw 地址
#      取一份落到 ~/kejilion.sh 再接上安装链（取内容只从本仓库，GLOSSARY.md「取内容」
#      与 docs/adr/0002）；默认地址写死在本仓库 raw，不许退回原作者域名；
#   3. 落盘后补执行位——curl 下载的文件默认 644，不补则 k 装上了也不能执行；
#   4. 装不上时清掉指向空气的 /usr/bin/k 软链，让输入 k 至少得到 command not found；
#   5. 首次装上屏幕给一句提示（README「首次运行时会自动装好 `k` 快捷命令（屏幕有提示）」
#      这句话里的"屏幕有提示"由此兑现）；
#   6. 管道安装不因当前目录里恰好躺着别的 kejilion.sh 就改装那份——以正在运行的
#      脚本（或从仓库新取的本体）为准，防止 CWD 里的旧文件/原版文件借尸还魂。
#
# 手法（沿用 tests/ 下冒烟测试的「截取 + 沙箱」做法，绝不碰真实系统）：
#   · 从 kejilion.sh 截出安装链那一截（kj_k_shortcut_failed 定义起、ip_address 之前止），
#     断言起止锚点存在且唯一——锚点漂移说明脚本结构变了，此时宁肯失败也不瞎猜；
#   · 在沙箱里以两种方式驱动截出来的块：bash <(cat …)（$0 是 /dev/fd/N，模拟管道
#     安装）与 bash 本地文件（$0 是磁盘文件，模拟下载后运行）；
#   · curl 换成只写本地夹具的桩：不发出任何网络请求（与 tests/ 全局约定一致）；
#   · HOME、/usr/local/bin、/usr/bin 全部指进沙箱（脚本留了 KJ_LOCAL_BIN_DIR 等
#     注入点，默认值即真实路径）；sed/cp/ln/chmod 用真的——在沙箱里跑，验的正是
#     真实文件效果。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ -f "${script_path}" ] || fail "找不到待测脚本: ${script_path}"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/k-shortcut-install.XXXXXX")"
trap 'rm -rf -- "${test_root}"' EXIT

# ---------------------------------------------------------------------------
# 截取安装链：从 kj_k_shortcut_failed() 定义到 ip_address() 之前（两者都必须在位且唯一）
# ---------------------------------------------------------------------------
anchor_start_count="$(grep -c '^kj_k_shortcut_failed() {$' "${script_path}" || true)"
[ "${anchor_start_count}" -eq 1 ] ||
	fail "${script_path} 里安装链起点锚点 kj_k_shortcut_failed() { 不唯一或不存在（共 ${anchor_start_count} 处），脚本结构已变，需同步维护本测试"
grep -q '^ip_address() {$' "${script_path}" ||
	fail "${script_path} 里安装链终点锚点 ip_address() { 不存在，脚本结构已变，需同步维护本测试"

awk '
	/^kj_k_shortcut_failed\(\) \{$/ { capture = 1 }
	capture && /^ip_address\(\) \{$/ { exit }
	capture { print }
' "${script_path}" >"${test_root}/block.sh"

[ -s "${test_root}/block.sh" ] || fail "未能从 ${script_path} 截取安装链（kj_k_shortcut_failed → ip_address 之间为空）"
bash -n "${test_root}/block.sh" || fail "截取出的安装链语法不合法"

# ---------------------------------------------------------------------------
# 沙箱与夹具
# ---------------------------------------------------------------------------
sandbox_home="${test_root}/home"
sandbox_local_bin="${test_root}/local-bin"    # 顶掉 /usr/local/bin
sandbox_system_bin="${test_root}/system-bin"  # 顶掉 /usr/bin
mkdir -p "${sandbox_home}" "${sandbox_local_bin}" "${sandbox_system_bin}"

k_bin="${sandbox_local_bin}/k"
k_link="${sandbox_system_bin}/k"
home_script="${sandbox_home}/kejilion.sh"
curl_log="${test_root}/curl.log"

# 取内容桩"下载"下来的脚本本体：与真脚本同首行，带唯一标记
fetch_fixture="${test_root}/fetched.sh"
printf '%s\n' '#!/bin/bash' 'sh_v="4.5.10"' '# FETCHED-FIXTURE-MARKER' >"${fetch_fixture}"

# 管道方式驱动的 driver：stub 掉 curl 与协议门，再 source 安装链
# （桩与本地方式共用一份，避免两个 driver 逐行重复）
stubs="${test_root}/stubs.sh"
cat >"${stubs}" <<'DRIVER'
# 脚本顶部定义的颜变量（安装链的提示文字要用；截取范围不含它们，在这里补）
gl_huang='\033[33m'
gl_bai='\033[0m'
gl_kjlan='\033[96m'
# 取内容桩：只把夹具内容写到 -o 目标并记录实参，绝不发真实请求
curl() {
	local out=""
	printf '%s\n' "curl $*" >>"${KJ_TEST_CURL_LOG}"
	if [ "${KJ_TEST_CURL_MODE:-ok}" = "fail" ]; then
		return 1
	fi
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			*) shift ;;
		esac
	done
	[ -n "${out}" ] && cp -f "${KJ_TEST_FETCH_FIXTURE}" "${out}"
	return 0
}
# 协议门：本测试就是要让安装链真的跑起来
kpanel_protocol_active() { return 1; }
DRIVER

driver_pipe="${test_root}/driver_pipe.sh"
cat >"${driver_pipe}" <<'DRIVER'
#!/bin/bash
set -u
source "${KJ_TEST_STUBS}"
source "${KJ_TEST_BLOCK}"
DRIVER

# 本地文件方式驱动的 driver：它自己就是"用户下载后运行的那个脚本文件"
# （首行必须是 #!/bin/bash，内容里带唯一标记）
driver_local="${test_root}/driver_local.sh"
cat >"${driver_local}" <<'DRIVER'
#!/bin/bash
set -u
# LOCAL-DRIVER-MARKER
source "${KJ_TEST_STUBS}"
source "${KJ_TEST_BLOCK}"
DRIVER

# 每个场景一套干净的沙箱：reset_sandbox 只留目录骨架
reset_sandbox() {
	rm -rf -- "${sandbox_home}" "${sandbox_local_bin}" "${sandbox_system_bin}"
	mkdir -p "${sandbox_home}" "${sandbox_local_bin}" "${sandbox_system_bin}"
}

work_clean="${test_root}/work_clean"       # 空目录：模拟用户在家目录直接粘命令
work_stale="${test_root}/work_stale"       # 躺着别的 kejilion.sh：模拟 CWD 有旧文件
mkdir -p "${work_clean}" "${work_stale}"
printf '%s\n' '#!/bin/bash' '# STALE-CWD-FILE-MARKER' >"${work_stale}/kejilion.sh"

# 统一的驱动入口：run_chain <pipe|local> <运行目录> [curl 模式 ok|fail]
#   pipe  → bash <(cat driver)：$0 是 /dev/fd/N，模拟 bash <(curl …) 管道安装
#   local → bash driver 文件：  $0 是磁盘文件，模拟下载后 ./kejilion.sh
# 输出（stdout+stderr）进全局变量 chain_output，退出码进 chain_rc。
chain_output=""
chain_rc=0
run_chain() {
	local mode="$1" rundir="$2" curl_mode="${3:-ok}"
	: >"${curl_log}"
	if [ "${mode}" = "local" ]; then
		chain_output="$(
			cd "${rundir}" &&
			HOME="${sandbox_home}" \
			KJ_LOCAL_BIN_DIR="${sandbox_local_bin}" \
			KJ_SYSTEM_BIN_DIR="${sandbox_system_bin}" \
			KJ_TEST_CURL_LOG="${curl_log}" \
			KJ_TEST_CURL_MODE="${curl_mode}" \
			KJ_TEST_FETCH_FIXTURE="${fetch_fixture}" \
			KJ_TEST_STUBS="${stubs}" \
			KJ_TEST_BLOCK="${test_root}/block.sh" \
			bash "${driver_local}" 2>&1
		)" && chain_rc=0 || chain_rc=$?
	else
		chain_output="$(
			cd "${rundir}" &&
			HOME="${sandbox_home}" \
			KJ_LOCAL_BIN_DIR="${sandbox_local_bin}" \
			KJ_SYSTEM_BIN_DIR="${sandbox_system_bin}" \
			KJ_TEST_CURL_LOG="${curl_log}" \
			KJ_TEST_CURL_MODE="${curl_mode}" \
			KJ_TEST_FETCH_FIXTURE="${fetch_fixture}" \
			KJ_TEST_STUBS="${stubs}" \
			KJ_TEST_BLOCK="${test_root}/block.sh" \
			bash <(cat "${driver_pipe}") 2>&1
		)" && chain_rc=0 || chain_rc=$?
	fi
}

strip_ansi() { sed -e $'s/\033\\[[0-9;]*m//g'; }

# ---------------------------------------------------------------------------
# 场景一：管道安装（bash <(curl …)）——第一跳断掉的那条路
#   断言：k 装上、可执行、内容正是从仓库取回来的本体、软链就位、
#         默认取内容地址指向本仓库、首次运行屏幕有提示。
# ---------------------------------------------------------------------------
reset_sandbox
run_chain pipe "${work_clean}"
[ "${chain_rc}" -eq 0 ] || {
	printf '%s\n' "${chain_output}" >&2
	fail "场景一：管道安装的安装链异常退出（rc=${chain_rc}）"
}
[ -f "${k_bin}" ] || fail "场景一：管道安装后 /usr/local/bin/k 没装上（第一跳断了的老问题复现？）"
[ -x "${k_bin}" ] || fail "场景一：k 装上了但没有执行位（curl 下载件默认 644，落盘后应补执行位）"
cmp -s "${fetch_fixture}" "${k_bin}" ||
	fail "场景一：k 的内容不是从仓库取回来的本体（管道安装应取自本仓库 raw 地址）"
[ -L "${k_link}" ] || fail "场景一：/usr/bin/k 软链没建上"
[ "$(readlink -f "${k_link}")" = "$(readlink -f "${k_bin}")" ] ||
	fail "场景一：/usr/bin/k 软链没指向 /usr/local/bin/k"
[ -f "${home_script}" ] || fail "场景一：~/kejilion.sh 没落盘"
[ -x "${home_script}" ] || fail "场景一：~/kejilion.sh 没有执行位"
grep -Fq 'raw.githubusercontent.com/howi3c/sh/main/kejilion.sh' "${curl_log}" ||
	fail "场景一：取内容没有走本仓库 raw 默认地址（防止默认地址退回原作者域名）: $(cat "${curl_log}")"
printf '%s\n' "${chain_output}" | strip_ansi | grep -Fq '快捷命令' ||
	fail "场景一：首次装上 k 时屏幕没有提示（README 承诺的「屏幕有提示」需兑现）: ${chain_output}"

# 场景一·补：再跑一次（k 已在位）——不重复提示，k 仍是仓库本体
run_chain pipe "${work_clean}"
[ "${chain_rc}" -eq 0 ] || fail "场景一补：二次运行异常退出"
[ -x "${k_bin}" ] || fail "场景一补：二次运行后 k 丢了执行位"
cmp -s "${fetch_fixture}" "${k_bin}" || fail "场景一补：二次运行后 k 的内容变了"
if printf '%s\n' "${chain_output}" | strip_ansi | grep -Fq '快捷命令'; then
	fail "场景一补：k 已在位时仍打印首次安装提示（提示只该出现一次）"
fi

# ---------------------------------------------------------------------------
# 场景二：本地文件安装（下载后 ./kejilion.sh）——以正在运行的文件为准
#   断言：k 内容 == 被运行的文件；全程不发起取内容（有本体就不是联网的理由）。
# ---------------------------------------------------------------------------
reset_sandbox
run_chain local "${work_clean}"
[ "${chain_rc}" -eq 0 ] || {
	printf '%s\n' "${chain_output}" >&2
	fail "场景二：本地文件安装异常退出（rc=${chain_rc}）"
}
[ -x "${k_bin}" ] || fail "场景二：本地文件安装后 k 没有执行位"
grep -Fq 'LOCAL-DRIVER-MARKER' "${k_bin}" ||
	fail "场景二：k 的内容不是正在运行的那个脚本文件（应以 \$0 为准）"
if grep -Fq 'FETCHED-FIXTURE-MARKER' "${k_bin}"; then
	fail "场景二：本地文件安装不该走取内容，k 里却出现了下载件的标记"
fi
[ -s "${curl_log}" ] && fail "场景二：本地文件安装不该调用 curl（磁盘上有本体就不必取内容）"

# ---------------------------------------------------------------------------
# 场景三：管道安装，但当前目录里躺着别的 kejilion.sh
#   断言：仍然装从仓库取回的新本体，不装 CWD 里那份——防止旧文件/原版借尸还魂。
# ---------------------------------------------------------------------------
reset_sandbox
run_chain pipe "${work_stale}"
[ "${chain_rc}" -eq 0 ] || fail "场景三：CWD 有旧文件时安装链异常退出"
cmp -s "${fetch_fixture}" "${k_bin}" ||
	fail "场景三：CWD 里躺着 kejilion.sh 时就改装那份了（管道安装必须以正在运行的脚本/仓库本体为准）"
if grep -Fq 'STALE-CWD-FILE-MARKER' "${k_bin}"; then
	fail "场景三：k 装成了 CWD 里的旧文件"
fi
[ -s "${curl_log}" ] || fail "场景三：管道安装没有从仓库取内容（本体不在磁盘上时必须自落盘）"

# ---------------------------------------------------------------------------
# 场景四：取内容也失败（网络不通）——不崩、不留指向空气的软链、说清没装上
# ---------------------------------------------------------------------------
reset_sandbox
# 预置一个指向空气的 /usr/bin/k 软链（老安装方式失败后的遗留形态）
ln -s "${k_bin}" "${k_link}"
run_chain pipe "${work_clean}" fail
if printf '%s\n' "${chain_output}" | strip_ansi | grep -Eq 'command not found|syntax error|unbound variable'; then
	printf '%s\n' "${chain_output}" >&2
	fail "场景四：取内容失败时安装链崩了（失败可以，崩不行）"
fi
[ -e "${k_bin}" ] && fail "场景四：取内容失败却装出了 k"
[ -L "${k_link}" ] &&
	fail "场景四：取内容失败后仍留着指向空气的 /usr/bin/k 软链（输入 k 只会得到看不懂的报错）"
[ -e "${home_script}" ] && fail "场景四：取内容失败却落盘了 ~/kejilion.sh"
printf '%s\n' "${chain_output}" | strip_ansi | grep -Fq '没装上' ||
	fail "场景四：取内容失败时没有明确告诉用户 k 没装上（静默失败正是当年这个坑看不见的原因）"

printf '%s\n' "k_shortcut_install=pass"

#!/bin/bash
# 净化版 kejilion.sh · 总验收入口（工单 #11「最终验收与交付」）
#
# 为什么要有这个文件：
#   验收尺子此前散落在九个脚本里，仓库主人要一条命令跑完全部并看到结论。
#   本文件只做「编排与汇报」——它**不新增任何判定规则**，只是把三条测试缝和
#   六个守门测试逐个调起来，逐项打印 PASS/FAIL，最后给总体结论与基线数字。
#   任何一项失败都让整体非零退出，因此可以直接当 CI 闸门用。
#
# 用法：
#   bash tests/run_all_checks.sh               # 跑完全部九项 + 基线数字 + 端点明细
#   bash tests/run_all_checks.sh --no-detail   # 只跑九项与汇总，不打印端点明细附录
#   bash tests/run_all_checks.sh --help
#
# 约定（沿用父议题 #1 的 Testing Decisions）：
#   · 本入口与它调用的测试全部只做静态分析 / 非交互冒烟，不执行 kejilion.sh 本体、
#     不安装任何软件、不发出任何网络请求；
#   · shellcheck 未安装时语法检查的 lint 部分按约定跳过，不算失败；
#   · tests/test_network_inventory.sh 的报信/取内容分类规则在此只被调用，不被改写。

set -uo pipefail   # 不用 -e：每一项都要跑完，不能在第一项失败时就收工

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory_check="${project_root}/tests/test_network_inventory.sh"
target_script="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"

detail=1
show_detail() { [ "${detail}" -eq 1 ]; }

usage() {
	sed -n '2,26p' "${BASH_SOURCE[0]}"
}

# ---------------------------------------------------------------------------
# 待跑清单：标签 <TAB> 脚本（相对仓库根）<TAB> 传给该脚本的参数
#   三项「缝」是这次改造的通用尺子；六项「守门」对应各工单自己的验收尺子。
#   顺序即打印顺序：先缝后背门，仓库主人从上往下看就是验收顺序。
# ---------------------------------------------------------------------------
ITEMS=(
	"缝 1 · 网络请求清点（报信清零闸门）	tests/test_network_inventory.sh	--assert-clean"
	"缝 2 · 非交互菜单冒烟（主菜单渲染与分发）	tests/test_main_menu_noninteractive_smoke.sh	"
	"缝 3 · 语法检查（bash -n，shellcheck 缺装则跳过）	tests/test_kejilion_syntax_check.sh	"
	"守门 · 广告清扫（工单 #8：返利与推广清空、教学链接/面板官网/致谢保留）	tests/test_ads_stripped.sh	"
	"守门 · 更新功能整体删除（工单 #7）	tests/test_update_removed.sh	"
	"守门 · 闭源面板整块移除（工单 #6）	tests/test_kpanel_main_menu_smoke.sh	"
	"守门 · 作者代理拔掉、下载直连（工单 #5）	tests/test_direct_downloads.sh	"
	"守门 · 署名、命名与 README（工单 #9）	tests/test_attribution_naming.sh	"
	"守门 · 语言资产删除（工单 #10）	tests/test_language_assets_removed.sh	"
)
TOTAL="${#ITEMS[@]}"

rule() { printf '%s\n' '================================================================================'; }
thin() { printf '%s\n' '--------------------------------------------------------------------------------'; }

# 打印一行，两侧对齐到 80 列
row() { printf '%-72s%8s\n' "$1" "$2"; }

# 失败的子测试输出原样带出：各守门测试自己就会写清楚「哪个菜单项 / 哪一行」，
# 这里只做缩进，不加工、不概括——笼统的 FAIL 等于没报。
emit_detail() {
	local log="$1" line
	while IFS= read -r line; do
		printf '      | %s\n' "${line}"
	done <"${log}"
}

# ---------------------------------------------------------------------------
# 清单的解析与执行
# ---------------------------------------------------------------------------
split_item() { # split_item <索引> <字段序号 1|2|3>
	local idx="$1" want="$2"
	printf '%s\n' "${ITEMS[$idx]}" | cut -f"${want}"
}

run_all() {
	local log_dir idx label script rel rc
	log_dir="$(mktemp -d "${TMPDIR:-/tmp}/run-all-checks.XXXXXX")"
	# shellcheck disable=SC2064  # 退出时连带清理临时日志目录
	trap "rm -rf -- '${log_dir}'" EXIT

	passed=0
	failed=0
	failed_labels=()

	for idx in "${!ITEMS[@]}"; do
		label="$(split_item "${idx}" 1)"
		script="$(split_item "${idx}" 2)"
		rel="${script}"
		script="${project_root}/${rel}"
		# 第三列是该尺子要带的参数（可能为空）
		args_note="$(split_item "${idx}" 3)"
		[ -n "${args_note}" ] && args_note=" ${args_note}"

		printf '\n'
		# 一行说清：通过与否、第几项、是哪一项、用的是哪把尺子。
		# 失败时紧随其后把子测试输出原样带出（子测试自己会点名到哪一行 / 哪个菜单项）。
		if [ ! -f "${script}" ]; then
			printf 'FAIL %s/%s  %s   ← 尺子文件 %s 不存在，不能算通过\n' \
				"$((idx + 1))" "${TOTAL}" "${label}" "${rel}"
			failed=$((failed + 1)); failed_labels+=("${label}")
			continue
		fi

		# 逐项调用：失败也继续跑完后面的项，最后统一给结论。
		bash "${script}" >"${log_dir}/item.log" 2>&1
		rc=$?

		if [ "${rc}" -eq 0 ]; then
			printf 'PASS %s/%s  %s   ← %s%s\n' "$((idx + 1))" "${TOTAL}" "${label}" "${rel}" "${args_note}"
			passed=$((passed + 1))
		else
			printf 'FAIL %s/%s  %s   ← %s%s\n' "$((idx + 1))" "${TOTAL}" "${label}" "${rel}" "${args_note}"
			printf '      —— 就是上面这一项没过（退出码 %s）。细节如下，已点名到哪一行 / 哪个菜单项：\n' "${rc}"
			emit_detail "${log_dir}/item.log"
			failed=$((failed + 1)); failed_labels+=("${label}")
		fi
	done

	printf '\n'
	rule
	if [ "${failed}" -eq 0 ]; then
		printf ' 总体结论: 全部通过（%s/%s 项）\n' "${passed}" "${TOTAL}"
		printf '           净化版达到交付状态，剩仓库主人在 VPS 上人工过目（见 docs/vps-smoke.md）。\n'
	else
		printf ' 总体结论: 未通过（%s/%s 项 PASS，%s 项 FAIL）\n' "${passed}" "${TOTAL}" "${failed}"
		printf '           没过的是这几项：\n'
		local l
		for l in ${failed_labels+"${failed_labels[@]}"}; do
			printf '             · %s\n' "${l}"
		done
		printf '           请按各行的行号 / 菜单项回到 kejilion.sh 对应位置核对。\n'
	fi
	rule
}

# ---------------------------------------------------------------------------
# 基线数字：调 tests/test_network_inventory.sh --records 取分类结果，
#   分类规则完全由那个脚本说了算，这里只按第一列计数。
# ---------------------------------------------------------------------------
print_baseline() {
	local records n_report n_content n_ref n_proxy
	records="$(bash "${inventory_check}" --records "${target_script}" 2>/dev/null || true)"
	n_report="$(grep -cE $'^报信\t' <<<"${records}" || true)"
	n_content="$(grep -cE $'^取内容\t' <<<"${records}" || true)"
	n_ref="$(grep -cE $'^参考链接\t' <<<"${records}" || true)"
	n_proxy="$(grep -E $'^取内容\t[^\t]+\tauthor-proxy\t' <<<"${records}" \
		| awk -F'\t' '$2 != "gh.kejilion.pro"' | wc -l | tr -d ' ' || true)"

	printf '\n'
	rule
	printf ' 当前基线数字（报信 / 取内容 / 参考链接 / 经作者代理）\n'
	rule
	row "  报信（红线，必须为 0）" "${n_report} 处"
	row "  取内容（下载安装包 / 测速节点 / 查 IP 归属地，允许保留）" "${n_content} 处"
	row "  参考链接（只打印给用户看，并不真发请求）" "${n_ref} 处"
	row "  经作者代理的下载（必须为 0）" "${n_proxy} 处"
	printf '\n'
	printf '   口径: %s\n' "GLOSSARY.md「报信 / 取内容」 + docs/adr/0001-keep-content-fetching-strip-reporting.md"
	printf '   明细见下方附录；逐条复核另有一份验收报告 docs/acceptance-report.md。\n'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--no-detail) detail=0 ;;
			-h|--help) usage; return 0 ;;
			*) printf '未知选项: %s（--help 看用法）\n' "$1" >&2; return 2 ;;
		esac
		shift
	done

	[ -f "${target_script}" ] || { printf '错误: 找不到目标脚本: %s\n' "${target_script}" >&2; exit 1; }
	[ -f "${inventory_check}" ] || { printf '错误: 找不到清点检查: %s\n' "${inventory_check}" >&2; exit 1; }

	rule
	printf ' kejilion.sh 净化版 · 总验收入口\n'
	printf ' 复跑方式: bash tests/run_all_checks.sh\n'
	printf ' 目标脚本: %s（%s 行）\n' "${target_script#"${project_root}/"}" "$(wc -l <"${target_script}" | tr -d ' ')"
	printf ' 当前提交: %s\n' "$(git -C "${project_root}" rev-parse --short HEAD 2>/dev/null || printf '（非 git 环境）')"
	printf ' 声明: 全部检查只做静态分析与非交互冒烟，不执行目标脚本、不安装软件、不发请求。\n'
	if command -v shellcheck >/dev/null 2>&1; then
		printf ' lint 环境: shellcheck 已安装（语法检查顺带跑，按约定只报告不阻断）\n'
	else
		printf ' lint 环境: shellcheck 未安装 —— 语法检查的 lint 部分按约定跳过，不算失败。\n'
	fi
	rule

	run_all
	print_baseline

	if show_detail; then
		printf '\n'
		rule
		printf ' 附录 · 对外端点清点明细（分类规则由 tests/test_network_inventory.sh 决定，此处只调用）\n'
		rule
		bash "${inventory_check}" "${target_script}" | sed -n '/^ kejilion.sh 对外端点清点/,$p'
	fi

	printf '\n'
	[ "${failed:-1}" -eq 0 ] || exit 1
}

main "$@"

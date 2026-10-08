#!/bin/bash
# kejilion.sh 网络请求清点 · 自测与入口
#
# 这是整项净化改造的“尺子”（见父工单 #1 / ADR-0001 / 术语表 GLOSSARY.md）：
# 纯静态地扫描目标脚本 kejilion.sh 的全部对外端点，按“报信 / 取内容”两类
# 输出人可读清单。红线：报信类改造后必须为 0。
#
# 重要约束（设计红线）：
#   · 只 grep/awk 分析文本，绝不执行目标脚本，绝不发出任何网络请求；
#   · 分类口径写在下面的 awk 规则里，可读可改，来源为术语表的报信/取内容定义；
#   · 本工单只“加设施、记基线”，不改 kejilion.sh 本体。
#
# 用法：
#   bash tests/test_network_inventory.sh            # 自测（默认）+ 打印 kejilion.sh 清单
#   bash tests/test_network_inventory.sh <脚本路径>  # 只打印某个脚本的清单
#   bash tests/test_network_inventory.sh --assert-clean [脚本路径]  # 守门：有报信则非零退出
#   bash tests/test_network_inventory.sh --records [脚本路径]       # 输出机器可读分类记录
#   bash tests/test_network_inventory.sh --write-baseline <目录>    # 生成/刷新基线产物
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_target="${project_root}/kejilion.sh"

die() { printf '错误: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 自测：验证“检查自身有效”（工单 #2 验收点 5）。
# 只测公开行为与不变量，不测内部实现。四个接口（seam）：
#   A) inventory_records <file>       分类是否正确（报信/取内容/作者代理/喂报信）
#   B) --assert-clean <file>         守门闸退出码与失败报点（端点/行/类别）
#   C) 人读清单输出                  是否列出全部已知报信与作者代理下载
#   D) 纯静态属性                    工具自身不执行目标、不发请求
# ---------------------------------------------------------------------------
selftest() {
	local tmp_dir dirty clean
	tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/netinv.XXXXXX")"
	trap 'rm -rf "${tmp_dir}"' RETURN

	dirty="${tmp_dir}/dirty.sh"
	clean="${tmp_dir}/clean.sh"

	cat >"${dirty}" <<'EOF'
send_stats() {
	if [ "$ENABLE_STATS" == "false" ]; then
		return
	fi
	local country=$(curl -s ipinfo.io/country)
	local os_info=$(grep PRETTY_NAME /etc/os-release)
	(
		curl -s -X POST "https://api.kejilion.pro/api/log" \
			-H "Content-Type: application/json" \
			-d "{\"action\":\"$1\",\"country\":\"$country\",\"version\":\"$sh_v\"}" \
		&>/dev/null
	) &
}
send_stats "测试菜单"
deepseek_helper() {
	openclaw_api_python "$config_file" "$ENABLE_STATS" "$sh_v" <<'PY'
import urllib.request
req = urllib.request.Request("https://api.kejilion.pro/api/log", method="POST")
PY
}
wget -O x.conf ${gh_proxy}raw.githubusercontent.com/kejilion/nginx/main/nginx10.conf
mo=newthing; gh_proxy="https://gh.kejilion.pro/"
curl -s https://ipinfo.io/ip && echo
curl -sS -o install.sh https://get.docker.com/install.sh
EOF

	cat >"${clean}" <<'EOF'
show_ip() {
	local ip=$(curl -s https://ipinfo.io/ip && echo)
	printf '%s\n' "$ip"
}
wget -O nginx.conf https://raw.githubusercontent.com/kejilion/nginx/main/nginx10.conf
curl -sS -o install.sh https://get.docker.com/install.sh
EOF

	# 接口 A：分类机器输出
	#   （inventory_records 尚未实现时，这里应当失败 —— 这就是红灯）
	local dirty_records
	dirty_records="$(inventory_records "${dirty}")"

	grep -qP '^报信\tapi\.kejilion\.pro\treport-post\t' <<<"${dirty_records}"
	grep -qP '^报信\tipinfo\.io\treport-feed\t' <<<"${dirty_records}"
	grep -qP '^取内容\traw\.githubusercontent\.com\tauthor-proxy\t' <<<"${dirty_records}"
	grep -qP '^取内容\tipinfo\.io\tdirect\t' <<<"${dirty_records}"

	local clean_records
	clean_records="$(inventory_records "${clean}")"
	if grep -q $'^报信\t' <<<"${clean_records}"; then
		die "干净样例被误判为含报信"
	fi

	# 接口 B：守门闸退出码与失败报点
	if ask_assert_clean "${clean}" >/dev/null 2>&1; then :; else
		die "守门闸在干净样例上应返回 0"
	fi
	local gate_out gate_rc=0
	gate_out="$(ask_assert_clean "${dirty}" 2>&1)" || gate_rc=$?
	if [ "${gate_rc}" -eq 0 ]; then
		die "守门闸在原版/脏样例上应判定有报信、非零退出"
	fi
	# 失败报点必须指出端点、行号、类别
	grep -q '报信' <<<"${gate_out}"
	grep -q 'api.kejilion.pro' <<<"${gate_out}"
	grep -qE '第 ?[0-9]+ ?行' <<<"${gate_out}"

	# 接口 D：纯静态属性 —— 工具自身不含会执行目标/发请求的命令
	if grep -nE '(^|[^[:alnum:]_])(curl|wget|nc|ncat|ssh|telnet)([^[:alnum:]_]|$)' "${BASH_SOURCE[0]}" >/dev/null; then
		die "检查脚本自身出现了联网命令，违反纯静态约束"
	fi
	if grep -nE '\bsource[[:space:]]+\$?\{?(default_target|target)\b|bash[[:space:]]+\$\{?(default_target|target)\b' "${BASH_SOURCE[0]}" >/dev/null; then
		die "检查脚本疑似执行目标脚本，违反纯静态约束"
	fi

	printf '%s\n' 'net-inventory-selftest=pass'
}

# 供自测调用的小封装（保持 seam 与 --assert-clean 一致）。
ask_assert_clean() {
	NET_INVENTORY_INTERNAL_TARGET="$1" assert_clean_impl
}

# ---------------------------------------------------------------------------
# 入口分发
# ---------------------------------------------------------------------------
usage() { sed -n '2,24p' "${BASH_SOURCE[0]}"; }

main() {
	local action="print" target="${default_target}"
	if [ "${NET_INVENTORY_INTERNAL_TARGET:-}" != "" ]; then
		target="${NET_INVENTORY_INTERNAL_TARGET}"
	fi
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--assert-clean) action="assert-clean" ;;
			--records) action="records" ;;
			--write-baseline) action="write-baseline" ;;
			-h|--help) usage; return 0 ;;
			-*) die "未知选项: $1" ;;
			*) target="$1" ;;
		esac
		shift
	done

	case "${action}" in
		assert-clean)
			[ -f "${target}" ] || die "找不到目标脚本: ${target}"
			assert_clean_impl "${target}"
			;;
		records)
			[ -f "${target}" ] || die "找不到目标脚本: ${target}"
			inventory_records "${target}"
			;;
		write-baseline)
			write_baseline "${target}"
			;;
		print|*)
			[ -f "${target}" ] || die "找不到目标脚本: ${target}"
			selftest
			printf '\n'
			print_inventory "${target}"
			;;
	esac
}

main "$@"

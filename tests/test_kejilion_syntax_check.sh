#!/bin/bash
set -euo pipefail

# 缝 3 · 语法检查。
#
# 目的：每一项清洗都在改 kejilion.sh，改完必须立刻知道脚本是否还被
# bash 接受。这是最便宜的守门人：纯解析、不执行、无任何副作用。
# 本机装有 shellcheck 时顺带跑一遍 lint，只报告、不强制零警告。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"

[ -f "${script_path}" ] || {
	echo "找不到待检查脚本: ${script_path}" >&2
	exit 1
}

# bash -n：只解析不执行，必须通过。
if ! bash -n "${script_path}"; then
	echo "bash -n 未通过: ${script_path}" >&2
	exit 1
fi

# shellcheck：装了就跑（严重度可用 SHELLCHECK_SEVERITY 调整），
# 报出来即可；没装则优雅跳过，不算失败。
if command -v shellcheck >/dev/null 2>&1; then
	severity="${SHELLCHECK_SEVERITY:-warning}"
	set +e
	shellcheck -S "${severity}" "${script_path}"
	shellcheck_status=$?
	set -e
	if [ "${shellcheck_status}" -eq 0 ]; then
		printf '%s\n' "shellcheck(severity=${severity}) 未发现问题"
	else
		printf '%s\n' "shellcheck(severity=${severity}) 报告了上述问题；按约定仅提示，不阻断" >&2
	fi
else
	printf '%s\n' "shellcheck 未安装，跳过 lint（不影响结果）"
fi

printf '%s\n' "kejilion_syntax_check=pass"

#!/bin/bash
# 工单 #12「把 tests/ 下 kpanel 前缀的测试改名」的命名守门测试。
#
# 背景：工单 #6 删掉了闭源面板二进制 kejilion-node，但保留了一套纯本地的非交互
# 适配器（`k kpanel ssh-port / dns / disk-management / network-operations /
# account-management / system-tuning / virus-scan` 等，只读写本机文件与系统服务）。
# 守护这批适配器的测试曾沿用同一个 kpanel 前缀，害得看 tests/ 的人以为「KPanel 不是
# 删了吗」。这些测试已改用不含 kpanel 的名字，让人一眼认出它们守的是本地系统适配器。
#
# 本测试守一条命名不变量：tests/ 下不得再有名字带 kpanel 前缀的测试文件。
#   唯一的例外是 tests/test_kpanel_main_menu_smoke.sh——它是**反向**守门人（断言二进制
#   那一层的痕迹在 kejilion.sh 里必须为 0），名字恰恰应当保留 kpanel。
#
# 只做目录名静态检查，不执行任何测试、不联网。
set -uo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 收集 tests/ 顶层带 kpanel 前缀的测试，剔除反向守门人 test_kpanel_main_menu_smoke.sh。
shopt -s nullglob
offenders=()
for path in "${tests_dir}"/test_kpanel_*; do
	base="$(basename "${path}")"
	[ "${base}" = "test_kpanel_main_menu_smoke.sh" ] && continue
	offenders+=("${base}")
done
shopt -u nullglob

if [ "${#offenders[@]}" -ne 0 ]; then
	fail "tests/ 下仍有 $((${#offenders[@]})) 个测试沿用已删闭源面板的 kpanel 前缀（应改用本地系统适配器的名字）: ${offenders[*]}"
fi

printf '%s\n' "tests-dir-local-adapter-naming=pass"

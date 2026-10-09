#!/usr/bin/env bash
# 工单 #13「README 的安装命令指向原作者域名，会把未净化原版装回来」的守门测试。
#
# 背景：净化版做完并推送后，README「一键安装」教的却是
#           bash <(curl -sL kejilion.sh)
#       kejilion.sh 是原作者的域名（解析到作者的服务器），域名后面挂着的是
#       原版未净化脚本。任何人照这条命令装，装回来的就是报信全齐的原版——
#       净化被一行命令撤销。父议题规格最担心的正是"这个状态稳定、可验证、
#       不会被意外撤销"。
# 本工单把命令改成从本仓库 raw 地址拉，并在命令附近加一句短说明；同时把
# 新发现的两件事记进 README「后续事项」：游戏开服脚本→原版 kejilion.sh
# 的重生路径、3 处图片热链 + 1 处官网链接的待定状态。
#
# 本测试守四条不变量（只读 README 这份文档，不动 kejilion.sh、不联网）：#   1. 「一键安装」一节的命令必须从本仓库 raw 地址取脚本；
#   2. README 里不得再出现任何"从作者域名下载并执行 kejilion.sh"的指令；
#   3. 命令附近必须有一小句说明：这是个人净化版，别从原作者域名拉；
#   4. 「后续事项」必须记着图片热链与官网链接的待定状态。
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${project_root}/README.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "${readme}" ] || fail "找不到 README: ${readme}"

# 本仓库 raw 地址：工单明确规定安装命令从这里拉（作者域名不算）
repo_raw_url="https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh"

# 抽出一节：从「## <标题>」顶格标题行到下一个顶格标题行之前。
# 用法：extract_section <文件> <完整标题文字>
extract_section() {
	awk -v want="## $2" '
		$0 == want { in_section = 1; next }
		/^## /     { in_section = 0 }
		in_section { print }
	' "$1"
}

# ---------------------------------------------------------------------------
# 1) 「一键安装」一节的命令必须指向本仓库 raw 地址
# ---------------------------------------------------------------------------
install_section="$(extract_section "${readme}" "一键安装")"
[ -n "${install_section}" ] || fail "README 里找不到「## 一键安装」这一节"

printf '%s\n' "${install_section}" | grep -Fq "${repo_raw_url}" ||
	fail "「一键安装」一节的命令没有指向本仓库 raw 地址（应为 ${repo_raw_url}；工单 #13：不许再从原作者域名 kejilion.sh 拉）"

# ---------------------------------------------------------------------------
# 2) 不得再有"从作者域名下载并执行 kejilion.sh"的指令
#    判定：任何一行里同时出现取用命令（curl/wget）与 kejilion.sh 目标，
#    且该目标不是本仓库 raw 地址——这正是工单验收口径
#    grep -n 'curl.*kejilion\.sh\b' README.md 为 0 的语义版。
# ---------------------------------------------------------------------------
author_install_hits="$(
	grep -nE '(curl|wget)[^|]*kejilion\.sh' "${readme}" |
		grep -v 'raw\.githubusercontent\.com/howi3c/sh' || true
)"
[ -z "${author_install_hits}" ] ||
	fail "README 仍有从作者域名下载 kejilion.sh 的指令（装回的是未净化原版）: ${author_install_hits}"

# ---------------------------------------------------------------------------
# 3) 命令附近必须有一小句说明：这是个人净化版，别从原作者域名拉
#    （工单要求"短，别写成段落"；这里只守语义，不锁具体措辞）
# ---------------------------------------------------------------------------
printf '%s\n' "${install_section}" | grep -Fq '净化版' ||
	fail "「一键安装」一节没有说明装的是净化版"
printf '%s\n' "${install_section}" | grep -Fq '原作者' ||
	fail "「一键安装」一节没有提醒别从原作者域名拉（否则装回原版）"

# ---------------------------------------------------------------------------
# 4) 「后续事项」必须记着还欠着的账
#    （原第 4a 条"游戏开服重生路径必须标记为已解决且要素齐全"已退役：仓库主人
#     决定「后续事项」只放还没解决的待办，已解决的一律移出，记录归验收报告。
#     那条路本身不许回来由别的尺子守着——test_spec15_slim_down_removed.sh 断言
#     games_server_tools/palworld.sh/mc.sh 等词汇在 kejilion.sh 里为 0、
#     test_update_removed.sh 判据 6 断言仓库根 6 个游戏脚本不得回来、
#     test_kpanel_main_menu_smoke.sh 的 retired_entry 也列着它，三层叠加。）
# ---------------------------------------------------------------------------
todo_section="$(extract_section "${readme}" "后续事项")"
[ -n "${todo_section}" ] || fail "README 里找不到「## 后续事项」这一节"

printf '%s\n' "${todo_section}" | grep -Fq '图片' ||
	fail "「后续事项」缺少图片热链待定状态这一条"
printf '%s\n' "${todo_section}" | grep -Fq '官方网站' ||
	fail "「后续事项」缺少「科技lion官方网站」链接待定状态这一条"

printf '%s\n' "readme-install-source=pass"

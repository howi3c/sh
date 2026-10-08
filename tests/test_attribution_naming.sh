#!/bin/bash
set -euo pipefail

# 工单 #9「署名、命名与 README」的内容性守门。
#
# 覆盖三处纯文本改动，防止将来被误删，也防止工单 #8 清掉的推广内容借尸还魂：
#   1. k_info()（事实上的“关于/帮助”页）须有一行**中性署名**，只如实交代功劳；
#   2. 该署名一行不得夹带任何链接（官网/频道回流不许回来；视频教学链接另有其行，不在此列）；
#   3. README（简体中文、唯一一份）顶部须有三行说明：个人净化版非官方、
#      删除了什么、其余功能与原版一致——且与实际净化结果相符。
#
# 手法：静态文本检查，不跑脚本、不联网；与 tests/ 下其它守门测试同风格。
# 菜单标题的“无遥测版”后缀由 tests/test_main_menu_noninteractive_smoke.sh 在渲染层守，本测试不管。

project_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"
readme_path="${project_root}/README.md"

fail() {
	echo "$*" >&2
	exit 1
}

[ -f "${script_path}" ] || fail "找不到待测脚本: ${script_path}"
[ -f "${readme_path}" ] || fail "找不到 README: ${readme_path}"

# ---- 1+2：k_info()（关于/帮助页）的一行中性署名 ----
# 抽出 k_info() 函数体：从顶格的“k_info() {”定义行到第一个独立成行的“}”。
# 只认顶格定义，避免误抓 k_info 的缩进调用点。
k_info_body="$(awk '/^k_info\(\)/{f=1} f{print} f&&/^\}/{exit}' "${script_path}")"
[ -n "${k_info_body}" ] || fail "未能从 ${script_path} 抽出 k_info() 函数体"

attr_line="$(printf '%s\n' "${k_info_body}" | grep -F 'kejilion 脚本' || true)"
[ -n "${attr_line}" ] ||
	fail "k_info()（关于/帮助页）缺少中性署名一行（应含'kejilion 脚本'，工单 #9）"

# 署名一行必须中性：只交代功劳，不得夹带任何 URL（http(s) 或 www 开头）。
printf '%s\n' "${attr_line}" | grep -Eq 'https?://|www\.' &&
	fail "k_info() 的中性署名一行夹带了链接（工单 #9：只交代功劳，不做推广）"

# ---- 3：README 顶部三行说明 ----
# “顶部”要求严：文件最开头几行就要交代身份。
readme_head="$(head -n 6 "${readme_path}")"
# “删除了什么 / 其余一致”是紧接着的说明行，放宽到前 20 行内。
readme_top="$(head -n 20 "${readme_path}")"

printf '%s\n' "${readme_head}" | grep -Fq '净化版' ||
	fail "README 顶部未说明这是“净化版”（工单 #9：应在文件最顶端交代）"
printf '%s\n' "${readme_head}" | grep -Fq '官方发布' ||
	fail "README 顶部未说明“不是官方发布”（工单 #9：个人维护版，非原版官方）"

printf '%s\n' "${readme_top}" | grep -Fq '广告' ||
	fail "README 说明未提及删除“广告”等推销内容（工单 #9：据实列出删减）"
printf '%s\n' "${readme_top}" | grep -Fq '面板' ||
	fail "README 说明未提及删除“面板”（工单 #9：据实列出删减）"
printf '%s\n' "${readme_top}" | grep -Fq '原版一致' ||
	fail "README 说明未写明“其余功能与原版一致”（工单 #9）"

printf '%s\n' "attribution_naming=pass"

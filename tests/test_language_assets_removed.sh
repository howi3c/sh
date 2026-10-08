#!/bin/bash
# 工单 #10「语言资产删除」守门测试。
#
# 背景（父工单 #1 用户故事 20 / 21 / 22）：
#   仓库只维护简体中文一份脚本与一份 README；七个语言副本目录、五个非简体
#   README、每周自动翻译工作流与根 translate.py 全部删除，且不得以任何形式
#   复活（否则每周定时任务会把语言目录重新生成出来）。
#
# 守的缝（外部不变量：磁盘上这些资产不存在 + 主脚本无指向它们的悬空引用）：
#   1. 七个语言副本目录（cn/en/tw/kr/jp/ir/ru，含 cn 下镜像的测试）不存在；
#   2. 五个非简体 README 不存在，仅存简体根 README.md；
#   3. .github/workflows/translate.yml（每周自动翻译）不存在；
#   4. 根 translate.py（翻译驱动脚本）不存在；
#   5. kejilion.sh 里没有指向语言副本 / 翻译脚本的悬空引用。
#
# 注意：本测试只做存在性与静态文本检查，绝不执行 kejilion.sh、绝不联网。
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_script="${project_root}/kejilion.sh"

fail_count=0
fail() { printf 'FAIL: %s\n' "$*" >&2; fail_count=$((fail_count + 1)); }

[ -f "${main_script}" ] || fail "找不到待测脚本: ${main_script}"

# ---- 判据 1：七个语言副本目录一律不存在 ----
for lang in cn en tw kr jp ir ru; do
	[ ! -e "${project_root}/${lang}" ] || fail "语言副本目录仍存在: ${lang}/（用户故事 20）"
done

# ---- 判据 2：五个非简体 README 不存在，简体根 README 保留 ----
for readme in README.fa.md README.ja.md README.kr.md README.ru.md README.tw.md; do
	[ ! -e "${project_root}/${readme}" ] || fail "非简体 README 仍存在: ${readme}（用户故事 22）"
done
[ -f "${project_root}/README.md" ] || fail "简体中文根 README.md 意外缺失"

# ---- 判据 3 / 4：每周自动翻译工作流与根翻译驱动脚本不存在 ----
[ ! -e "${project_root}/.github/workflows/translate.yml" ] ||
	fail "每周自动翻译工作流仍存在: .github/workflows/translate.yml（用户故事 21）"
[ ! -e "${project_root}/translate.py" ] || fail "根翻译驱动脚本仍存在: translate.py"

# ---- 判据 5：主脚本无指向语言副本 / 翻译脚本的悬空引用 ----
# 只匹配语言资产路径形态（<lang>/kejilion.sh、to-*.py、translate.py、工作流文件），
# 不去裸匹配 cn/ ir/ 等两字母片段，避免把 URL 域名（linuxmirrors.cn）与
# Docker 镜像名（libretranslate）误判成悬空引用。
dangling_patterns=(
	'(cn|en|tw|kr|jp|ir|ru)/kejilion\.sh'          # 各语言副本脚本
	'(to-en|to-tw|to-kr|to-jp|to-fa|to-ru)\.py'     # 各语言翻译脚本
	'translate\.py'                                 # 根翻译驱动脚本
	'\.github/workflows/translate\.yml'             # 翻译工作流
)
for pattern in "${dangling_patterns[@]}"; do
	hits="$(grep -nE -- "${pattern}" "${main_script}" || true)"
	[ -z "${hits}" ] || fail "kejilion.sh 含指向语言资产的悬空引用 [${pattern}]: ${hits%%$'\n'*}"
done

if [ "${fail_count}" -ne 0 ]; then
	printf 'language-assets-removed: FAIL（%s 处）\n' "${fail_count}" >&2
	exit 1
fi
printf '%s\n' 'language-assets-removed=pass'

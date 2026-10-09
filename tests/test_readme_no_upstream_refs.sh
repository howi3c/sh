#!/usr/bin/env bash
# 工单 #14「删掉 README 里指向原版仓库的引用与原作者的钱包地址」的守门测试。
#
# 背景：README 顶部三行写着"这是 kejilion 脚本的个人净化版"，但正文里还留着几处
#       把读者往**原版仓库 kejilion/sh** 引的东西：三枚统计原版 star/fork/活跃度的
#       徽章、去原版仓库提问题的「问题反馈」、指向原版更新日志的链接、统计原版 star
#       的 Star History 图表，以及原作者的 USDT 钱包地址——留着它等于让别人的打赏
#       直接打到原作者账上。这些和"净化版"的定位自相矛盾。
# 仓库主人对这几处的指示是**直接删除**，不是"改成指向本 fork"。本测试把删除结果钉住。
#
# 本测试守六条不变量（只读 README 这份文档，不动 kejilion.sh、不联网）：
#   1. 「## 支持我们」整节消失，连带原作者的钱包地址与 USDT 字样；
#   2. 指向原版仓库 kejilion/sh 的徽章消失，指向仓库内 LICENSE 的那枚保留；
#   3. 「## 项目文档」里「问题反馈」「脚本更新日志」两行消失，
#      指向本 fork 自己的 apps/README.md 与官网链接保留；
#   4. README 末尾「## Star History」整节消失（含 star-history.com 图表）；
#   5. 整份 README 不再出现 `kejilion/sh` 这个原版仓库路径；
#   6. 「后续事项」记下 kejilion_sh_log.txt 变成无链接孤儿这一笔。
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${project_root}/README.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "${readme}" ] || fail "找不到 README: ${readme}"

# 原作者的钱包地址：这一串一旦回 README，别人的打赏就打给原作者而不是本 fork 维护者
wallet_address="TCP3PLGUTG9Z4z4tnHHSLbw5bgp8NXhTT3"

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
# 1) 「## 支持我们」整节消失：标题、"Feel free to support..."、USDT 钱包地址
#    验收口径 grep -n '支持我们\|USDT\|<钱包地址>' README.md 为 0。
# ---------------------------------------------------------------------------
support_section="$(extract_section "${readme}" "支持我们")"
[ -z "${support_section}" ] ||
	fail "README 仍有「## 支持我们」一节（工单 #14 要求整节删除，内含原作者钱包地址）"

for pattern in '支持我们' 'USDT' "${wallet_address}"; do
	hits="$(grep -n -F "${pattern}" "${readme}" || true)"
	[ -z "${hits}" ] ||
		fail "README 仍出现「${pattern}」（原作者钱包地址/打赏引导，工单 #14 要求为 0 处）: ${hits}"
done

# ---------------------------------------------------------------------------
# 2) 指向原版仓库 kejilion/sh 的徽章消失，LICENSE 徽章保留
#    口径：整份 README 不得再出现 kejilion/sh 这个仓库路径（详见第 5 条）；
#    这里单独守 LICENSE 那一枚——它指向仓库内的 LICENSE 文件，是真实许可标识，
#    不该被顺带删掉；另外守住徽章区别被删成空段落。
# ---------------------------------------------------------------------------
license_badge_hits="$(grep -n -F 'href="LICENSE"' "${readme}" || true)"
[ -n "${license_badge_hits}" ] ||
	fail "README 丢了指向 LICENSE 文件的徽章（工单 #14 明确要求保留这一枚）"

# 徽章区不能删成空壳：任何 <p ...> 开行后紧跟 </p>，就是留下了一个空段落
empty_paragraph="$(
	awk '/^<p[ >]/ { open = $0; getline; if ($0 ~ /^<\/p>/) print open " ⇒ " $0 }' "${readme}" || true
)"
[ -z "${empty_paragraph}" ] ||
	fail "README 里有空段落（删徽章/删节时把 <p> 删空了）: ${empty_paragraph}"

# ---------------------------------------------------------------------------
# 3) 「## 项目文档」：删两行、留两行
#    删：「问题反馈」（引去原版仓库提问题）、「脚本更新日志」（指向原版更新日志）
#    留：「应用市场说明」（指向本 fork 自己的 apps/README.md）、
#        「科技lion官方网站」（工单 #13 的「后续事项」第 8 条记账待定，本次不许动）
# ---------------------------------------------------------------------------
docs_section="$(extract_section "${readme}" "项目文档")"
[ -n "${docs_section}" ] || fail "README 里找不到「## 项目文档」这一节"

printf '%s\n' "${docs_section}" | grep -Fq '应用市场说明' ||
	fail "「项目文档」丢了「应用市场说明」链接（指向本 fork 的 apps/README.md，不在删除范围）"
printf '%s\n' "${docs_section}" | grep -Fq 'apps/README.md' ||
	fail "「项目文档」丢了指向 apps/README.md 的链接"
printf '%s\n' "${docs_section}" | grep -Fq '科技lion官方网站' ||
	fail "「项目文档」丢了「科技lion官方网站」链接（由「后续事项」第 8 条记账待定，本次不许动）"

feedback_hits="$(grep -n -F '问题反馈' "${readme}" || true)"
[ -z "${feedback_hits}" ] ||
	fail "README 仍出现「问题反馈」（工单 #14 要求整行删除，不要改成指向本 fork）: ${feedback_hits}"

printf '%s\n' "${docs_section}" | grep -Fq '更新日志' &&
	fail "「项目文档」仍有「脚本更新日志」条目（工单 #14 要求整行删除）"

# 「脚本更新日志」那行不得再留下指向该文件的**链接**。
# 这里只判链接、不判字样：工单同时要求把"它成了无链接孤儿"记进「后续事项」，
# 记账条目里必然要提到这个文件名（见第 6 条），判链接才能既锁住删除、又容得下记账。
log_link_hits="$(grep -n -F '](kejilion_sh_log.txt)' "${readme}" || true)"
[ -z "${log_link_hits}" ] ||
	fail "README 仍有指向 kejilion_sh_log.txt 的链接（工单 #14 要求整行删除）: ${log_link_hits}"

# ---------------------------------------------------------------------------
# 4) README 末尾「## Star History」整节消失（图表统计的是原版仓库的 star）
# ---------------------------------------------------------------------------
star_history_section="$(extract_section "${readme}" "Star History")"
[ -z "${star_history_section}" ] ||
	fail "README 仍有「## Star History」一节（统计的是 kejilion/sh 的 star，不是本仓库）"

for pattern in 'Star History' 'star-history'; do
	hits="$(grep -n -F "${pattern}" "${readme}" || true)"
	[ -z "${hits}" ] ||
		fail "README 仍出现「${pattern}」（工单 #14 要求为 0 处）: ${hits}"
done

# ---------------------------------------------------------------------------
# 5) 整份 README 不得再出现原版仓库路径 kejilion/sh
#    这一条同时兜住三枚徽章（stars/forks/last-commit 三个 shields 接口都带仓库名）
#    与一切将来可能被加回来的 kejilion/sh 引用。
# ---------------------------------------------------------------------------
upstream_hits="$(grep -n -F 'kejilion/sh' "${readme}" || true)"
[ -z "${upstream_hits}" ] ||
	fail "README 仍指向原版仓库 kejilion/sh（本 fork 是 howi3c/sh）: ${upstream_hits}"

# ---------------------------------------------------------------------------
# 6) 「后续事项」必须记下 kejilion_sh_log.txt 成为无链接孤儿这一笔
#    文件本身在工单 #14 明确不动，但链接删了就得记账，否则没人知道它还躺在那。
# ---------------------------------------------------------------------------
todo_section="$(extract_section "${readme}" "后续事项")"
[ -n "${todo_section}" ] || fail "README 里找不到「## 后续事项」这一节"

printf '%s\n' "${todo_section}" | grep -Fq 'kejilion_sh_log' ||
	fail "「后续事项」没有记录 kejilion_sh_log 变成无链接孤儿（工单 #14 要求记账）"

printf '%s\n' "readme-no-upstream-refs=pass"

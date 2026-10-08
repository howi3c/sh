#!/bin/bash
# kejilion.sh 网络请求清点 · 自测与入口
#
# 这是整项净化改造的“尺子”（见父工单 #1 / ADR-0001 / 术语表 GLOSSARY.md）：
# 纯静态地扫描目标脚本 kejilion.sh 的全部对外端点，按“报信 / 取内容”两类
# 输出人可读清单（另附一类“参考链接”：脚本只是打印给用户看、并不真发请求）。
# 红线：报信类改造后必须为 0。
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
#   bash tests/test_network_inventory.sh --summary [脚本路径]       # 只输出四类计数（key=value）
#   bash tests/test_network_inventory.sh --write-baseline <目录>    # 生成/刷新基线产物
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_target="${project_root}/kejilion.sh"

die() { printf '错误: %s\n' "$*" >&2; exit 1; }
rule() { printf '%s\n' '--------------------------------------------------------------------------------'; }

# 自测用的临时目录统一登记，脚本退出时清理。
# 不用 RETURN 陷阱：它在命令替换里的触发时机不可靠，会连带把还在用的目录删掉。
NETINV_TMP_DIRS=()
netinv_cleanup() {
	local d
	for d in ${NETINV_TMP_DIRS+"${NETINV_TMP_DIRS[@]}"}; do
		[ -n "${d}" ] && rm -rf "${d}"
	done
}
trap netinv_cleanup EXIT
netinv_mktemp() {
	local d
	d="$(mktemp -d "${TMPDIR:-/tmp}/netinv.XXXXXX")"
	NETINV_TMP_DIRS+=("${d}")
	printf '%s\n' "${d}"
}

# ---------------------------------------------------------------------------
# 引擎：inventory_records <文件>
#   一行一条对外端点记录，制表符分隔:  类别 <TAB> 端点 <TAB> 类型 <TAB> 行号
#     类别 ∈ {报信, 取内容, 参考链接}
#     报信·类型 report-post     = 直接把资料 POST 出去的上报端点
#     报信·类型 report-feed     = 先被抓取、再随上报发出的数据源（端点本身在别处合法）
#     报信·类型 report-trigger  = 附属报信的触发行（不带端点，但带 ENABLE_STATS）
#     取内容·类型 author-proxy   = 经作者代理 gh.kejilion.pro 拼接出来的下载
#     取内容·类型 author-host    = 作者自有站点/镜像（非上报）
#     取内容·类型 direct         = 直连取内容
#     参考链接·类型 reference-link = 脚本只是打印/提及给用户看的链接，并不真的发请求
#
# 取用上下文 fetch_ctx：一行处在 curl/wget/docker/包管理/URL 变量赋值等取用位置，
#   才认为该行真的会发出请求；否则行内的完整 URL 归为“参考链接”。
# 分类规则（可读可改，口径来自 GLOSSARY.md 的“报信 / 取内容”）：
#   · 端点 api.kejilion.pro            → 报信（它就是“把版本/系统/IP 归属地发给作者”那一跳）
#   · 出现在 send_stats() 函数体内的   → 报信（这个函数的唯一职责就是收集并上报）
#   · ${gh_proxy} 拼出来的             → 取内容（下载用户要的东西，只是经作者代理转发）
#   · 其余 kejilion.pro / kejilion.sh  → 取内容（作者的镜像、文档站，不是上报）
#   · 其余一切                         → 取内容
# ---------------------------------------------------------------------------
inventory_records() {
	awk '
		# ---- 静态知识：真实域名后缀白名单，以及“只是文件后缀”的排除集 ----
		BEGIN {
			q = sprintf("%c", 39)
			n = split("com net org io sh pro cn dev ai xyz top eu me tv cloud run app wiki place cat", tl, " ")
			for (i = 1; i <= n; i++) tld[tl[i]] = 1
			n = split("json yml yaml conf cnf ini txt log lock bak py pyc toml service sock so a d md bin", ex, " ")
			for (i = 1; i <= n; i++) ext[ex[i]] = 1
		}

		# 形如主机的 token：至少两段、末级是公共后缀，且末级不是常见文件扩展名
		function hostlike(t,    p, m, last) {
			t = tolower(t)
			if (t !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?([.][a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/) return 0
			m = split(t, p, ".")
			last = p[m]
			if (ext[last]) return 0
			if (last == "org" && p[m-1] == "eu") return 1
			return tld[last]
		}

		# 把 [start, start+len) 区间抹成等长空格，便于继续在同一行里向后扫描
		function blank(s, start, len) {
			return substr(s, 1, start - 1) sprintf("%*s", len, "") substr(s, start + len)
		}

		# 该位置上的“域名形状 token”其实只是操作数的值（输出文件名、路径、选项参数）而不是端点
		function value_slot(work, pos,    pre, prev) {
			pre = substr(work, 1, pos - 1)
			sub(/[[:space:]]+$/, "", pre)
			# 紧跟标识符/文件名的一部分（如 auto_cert_renewal.sh 里的 renewal.sh）
			prev = substr(work, pos - 1, 1)
			if (prev ~ /[A-Za-z0-9_.-]/) return 1
			if (pre ~ /(\/|\.|\$)$/) return 1
			if (pre ~ /(\/|chmod([[:space:]]*(\+|-)[A-Za-z]*)?|cp|mv|ln|source|install|cat|rm|touch|tee|exec|bash|sh|zsh|dash)$/) return 1
			if (pre ~ /(2>|>|>>)$/) return 1
			if (pre ~ /a\+x$/) return 1
			if (pre ~ /(-[A-Za-z]*[oOdDpPvVeE]|--output|--name)$/) return 1
			return 0
		}

		# 展示链接：整行只是 echo 给用户看，或 scheme 前面是“标签: ”——这些不是请求
		function display_ctx(work, pos,    before) {
			if (work ~ /^[[:space:]]*echo([[:space:]]|$)/) return 1
			before = substr(work, 1, pos - 1)
			sub(/["\x27]+[[:space:]]*$/, "", before)
			sub(/[[:space:]]+$/, "", before)
			if (before ~ /(:|：)$/) return 1
			return 0
		}

		# 这一行是否处在“发对外请求/取用”上下文：出现网络/包管理/容器/取用选项/URL 变量
		function fetch_ctx(s,    t) {
			t = s
			if (t ~ /^[[:space:]]*(apt|apt-get|yum|dnf|zypper|apk|pip|pip3|npm|yarn|pnpm|gem)/) return 1
			if (t ~ /(^|[^A-Za-z0-9._-])(curl|wget|nc|ncat|telnet|ssh|scp|rsync|git)([^A-Za-z0-9._-]|$)/) return 1
			if (t ~ /(^|[^A-Za-z0-9._-])docker([^A-Za-z0-9._-]|$)/) return 1
			if (t ~ /(^|[^A-Za-z0-9._-])(kpanel_run_remote_bash|openclaw_memory_probe_url|install)([^A-Za-z0-9._-]|$)/) return 1
			if (t ~ /--source(-registry)?([^A-Za-z0-9._-]|$)/) return 1
			# 整行就是一个容器镜像引用（命名空间/仓库[:标签]）
			if (t ~ /^[[:space:]]*[a-z0-9]([a-z0-9._-]*[a-z0-9])?(\/[a-z0-9._-]+)+(:[a-z0-9._-]+)?[[:space:]]*$/) return 1
			# URL 类变量赋值
			if (t ~ /=/ && t ~ /(^|[^A-Za-z0-9._-])(url|endpoint|registry|mirror|proxy)([^A-Za-z0-9._-]|$)/) return 1
			if (t ~ /=/ && t ~ /_url([^A-Za-z0-9._-]|$)/) return 1
			return 0
		}

		{
			raw = $0
			# 注释行不是真正会发出去的行，不计入对外端点
			if (raw ~ /^[[:space:]]*#/) next

			line = raw
			# 作者代理的几种前缀变量（gh_proxy / cron_proxy / mirror_prefix / OPENCLAW_MEMORY_GH_PROXY）
			# 统一还原成 https:// 前缀，才能抽出它后面的真实目标主机
			gsub(/\$\{[A-Za-z0-9_]*(proxy|PROXY|mirror_prefix)\}/, "https://", line)
			via_proxy = (raw ~ /\$\{[A-Za-z0-9_]*(proxy|PROXY|mirror_prefix)\}/) ? 1 : 0

			# send_stats() 函数体跟踪：它整体就是“报信上下文”
			if (line ~ /^send_stats\(\)[[:space:]]*\{/) { in_stats = 1; next }
			if (in_stats && line ~ /^[}]/)            { in_stats = 0; next }

			# Python 版附属报信触发：openclaw_api_python 携带 ENABLE_STATS 且以 PY heredoc 传参
			if (raw ~ /openclaw_api_python/ && raw ~ /ENABLE_STATS/ && index(raw, "<<" q "PY" q) > 0) {
				printf "报信\t<python-附属报信>\treport-trigger\t%d\n", NR
			}

			# 先抹掉 sed 的 s/旧/新/ 段，避免里面的占位域名被当成端点
			work = line
			while (match(work, /(^|[^A-Za-z0-9_])s\/[^\/[:space:]]+\/[^\/[:space:]]*\//)) {
				work = blank(work, RSTART, RLENGTH)
			}

			delete found
			delete ref
			isfetch = fetch_ctx(work)

			# 规则一：带协议的完整 URL —— 一律视为端点（数组元素、多行命令参数都靠
			#   这一条兜住），只有“只是打印/提及给用户看”的才降级为参考链接。
			s = work
			while (match(s, "https?://[A-Za-z0-9._-]+")) {
				host = substr(s, RSTART, RLENGTH)
				sub(/^https?:\/\//, "", host)
				if (hostlike(host)) {
					if (display_ctx(work, RSTART)) ref[host] = 1
					else found[host] = 1
				}
				s = substr(s, RSTART + RLENGTH)
			}

			# 规则二：裸域名 + 路径（无协议下载路径、容器镜像引用等）
			s = work
			while (match(s, /(^|[^A-Za-z0-9._\/-])[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+\//)) {
				seg = substr(s, RSTART, RLENGTH)
				if (RSTART > 1) seg = substr(seg, 2)
				sub(/\/$/, "", seg)
				if (hostlike(seg) && isfetch) found[seg] = 1
				s = substr(s, RSTART + RLENGTH)
			}

			# 规则三：裸主机名（无路径）—— 只在取用上下文里才算，避免命中文案/占位符
			nf = 0; for (k in found) nf++
			if (isfetch) {
				s = work
				while (match(s, /[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+/)) {
					if (hostlike(substr(s, RSTART, RLENGTH)) && !value_slot(s, RSTART)) found[substr(s, RSTART, RLENGTH)] = 1
					s = substr(s, RSTART + RLENGTH)
				}
			} else if (nf == 0) {
				if (length(ref) == 0) next
			}

			# 归类并输出（同一行同一端点只记一次）
			for (h in found) {
				if (h == "api.kejilion.pro")                       { cat = "报信";  kind = "report-post" }
				else if (in_stats)                                { cat = "报信";  kind = "report-feed" }
				else if (h == "gh.kejilion.pro" || via_proxy)     { cat = "取内容"; kind = "author-proxy" }
				else if (h ~ /(^|[.])kejilion[.](pro|sh)$/)        { cat = "取内容"; kind = "author-host" }
				else                                              { cat = "取内容"; kind = "direct" }
				printf "%s\t%s\t%s\t%d\n", cat, h, kind, NR
			}
			for (h in ref) {
				if (h == "api.kejilion.pro")                      { cat = "报信";  kind = "report-post" }
				else if (in_stats)                               { cat = "报信";  kind = "report-feed" }
				else                                             { cat = "参考链接"; kind = "reference-link" }
				printf "%s\t%s\t%s\t%d\n", cat, h, kind, NR
			}
		}
	' "$1"
}

# ---------------------------------------------------------------------------
# 闸门：assert_clean_impl <文件>
#   报信类为 0 则 PASS 并返回 0；否则把“哪个端点、哪一行、归到哪一类”逐条点名后返回 1。
#   源级兜底：即便端点被字符串拼接藏起来，只要出现作者上报主机名或报信函数名，也算未净化。
# ---------------------------------------------------------------------------
assert_clean_impl() {
	local f="$1" records reporting src_hits src_count
	records="$(inventory_records "$f")"
	reporting="$(grep -E $'^报信\t' <<<"${records}" || true)"
	# 源级兜底：端点即使被字符串拼接藏起来，只要出现作者上报主机名或报信函数名就算未净化。
	# 忽略纯注释行——注释里提到名字不构成“可复活的报信路径”。
	src_hits="$(grep -nE 'api\.kejilion\.pro|send_stats' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
	src_count="$(printf '%s\n' "${src_hits}" | grep -c . || true)"

	if [ -z "${reporting}" ] && [ -z "${src_hits}" ]; then
		printf 'PASS: %s 未检出报信端点（报信类 = 0）\n' "${f}"
		return 0
	fi

	printf 'FAIL: %s 仍存在报信，净化验收不通过\n' "${f}" >&2
	if [ -n "${reporting}" ]; then
		printf '%s\n' "${reporting}" | awk -F'\t' '
			{ lines[$2] = lines[$2] (lines[$2] == "" ? "" : "、") "第 " $4 " 行"; kinds[$2] = $3 }
			END { for (e in lines) printf "  [报信] 类别=报信 · 端点=%s · 类型=%s · %s\n", e, kinds[e], lines[e] }
		' | sort >&2
	fi
	if [ -n "${src_hits}" ]; then
		if [ "${src_count}" -gt 10 ]; then
			printf '%s\n' "${src_hits}" | head -10 | awk -F: '
				{ printf "  [报信·源级] 类别=报信 · 第 %s 行 命中作者上报特征: %s\n", $1, substr($0, index($0, ":") + 1) }
			' >&2
			printf '  [报信·源级] …… 另有余下 %s 处同类命中（作者上报主机名或报信函数名残留）\n' "$(( src_count - 10 ))" >&2
		else
			printf '%s\n' "${src_hits}" | awk -F: '
				{ printf "  [报信·源级] 类别=报信 · 第 %s 行 命中作者上报特征: %s\n", $1, substr($0, index($0, ":") + 1) }
			' >&2
		fi
	fi
	return 1
}

# ---------------------------------------------------------------------------
# 人读清单：print_inventory <文件>
#   仓库主人不看代码也能核对：分「报信」「取内容」两栏，每条给端点 + 行号 + 归类。
# ---------------------------------------------------------------------------
print_inventory() {
	local f="$1" records total_lines
	records="$(inventory_records "$f")"
	total_lines="$(wc -l <"${f}")"

	rule
	printf ' kejilion.sh 对外端点清点（静态分析；未执行目标脚本、未发出任何请求）\n'
	printf ' 目标脚本: %s（%s 行）\n' "${f}" "${total_lines}"
	printf ' 判定口径: GLOSSARY.md「报信 / 取内容」 + docs/adr/0001-keep-content-fetching-strip-reporting.md\n'
	rule

	# ---- 报信 ----
	local n_report
	n_report="$(grep -cE $'^报信\t' <<<"${records}" || true)"
	printf '\n【一】报信类 —— 把“你是谁 / 你的机器什么样”发给作者或第三方\n'
	printf '      （红线：净化后这一栏必须为 0。当前检出 %s 处）\n' "${n_report}"
	rule

	if [ "${n_report}" -eq 0 ]; then
		printf '  （无）报信已清零。\n'
	else
		printf ' 1) 上报端点（把版本号 / 系统信息 / IP 归属地 POST 给作者）\n'
		grep -E $'^报信\t[^\t]+\treport-post\t' <<<"${records}" | sort -t$'\t' -k2,2 -k4,4n | awk -F'\t' '
			{ lines[$2] = lines[$2] (lines[$2] == "" ? "" : "、") "第 " $4 " 行"; if (!seen[$2]++) order[++n] = $2 }
			END { for (i = 1; i <= n; i++) printf "      · %-28s %s\n", order[i], lines[order[i]] }
		' || true

		printf ' 2) 喂给上报的数据源（端点本身在别处是合法取内容，但在报信函数里被抓去上报）\n'
		if grep -Eq $'^报信\t[^\t]+\treport-feed\t' <<<"${records}"; then
			grep -E $'^报信\t[^\t]+\treport-feed\t' <<<"${records}" | sort -t$'\t' -k2,2 -k4,4n | awk -F'\t' '
				{ lines[$2] = lines[$2] (lines[$2] == "" ? "" : "、") "第 " $4 " 行"; if (!seen[$2]++) order[++n] = $2 }
				END { for (i = 1; i <= n; i++) printf "      · %-28s %s\n", order[i], lines[order[i]] }
			' || true
		else
			printf '      （无）\n'
		fi

		printf ' 3) 附属报信触发点（Python 版 / 子进程里把版本号等发出去）\n'
		local n_trig=0
		if grep -Eq $'report-trigger\t' <<<"${records}"; then
			grep -E $'report-trigger\t' <<<"${records}" | sort -t$'\t' -k4,4n | awk -F'\t' '{printf "      · 第 %s 行（openclaw_api_python ... ENABLE_STATS ... <<PY）\n", $4}' || true
			n_trig="$(grep -cE $'report-trigger\t' <<<"${records}" || true)"
		fi
		if [ "${n_trig}" -eq 0 ]; then printf '      （无）\n'; fi

		local stats_calls
		stats_calls="$( { grep -nE 'send_stats[[:space:]]+"' "${f}" || true; } | wc -l)"
		printf '\n      ※ send_stats 调用点共 %s 处，全部汇聚到上面的上报端点。\n' "${stats_calls}"
		printf '      ※ 以上行号可直接回到 kejilion.sh 对应位置核对。\n'
	fi

	# ---- 取内容 ----
	local n_content proxy_lines proxy_dl_lines proxy_hosts direct_hosts author_hosts
	n_content="$(grep -cE $'^取内容\t' <<<"${records}" || true)"
	printf '\n【二】取内容类 —— 下载安装包 / 查询测速节点 / 查公网 IP 归属地（允许保留）\n'
	printf '      （请求里不夹带用户信息；检出 %s 处使用点）\n' "${n_content}"
	rule

	proxy_lines="$(grep -E $'^取内容\t[^\t]+\tauthor-proxy\t' <<<"${records}" | awk -F'\t' '$2 != "gh.kejilion.pro" {print $4}' | sort -n | uniq | wc -l || true)"
	proxy_dl_lines="$(grep -nE '\$\{[A-Za-z0-9_]*(proxy|PROXY|mirror_prefix)\}' "${f}" | grep -cE 'wget|curl' || true)"
	proxy_hosts="$(grep -E $'^取内容\t[^\t]+\tauthor-proxy\t' <<<"${records}" | awk -F'\t' '$2 != "gh.kejilion.pro" {print $2}' | sort -u | paste -sd, - | sed 's/,/, /g' || true)"
	printf ' A) 经作者代理的下载（gh_proxy = https://gh.kejilion.pro/，改造单另处理）\n'
	printf '      其中 curl/wget 下载命令 %s 处；作者代理变量引用合计 %s 处。\n' "${proxy_dl_lines}" "${proxy_lines}"
	printf '      目标主机: %s\n' "${proxy_hosts:-（无）}"

	author_hosts="$(grep -E $'^取内容\t[^\t]+\tauthor-host\t' <<<"${records}" | awk -F'\t' '{print $2}' | sort -u | paste -sd, - | sed 's/,/, /g' || true)"
	printf ' B) 作者自有站点/镜像（取内容，非上报）: %s\n' "${author_hosts:-（无）}"

	printf ' C) 直连取内容主机（去重）:\n'
	grep -E $'^取内容\t[^\t]+\tdirect\t' <<<"${records}" | awk -F'\t' '{print $2}' | sort -u | awk '{printf "       · %s\n", $0}' || true

	# ---- 参考链接（既不是报信、也不是真的请求：只是脚本打印/提及给用户看）----
	local n_ref
	n_ref="$(grep -cE $'^参考链接\t' <<<"${records}" || true)"
	printf '\n【三】参考链接 —— 脚本只是打印/提及给用户看，并不真的发请求\n'
	printf '      （如菜单里的教学视频、面板官网；既非报信也非取内容，列出供后续清扫参考。%s 处）\n' "${n_ref}"
	rule
	grep -E $'^参考链接\t' <<<"${records}" | awk -F'\t' '{print $2}' | sort -u | awk '{printf "       · %s\n", $0}' || true

	printf '\n'
	rule
	printf ' 汇总: 报信 %s 处 · 取内容 %s 处（其中经作者代理 %s 处下载）· 参考链接 %s 处\n' \
		"${n_report}" "${n_content}" "${proxy_lines}" "${n_ref}"
	printf ' 结论: 报信类%s\n' "$([ "${n_report}" -eq 0 ] && echo '已清零 ✔' || echo '未清零，需继续净化 ✗')"
	rule
}

# ---------------------------------------------------------------------------
# 机器可读计数：emit_summary <文件>
#   只统计条数，不新增、不改动任何分类口径（归类仍由 inventory_records 独揽）。
#   以后新增一类，只需要在 inventory_records 里归一次类、在这里加一行计数。
#   基线产物（下面的 write_baseline）与总验收入口（tests/run_all_checks.sh）
#   共用这一处，不再在两处各写一遍 awk。
# ---------------------------------------------------------------------------
emit_summary() {
	local f="$1" records
	records="$(inventory_records "$f")"
	printf '报信_处数=%s\n'       "$(grep -cE $'^报信\t'     <<<"${records}" || true)"
	printf '取内容_处数=%s\n'     "$(grep -cE $'^取内容\t'   <<<"${records}" || true)"
	printf '参考链接_处数=%s\n'   "$(grep -cE $'^参考链接\t' <<<"${records}" || true)"
	printf '经作者代理_处数=%s\n' "$( { grep -E $'^取内容\t[^\t]+\tauthor-proxy\t' <<<"${records}" | awk -F'\t' '$2 != "gh.kejilion.pro"'; } | wc -l | tr -d ' ')"
}

# ---------------------------------------------------------------------------
# 基线产物：write_baseline <目录>
#   把当前清单固化成仓库文件，作为后续每项改造后逐条比对的预期集合。
#   · network_inventory.records.tsv —— 机器可读全量记录（改造后 diff 用）
#   · network_inventory.summary.txt  —— 人读摘要（报信/取内容计数）
# ---------------------------------------------------------------------------
write_baseline() {
	local dir="$1"
	mkdir -p "${dir}"
	inventory_records "${default_target}" | sort -u >"${dir}/network_inventory.records.tsv"
	{
		printf '# 网络请求清点基线 · 生成命令: bash tests/test_network_inventory.sh --write-baseline tests/fixtures\n'
		# 目标写成相对仓库根的路径：基线产物不能把本机绝对路径焊死，否则换台机器、
		# 换个 clone 重跑 --write-baseline 就会与库里的产物对不上（一条命令重跑不成立）。
		printf '# 目标: %s\n' "${default_target#"${project_root}/"}"
		printf '# 终态目标：报信_处数 = 0。取内容清单为后续每项改造后逐条比对的预期集合。\n'
		# 计数走 emit_summary：与 run_all_checks.sh 的基线数字同一处算出来
		emit_summary "${default_target}"
		printf '\n# 全量记录见同目录 network_inventory.records.tsv（已去重排序，改造后可直接 diff）\n'
	} >"${dir}/network_inventory.summary.txt"
	printf '已写入基线产物到 %s\n' "${dir}"
}

# ---------------------------------------------------------------------------
# 自测：证明“检查自身有效”（工单 #2 验收点 5）。
# 只测公开行为与不变量，不测内部实现。
#   A) inventory_records <file>    分类是否正确（报信/取内容/作者代理/喂报信）
#   B) assert_clean_impl <file>    闸门退出码 + 失败报点（端点/行/类别）
#   C) print_inventory <file>      人读清单是否覆盖全部已知项
#   D) 纯静态属性                 哨兵文件证明目标从未被执行
# ---------------------------------------------------------------------------
selftest() {
	local tmp_dir dirty clean hostile
	tmp_dir="$(netinv_mktemp)"

	dirty="${tmp_dir}/dirty.sh"
	clean="${tmp_dir}/clean.sh"
	hostile="${tmp_dir}/hostile.sh"
	local canary="${tmp_dir}/EXECUTED"

	# 样本一：含全部已知报信形态（bash 上报 + Python 附属报信 + 喂报信数据源）
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
# 多行 docker run 的续行参数：真实端点，不能因为本行没有 docker 字样就漏掉
docker run -d --name demo \
	-e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
	ghcr.io/example/panel:latest
# 数组形式的镜像源清单：真实端点
declare -a mirrors=(
	"https://docker.kejilion.pro",
	"https://hub.1panel.dev",
)
# 只是打印给用户看的链接：不是请求
echo "视频教学: https://www.bilibili.com/video/BV1"
local app_url="官网介绍: https://1panel.cn/"
EOF

	# 样本二：只取内容、无报信（净化后应有的样子）
	cat >"${clean}" <<'EOF'
show_ip() {
	local ip=$(curl -s https://ipinfo.io/ip && echo)
	printf '%s\n' "$ip"
}
wget -O nginx.conf https://raw.githubusercontent.com/kejilion/nginx/main/nginx10.conf
curl -sS -o install.sh https://get.docker.com/install.sh
EOF

	# 样本三：若被本工具执行，就会留下哨兵文件并真的发起联网请求
	cat >"${hostile}" <<EOF
#!/bin/bash
: > "${canary}"
curl -s -X POST https://example.invalid/report
EOF

	# 接口 A：分类机器输出
	local dirty_records
	dirty_records="$(inventory_records "${dirty}")"

	grep -qP '^报信\tapi\.kejilion\.pro\treport-post\t' <<<"${dirty_records}"
	grep -qP '^报信\tipinfo\.io\treport-feed\t' <<<"${dirty_records}"
	grep -qP '^报信\t<python-附属报信>\treport-trigger\t' <<<"${dirty_records}"
	grep -qP '^取内容\traw\.githubusercontent\.com\tauthor-proxy\t' <<<"${dirty_records}"
	grep -qP '^取内容\tipinfo\.io\tdirect\t' <<<"${dirty_records}"

	# 防回归：多行续行参数、数组元素里的真实端点，不能因为没有同行命令字样就漏掉
	grep -qP '^取内容\tregistry-1\.docker\.io\tdirect\t' <<<"${dirty_records}"
	grep -qP '^取内容\tghcr\.io\tdirect\t' <<<"${dirty_records}"
	grep -qP '^取内容\tdocker\.kejilion\.pro\tauthor-host\t' <<<"${dirty_records}"
	grep -qP '^取内容\thub\.1panel\.dev\tdirect\t' <<<"${dirty_records}"
	# 防回归：只是打印给用户看的链接必须归到“参考链接”，不算取内容请求
	grep -qP '^参考链接\twww\.bilibili\.com\treference-link\t' <<<"${dirty_records}"
	if grep -qP $'^取内容\twww\.bilibili\.com\t' <<<"${dirty_records}"; then
		die "打印给用户看的链接被误判成取内容请求"
	fi

	local clean_records
	clean_records="$(inventory_records "${clean}")"
	if grep -q $'^报信\t' <<<"${clean_records}"; then
		die "干净样例被误判为含报信"
	fi

	# 接口 B：闸门退出码与失败报点
	assert_clean_impl "${clean}" >/dev/null
	local gate_out gate_rc=0
	gate_out="$(assert_clean_impl "${dirty}" 2>&1)" || gate_rc=$?
	if [ "${gate_rc}" -eq 0 ]; then
		die "闸门在含报信样例上应判定失败"
	fi
	grep -q '报信' <<<"${gate_out}"
	grep -q 'api.kejilion.pro' <<<"${gate_out}"
	grep -qE '第 ?[0-9]+ ?行' <<<"${gate_out}"
	grep -q 'report-post' <<<"${gate_out}"

	# 接口 C：人读清单覆盖全部已知项
	local printed
	printed="$(print_inventory "${dirty}")"
	grep -q '报信类' <<<"${printed}"
	grep -q '取内容类' <<<"${printed}"
	grep -q 'api.kejilion.pro' <<<"${printed}"
	grep -q 'gh.kejilion.pro' <<<"${printed}"
	grep -q 'send_stats 调用点共 1 处' <<<"${printed}"

	# 接口 D：纯静态属性 —— 对“一执行就留痕还会联网”的样本跑完，哨兵必须不存在
	if [ -e "${canary}" ]; then
		die "测试夹具异常：哨兵在执行前就已存在"
	fi
	inventory_records "${hostile}" >/dev/null
	assert_clean_impl "${hostile}" >/dev/null 2>&1 || true
	print_inventory "${hostile}" >/dev/null
	if [ -e "${canary}" ]; then
		die "静态检查执行了目标脚本，违反“绝不执行目标”红线"
	fi

	printf '%s\n' 'net-inventory-selftest=pass'
}

# ---------------------------------------------------------------------------
# 入口分发
# ---------------------------------------------------------------------------
usage() { sed -n '2,20p' "${BASH_SOURCE[0]}"; }

main() {
	local action="print" target="${default_target}"
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--assert-clean) action="assert-clean" ;;
			--records) action="records" ;;
			--summary) action="summary" ;;
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
		summary)
			[ -f "${target}" ] || die "找不到目标脚本: ${target}"
			emit_summary "${target}"
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

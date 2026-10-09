#!/usr/bin/env bash
# 工单 #5「作者代理拔掉，下载全部直连」的验收尺子
#
# 守的缝（都是外部行为/不变量，不碰内部实现细节）：
#   1. 全脚本里不再出现作者代理域名（gh.kejilion.pro / docker.kejilion.pro）；
#   2. 作者的代理前缀变量不再参与任何下载拼接，GitHub 类目标一律 https:// 直连，
#      而取内容的目标主机一个都没换（用 tests/test_network_inventory.sh 的清单做比对面）；
#   3. 地区开关（quanju_canshu 的 zhushi 三分支）不因拔代理而退化；
#   4. Docker 镜像加速列表里作者的代理镜像被删掉，其余镜像一条不少；
#   5. KPanel 轻节点更新器不再回退到作者代理；
#   6. 更新流程里的硬编码代理同样改成直连。
#
# 关于 5/6 的写法：这些位置所属的功能后续还会被别的工单整体移除（闭源面板、自动更新）。
# 所以这里只断言"代码还在，就必须是直连"——整块消失算通过，反向改回作者代理算失败。
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_script="${project_root}/kejilion.sh"
inventory_check="${project_root}/tests/test_network_inventory.sh"

work="$(mktemp)"
trap 'rm -f "$work"' EXIT
sed 's/\r$//' "$source_script" >"$work"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1) 作者代理域名：全脚本零出现
#    （api.kejilion.pro 等报信/推销域名归其他工单，这里只认下载渠道用的两个）
# ---------------------------------------------------------------------------
author_proxy_hits="$(grep -n 'gh\.kejilion\.pro\|docker\.kejilion\.pro' "$work" || true)"
[ -z "${author_proxy_hits}" ] || fail "仍存在作者代理域名: ${author_proxy_hits}"

# ---------------------------------------------------------------------------
# 2) 代理前缀变量不再参与下载拼接；GitHub 类目标保持 https:// 直连
# ---------------------------------------------------------------------------
gh_proxy_hits="$(grep -c '${gh_proxy}' "$work" || true)"
[ "${gh_proxy_hits}" -eq 0 ] || fail "仍有 ${gh_proxy_hits} 处 \${gh_proxy} 拼接"
gh_proxy_assignments="$(grep -cE '^[[:space:]]*(local[[:space:]]+)?gh_proxy=' "$work" || true)"
[ "${gh_proxy_assignments}" -eq 0 ] || fail "仍在定义 gh_proxy 代理前缀变量"

# 任何取用行（curl/wget/git/bash）里都不该再出现代理前缀变量
fetch_proxy_hits="$(grep -nE '(curl|wget|git|bash)[^|]*\$\{[A-Za-z0-9_]*(proxy|PROXY|mirror_prefix)\}' "$work" || true)"
[ -z "${fetch_proxy_hits}" ] || fail "取用命令里仍有代理前缀变量: ${fetch_proxy_hits}"

# 指回 GitHub 的目标必须是 https:// 直连，且目标主机原样保留
grep -Fq 'https://raw.githubusercontent.com/' "$work" || fail "取内容目标 raw.githubusercontent.com 的直连地址不见了"
grep -Fq 'https://github.com/' "$work" || fail "取内容目标 github.com 的直连地址不见了"
bad_downloads="$(grep -nE 'https://gh\.kejilion\.pro|gh\.kejilion\.pro/https' "$work" || true)"
[ -z "${bad_downloads}" ] || fail "仍有经作者代理的下载目标: ${bad_downloads}"

# ---------------------------------------------------------------------------
# 3) 地区开关不退化：quanju_canshu 的三分支与 https 前缀变量都还在
# ---------------------------------------------------------------------------
canshu_body="$(awk '
	/^quanju_canshu\(\) \{/ { capture = 1 }
	capture { print }
	capture && /^\}/ { exit }
' "$work")"
[ -n "${canshu_body}" ] || fail "quanju_canshu() 不见了"
grep -Fq 'if [ "$canshu" = "CN" ]; then' <<<"${canshu_body}" || fail "quanju_canshu 丢了 CN 分支"
grep -Fq 'elif [ "$canshu" = "V6" ]; then' <<<"${canshu_body}" || fail "quanju_canshu 丢了 V6 分支"
grep -Fq 'gh_https_url="https://"' <<<"${canshu_body}" || fail "quanju_canshu 丢了 gh_https_url"
if grep -Eq 'zhushi=' <<<"${canshu_body}"; then :; else fail "quanju_canshu 丢了地区开关 zhushi"; fi

# ---------------------------------------------------------------------------
# 4) Docker 镜像加速列表：作者的代理镜像已删，其余一条不少
# ---------------------------------------------------------------------------
docker_mirrors="$(
	awk '
		/^install_add_docker_cn\(\) \{$/ { capture = 1 }
		capture && /^[[:space:]]*"https:\/\// {
			gsub(/^[[:space:]]*"/, "", $0); gsub(/",?[[:space:]]*$/, "", $0); print
		}
		capture && /^\}$/ { exit }
	' "$work" | sort -u
)"
[ -n "${docker_mirrors}" ] || fail "没能抽出 Docker 镜像加速列表"
if grep -Fxq 'https://docker.kejilion.pro' <<<"${docker_mirrors}"; then
	fail "Docker 镜像列表仍含作者代理镜像"
fi
expected_mirrors='https://docker.1ms.run
https://docker.m.ixdev.cn
https://hub.rat.dev
https://dockerproxy.net
https://docker-registry.nmqu.com
https://docker.amingg.com
https://docker.hlmirror.com
https://hub1.nat.tf
https://hub2.nat.tf
https://hub3.nat.tf
https://docker.m.daocloud.io
https://docker.367231.xyz
https://hub.1panel.dev
https://dockerproxy.cool
https://docker.apiba.cn
https://proxy.vvvv.ee'
expected_sorted="$(printf '%s\n' "${expected_mirrors}" | sort -u)"
missing_mirrors="$(comm -23 <(printf '%s\n' "${expected_sorted}") <(printf '%s\n' "${docker_mirrors}"))"
[ -z "${missing_mirrors}" ] || fail "Docker 镜像列表丢了不该丢的镜像: $(printf '%s ' ${missing_mirrors})"
extra_mirrors="$(comm -13 <(printf '%s\n' "${expected_sorted}") <(printf '%s\n' "${docker_mirrors}"))"
[ -z "${extra_mirrors}" ] || fail "Docker 镜像列表多出条目: $(printf '%s ' ${extra_mirrors})"

# ---------------------------------------------------------------------------
# 5) KPanel 轻节点更新器：作者代理回退源已改成直连 GitHub
#    （整块被后续工单移除时，本条自动视为通过）
# ---------------------------------------------------------------------------
updater="$(awk '
	/<<[^A-Za-z0-9_]KPANEL_NODE_UPDATE[^A-Za-z0-9_]/ { capture = 1; next }
	capture && /^KPANEL_NODE_UPDATE$/ { exit }
	capture { print }
' "$work")"
if [ -z "${updater}" ]; then
	printf '%s\n' "note: KPanel 轻节点更新器已不在脚本中（作者代理随之不存在）"
else
	if grep -Fq 'gh.kejilion.pro' <<<"${updater}"; then
		fail "KPanel 更新器仍在引用作者代理"
	fi
	grep -Fq 'https://${github_host}/kejilion/KPanel/releases/latest/download' <<<"${updater}" \
		|| fail "KPanel 更新器的下载目标变了（必须仍是 GitHub releases）"
	grep -Fq 'SHA256SUMS' <<<"${updater}" || fail "KPanel 更新器丢了校验清单"
	grep -Fq 'sha256sum' <<<"${updater}" || fail "KPanel 更新器丢了校验步骤"
	mirror_pad_hits="$(grep -c 'mirror_prefix' <<<"${updater}" || true)"
	[ "${mirror_pad_hits}" -eq 0 ] || fail "KPanel 更新器里仍有 ${mirror_pad_hits} 处 mirror_prefix 引用"
fi

# ---------------------------------------------------------------------------
# 6) 其他硬编码代理（自动更新定时任务）同样改直连
#    （按"整块消失算通过"处理）
# ---------------------------------------------------------------------------
cron_task="$(grep -F 'SH_Update_task=' "$work" | head -n 1 || true)"
if [ -n "${cron_task}" ]; then
	grep -Fq 'curl -sS --max-time 60 --fail -o' <<<"${cron_task}" || fail "定时任务的下载命令变了"
	grep -Fq 'https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh' <<<"${cron_task}" \
		|| fail "自动更新定时任务未直连 raw.githubusercontent.com"
	# 地区差异（canshu 切换命令）必须保留，不能因拔代理一起被删掉
	grep -Fq 'canshu=\"CN\"' "$work" || fail "定时任务丢了 CN 地区切换命令"
	grep -Fq 'canshu=\"V6\"' "$work" || fail "定时任务丢了 V6 地区切换命令"
else
	printf '%s\n' "note: 自动更新定时任务已不在脚本中（作者代理随之不存在）"
fi
# 说明：OpenClaw 记忆下载用的 OPENCLAW_MEMORY_GH_PROXY 代理前缀变量，随工单 #19
# 「AI 与 OpenClaw 整块删除」连函数体一起消失，这里不再为它单独留断言（变量已不存在，
# 反向改回作者代理时上面第 1/2 条的全局代理判据一样会拦住）。

# ---------------------------------------------------------------------------
# 7) 取内容清单：作者代理端点消失，GitHub 类目标主机一个没换
# ---------------------------------------------------------------------------
records="$(bash "${inventory_check}" --records "${source_script}")"
if grep -E $'^取内容\t(gh|docker)\.kejilion\.pro\t' <<<"${records}"; then
	fail "清点清单里仍有作者代理端点"
fi
for host in raw.githubusercontent.com github.com; do
	if ! awk -F'\t' -v h="${host}" '$1=="取内容" && $2==h { found=1 } END { exit !found }' <<<"${records}"; then
		fail "清点清单里丢了取内容端点 ${host}（取内容目标必须原样保留）"
	fi
done
proxy_kind_count="$(grep -cE $'^取内容\t[^\t]+\tauthor-proxy\t' <<<"${records}" || true)"
[ "${proxy_kind_count}" -eq 0 ] || fail "仍有 ${proxy_kind_count} 处被判定为经作者代理的下载"

printf '%s\n' "direct-downloads=pass"

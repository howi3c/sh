#!/bin/bash
# 工单 #8「广告清扫」静态守门测试。
#
# 判定口径（来自 GLOSSARY.md / ADR-0001）：删利益导流与推广引流，留功能说明书与署名。
# 只静态分析 kejilion.sh 与 cn/kejilion.sh 的文本：绝不执行目标脚本、绝不联网。
# 与 tests/test_network_inventory.sh 互补——后者盯“报信=0”，本测试盯“推销清空、
# 但教学链接 / 面板官网信息 / 致谢一个不少”。
set -uo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
targets=("${project_root}/kejilion.sh" "${project_root}/cn/kejilion.sh")

fail_count=0
fail() { printf 'FAIL: %s\n' "$*" >&2; fail_count=$((fail_count + 1)); }

for target in "${targets[@]}"; do
	[ -f "$target" ] || { fail "找不到待测脚本: ${target}"; continue; }
	name="$(basename "$(dirname "$target")")/$(basename "$target")"

	# 只在“非注释”行命中才算残留：脚本里可有说明性注释提及名字，不构成可复活路径。
	absent_patterns=(
		'kejilion_Affiliates'          # 广告专栏函数 / 主菜单入口 / 分发扬
		'UserLicenseAgreement'         # 首屏协议弹窗
		'CheckFirstRun_true'           # 首次运行同意状态的跨更新恢复
		'CheckFirstRun_false'          # 首次运行许可门
		'permission_granted'           # 许可状态变量
		'欢迎使用科技lion脚本工具箱'    # 协议弹窗欢迎语
		'user-license-agreement'       # 协议网址
		'blog.kejilion.pro/ssh-key'    # 密钥面板“进阶玩法”引流
		'dev.kejilion.sh'              # 应用市场“开发者指南”引流
		'board.kejilion.pro'           # “官方留言板”引流
		'广告专栏'                     # 菜单项文案
		'科技lion周边'                 # 广告专栏内“周边”推广段
		'topvps'                       # 作者自有 VPS 优惠页
		# —— VPS / 域名返利入口（URL 带 aff/ref/返利参数）——
		'lcayun.com/aff/'
		'vmrack.net?ref_code='
		'racknerd.com/aff.php'
		'bandwagonhost.com/aff.php'
		'dmit.io/aff.php'
		'?affid='
		'gname.com/register?tt='
		'cart.hostinger.com/pay/'
		# —— API 厂商返利入口 ——
		'passport.compshare.cn/register?referral_code='
		'cloud.siliconflow.cn/i/'
		'bigmodel.cn/glm-coding?ic='
		'packyapi.com/register?aff='
		'yunwu.ai/register?aff='
		'bltcy.ai/register?aff='
		'[AFF]'                        # 厂商列表返利标记
		# —— 广告专栏内作者频道导流（区别于功能内教学视频）——
		'b23.tv/2mqnQyh'
		'youtube.com/@kejilion'
	)
	for pat in "${absent_patterns[@]}"; do
		hits="$(grep -nF -- "$pat" "$target" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
		[ -z "$hits" ] || fail "${name} 仍含应删内容 [$pat]: ${hits%%$'\n'*}"
	done

	# 必须保留：删过头就是事故（用户故事 17 / 19 / 28）。
	# 功能内视频教学链接（形如 bilibili / youtu.be 教程，出现在具体功能说明处）
	for keep in \
		'bilibili.com/video/BV14K421x7BS' \
		'bilibili.com/video/BV1mH4y1w7qA' \
		'youtu.be/vLL-eb3Z_TY'
	do
		grep -Fq -- "$keep" "$target" || fail "${name} 丢了功能内教学视频链接 [$keep]"
	done
	# 安装第三方面板时打印该面板自己的中性官网信息 + 面板安装器本体
	grep -Fq -- 'bt.cn/new/index.html' "$target" || fail "${name} 丢了三方面板自身中性官网信息（bt.cn）"
	grep -Fq -- 'install_panel()' "$target" || fail "${name} 丢了 install_panel() 面板安装器"
	# “借用的脚本”致谢段（署名，不是广告）
	grep -Fq -- '感谢bin456789' "$target" || fail "${name} 丢了致谢段（bin456789/leitbogioro）"
	grep -Fq -- 'leitbogioro项目地址' "$target" || fail "${name} 丢了致谢链接（leitbogioro）"
	grep -Fq -- '该功能由jhb大神提供' "$target" || fail "${name} 丢了致谢信息（jhb大神）"
done

if [ "${fail_count}" -ne 0 ]; then
	printf 'ads-stripped: FAIL（%s 处）\n' "${fail_count}" >&2
	exit 1
fi
printf '%s\n' 'ads-stripped=pass'

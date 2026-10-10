#!/bin/bash
set -euo pipefail

# 规格工单 #26：高级防火墙关闭/开放所有端口时自动保留 SSH 端口放行
#
# 验证：
#   1. 默认配置（#Port 22 注释）：自动兜底放行 22 端口，且绝不产生空的 --dport 参数。
#   2. 自定义端口（Port 2222）：准确放行 2222 端口。
#   3. 配置子目录（sshd_config.d/ 自定义端口）：准确解析并放行对应端口。
#   4. 多端口配置：所有有效 SSH 端口全部生成对应的放行规则。
#   5. 双栈支持：IPv4 (iptables) 与可用时的 IPv6 (ip6tables) 均同步放行。
#   6. 开放所有端口（选项 3）：同样正确识别端口，不产生空的 --dport 参数。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"

[ -f "${script_path}" ] || {
	echo "错误: 找不到待测脚本 ${script_path}" >&2
	exit 1
}

run_firewall_test() {
	local test_case="$1"
	local menu_choice="$2"
	local test_dir
	test_dir="$(mktemp -d)"
	trap 'rm -rf "${test_dir}"' RETURN

	local mock_iptables_log="${test_dir}/iptables.log"
	local mock_ip6tables_log="${test_dir}/ip6tables.log"
	local mock_sshd_config="${test_dir}/sshd_config"
	local mock_sshd_config_d="${test_dir}/sshd_config.d"
	mkdir -p "${mock_sshd_config_d}"
	: >"${mock_iptables_log}"
	: >"${mock_ip6tables_log}"

	case "${test_case}" in
		default_commented)
			printf '#Port 22\n#AddressFamily any\n' >"${mock_sshd_config}"
			;;
		custom_port)
			printf 'Port 2222\n' >"${mock_sshd_config}"
			;;
		dropin_port)
			printf '# Default config\n' >"${mock_sshd_config}"
			printf 'Port 3333\n' >"${mock_sshd_config_d}/custom.conf"
			;;
		multi_ports)
			printf 'Port 22\nPort 2222\n' >"${mock_sshd_config}"
			;;
		empty_config)
			: >"${mock_sshd_config}"
			;;
		*)
			echo "未知测试用例: ${test_case}" >&2
			return 1
			;;
	esac

	(
		export KJ_TEST_NONINTERACTIVE=1
		eval "$(
			sed "s|/etc/ssh/sshd_config|${mock_sshd_config}|g; s|/etc/ssh/sshd_config\.d|${mock_sshd_config_d}|g" "${script_path}" |
			awk '/^if \[ "\$#" -eq 0 \]; then$/ { exit } { print }'
		)"

		# 屏蔽终端清屏与写系统的命令，仅记录防火墙调用
		root_use() { :; }
		install() { :; }
		save_iptables_rules() { :; }
		clear() { :; }
		ip6tables_available() { return 0; }
		iptables-save() { :; }
		ip6tables-save() { :; }
		iptables() {
			printf '%s\n' "$*" >>"${mock_iptables_log}"
		}
		ip6tables() {
			printf '%s\n' "$*" >>"${mock_ip6tables_log}"
		}

		printf "%s\n0\n" "${menu_choice}" | iptables_panel >/dev/null 2>&1 || true
	)

	# 语法安全检查：绝不可向 iptables 或 ip6tables 传递空的 --dport
	if grep -q -- '--dport  -j ACCEPT' "${mock_iptables_log}" || grep -q -- '--dport -j ACCEPT' "${mock_iptables_log}"; then
		echo "[FAIL] ${test_case}: iptables 调用中存在空的 --dport 参数！" >&2
		return 1
	fi
	if grep -q -- '--dport  -j ACCEPT' "${mock_ip6tables_log}" || grep -q -- '--dport -j ACCEPT' "${mock_ip6tables_log}"; then
		echo "[FAIL] ${test_case}: ip6tables 调用中存在空的 --dport 参数！" >&2
		return 1
	fi

	# 业务放行断言
	case "${test_case}" in
		default_commented|empty_config)
			grep -q -- '-p tcp --dport 22 -j ACCEPT' "${mock_iptables_log}" || {
				echo "[FAIL] ${test_case}: iptables 未放行默认 22 端口！" >&2
				return 1
			}
			grep -q -- '-p tcp --dport 22 -j ACCEPT' "${mock_ip6tables_log}" || {
				echo "[FAIL] ${test_case}: ip6tables 未放行默认 22 端口！" >&2
				return 1
			}
			;;
		custom_port)
			grep -q -- '-p tcp --dport 2222 -j ACCEPT' "${mock_iptables_log}" || {
				echo "[FAIL] ${test_case}: iptables 未放行自定义 2222 端口！" >&2
				return 1
			}
			grep -q -- '-p tcp --dport 2222 -j ACCEPT' "${mock_ip6tables_log}" || {
				echo "[FAIL] ${test_case}: ip6tables 未放行自定义 2222 端口！" >&2
				return 1
			}
			;;
		dropin_port)
			grep -q -- '-p tcp --dport 3333 -j ACCEPT' "${mock_iptables_log}" || {
				echo "[FAIL] ${test_case}: iptables 未放行子配置中的 3333 端口！" >&2
				return 1
			}
			grep -q -- '-p tcp --dport 3333 -j ACCEPT' "${mock_ip6tables_log}" || {
				echo "[FAIL] ${test_case}: ip6tables 未放行子配置中的 3333 端口！" >&2
				return 1
			}
			;;
		multi_ports)
			grep -q -- '-p tcp --dport 22 -j ACCEPT' "${mock_iptables_log}" &&
			grep -q -- '-p tcp --dport 2222 -j ACCEPT' "${mock_iptables_log}" || {
				echo "[FAIL] ${test_case}: iptables 未同时放行 22 与 2222 端口！" >&2
				return 1
			}
			grep -q -- '-p tcp --dport 22 -j ACCEPT' "${mock_ip6tables_log}" &&
			grep -q -- '-p tcp --dport 2222 -j ACCEPT' "${mock_ip6tables_log}" || {
				echo "[FAIL] ${test_case}: ip6tables 未同时放行 22 与 2222 端口！" >&2
				return 1
			}
			;;
	esac
}

echo "=== 正在运行防火墙 SSH 端口保留测试（选择 4：关闭所有端口）==="
run_firewall_test "default_commented" "4"
run_firewall_test "custom_port" "4"
run_firewall_test "dropin_port" "4"
run_firewall_test "multi_ports" "4"
run_firewall_test "empty_config" "4"

echo "=== 正在运行防火墙 SSH 端口保留测试（选择 3：开放所有端口）==="
run_firewall_test "default_commented" "3"
run_firewall_test "custom_port" "3"

printf '%s\n' "firewall_close_all_ports_ssh_retain_smoke=pass"

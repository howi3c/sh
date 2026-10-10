#!/bin/bash
set -euo pipefail

# 规格工单 #26：高级防火墙关闭/开放所有端口时自动保留 SSH 端口放行
#
# 验证：
#   1. 默认配置（#Port 22 注释）：自动兜底放行 22 端口，且绝不产生空的 --dport 参数。
#   2. 自定义端口（Port 2222）：准确放行 2222 端口。
#   3. 配置子目录（sshd_config.d/ 自定义端口）：准确解析并放行对应端口。
#   4. 多端口配置：所有有效 SSH 端口全部生成对应的放行规则。
#   5. 配置文件不存在：安全兜底放行 22 端口。
#   6. 双栈支持：IPv4 (iptables) 与可用时的 IPv6 (ip6tables) 均同步放行。
#   7. IPv6 不可用：优雅降级，IPv4 依然安全生效。
#   8. 基础安全规则：RELATED,ESTABLISHED 与 lo 环回规则必须同时放行。
#   9. 开放所有端口（选项 3）：同样正确识别端口，不产生空的 --dport 参数。

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="${KEJILION_SCRIPT_PATH:-${project_root}/kejilion.sh}"

[ -f "${script_path}" ] || {
	echo "错误: 找不到待测脚本 ${script_path}" >&2
	exit 1
}

run_firewall_test() {
	local test_case="$1"
	local menu_choice="$2"
	local ipv6_enabled="${3:-yes}"

	local test_dir
	test_dir="$(mktemp -d)"
	trap 'rm -rf "${test_dir}"' RETURN

	local mock_iptables_log="${test_dir}/iptables.log"
	local mock_ip6tables_log="${test_dir}/ip6tables.log"
	local mock_sshd_config="${test_dir}/sshd_config"
	local mock_sshd_config_d="${test_dir}/sshd_config.d"
	local mock_iptables_dir="${test_dir}/iptables_dir"
	mkdir -p "${mock_sshd_config_d}" "${mock_iptables_dir}"
	: >"${mock_iptables_log}"
	: >"${mock_ip6tables_log}"

	local expected_ports=()

	case "${test_case}" in
		default_commented)
			printf '#Port 22\n#AddressFamily any\n' >"${mock_sshd_config}"
			expected_ports=(22)
			;;
		custom_port)
			printf 'Port 2222\n' >"${mock_sshd_config}"
			expected_ports=(2222)
			;;
		dropin_port)
			printf '# Default config\n' >"${mock_sshd_config}"
			printf 'Port 3333\n' >"${mock_sshd_config_d}/custom.conf"
			expected_ports=(3333)
			;;
		multi_ports)
			printf 'Port 22\nPort 2222\n' >"${mock_sshd_config}"
			expected_ports=(22 2222)
			;;
		empty_config)
			: >"${mock_sshd_config}"
			expected_ports=(22)
			;;
		missing_config)
			rm -rf "${mock_sshd_config}" "${mock_sshd_config_d}"
			expected_ports=(22)
			;;
		*)
			echo "未知测试用例: ${test_case}" >&2
			return 1
			;;
	esac

	(
		export KJ_TEST_NONINTERACTIVE=1
		# 将 /etc/ssh 及 /etc/iptables 隔离至测试临时目录，杜绝污染宿主机
		eval "$(
			sed "s|/etc/ssh/sshd_config|${mock_sshd_config}|g;
			     s|/etc/ssh/sshd_config\.d|${mock_sshd_config_d}|g;
			     s|/etc/iptables|${mock_iptables_dir}|g" "${script_path}" |
			awk '/^if \[ "\$#" -eq 0 \]; then$/ { exit } { print }'
		)"

		# 屏蔽外部依赖与宿主机服务状态，确保纯配置文件探测测试
		root_use() { :; }
		install() { :; }
		save_iptables_rules() { :; }
		clear() { :; }
		sshd() { return 1; }
		ss() { return 1; }
		ip6tables_available() {
			[ "${ipv6_enabled}" = "yes" ]
		}
		iptables-save() { :; }
		ip6tables-save() { :; }
		iptables() {
			case "$1" in
				-C) return 0 ;;
				*) printf '%s\n' "$*" >>"${mock_iptables_log}" ;;
			esac
		}
		ip6tables() {
			case "$1" in
				-C) return 0 ;;
				*) printf '%s\n' "$*" >>"${mock_ip6tables_log}" ;;
			esac
		}

		printf "%s\n0\n" "${menu_choice}" | iptables_panel >/dev/null 2>&1 || true
	)

	# 语法安全检查：绝不可向 iptables 或 ip6tables 传递空的 --dport
	for log_file in "${mock_iptables_log}" "${mock_ip6tables_log}"; do
		if grep -Eq -- '--dport[[:space:]]+-j' "${log_file}" || grep -Eq -- '--dport[[:space:]]*$' "${log_file}"; then
			echo "[FAIL] ${test_case}: 防火墙调用日志 ${log_file} 中存在空的 --dport 参数！" >&2
			return 1
		fi
	done

	# 基础规则断言：必须放行状态关联连接与回环 lo
	grep -q -- '-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT' "${mock_iptables_log}" || {
		echo "[FAIL] ${test_case}: iptables 未放行 ESTABLISHED,RELATED 会话！" >&2
		return 1
	}
	grep -q -- '-A INPUT -i lo -j ACCEPT' "${mock_iptables_log}" || {
		echo "[FAIL] ${test_case}: iptables 未放行 lo 本地环回接口！" >&2
		return 1
	}

	# 预期端口放行断言
	for port in "${expected_ports[@]}"; do
		grep -q -- "-p tcp --dport ${port} -j ACCEPT" "${mock_iptables_log}" || {
			echo "[FAIL] ${test_case}: iptables 未放行预期端口 ${port}！" >&2
			return 1
		}
		if [ "${ipv6_enabled}" = "yes" ]; then
			grep -q -- "-p tcp --dport ${port} -j ACCEPT" "${mock_ip6tables_log}" || {
				echo "[FAIL] ${test_case}: ip6tables 未放行预期端口 ${port}！" >&2
				return 1
			}
		fi
	done

	# IPv6 禁用时确保没有向 ip6tables 写入规则
	if [ "${ipv6_enabled}" = "no" ]; then
		[ ! -s "${mock_ip6tables_log}" ] || {
			echo "[FAIL] ${test_case}: IPv6 禁用时意外调用了 ip6tables！" >&2
			return 1
		}
	fi
}

echo "=== 正在运行防火墙 SSH 端口保留测试（选择 4：关闭所有端口）==="
run_firewall_test "default_commented" "4" "yes"
run_firewall_test "custom_port" "4" "yes"
run_firewall_test "dropin_port" "4" "yes"
run_firewall_test "multi_ports" "4" "yes"
run_firewall_test "empty_config" "4" "yes"
run_firewall_test "missing_config" "4" "yes"

echo "=== 正在运行防火墙 IPv6 禁用降级测试 ==="
run_firewall_test "default_commented" "4" "no"

echo "=== 正在运行防火墙 SSH 端口保留测试（选择 3：开放所有端口）==="
run_firewall_test "default_commented" "3" "yes"
run_firewall_test "custom_port" "3" "yes"

printf '%s\n' "firewall_close_all_ports_ssh_retain_smoke=pass"

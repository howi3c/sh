#!/bin/bash
# #27 已确认的边界：现有重装菜单；只替换操作系统边界，不触碰本机。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export KJ_TEST_NONINTERACTIVE=1
source <(awk '/^if \[ "\$#" -eq 0 \]; then$/ {exit} {print}' "$root/kejilion.sh")
root_use() { :; }
clear() { :; }
# 入口不应自行下载外部安装器或重启；真实模块由下面的记录边界替代。
curl() { echo unsafe-download >> "$work/events"; return 1; }
wget() { echo unsafe-download >> "$work/events"; return 1; }
reboot() { echo unsafe-reboot >> "$work/events"; }
install() { :; }
kj_secure_reinstall() { printf 'secure %s %s\n' "$1" "$2" >> "$work/events"; return 1; }
for spec in '1 debian 13' '2 debian 12' '3 debian 11' '4 debian 10' '11 ubuntu 26.04' '12 ubuntu 24.04' '13 ubuntu 22.04' '14 ubuntu 20.04'; do
    read -r choice distro version <<< "$spec"
    : > "$work/events"
    # 0 从菜单返回；失败不被解释成同意重启。
    if printf '%s\n0\n' "$choice" | dd_xitong > "$work/output"; then :; fi
    printf 'secure %s %s\n' "$distro" "$version" > "$work/expected"
    diff -u "$work/expected" "$work/events"
    if grep -q '123@@@' "$work/output"; then
        echo 'FAIL: Debian/Ubuntu 入口泄露无关公开固定密码提示' >&2; exit 1
    fi
    grep -q '按任意键返回重装菜单' "$work/output" || {
        echo 'FAIL: 失败原因未停留，菜单重绘会把它清掉' >&2; exit 1
    }
done
# 菜单 EOF 不能被当作确认，也不能死循环。
: > "$work/events"
dd_xitong < /dev/null > "$work/output"
[ ! -s "$work/events" ]
echo 'reinstall-entry=pass'

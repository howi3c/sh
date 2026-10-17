#!/bin/bash
# Bootstrap seam: genuine private downloads + SHA256, replace only curl/Python.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
test_work=$(mktemp -d)
trap 'rm -rf -- "$test_work"' EXIT
export KJ_TEST_NONINTERACTIVE=1
source <(awk '/^if \[ "\$#" -eq 0 \]; then$/ {exit} {print}' "$root/kejilion.sh")
get_ssh_ports() { printf '2222\n'; }
reboot() { echo UNSAFE_REBOOT >> "$test_work/events"; return 99; }
curl() {
    local destination='' url='' arg
    printf '%s\n' "$*" >> "$test_work/curl-args"
    while [ "$#" -gt 0 ]; do
        arg=$1; shift
        case "$arg" in
            --output) destination=$1; shift ;;
            https://*) url=$arg ;;
        esac
    done
    [[ "$url" =~ ^https://raw.githubusercontent.com/howi3c/sh/[a-f0-9]{40}/reinstall\.py$ ]] || return 97
    [ "$(stat -c %a "$(dirname "$destination")")" = 700 ] || return 98
    printf '%s\n' "$(dirname "$destination")" >> "$test_work/dirs"
    case "$scenario" in
        tls|timeout) printf 'partial' > "$destination"; return 60 ;;
        missing) printf 200 ;;
        redirect) printf 'redirect body' > "$destination"; printf 302 ;;
        tampered) printf 'raise RuntimeError("old script")\n' > "$destination"; printf 200 ;;
        ok) cp "$root/reinstall.py" "$destination"; printf 200 ;;
    esac
}
python3() {
    printf '%s\n' "$*" >> "$test_work/events"
    [ "$1" = -I ] || return 99
    shift
    [ "$2" = --distro ] && [ "$3" = debian ] && [ "$4" = --version ] && [ "$5" = 13 ] && [ "$6" = --ssh-ports ] && [ "$7" = 2222 ]
}
mkdir "$test_work/current"
printf 'old untrusted script' > "$test_work/old"
ln -s "$test_work/old" "$test_work/current/reinstall.py"
cd "$test_work/current"
for scenario in tls timeout missing redirect tampered ok; do
    : > "$test_work/events"; : > "$test_work/curl-args"; : > "$test_work/dirs"
    if kj_secure_reinstall debian 13 > "$test_work/output" 2>&1; then result=0; else result=$?; fi
    if [ "$scenario" = ok ]; then
        [ "$result" = 0 ] && [ "$(wc -l < "$test_work/events")" = 1 ] || { echo 'FAIL: fixed module did not execute exactly once'; exit 1; }
    else
        [ "$result" != 0 ] && [ ! -s "$test_work/events" ] || { echo "FAIL: $scenario executed code/reboot"; exit 1; }
    fi
    while IFS= read -r directory; do [ ! -e "$directory" ] || { echo 'FAIL: bootstrap private material retained'; exit 1; }; done < "$test_work/dirs"
    grep -q -- '--disable --proto =https --proto-redir =https --fail' "$test_work/curl-args"
    ! grep -Eq -- '--location|--insecure|(^| )-k( |$)' "$test_work/curl-args"
    [ "$(readlink "$test_work/current/reinstall.py")" = "$test_work/old" ]
    [ "$(< "$test_work/old")" = 'old untrusted script' ]
done
echo 'reinstall-loader=pass'

#!/bin/bash
sh_v="4.5.10"


gl_hui='\e[37m'
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'


# 拼 GitHub 展示/取用地址用的 https:// 前缀（原住在 quanju_canshu 里，随地区开关删除提为顶层常量）
gh_https_url="https://"
KPANEL_WEB_CERTIFICATE_PROTOCOL_VERSION="1"
KPANEL_WEB_CERTIFICATE_REPLACE_PROTOCOL_VERSION="1"
KPANEL_APP_CONCURRENCY_PROTOCOL_VERSION="1"
unset KJ_APP_LOCKS_HELD

# Locks live outside PrivateTmp and app data. Only the paired KPanel worker
# enables this protocol; old workers keep their existing exclusive admission.
kpanel_app_lock_held() {
	case ":${KJ_APP_LOCKS_HELD:-}:" in *":$1:"*) return 0 ;; esac
	return 1
}

kpanel_app_with_lock() {
	local resource="$1"
	shift
	case "$resource" in system|catalog|markers) ;; *) exit 1 ;; esac
	if kpanel_app_lock_held "$resource"; then "$@"; return $?; fi
	local lock_dir="/run/lock/kejilion-app"
	local lock_fd result
	command -v flock >/dev/null 2>&1 || { echo "错误: 应用并行交互需要 flock" >&2; exit 1; }
	[ "$(id -u)" = "0" ] || exit 1
	[ ! -L "$lock_dir" ] || exit 1
	(umask 077; mkdir -p "$lock_dir") || exit 1
	[ ! -L "$lock_dir" ] && [ -d "$lock_dir" ] && [ "$(stat -c '%u:%a' "$lock_dir")" = "0:700" ] || exit 1
	[ ! -L "$lock_dir/$resource.lock" ] || exit 1
	(umask 077; touch "$lock_dir/$resource.lock") || exit 1
	[ -f "$lock_dir/$resource.lock" ] || exit 1
	exec {lock_fd}>>"$lock_dir/$resource.lock" || exit 1
	if ! flock -w 300 "$lock_fd"; then
		echo "共享系统资源正忙，等待超过 300 秒，请稍后重试。" >&2
		exec {lock_fd}>&-
		exit 1
	fi
	local KJ_APP_LOCKS_HELD="${KJ_APP_LOCKS_HELD:-}:$resource"
	export -n KJ_APP_LOCKS_HELD
	if "$@"; then result=0; else result=$?; fi
	flock -u "$lock_fd" || exit 1
	exec {lock_fd}>&-
	return "$result"
}

kpanel_protocol_active() {
	[ "${KJ_SSH_PORT_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_DNS_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_SYSTEM_RESOURCE_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_DISK_MANAGEMENT_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_NETWORK_OPERATIONS_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_ACCOUNT_MANAGEMENT_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_F2B_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_SYSTEM_TUNING_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_VIRUS_SCAN_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_BBRV3_NONINTERACTIVE:-}" = "1" ] ||
	[ "${KJ_TEST_NONINTERACTIVE:-}" = "1" ]
}


# k 快捷命令的安装链：脚本本体 → ~/kejilion.sh → /usr/local/bin/k →（软链）/usr/bin/k。
#
# 原版只认「当前目录里的 ./kejilion.sh」当第一跳，于是 bash <(curl …) 这类管道
# 跑法（脚本本体从不在磁盘上）会让整条链断在第一跳，且每跳报错都被吞，k 静默装不上。
# 净化版删掉更新功能（工单 #7）后没有别的兜底，这里补上自落盘：
#   · 跑的是磁盘上的脚本文件（./kejilion.sh、bash kejilion.sh、直接跑 k）→ 以它为准；
#   · 脚本本体不在磁盘上（bash <(curl …) 管道 / curl | bash）→ 从本仓库 raw 地址
#     取一份落到 ~/kejilion.sh 再接上安装链（取内容只从本仓库，见 GLOSSARY.md
#     「取内容」与 docs/adr/0002-content-fetching-only-from-this-repo.md）。
# 另外补三件原版没有的事：落盘后补执行位（curl 下载的文件默认 644，不补则 k 装上
# 也不能执行）；装不上时把原因说明白并清掉烂尾（见下面的 kj_k_shortcut_failed）；
# 首次装上屏幕给一句提示，安装结果不再不可见。
kj_k_shortcut_failed() {
	local k_link="$1" reason="$2"
	[ -L "${k_link}" ] && rm -f "${k_link}"
	echo -e "${gl_huang}提示: ${gl_bai}k 命令没装上（${reason}）。"
	return 1
}

kj_install_k_shortcut() {
	local self="$0"
	local k_bin="${KJ_LOCAL_BIN_DIR:-/usr/local/bin}/k"
	local k_link="${KJ_SYSTEM_BIN_DIR:-/usr/bin}/k"
	local home_script="${HOME}/kejilion.sh"
	local installed_before=0 from_fetch=0

	sed -i '/^alias k=/d' ~/.bashrc > /dev/null 2>&1
	sed -i '/^alias k=/d' ~/.profile > /dev/null 2>&1
	sed -i '/^alias k=/d' ~/.bash_profile > /dev/null 2>&1

	[ -f "${k_bin}" ] && installed_before=1

	if [ -f "${self}" ] && head -1 "${self}" 2>/dev/null | grep -q '^#!/bin/bash'; then
		cp -f "${self}" "${home_script}" > /dev/null 2>&1
	else
		# 脚本本体不在磁盘上（bash <(curl …) / curl | bash）：从本仓库取一份，接上第一跳
		from_fetch=1
		curl -fsSL --connect-timeout 15 --max-time 60 -o "${home_script}" "https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh" > /dev/null 2>&1
	fi

	if [ ! -f "${home_script}" ]; then
		if [ "${from_fetch}" -eq 1 ]; then
			kj_k_shortcut_failed "${k_link}" "脚本本体没落到磁盘，从仓库取内容也没成功"
		else
			kj_k_shortcut_failed "${k_link}" "脚本本体没落到磁盘，复制运行中的脚本失败"
		fi
		return 1
	fi

	chmod +x "${home_script}" > /dev/null 2>&1
	cp -f "${home_script}" "${k_bin}" > /dev/null 2>&1
	chmod +x "${k_bin}" > /dev/null 2>&1
	if [ -f "${k_bin}" ]; then
		ln -sf "${k_bin}" "${k_link}" > /dev/null 2>&1
		if [ "${installed_before}" -eq 0 ]; then
			echo -e "${gl_kjlan}快捷命令 k 已就绪，之后输入 k 就能打开本菜单。${gl_bai}"
		fi
	else
		kj_k_shortcut_failed "${k_link}" "写入 ${k_bin} 失败"
		return 1
	fi
	return 0
}

if ! kpanel_protocol_active; then
	kj_install_k_shortcut
fi



ip_address() {

get_public_ip() {
	curl -s https://ipinfo.io/ip && echo
}

get_local_ip() {
	ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || \
	hostname -I 2>/dev/null | awk '{print $1}' || \
	ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1
}

public_ip=$(get_public_ip)
isp_info=$(curl -s --max-time 3 http://ipinfo.io/org)


if echo "$isp_info" | grep -Eiq 'CHINANET|mobile|unicom|telecom'; then
  ipv4_address=$(get_local_ip)
else
  ipv4_address="$public_ip"
fi


# ipv4_address=$(curl -s https://ipinfo.io/ip && echo)
ipv6_address=$(curl -s --max-time 1 https://v6.ipinfo.io/ip && echo)

}



install() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system install "$@"; return $?
	fi
	if [ $# -eq 0 ]; then
		echo "未提供软件包参数!"
		return 1
	fi

	for package in "$@"; do
		if ! command -v "$package" &>/dev/null; then
			echo -e "${gl_kjlan}正在安装 $package...${gl_bai}"
			if command -v dnf &>/dev/null; then
				dnf -y update
				dnf install -y epel-release
				dnf install -y "$package"
			elif command -v yum &>/dev/null; then
				yum -y update
				yum install -y epel-release
				yum install -y "$package"
			elif command -v apt &>/dev/null; then
				apt update -y
				apt install -y "$package"
			elif command -v apk &>/dev/null; then
				apk update
				apk add "$package"
			elif command -v pacman &>/dev/null; then
				pacman -Syu --noconfirm
				pacman -S --noconfirm "$package"
			elif command -v zypper &>/dev/null; then
				zypper refresh
				zypper install -y "$package"
			elif command -v opkg &>/dev/null; then
				opkg update
				opkg install "$package"
			elif command -v pkg &>/dev/null; then
				pkg update
				pkg install -y "$package"
			else
				echo "未知的包管理器!"
				return 1
			fi
		fi
	done
}


check_disk_space() {
	local required_gb=$1
	local path=${2:-/}

	mkdir -p "$path"

	local required_space_mb=$((required_gb * 1024))
	local available_space_mb=$(df -m "$path" | awk 'NR==2 {print $4}')

	if [ "$available_space_mb" -lt "$required_space_mb" ]; then
		echo -e "${gl_huang}提示: ${gl_bai}磁盘空间不足！"
		echo "当前可用空间: $((available_space_mb/1024))G"
		echo "最小需求空间: ${required_gb}G"
		echo "无法继续安装，请清理磁盘空间后重试。"
		break_end
		kejilion
	fi
}



remove() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system remove "$@"; return $?
	fi
	if [ $# -eq 0 ]; then
		echo "未提供软件包参数!"
		return 1
	fi

	for package in "$@"; do
		echo -e "${gl_kjlan}正在卸载 $package...${gl_bai}"
		if command -v dnf &>/dev/null; then
			dnf remove -y "$package"
		elif command -v yum &>/dev/null; then
			yum remove -y "$package"
		elif command -v apt &>/dev/null; then
			apt purge -y "$package"
		elif command -v apk &>/dev/null; then
			apk del "$package"
		elif command -v pacman &>/dev/null; then
			pacman -Rns --noconfirm "$package"
		elif command -v zypper &>/dev/null; then
			zypper remove -y "$package"
		elif command -v opkg &>/dev/null; then
			opkg remove "$package"
		elif command -v pkg &>/dev/null; then
			pkg delete -y "$package"
		else
			echo "未知的包管理器!"
			return 1
		fi
	done
}


# 通用 systemctl 函数，适用于各种发行版
systemctl() {
	local COMMAND="$1"
	local SERVICE_NAME="$2"

	if command -v apk &>/dev/null; then
		service "$SERVICE_NAME" "$COMMAND"
	else
		/bin/systemctl "$COMMAND" "$SERVICE_NAME"
	fi
}


# 重启服务
restart() {
	systemctl restart "$1"
	if [ $? -eq 0 ]; then
		echo "$1 服务已重启。"
	else
		echo "错误：重启 $1 服务失败。"
	fi
}

# 启动服务
start() {
	systemctl start "$1"
	if [ $? -eq 0 ]; then
		echo "$1 服务已启动。"
	else
		echo "错误：启动 $1 服务失败。"
	fi
}

# 停止服务
stop() {
	systemctl stop "$1"
	if [ $? -eq 0 ]; then
		echo "$1 服务已停止。"
	else
		echo "错误：停止 $1 服务失败。"
	fi
}

# 查看服务状态
status() {
	systemctl status "$1"
	if [ $? -eq 0 ]; then
		echo "$1 服务状态已显示。"
	else
		echo "错误：无法显示 $1 服务状态。"
	fi
}


enable() {
	local SERVICE_NAME="$1"
	if command -v apk &>/dev/null; then
		rc-update add "$SERVICE_NAME" default
	else
	   /bin/systemctl enable "$SERVICE_NAME"
	fi

	echo "$SERVICE_NAME 已设置为开机自启。"
}



break_end() {
	  echo -e "${gl_lv}操作完成${gl_bai}"
	  echo "按任意键继续..."
	  read -n 1 -s -r -p ""
	  echo ""
	  clear
}

kejilion() {
			cd ~
			kejilion_sh
}




install_add_docker_cn() {

local country=$(curl -s ipinfo.io/country)
if [ "$country" = "CN" ]; then
	cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
	"https://docker.1ms.run",
	"https://docker.m.ixdev.cn",
	"https://hub.rat.dev",
	"https://dockerproxy.net",
	"https://docker-registry.nmqu.com",
	"https://docker.amingg.com",
	"https://docker.hlmirror.com",
	"https://hub1.nat.tf",
	"https://hub2.nat.tf",
	"https://hub3.nat.tf",
	"https://docker.m.daocloud.io",
	"https://docker.367231.xyz",
	"https://hub.1panel.dev",
	"https://dockerproxy.cool",
	"https://docker.apiba.cn",
	"https://proxy.vvvv.ee"
  ]
}
EOF
fi


enable docker
start docker
restart docker

}



linuxmirrors_install_docker() {

local country=$(curl -s ipinfo.io/country)
if [ "$country" = "CN" ]; then
	bash <(curl -sSL https://linuxmirrors.cn/docker.sh) \
	  --source mirrors.huaweicloud.com/docker-ce \
	  --source-registry docker.1ms.run \
	  --protocol https \
	  --use-intranet-source false \
	  --install-latest true \
	  --close-firewall false \
	  --ignore-backup-tips
else
	bash <(curl -sSL https://linuxmirrors.cn/docker.sh) \
	  --source download.docker.com \
	  --source-registry registry.hub.docker.com \
	  --protocol https \
	  --use-intranet-source false \
	  --install-latest true \
	  --close-firewall false \
	  --ignore-backup-tips
fi

install_add_docker_cn

}



install_add_docker() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system install_add_docker "$@"; return $?
	fi
	echo -e "${gl_kjlan}正在安装docker环境...${gl_bai}"
	if command -v apt &>/dev/null || command -v yum &>/dev/null || command -v dnf &>/dev/null; then
		linuxmirrors_install_docker
	else
		install docker docker-compose
		install_add_docker_cn

	fi
	sleep 2
}


install_docker() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system install_docker "$@"; return $?
	fi
	if ! command -v docker &>/dev/null; then
		install_add_docker
	fi
}


docker_ps() {
while true; do
	clear
	echo "Docker容器列表"
	docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
	echo ""
	echo "容器操作"
	echo "------------------------"
	echo "1. 创建新的容器"
	echo "------------------------"
	echo "2. 启动指定容器             6. 启动所有容器"
	echo "3. 停止指定容器             7. 停止所有容器"
	echo "4. 删除指定容器             8. 删除所有容器"
	echo "5. 重启指定容器             9. 重启所有容器"
	echo "------------------------"
	echo "11. 进入指定容器           12. 查看容器日志"
	echo "13. 查看容器网络           14. 查看容器占用"
	echo "------------------------"
	echo "15. 开启容器端口访问       16. 关闭容器端口访问"
	echo "------------------------"
	echo "0. 返回上一级选单"
	echo "------------------------"
	read -e -p "请输入你的选择: " sub_choice
	case $sub_choice in
		1)
			read -e -p "请输入创建命令: " dockername
			$dockername
			;;
		2)
			read -e -p "请输入容器名（多个容器名请用空格分隔）: " dockername
			docker start $dockername
			;;
		3)
			read -e -p "请输入容器名（多个容器名请用空格分隔）: " dockername
			docker stop $dockername
			;;
		4)
			read -e -p "请输入容器名（多个容器名请用空格分隔）: " dockername
			docker rm -f $dockername
			;;
		5)
			read -e -p "请输入容器名（多个容器名请用空格分隔）: " dockername
			docker restart $dockername
			;;
		6)
			docker start $(docker ps -a -q)
			;;
		7)
			docker stop $(docker ps -q)
			;;
		8)
			read -e -p "$(echo -e "${gl_hong}注意: ${gl_bai}确定删除所有容器吗？(Y/N): ")" choice
			case "$choice" in
			  [Yy])
				docker rm -f $(docker ps -a -q)
				;;
			  [Nn])
				;;
			  *)
				echo "无效的选择，请输入 Y 或 N。"
				;;
			esac
			;;
		9)
			docker restart $(docker ps -q)
			;;
		11)
			read -e -p "请输入容器名: " dockername
			docker exec -it $dockername /bin/sh
			break_end
			;;
		12)
			read -e -p "请输入容器名: " dockername
			docker logs $dockername
			break_end
			;;
		13)
			echo ""
			container_ids=$(docker ps -q)
			echo "------------------------------------------------------------"
			printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"
			for container_id in $container_ids; do
				local container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")
				local container_name=$(echo "$container_info" | awk '{print $1}')
				local network_info=$(echo "$container_info" | cut -d' ' -f2-)
				while IFS= read -r line; do
					local network_name=$(echo "$line" | awk '{print $1}')
					local ip_address=$(echo "$line" | awk '{print $2}')
					printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
				done <<< "$network_info"
			done
			break_end
			;;
		14)
			docker stats --no-stream
			break_end
			;;

		15)
			read -e -p "请输入容器名: " docker_name
			ip_address
			clear_container_rules "$docker_name" "$ipv4_address" || return 1
			local docker_port=$(docker port $docker_name | awk -F'[:]' '/->/ {print $NF}' | uniq)
			check_docker_app_ip
			break_end
			;;

		16)
			read -e -p "请输入容器名: " docker_name
			ip_address
			block_container_port "$docker_name" "$ipv4_address" || return 1
			local docker_port=$(docker port $docker_name | awk -F'[:]' '/->/ {print $NF}' | uniq)
			check_docker_app_ip
			break_end
			;;

		*)
			break  # 跳出循环，退出菜单
			;;
	esac
done
}


docker_image() {
while true; do
	clear
	echo "Docker镜像列表"
	docker image ls
	echo ""
	echo "镜像操作"
	echo "------------------------"
	echo "1. 获取指定镜像             3. 删除指定镜像"
	echo "2. 更新指定镜像             4. 删除所有镜像"
	echo "------------------------"
	echo "0. 返回上一级选单"
	echo "------------------------"
	read -e -p "请输入你的选择: " sub_choice
	case $sub_choice in
		1)
			read -e -p "请输入镜像名（多个镜像名请用空格分隔）: " imagenames
			for name in $imagenames; do
				echo -e "${gl_kjlan}正在获取镜像: $name${gl_bai}"
				docker pull $name
			done
			;;
		2)
			read -e -p "请输入镜像名（多个镜像名请用空格分隔）: " imagenames
			for name in $imagenames; do
				echo -e "${gl_kjlan}正在更新镜像: $name${gl_bai}"
				docker pull $name
			done
			;;
		3)
			read -e -p "请输入镜像名（多个镜像名请用空格分隔）: " imagenames
			for name in $imagenames; do
				docker rmi -f $name
			done
			;;
		4)
			read -e -p "$(echo -e "${gl_hong}注意: ${gl_bai}确定删除所有镜像吗？(Y/N): ")" choice
			case "$choice" in
			  [Yy])
				docker rmi -f $(docker images -q)
				;;
			  [Nn])
				;;
			  *)
				echo "无效的选择，请输入 Y 或 N。"
				;;
			esac
			;;
		*)
			break  # 跳出循环，退出菜单
			;;
	esac
done


}





check_crontab_installed() {
	if ! command -v crontab >/dev/null 2>&1; then
		install_crontab
	fi
}



install_crontab() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system install_crontab "$@"; return $?
	fi
	local package_manager

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		case "$ID" in
			ubuntu|debian|kali)
				apt update
				apt install -y cron
				systemctl enable cron
				systemctl start cron
				;;
			centos|rhel|almalinux|rocky|fedora)
				if command -v dnf >/dev/null 2>&1; then
					package_manager=dnf
				elif command -v yum >/dev/null 2>&1; then
					package_manager=yum
				else
					echo "错误: 未找到 DNF/YUM，无法安装 cronie"
					return 1
				fi
				"$package_manager" install -y cronie || return 1
				/bin/systemctl enable --now crond.service || return 1
				command -v crontab >/dev/null 2>&1 || return 1
				/bin/systemctl is-active --quiet crond.service || return 1
				;;
			alpine)
				apk add --no-cache cronie
				rc-update add crond
				rc-service crond start
				;;
			arch|manjaro)
				pacman -S --noconfirm cronie
				systemctl enable cronie
				systemctl start cronie
				;;
			opensuse|suse|opensuse-tumbleweed)
				zypper install -y cron
				systemctl enable cron
				systemctl start cron
				;;
			iStoreOS|openwrt|ImmortalWrt|lede)
				opkg update
				opkg install cron
				/etc/init.d/cron enable
				/etc/init.d/cron start
				;;
			FreeBSD)
				pkg install -y cronie
				sysrc cron_enable="YES"
				service cron start
				;;
			*)
				echo "不支持的发行版: $ID"
				return
				;;
		esac
	else
		echo "无法确定操作系统。"
		return
	fi

	command -v crontab >/dev/null 2>&1 || return 1
	echo -e "${gl_lv}crontab 已安装且 cron 服务正在运行。${gl_bai}"
}



docker_ipv6_on() {
	root_use
	install jq

	local CONFIG_FILE="/etc/docker/daemon.json"
	local REQUIRED_IPV6_CONFIG='{"ipv6": true, "fixed-cidr-v6": "2001:db8:1::/64"}'

	# 检查配置文件是否存在，如果不存在则创建文件并写入默认设置
	if [ ! -f "$CONFIG_FILE" ]; then
		echo "$REQUIRED_IPV6_CONFIG" | jq . > "$CONFIG_FILE"
		restart docker
	else
		# 使用jq处理配置文件的更新
		local ORIGINAL_CONFIG=$(<"$CONFIG_FILE")

		# 检查当前配置是否已经有 ipv6 设置
		local CURRENT_IPV6=$(echo "$ORIGINAL_CONFIG" | jq '.ipv6 // false')

		# 更新配置，开启 IPv6
		if [[ "$CURRENT_IPV6" == "false" ]]; then
			UPDATED_CONFIG=$(echo "$ORIGINAL_CONFIG" | jq '. + {ipv6: true, "fixed-cidr-v6": "2001:db8:1::/64"}')
		else
			UPDATED_CONFIG=$(echo "$ORIGINAL_CONFIG" | jq '. + {"fixed-cidr-v6": "2001:db8:1::/64"}')
		fi

		# 对比原始配置与新配置
		if [[ "$ORIGINAL_CONFIG" == "$UPDATED_CONFIG" ]]; then
			echo -e "${gl_huang}当前已开启ipv6访问${gl_bai}"
		else
			echo "$UPDATED_CONFIG" | jq . > "$CONFIG_FILE"
			restart docker
		fi
	fi
}


docker_ipv6_off() {
	root_use
	install jq

	local CONFIG_FILE="/etc/docker/daemon.json"

	# 检查配置文件是否存在
	if [ ! -f "$CONFIG_FILE" ]; then
		echo -e "${gl_hong}配置文件不存在${gl_bai}"
		return
	fi

	# 读取当前配置
	local ORIGINAL_CONFIG=$(<"$CONFIG_FILE")

	# 使用jq处理配置文件的更新
	local UPDATED_CONFIG=$(echo "$ORIGINAL_CONFIG" | jq 'del(.["fixed-cidr-v6"]) | .ipv6 = false')

	# 检查当前的 ipv6 状态
	local CURRENT_IPV6=$(echo "$ORIGINAL_CONFIG" | jq -r '.ipv6 // false')

	# 对比原始配置与新配置
	if [[ "$CURRENT_IPV6" == "false" ]]; then
		echo -e "${gl_huang}当前已关闭ipv6访问${gl_bai}"
	else
		echo "$UPDATED_CONFIG" | jq . > "$CONFIG_FILE"
		restart docker
		echo -e "${gl_huang}已成功关闭ipv6访问${gl_bai}"
	fi
}



ip6tables_available() {
	command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1
}

save_iptables_rules() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system save_iptables_rules "$@"; return $?
	fi
	mkdir -p /etc/iptables
	local rules_temp rules6_temp
	rules_temp=$(mktemp /etc/iptables/.rules.v4.XXXXXX) || return 1
	ip6tables_available && rules6_temp=$(mktemp /etc/iptables/.rules.v6.XXXXXX)
	if ! iptables-save > "$rules_temp" || ! mv -f -- "$rules_temp" /etc/iptables/rules.v4; then
		rm -f -- "$rules_temp" "$rules6_temp"
		return 1
	fi
	if [ -n "${rules6_temp:-}" ]; then
		if ! ip6tables-save > "$rules6_temp" || ! mv -f -- "$rules6_temp" /etc/iptables/rules.v6; then
			rm -f -- "$rules6_temp"
			return 1
		fi
	fi
	check_crontab_installed || return 1
	crontab -l | grep -v 'iptables-restore' | grep -v 'ip6tables-restore' | crontab - > /dev/null 2>&1 || return 1
	(crontab -l ; echo '@reboot iptables-restore < /etc/iptables/rules.v4') | crontab - > /dev/null 2>&1 || return 1
	if [ -n "${rules6_temp:-}" ]; then
		(crontab -l ; echo '@reboot ip6tables-restore < /etc/iptables/rules.v6') | crontab - > /dev/null 2>&1 || return 1
	fi

}




iptables_open() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system iptables_open "$@"; return $?
	fi
	install iptables || return 1
	save_iptables_rules || return 1
	iptables -P INPUT ACCEPT || return 1
	iptables -P FORWARD ACCEPT || return 1
	iptables -P OUTPUT ACCEPT || return 1
	iptables -F || return 1

	ip6tables -P INPUT ACCEPT || return 1
	ip6tables -P FORWARD ACCEPT || return 1
	ip6tables -P OUTPUT ACCEPT || return 1
	ip6tables -F || return 1

}



open_port() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system open_port "$@"; return $?
	fi
	local ports=($@)  # 将传入的参数转换为数组
	if [ ${#ports[@]} -eq 0 ]; then
		echo "请提供至少一个端口号"
		return 1
	fi

	install iptables || return 1
	local ipv6_ready=false
	ip6tables_available && ipv6_ready=true

	for port in "${ports[@]}"; do
		# 删除已存在的关闭规则
		iptables -D INPUT -p tcp --dport $port -j DROP 2>/dev/null
		iptables -D INPUT -p udp --dport $port -j DROP 2>/dev/null

		# 添加打开规则
		if ! iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
			iptables -I INPUT 1 -p tcp --dport $port -j ACCEPT || return 1
		fi

		if ! iptables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null; then
			iptables -I INPUT 1 -p udp --dport $port -j ACCEPT || return 1
			echo "已打开端口 $port"
		fi
	done

	if [ "$ipv6_ready" = true ]; then
		for port in "${ports[@]}"; do
			ip6tables -D INPUT -p tcp --dport $port -j DROP 2>/dev/null
			ip6tables -D INPUT -p udp --dport $port -j DROP 2>/dev/null

			if ! ip6tables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
				ip6tables -I INPUT 1 -p tcp --dport $port -j ACCEPT || return 1
			fi

			if ! ip6tables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null; then
				ip6tables -I INPUT 1 -p udp --dport $port -j ACCEPT || return 1
			fi
		done
	fi

	save_iptables_rules || return 1
}


close_port() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system close_port "$@"; return $?
	fi
	local ports=($@)  # 将传入的参数转换为数组
	if [ ${#ports[@]} -eq 0 ]; then
		echo "请提供至少一个端口号"
		return 1
	fi

	install iptables || return 1
	local ipv6_ready=false
	ip6tables_available && ipv6_ready=true

	for port in "${ports[@]}"; do
		# 删除已存在的打开规则
		iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
		iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null

		# 添加关闭规则
		if ! iptables -C INPUT -p tcp --dport $port -j DROP 2>/dev/null; then
			iptables -I INPUT 1 -p tcp --dport $port -j DROP || return 1
		fi

		if ! iptables -C INPUT -p udp --dport $port -j DROP 2>/dev/null; then
			iptables -I INPUT 1 -p udp --dport $port -j DROP || return 1
			echo "已关闭端口 $port"
		fi
	done

	if [ "$ipv6_ready" = true ]; then
		for port in "${ports[@]}"; do
			ip6tables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
			ip6tables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null

			if ! ip6tables -C INPUT -p tcp --dport $port -j DROP 2>/dev/null; then
				ip6tables -I INPUT 1 -p tcp --dport $port -j DROP || return 1
			fi

			if ! ip6tables -C INPUT -p udp --dport $port -j DROP 2>/dev/null; then
				ip6tables -I INPUT 1 -p udp --dport $port -j DROP || return 1
			fi
		done

		# 删除已存在的规则（如果有）
		ip6tables -D INPUT -i lo -j ACCEPT 2>/dev/null
		ip6tables -D FORWARD -i lo -j ACCEPT 2>/dev/null

		# 插入新规则到第一条
		ip6tables -I INPUT 1 -i lo -j ACCEPT || return 1
		ip6tables -I FORWARD 1 -i lo -j ACCEPT || return 1
	fi

	# 删除已存在的规则（如果有）
	iptables -D INPUT -i lo -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i lo -j ACCEPT 2>/dev/null

	# 插入新规则到第一条
	iptables -I INPUT 1 -i lo -j ACCEPT || return 1
	iptables -I FORWARD 1 -i lo -j ACCEPT || return 1

	save_iptables_rules || return 1
}


allow_ip() {
	local ips=($@)  # 将传入的参数转换为数组
	if [ ${#ips[@]} -eq 0 ]; then
		echo "请提供至少一个IP地址或IP段"
		return 1
	fi

	install iptables

	for ip in "${ips[@]}"; do
		# 删除已存在的阻止规则
		iptables -D INPUT -s $ip -j DROP 2>/dev/null

		# 添加允许规则
		if ! iptables -C INPUT -s $ip -j ACCEPT 2>/dev/null; then
			iptables -I INPUT 1 -s $ip -j ACCEPT
			echo "已放行IP $ip"
		fi
	done

	save_iptables_rules
}

block_ip() {
	local ips=($@)  # 将传入的参数转换为数组
	if [ ${#ips[@]} -eq 0 ]; then
		echo "请提供至少一个IP地址或IP段"
		return 1
	fi

	install iptables

	for ip in "${ips[@]}"; do
		# 删除已存在的允许规则
		iptables -D INPUT -s $ip -j ACCEPT 2>/dev/null

		# 添加阻止规则
		if ! iptables -C INPUT -s $ip -j DROP 2>/dev/null; then
			iptables -I INPUT 1 -s $ip -j DROP
			echo "已阻止IP $ip"
		fi
	done

	save_iptables_rules
}







enable_ddos_defense() {
	# 开启防御 DDoS
	iptables -A DOCKER-USER -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT
	iptables -A DOCKER-USER -p tcp --syn -j DROP
	iptables -A DOCKER-USER -p udp -m limit --limit 3000/s -j ACCEPT
	iptables -A DOCKER-USER -p udp -j DROP
	iptables -A INPUT -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT
	iptables -A INPUT -p tcp --syn -j DROP
	iptables -A INPUT -p udp -m limit --limit 3000/s -j ACCEPT
	iptables -A INPUT -p udp -j DROP

}

# 关闭DDoS防御
disable_ddos_defense() {
	# 关闭防御 DDoS
	iptables -D DOCKER-USER -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT 2>/dev/null
	iptables -D DOCKER-USER -p tcp --syn -j DROP 2>/dev/null
	iptables -D DOCKER-USER -p udp -m limit --limit 3000/s -j ACCEPT 2>/dev/null
	iptables -D DOCKER-USER -p udp -j DROP 2>/dev/null
	iptables -D INPUT -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT 2>/dev/null
	iptables -D INPUT -p tcp --syn -j DROP 2>/dev/null
	iptables -D INPUT -p udp -m limit --limit 3000/s -j ACCEPT 2>/dev/null
	iptables -D INPUT -p udp -j DROP 2>/dev/null

}





# 管理国家IP规则的函数
manage_country_rules() {
	local action="$1"
	shift  # 去掉第一个参数，剩下的全是国家代码

	install ipset

	for country_code in "$@"; do
		local ipset_name="${country_code,,}_block"
		local download_url="http://www.ipdeny.com/ipblocks/data/countries/${country_code,,}.zone"

		case "$action" in
			block)
				if ! ipset list "$ipset_name" &> /dev/null; then
					ipset create "$ipset_name" hash:net
				fi

				if ! wget -q "$download_url" -O "${country_code,,}.zone"; then
					echo "错误：下载 $country_code 的 IP 区域文件失败"
					continue
				fi

				while IFS= read -r ip; do
					ipset add "$ipset_name" "$ip" 2>/dev/null
				done < "${country_code,,}.zone"

				iptables -I INPUT -m set --match-set "$ipset_name" src -j DROP

				echo "已成功阻止 $country_code 的 IP 地址"
				rm "${country_code,,}.zone"
				;;

			allow)
				if ! ipset list "$ipset_name" &> /dev/null; then
					ipset create "$ipset_name" hash:net
				fi

				if ! wget -q "$download_url" -O "${country_code,,}.zone"; then
					echo "错误：下载 $country_code 的 IP 区域文件失败"
					continue
				fi

				ipset flush "$ipset_name"
				while IFS= read -r ip; do
					ipset add "$ipset_name" "$ip" 2>/dev/null
				done < "${country_code,,}.zone"


				iptables -P INPUT DROP
				iptables -A INPUT -m set --match-set "$ipset_name" src -j ACCEPT

				echo "已成功允许 $country_code 的 IP 地址"
				rm "${country_code,,}.zone"
				;;

			unblock)
				iptables -D INPUT -m set --match-set "$ipset_name" src -j DROP 2>/dev/null

				if ipset list "$ipset_name" &> /dev/null; then
					ipset destroy "$ipset_name"
				fi

				echo "已成功解除 $country_code 的 IP 地址限制"
				;;

			*)
				echo "用法: manage_country_rules {block|allow|unblock} <country_code...>"
				;;
		esac
	done
}










get_ssh_ports() {
	local ports="" config
	if command -v sshd >/dev/null 2>&1; then
		ports="$(sshd -T 2>/dev/null | awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}')"
	fi
	if [ -z "$ports" ]; then
		ports="$({
			for config in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
				[ -f "$config" ] || continue
				awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}' "$config"
			done
		} 2>/dev/null)"
	fi
	[ -n "$ports" ] || ports=22
	printf '%s\n' "$ports" | awk '/^[0-9]+$/ && $1 >= 1 && $1 <= 65535' | sort -nu
}

iptables_panel() {
  root_use
  install iptables
  save_iptables_rules
  while true; do
		  clear
		  echo "高级防火墙管理"
		  echo "------------------------"
		  iptables -L INPUT -v
		  echo ""
		  echo "防火墙管理"
		  echo "------------------------"
		  echo "1.  开放指定端口                 2.  关闭指定端口"
		  echo "3.  开放所有端口                 4.  关闭所有端口"
		  echo "------------------------"
		  echo "5.  IP白名单                  	 6.  IP黑名单"
		  echo "7.  清除指定IP"
		  echo "------------------------"
		  echo "11. 允许PING                  	 12. 禁止PING"
		  echo "------------------------"
		  echo "13. 启动DDOS防御                 14. 关闭DDOS防御"
		  echo "------------------------"
		  echo "15. 阻止指定国家IP               16. 仅允许指定国家IP"
		  echo "17. 解除指定国家IP限制"
		  echo "------------------------"
		  echo "0. 返回上一级选单"
		  echo "------------------------"
		  read -e -p "请输入你的选择: " sub_choice
		  case $sub_choice in
			  1)
				  read -e -p "请输入开放的端口号: " o_port
				  open_port $o_port
				  ;;
			  2)
				  read -e -p "请输入关闭的端口号: " c_port
				  close_port $c_port
				  ;;
			  3)
				  # 开放所有端口
				  local ssh_ports=($(get_ssh_ports))
				  local ssh_port
				  [ ${#ssh_ports[@]} -gt 0 ] || ssh_ports=(22)
				  iptables -F
				  iptables -X
				  iptables -P INPUT ACCEPT
				  iptables -P FORWARD ACCEPT
				  iptables -P OUTPUT ACCEPT
				  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
				  iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
				  iptables -A INPUT -i lo -j ACCEPT
				  iptables -A FORWARD -i lo -j ACCEPT
				  for ssh_port in "${ssh_ports[@]}"; do
					  iptables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
				  done
				  iptables-save > /etc/iptables/rules.v4
				  if ip6tables_available; then
					  ip6tables -F
					  ip6tables -X
					  ip6tables -P INPUT ACCEPT
					  ip6tables -P FORWARD ACCEPT
					  ip6tables -P OUTPUT ACCEPT
					  ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
					  ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
					  ip6tables -A INPUT -i lo -j ACCEPT
					  ip6tables -A FORWARD -i lo -j ACCEPT
					  for ssh_port in "${ssh_ports[@]}"; do
						  ip6tables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
					  done
					  ip6tables-save > /etc/iptables/rules.v6
				  fi
				  save_iptables_rules
				  ;;
			  4)
				  # 关闭所有端口
				  local ssh_ports=($(get_ssh_ports))
				  local ssh_port
				  [ ${#ssh_ports[@]} -gt 0 ] || ssh_ports=(22)
				  iptables -F
				  iptables -X
				  iptables -P INPUT DROP
				  iptables -P FORWARD DROP
				  iptables -P OUTPUT ACCEPT
				  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
				  iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
				  iptables -A INPUT -i lo -j ACCEPT
				  iptables -A FORWARD -i lo -j ACCEPT
				  for ssh_port in "${ssh_ports[@]}"; do
					  iptables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
				  done
				  iptables-save > /etc/iptables/rules.v4
				  if ip6tables_available; then
					  ip6tables -F
					  ip6tables -X
					  ip6tables -P INPUT DROP
					  ip6tables -P FORWARD DROP
					  ip6tables -P OUTPUT ACCEPT
					  ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
					  ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
					  ip6tables -A INPUT -i lo -j ACCEPT
					  ip6tables -A FORWARD -i lo -j ACCEPT
					  for ssh_port in "${ssh_ports[@]}"; do
						  ip6tables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
					  done
					  ip6tables-save > /etc/iptables/rules.v6
				  fi
				  save_iptables_rules
				  ;;

			  5)
				  # IP 白名单
				  read -e -p "请输入放行的IP或IP段: " o_ip
				  allow_ip $o_ip
				  ;;
			  6)
				  # IP 黑名单
				  read -e -p "请输入封锁的IP或IP段: " c_ip
				  block_ip $c_ip
				  ;;
			  7)
				  # 清除指定 IP
				  read -e -p "请输入清除的IP: " d_ip
				  iptables -D INPUT -s $d_ip -j ACCEPT 2>/dev/null
				  iptables -D INPUT -s $d_ip -j DROP 2>/dev/null
				  iptables-save > /etc/iptables/rules.v4
				  ;;
			  11)
				  # 允许 PING
				  iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
				  iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
				  iptables-save > /etc/iptables/rules.v4
				  ;;
			  12)
				  # 禁用 PING
				  iptables -D INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null
				  iptables -D OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT 2>/dev/null
				  iptables-save > /etc/iptables/rules.v4
				  ;;
			  13)
				  enable_ddos_defense
				  ;;
			  14)
				  disable_ddos_defense
				  ;;

			  15)
				  read -e -p "请输入阻止的国家代码（多个国家代码可用空格隔开如 CN US JP）: " country_code
				  manage_country_rules block $country_code
				  ;;
			  16)
				  read -e -p "请输入允许的国家代码（多个国家代码可用空格隔开如 CN US JP）: " country_code
				  manage_country_rules allow $country_code
				  ;;

			  17)
				  read -e -p "请输入清除的国家代码（多个国家代码可用空格隔开如 CN US JP）: " country_code
				  manage_country_rules unblock $country_code
				  ;;

			  *)
				  break  # 跳出循环，退出菜单
				  ;;
		  esac
  done

}






add_swap() {
	local new_swap=$1  # 获取传入的参数

	# 获取当前系统中所有的 swap 分区
	local swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')

	# 遍历并删除所有的 swap 分区
	for partition in $swap_partitions; do
		swapoff "$partition"
		wipefs -a "$partition"
		mkswap -f "$partition"
	done

	# 确保 /swapfile 不再被使用
	swapoff /swapfile

	# 删除旧的 /swapfile
	rm -f /swapfile

	# 创建新的 swap 分区
	fallocate -l ${new_swap}M /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile

	sed -i '/\/swapfile/d' /etc/fstab
	echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

	if [ -f /etc/alpine-release ]; then
		echo "nohup swapon /swapfile" > /etc/local.d/swap.start
		chmod +x /etc/local.d/swap.start
		rc-update add local
	fi

	echo -e "虚拟内存大小已调整为${gl_huang}${new_swap}${gl_bai}M"
}




check_swap() {

local swap_total=$(free -m | awk 'NR==3{print $2}')

# 判断是否需要创建虚拟内存
[ "$swap_total" -gt 0 ] || add_swap 1024


}









prefer_ipv4() {
grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null \
	|| echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
echo "已切换为 IPv4 优先"
}


check_docker_app_ip() {
echo "------------------------"
echo "访问地址:"
ip_address



if [ -n "$ipv4_address" ]; then
	echo "http://$ipv4_address:${docker_port}"
fi

if [ -n "$ipv6_address" ]; then
	echo "http://[$ipv6_address]:${docker_port}"
fi

}


get_container_ipv4_addresses() {
	local container_name_or_id=$1
	local container_ips

	container_ips=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{if .IPAddress}}{{println .IPAddress}}{{end}}{{end}}' "$container_name_or_id" 2>/dev/null) || return 1
	printf '%s\n' "$container_ips" | awk 'NF && !seen[$0]++'
}

ensure_docker_user_rule() {
	if ! iptables -C DOCKER-USER "$@" &>/dev/null; then
		iptables -I DOCKER-USER "$@"
	fi
}

remove_docker_user_rule() {
	if iptables -C DOCKER-USER "$@" &>/dev/null; then
		iptables -D DOCKER-USER "$@"
	fi
}

block_container_port() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system block_container_port "$@"; return $?
	fi
	local container_name_or_id=$1
	local allowed_ip=$2
	local container_ips
	local container_ip

	# 获取容器在所有 Docker 网络中的 IPv4 地址，逐个应用规则。
	container_ips=$(get_container_ipv4_addresses "$container_name_or_id")
	if [ -z "$container_ips" ]; then
		echo "错误：无法获取容器 ${container_name_or_id} 的 IPv4 地址。" >&2
		return 1
	fi

	install iptables || return 1

	while IFS= read -r container_ip; do
		ensure_docker_user_rule -p tcp -d "$container_ip" -j DROP || return 1
		ensure_docker_user_rule -p tcp -s "$allowed_ip" -d "$container_ip" -j ACCEPT || return 1
		ensure_docker_user_rule -p tcp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT || return 1
		ensure_docker_user_rule -p udp -d "$container_ip" -j DROP || return 1
		ensure_docker_user_rule -p udp -s "$allowed_ip" -d "$container_ip" -j ACCEPT || return 1
		ensure_docker_user_rule -p udp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT || return 1
		ensure_docker_user_rule -m state --state ESTABLISHED,RELATED -d "$container_ip" -j ACCEPT || return 1
	done <<< "$container_ips"

	echo "已阻止IP+端口访问该服务"
	save_iptables_rules || return 1
}




clear_container_rules() {
	if [ "${KJ_APP_CONCURRENCY:-}" = "1" ] && ! kpanel_app_lock_held system; then
		kpanel_app_with_lock system clear_container_rules "$@"; return $?
	fi
	local container_name_or_id=$1
	local allowed_ip=$2
	local container_ips
	local container_ip

	# 获取容器在所有 Docker 网络中的 IPv4 地址，逐个清除规则。
	container_ips=$(get_container_ipv4_addresses "$container_name_or_id")
	if [ -z "$container_ips" ]; then
		echo "错误：无法获取容器 ${container_name_or_id} 的 IPv4 地址。" >&2
		return 1
	fi

	install iptables || return 1

	while IFS= read -r container_ip; do
		remove_docker_user_rule -p tcp -d "$container_ip" -j DROP || return 1
		remove_docker_user_rule -p tcp -s "$allowed_ip" -d "$container_ip" -j ACCEPT || return 1
		remove_docker_user_rule -p tcp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT || return 1
		remove_docker_user_rule -p udp -d "$container_ip" -j DROP || return 1
		remove_docker_user_rule -p udp -s "$allowed_ip" -d "$container_ip" -j ACCEPT || return 1
		remove_docker_user_rule -p udp -s 127.0.0.0/8 -d "$container_ip" -j ACCEPT || return 1
		remove_docker_user_rule -m state --state ESTABLISHED,RELATED -d "$container_ip" -j ACCEPT || return 1
	done <<< "$container_ips"

	echo "已允许IP+端口访问该服务"
	save_iptables_rules || return 1
}

tmux_run() {
	# Check if the session already exists
	tmux has-session -t $SESSION_NAME 2>/dev/null
	# $? is a special variable that holds the exit status of the last executed command
	if [ $? != 0 ]; then
	  # Session doesn't exist, create a new one
	  tmux new -s $SESSION_NAME
	else
	  # Session exists, attach to it
	  tmux attach-session -t $SESSION_NAME
	fi
}


tmux_run_d() {

local base_name="tmuxd"
local tmuxd_ID=1

# 检查会话是否存在的函数
session_exists() {
  tmux has-session -t $1 2>/dev/null
}

# 循环直到找到一个不存在的会话名称
while session_exists "$base_name-$tmuxd_ID"; do
  local tmuxd_ID=$((tmuxd_ID + 1))
done

# 创建新的 tmux 会话
tmux new -d -s "$base_name-$tmuxd_ID" "$tmuxd"


}



f2b_status() {
	 fail2ban-client reload
	 sleep 3
	 fail2ban-client status
}

f2b_status_xxx() {
	fail2ban-client status $xxx
}

check_f2b_status() {
	if command -v fail2ban-client >/dev/null 2>&1; then
		check_f2b_status="${gl_lv}已安装${gl_bai}"
	else
		check_f2b_status="${gl_hui}未安装${gl_bai}"
	fi
}

f2b_install_sshd() {

	docker rm -f fail2ban >/dev/null 2>&1
	install fail2ban || return 1

	if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
		install rsyslog || return 1
		/bin/systemctl enable --now rsyslog.service || return 1
		cd /etc/fail2ban/jail.d/
		curl --fail --silent --show-error --location \
			--output centos-ssh.conf \
			"https://raw.githubusercontent.com/howi3c/sh/main/fail2ban-ssh.conf" || return 1
		if [ ! -e /var/log/secure ]; then
			touch /var/log/secure || return 1
			chmod 0600 /var/log/secure || return 1
			command -v restorecon >/dev/null 2>&1 && restorecon /var/log/secure || true
		fi
	fi

	if command -v apt &>/dev/null; then
		install rsyslog || return 1
		/bin/systemctl enable --now rsyslog.service || return 1
	fi

	if command -v apk >/dev/null 2>&1; then
		rc-update add fail2ban default || return 1
		rc-service fail2ban start || return 1
	else
		/bin/systemctl enable --now fail2ban.service || return 1
	fi
	fail2ban-client -t >/dev/null 2>&1 || return 1
	if ! fail2ban-client reload >/dev/null 2>&1; then
		if command -v apk >/dev/null 2>&1; then
			rc-service fail2ban restart || return 1
		else
			/bin/systemctl restart fail2ban.service || return 1
		fi
	fi

}

kpanel_f2b_jail_name() {
	if grep -qi 'Alpine' /etc/issue 2>/dev/null &&
		{ [ -f /etc/fail2ban/filter.d/alpine-sshd.conf ] ||
		  [ -f /etc/fail2ban/jail.d/alpine-ssh.conf ] ||
		  [ -f /etc/fail2ban/jail.d/alpine-sshd.local ]; }; then
		printf '%s\n' "alpine-sshd"
	else
		printf '%s\n' "sshd"
	fi
}

kpanel_f2b_enabled() {
	local jail_name
	command -v fail2ban-client >/dev/null 2>&1 || return 1
	fail2ban-client ping >/dev/null 2>&1 || return 1
	jail_name=$(kpanel_f2b_jail_name)
	fail2ban-client status "$jail_name" >/dev/null 2>&1
}

kpanel_f2b_autostart() {
	if command -v apk >/dev/null 2>&1; then
		rc-update show default 2>/dev/null | grep -Eq '(^|[[:space:]])fail2ban([[:space:]]|$)'
	else
		/bin/systemctl is-enabled fail2ban.service >/dev/null 2>&1
	fi
}

kpanel_f2b_status() {
	local installed=false running=false enabled=false autostart=false
	local jail_name banned=0 jail_status=""
	jail_name=$(kpanel_f2b_jail_name)
	if command -v fail2ban-client >/dev/null 2>&1; then
		installed=true
		if fail2ban-client ping >/dev/null 2>&1; then
			running=true
			if jail_status=$(fail2ban-client status "$jail_name" 2>/dev/null); then
				enabled=true
				banned=$(printf '%s\n' "$jail_status" |
					awk -F: '/Currently banned/{gsub(/[[:space:]]/, "", $2); print $2; exit}')
				case "$banned" in
					''|*[!0-9]*) banned=0 ;;
				esac
			fi
		fi
		kpanel_f2b_autostart && autostart=true
	fi
	printf 'KPANEL_F2B_STATUS {"installed":%s,"running":%s,"enabled":%s,"autostart":%s,"jail":"%s","banned":%s}\n' \
		"$installed" "$running" "$enabled" "$autostart" "$jail_name" "$banned"
}

kpanel_f2b_dispatch() {
	local command="${1:-status}" changed=false
	printf '%s\n' "KPANEL_F2B_PROTOCOL 1"
	if [ "$command" = "manager" ]; then
		shift
		kpanel_f2b_manager_dispatch "$@"
		return $?
	fi
	case "$command" in
		status)
			kpanel_f2b_status
			;;
		enable)
			root_use
			if kpanel_f2b_enabled && kpanel_f2b_autostart; then
				printf '%s\n' "KPANEL_F2B_RESULT unchanged"
				kpanel_f2b_status
				return 0
			fi
			f2b_install_sshd || return 1
			kpanel_f2b_enabled || {
				echo "Fail2Ban SSH jail 未能正常启动" >&2
				return 1
			}
			changed=true
			printf 'KPANEL_F2B_RESULT %s\n' "$changed"
			kpanel_f2b_status
			;;
		disable)
			root_use
			if ! command -v fail2ban-client >/dev/null 2>&1; then
				printf '%s\n' "KPANEL_F2B_RESULT unchanged"
				kpanel_f2b_status
				return 0
			fi
			if command -v apk >/dev/null 2>&1; then
				service fail2ban stop >/dev/null 2>&1 || true
				rc-update del fail2ban default >/dev/null 2>&1 || true
			else
				/bin/systemctl disable --now fail2ban.service >/dev/null 2>&1 || return 1
			fi
			if fail2ban-client ping >/dev/null 2>&1; then
				echo "Fail2Ban 服务仍在运行" >&2
				return 1
			fi
			changed=true
			printf 'KPANEL_F2B_RESULT %s\n' "$changed"
			kpanel_f2b_status
			;;
		*)
			echo "用法: k f2b [status|enable|disable]" >&2
			return 2
			;;
	esac
}

KPANEL_F2B_MANAGER_PROTOCOL_VERSION="1"

kpanel_f2b_manager_config_file() {
	printf '%s/etc/fail2ban/jail.d/99-kejilion-sshd.local\n' "${KPANEL_F2B_TEST_ROOT:-}"
}

kpanel_f2b_manager_log_file() {
	printf '%s/var/log/fail2ban.log\n' "${KPANEL_F2B_TEST_ROOT:-}"
}

kpanel_f2b_manager_emit() {
	local status="$1" version="${2:-}" backup="${3:-}"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || version="$(kpanel_system_resource_zero_version)"
	printf 'KPANEL_F2B_MANAGER_STATUS=%s\n' "$status"
	printf 'KPANEL_F2B_MANAGER_VERSION=%s\n' "$version"
	[ -z "$backup" ] || printf 'KPANEL_F2B_MANAGER_BACKUP=%s\n' "$backup"
}

kpanel_f2b_manager_error() {
	printf '错误: %s\n' "$1" >&2
}

kpanel_f2b_manager_valid_address() {
	local value="$1"
	[ -n "$value" ] && [ "${#value}" -le 80 ] &&
		[[ "$value" != *$'\n'* ]] && [[ "$value" != *$'\r'* ]] &&
		command -v python3 >/dev/null 2>&1 &&
		python3 -c 'import ipaddress,sys; value=sys.argv[1]; ipaddress.ip_network(value, strict=False) if "/" in value else ipaddress.ip_address(value)' "$value" >/dev/null 2>&1
}

kpanel_f2b_manager_valid_ip() {
	local value="$1"
	[ -n "$value" ] && [ "${#value}" -le 80 ] && [[ "$value" != */* ]] &&
		command -v python3 >/dev/null 2>&1 &&
		python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$value" >/dev/null 2>&1
}

kpanel_f2b_manager_profile_values() {
	case "$1" in
		mild) printf '%s\n' "600 600 8" ;;
		standard) printf '%s\n' "3600 600 5" ;;
		strict) printf '%s\n' "43200 600 3" ;;
		*) return 1 ;;
	esac
}

kpanel_f2b_manager_profile() {
	case "$1:$2:$3" in
		600:600:8) printf '%s\n' "mild" ;;
		3600:600:5) printf '%s\n' "standard" ;;
		43200:600:3) printf '%s\n' "strict" ;;
		*) printf '%s\n' "custom" ;;
	esac
}

kpanel_f2b_manager_read_number() {
	local jail="$1" key="$2" fallback="$3" value
	value="$(fail2ban-client get "$jail" "$key" 2>/dev/null | tail -n 1 | tr -d '[:space:]')" || true
	[[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -le 315360000 ] || value="$fallback"
	printf '%s\n' "$value"
}

kpanel_f2b_manager_collect() {
	local status_file token raw line hex log_file
	F2B_MANAGER_INSTALLED=false
	F2B_MANAGER_RUNNING=false
	F2B_MANAGER_ENABLED=false
	F2B_MANAGER_AUTOSTART=false
	F2B_MANAGER_JAIL="$(kpanel_f2b_jail_name)"
	F2B_MANAGER_CURRENT_FAILED=0
	F2B_MANAGER_TOTAL_FAILED=0
	F2B_MANAGER_CURRENT_BANNED=0
	F2B_MANAGER_TOTAL_BANNED=0
	F2B_MANAGER_BANTIME=3600
	F2B_MANAGER_FINDTIME=600
	F2B_MANAGER_MAXRETRY=5
	F2B_MANAGER_PROFILE=standard
	F2B_MANAGER_BANS=()
	F2B_MANAGER_TRUSTED=()
	F2B_MANAGER_EVENTS=()
	F2B_MANAGER_BANS_TRUNCATED=false

	command -v fail2ban-client >/dev/null 2>&1 || return 0
	F2B_MANAGER_INSTALLED=true
	fail2ban-client ping >/dev/null 2>&1 || {
		kpanel_f2b_autostart && F2B_MANAGER_AUTOSTART=true
		return 0
	}
	F2B_MANAGER_RUNNING=true
	kpanel_f2b_autostart && F2B_MANAGER_AUTOSTART=true
	status_file="$(mktemp /tmp/kejilion-f2b-status.XXXXXX)" || return 1
	if ! fail2ban-client status "$F2B_MANAGER_JAIL" > "$status_file" 2>/dev/null; then
		rm -f -- "$status_file"
		return 0
	fi
	if ! kpanel_system_resource_file_within_bounds "$status_file" 4194304 4096; then
		rm -f -- "$status_file"
		return 1
	fi
	F2B_MANAGER_ENABLED=true
	F2B_MANAGER_CURRENT_FAILED="$(awk -F: '/Currently failed/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$status_file")"
	F2B_MANAGER_TOTAL_FAILED="$(awk -F: '/Total failed/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$status_file")"
	F2B_MANAGER_CURRENT_BANNED="$(awk -F: '/Currently banned/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$status_file")"
	F2B_MANAGER_TOTAL_BANNED="$(awk -F: '/Total banned/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$status_file")"
	for token in F2B_MANAGER_CURRENT_FAILED F2B_MANAGER_TOTAL_FAILED F2B_MANAGER_CURRENT_BANNED F2B_MANAGER_TOTAL_BANNED; do
		raw="${!token}"
		[[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -le 1000000000 ] || printf -v "$token" '%s' 0
	done
	raw="$(awk -F: '/Banned IP list/{sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "$status_file")"
	rm -f -- "$status_file"
	for token in $raw; do
		if kpanel_f2b_manager_valid_ip "$token"; then
			if [ "${#F2B_MANAGER_BANS[@]}" -lt 256 ]; then
				F2B_MANAGER_BANS+=("$token")
			else
				F2B_MANAGER_BANS_TRUNCATED=true
				break
			fi
		fi
	done

	F2B_MANAGER_BANTIME="$(kpanel_f2b_manager_read_number "$F2B_MANAGER_JAIL" bantime 3600)"
	F2B_MANAGER_FINDTIME="$(kpanel_f2b_manager_read_number "$F2B_MANAGER_JAIL" findtime 600)"
	F2B_MANAGER_MAXRETRY="$(kpanel_f2b_manager_read_number "$F2B_MANAGER_JAIL" maxretry 5)"
	[ "$F2B_MANAGER_MAXRETRY" -ge 1 ] && [ "$F2B_MANAGER_MAXRETRY" -le 1000 ] || F2B_MANAGER_MAXRETRY=5
	F2B_MANAGER_PROFILE="$(kpanel_f2b_manager_profile "$F2B_MANAGER_BANTIME" "$F2B_MANAGER_FINDTIME" "$F2B_MANAGER_MAXRETRY")"

	raw="$(fail2ban-client get "$F2B_MANAGER_JAIL" ignoreip 2>/dev/null || true)"
	for token in $raw; do
		token="${token#[}"
		token="${token%]}"
		token="${token%,}"
		token="${token#\'}"
		token="${token%\'}"
		if kpanel_f2b_manager_valid_address "$token"; then
			[ "${#F2B_MANAGER_TRUSTED[@]}" -ge 64 ] || F2B_MANAGER_TRUSTED+=("$token")
		fi
	done

	log_file="$(kpanel_f2b_manager_log_file)"
	if [ -f "$log_file" ] && [ ! -L "$log_file" ]; then
		while IFS= read -r line; do
			[ "${#line}" -le 2048 ] || line="${line:0:2048}"
			hex="$(printf '%s' "$line" | od -An -v -tx1 | tr -d ' \n')" || continue
			[ -n "$hex" ] && F2B_MANAGER_EVENTS+=("$hex")
		done < <(tail -n 200 -- "$log_file" 2>/dev/null | grep -E '\[(sshd|alpine-sshd)\].*(Found|Ban|Unban)[[:space:]]' | tail -n 20)
	fi
}

kpanel_f2b_manager_set_version() {
	local canonical config_file config_hash=absent value version
	kpanel_f2b_manager_collect || return 1
	canonical="$(mktemp /tmp/kejilion-f2b-version.XXXXXX)" || return 1
	config_file="$(kpanel_f2b_manager_config_file)"
	if [ -f "$config_file" ] && [ ! -L "$config_file" ]; then
		config_hash="$(sha256sum -- "$config_file" 2>/dev/null | awk '{print $1}')"
	fi
	{
		printf 'installed=%s\nrunning=%s\nenabled=%s\nautostart=%s\njail=%s\n' \
			"$F2B_MANAGER_INSTALLED" "$F2B_MANAGER_RUNNING" "$F2B_MANAGER_ENABLED" "$F2B_MANAGER_AUTOSTART" "$F2B_MANAGER_JAIL"
		printf 'bantime=%s\nfindtime=%s\nmaxretry=%s\nconfig=%s\n' \
			"$F2B_MANAGER_BANTIME" "$F2B_MANAGER_FINDTIME" "$F2B_MANAGER_MAXRETRY" "$config_hash"
		printf '%s\n' "${F2B_MANAGER_TRUSTED[@]}" | sed '/^$/d' | sort -u | sed 's/^/trusted=/'
	} > "$canonical"
	version="$(sha256sum -- "$canonical" 2>/dev/null | awk '{print $1}')"
	rm -f -- "$canonical"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || return 1
	F2B_MANAGER_VERSION="$version"
}

kpanel_f2b_manager_current_version() {
	kpanel_f2b_manager_set_version || return 1
	printf '%s\n' "$F2B_MANAGER_VERSION"
}

kpanel_f2b_manager_snapshot() {
	local status="${1:-ok}" backup="${2:-}" version value
	kpanel_f2b_manager_set_version || {
		kpanel_f2b_manager_emit failed ""
		return 1
	}
	version="$F2B_MANAGER_VERSION"
	kpanel_f2b_manager_emit "$status" "$version" "$backup"
	printf 'KPANEL_F2B_MANAGER_INSTALLED=%s\n' "$F2B_MANAGER_INSTALLED"
	printf 'KPANEL_F2B_MANAGER_RUNNING=%s\n' "$F2B_MANAGER_RUNNING"
	printf 'KPANEL_F2B_MANAGER_ENABLED=%s\n' "$F2B_MANAGER_ENABLED"
	printf 'KPANEL_F2B_MANAGER_AUTOSTART=%s\n' "$F2B_MANAGER_AUTOSTART"
	printf 'KPANEL_F2B_MANAGER_JAIL=%s\n' "$F2B_MANAGER_JAIL"
	printf 'KPANEL_F2B_MANAGER_CURRENT_FAILED=%s\n' "$F2B_MANAGER_CURRENT_FAILED"
	printf 'KPANEL_F2B_MANAGER_TOTAL_FAILED=%s\n' "$F2B_MANAGER_TOTAL_FAILED"
	printf 'KPANEL_F2B_MANAGER_CURRENT_BANNED=%s\n' "$F2B_MANAGER_CURRENT_BANNED"
	printf 'KPANEL_F2B_MANAGER_TOTAL_BANNED=%s\n' "$F2B_MANAGER_TOTAL_BANNED"
	printf 'KPANEL_F2B_MANAGER_BANTIME=%s\n' "$F2B_MANAGER_BANTIME"
	printf 'KPANEL_F2B_MANAGER_FINDTIME=%s\n' "$F2B_MANAGER_FINDTIME"
	printf 'KPANEL_F2B_MANAGER_MAXRETRY=%s\n' "$F2B_MANAGER_MAXRETRY"
	printf 'KPANEL_F2B_MANAGER_PROFILE=%s\n' "$F2B_MANAGER_PROFILE"
	printf 'KPANEL_F2B_MANAGER_BANS_TRUNCATED=%s\n' "$F2B_MANAGER_BANS_TRUNCATED"
	for value in "${F2B_MANAGER_BANS[@]}"; do printf 'KPANEL_F2B_MANAGER_BAN=%s\n' "$value"; done
	for value in "${F2B_MANAGER_TRUSTED[@]}"; do printf 'KPANEL_F2B_MANAGER_TRUSTED=%s\n' "$value"; done
	for value in "${F2B_MANAGER_EVENTS[@]}"; do printf 'KPANEL_F2B_MANAGER_EVENT_HEX=%s\n' "$value"; done
}

kpanel_f2b_manager_set_file_identity() {
	local path="$1"
	if [ -n "${KPANEL_F2B_TEST_ROOT:-}" ]; then
		chmod 600 -- "$path"
	else
		chown 0:0 -- "$path" && chmod 600 -- "$path"
	fi
}

kpanel_f2b_manager_write_config() {
	local jail="$1" bantime="$2" findtime="$3" maxretry="$4" config_file config_dir temporary value
	shift 4
	config_file="$(kpanel_f2b_manager_config_file)"
	config_dir="$(dirname -- "$config_file")"
	[ -d "$config_dir" ] && [ ! -L "$config_dir" ] && [ ! -L "$config_file" ] || return 1
	temporary="$(mktemp "$config_dir/.99-kejilion-sshd.local.XXXXXX")" || return 1
	{
		printf '[%s]\n' "$jail"
		printf '%s\n' '# Managed by kejilion.sh for SSH defense'
		printf 'enabled = true\nbantime = %s\nfindtime = %s\nmaxretry = %s\n' "$bantime" "$findtime" "$maxretry"
		if [ "$#" -gt 0 ]; then
			printf 'ignoreip ='
			for value in "$@"; do printf ' %s' "$value"; done
			printf '\n'
		fi
	} > "$temporary" || { rm -f -- "$temporary"; return 1; }
	kpanel_f2b_manager_set_file_identity "$temporary" && mv -f -- "$temporary" "$config_file"
}

kpanel_f2b_manager_restore_config() {
	local snapshot="$1" config_file
	config_file="$(kpanel_f2b_manager_config_file)"
	if [ "$(cat "$snapshot/config.existed" 2>/dev/null)" = true ]; then
		cp -a -- "$snapshot/config" "$config_file" || return 1
	else
		rm -f -- "$config_file" || return 1
	fi
	fail2ban-client -t >/dev/null 2>&1 && fail2ban-client reload >/dev/null 2>&1
}

kpanel_f2b_manager_config_failure() {
	local snapshot="$1" message="$2" version recovery=""
	kpanel_f2b_manager_error "$message"
	if kpanel_f2b_manager_restore_config "$snapshot"; then
		version="$(kpanel_f2b_manager_current_version 2>/dev/null || true)"
		rm -rf -- "$snapshot"
		kpanel_f2b_manager_emit failed "$version"
	else
		recovery="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot" ssh-defense 2>/dev/null || true)"
		version="$(kpanel_f2b_manager_current_version 2>/dev/null || true)"
		kpanel_f2b_manager_emit rollback-failed "$version" "$recovery"
	fi
	return 1
}

kpanel_f2b_manager_config_action() {
	local action="$1" expected="$2" value="$3" current_version profile bantime findtime maxretry snapshot config_file
	local trusted=() item changed=false
	kpanel_f2b_manager_set_version || { kpanel_f2b_manager_emit failed ""; return 1; }
	current_version="$F2B_MANAGER_VERSION"
	if [ "$current_version" != "$expected" ]; then
		kpanel_f2b_manager_emit conflict "$current_version"
		return 2
	fi
	[ "$F2B_MANAGER_ENABLED" = true ] || { kpanel_f2b_manager_error "SSH jail 未运行"; kpanel_f2b_manager_emit failed "$current_version"; return 1; }
	bantime="$F2B_MANAGER_BANTIME"; findtime="$F2B_MANAGER_FINDTIME"; maxretry="$F2B_MANAGER_MAXRETRY"
	trusted=("${F2B_MANAGER_TRUSTED[@]}")
	case "$action" in
		set-profile)
			read -r bantime findtime maxretry <<< "$(kpanel_f2b_manager_profile_values "$value")" || return 2
			[ "$F2B_MANAGER_PROFILE" = "$value" ] || changed=true
			;;
		add-trusted)
			kpanel_f2b_manager_valid_address "$value" || return 2
			for item in "${trusted[@]}"; do [ "$item" != "$value" ] || { kpanel_f2b_manager_snapshot unchanged; return 0; }; done
			[ "${#trusted[@]}" -lt 64 ] || { kpanel_f2b_manager_error "信任地址已达到 64 条上限"; return 1; }
			trusted+=("$value"); changed=true
			;;
		remove-trusted)
			kpanel_f2b_manager_valid_address "$value" || return 2
			local filtered=()
			for item in "${trusted[@]}"; do [ "$item" = "$value" ] || filtered+=("$item"); done
			[ "${#filtered[@]}" -ne "${#trusted[@]}" ] || { kpanel_f2b_manager_snapshot unchanged; return 0; }
			trusted=("${filtered[@]}"); changed=true
			;;
		*) return 2 ;;
	esac
	[ "$changed" = true ] || { kpanel_f2b_manager_snapshot unchanged; return 0; }
	snapshot="$(kpanel_system_resource_tempdir ssh-defense)" || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
	config_file="$(kpanel_f2b_manager_config_file)"
	if [ -f "$config_file" ] && [ ! -L "$config_file" ]; then
		printf '%s\n' true > "$snapshot/config.existed"
		cp -a -- "$config_file" "$snapshot/config" || { rm -rf -- "$snapshot"; return 1; }
	else
		printf '%s\n' false > "$snapshot/config.existed"
	fi
	kpanel_f2b_manager_write_config "$F2B_MANAGER_JAIL" "$bantime" "$findtime" "$maxretry" "${trusted[@]}" ||
		kpanel_f2b_manager_config_failure "$snapshot" "无法写入 SSH 防御配置" || return 1
	fail2ban-client -t >/dev/null 2>&1 || kpanel_f2b_manager_config_failure "$snapshot" "Fail2Ban 配置验证失败" || return 1
	fail2ban-client reload >/dev/null 2>&1 || kpanel_f2b_manager_config_failure "$snapshot" "Fail2Ban 配置重载失败" || return 1
	kpanel_f2b_manager_collect || kpanel_f2b_manager_config_failure "$snapshot" "SSH 防御配置回读失败" || return 1
	[ "$F2B_MANAGER_BANTIME" = "$bantime" ] && [ "$F2B_MANAGER_FINDTIME" = "$findtime" ] && [ "$F2B_MANAGER_MAXRETRY" = "$maxretry" ] ||
		kpanel_f2b_manager_config_failure "$snapshot" "SSH 防御策略回读不一致" || return 1
	case "$action" in
		add-trusted)
			for item in "${F2B_MANAGER_TRUSTED[@]}"; do [ "$item" != "$value" ] || changed=verified; done
			[ "$changed" = verified ] || kpanel_f2b_manager_config_failure "$snapshot" "SSH 防御信任地址回读不一致" || return 1
			;;
		remove-trusted)
			for item in "${F2B_MANAGER_TRUSTED[@]}"; do
				[ "$item" != "$value" ] || kpanel_f2b_manager_config_failure "$snapshot" "SSH 防御信任地址仍然生效" || return 1
			done
			;;
	esac
	rm -rf -- "$snapshot"
	kpanel_f2b_manager_snapshot applied
}

kpanel_f2b_manager_unban_action() {
	local expected="$1" address="${2:-}" current_version item target changed=false
	local targets=()
	kpanel_f2b_manager_set_version || { kpanel_f2b_manager_emit failed ""; return 1; }
	current_version="$F2B_MANAGER_VERSION"
	[ "$current_version" = "$expected" ] || { kpanel_f2b_manager_emit conflict "$current_version"; return 2; }
	[ "$F2B_MANAGER_ENABLED" = true ] || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
	if [ -n "$address" ]; then
		kpanel_f2b_manager_valid_ip "$address" || return 2
		for item in "${F2B_MANAGER_BANS[@]}"; do
			[ "$item" = "$address" ] || continue
			fail2ban-client set "$F2B_MANAGER_JAIL" unbanip --report-absent "$address" >/dev/null 2>&1 || {
				kpanel_f2b_manager_emit needs-attention "$current_version"
				return 1
			}
			targets+=("$address")
			changed=true
		done
	else
		for item in "${F2B_MANAGER_BANS[@]}"; do
			fail2ban-client set "$F2B_MANAGER_JAIL" unbanip --report-absent "$item" >/dev/null 2>&1 || {
				kpanel_f2b_manager_emit needs-attention "$current_version"
				return 1
			}
			targets+=("$item")
			changed=true
		done
	fi
	if [ "$changed" = true ]; then
		kpanel_f2b_manager_collect || { kpanel_f2b_manager_emit needs-attention "$current_version"; return 1; }
		for target in "${targets[@]}"; do
			for item in "${F2B_MANAGER_BANS[@]}"; do
				[ "$item" != "$target" ] || {
					kpanel_f2b_manager_error "SSH 封禁解除后回读不一致"
					kpanel_f2b_manager_emit needs-attention "$current_version"
					return 1
				}
			done
		done
	fi
	kpanel_f2b_manager_snapshot "$([ "$changed" = true ] && printf applied || printf unchanged)"
}

kpanel_f2b_manager_service_action() {
	local action="$1" current_version changed=false
	root_use
	current_version="$(kpanel_f2b_manager_current_version 2>/dev/null || true)"
	case "$action" in
		enable)
			if kpanel_f2b_enabled && kpanel_f2b_autostart; then kpanel_f2b_manager_snapshot unchanged; return 0; fi
			f2b_install_sshd >/dev/null || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			kpanel_f2b_enabled || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			changed=true
			;;
		disable)
			if ! command -v fail2ban-client >/dev/null 2>&1; then kpanel_f2b_manager_snapshot unchanged; return 0; fi
			if command -v apk >/dev/null 2>&1; then
				service fail2ban stop >/dev/null 2>&1 || true
				rc-update del fail2ban default >/dev/null 2>&1 || true
			else
				/bin/systemctl disable --now fail2ban.service >/dev/null 2>&1 || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			fi
			fail2ban-client ping >/dev/null 2>&1 && { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			changed=true
			;;
		uninstall)
			if ! command -v fail2ban-client >/dev/null 2>&1; then kpanel_f2b_manager_snapshot unchanged; return 0; fi
			remove fail2ban >/dev/null 2>&1 || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			rm -rf -- "${KPANEL_F2B_TEST_ROOT:-}/etc/fail2ban" || { kpanel_f2b_manager_emit failed "$current_version"; return 1; }
			changed=true
			;;
		*) return 2 ;;
	esac
	kpanel_f2b_manager_snapshot "$([ "$changed" = true ] && printf applied || printf unchanged)"
}

kpanel_f2b_manager_run_locked() (
	local action="$1"
	shift
	case "$action" in
		set-profile|add-trusted|remove-trusted) kpanel_f2b_manager_config_action "$action" "$@" ;;
		unban) kpanel_f2b_manager_unban_action "$@" ;;
		unban-all) kpanel_f2b_manager_unban_action "$1" ;;
		enable|disable|uninstall) kpanel_f2b_manager_service_action "$action" ;;
		*) return 2 ;;
	esac
)

kpanel_f2b_manager_dispatch() {
	local action="${1:-status}" expected value lock_file rc
	shift || true
	printf '%s\n' "KPANEL_F2B_MANAGER_PROTOCOL 1"
	case "$action" in
		status)
			[ "$#" -eq 0 ] || return 2
			kpanel_f2b_manager_snapshot ok
			;;
		set-profile)
			[ "$#" -eq 2 ] && kpanel_system_resource_valid_version "$1" && kpanel_f2b_manager_profile_values "$2" >/dev/null || return 2
			expected="$1"; value="$2"
			;;
		add-trusted|remove-trusted)
			[ "$#" -eq 2 ] && kpanel_system_resource_valid_version "$1" && kpanel_f2b_manager_valid_address "$2" || return 2
			expected="$1"; value="$2"
			;;
		unban)
			[ "$#" -eq 2 ] && kpanel_system_resource_valid_version "$1" && kpanel_f2b_manager_valid_ip "$2" || return 2
			expected="$1"; value="$2"
			;;
		unban-all)
			[ "$#" -eq 1 ] && kpanel_system_resource_valid_version "$1" || return 2
			expected="$1"
			;;
		enable|disable|uninstall)
			[ "$#" -eq 0 ] || return 2
			;;
		*)
			kpanel_f2b_manager_error "用法: k f2b manager <status|enable|disable|set-profile|unban|unban-all|add-trusted|remove-trusted|uninstall>"
			return 2
			;;
	esac
	[ "$action" = status ] && return 0
	lock_file="$(kpanel_system_resource_prepare_lock_file)" || { kpanel_f2b_manager_emit failed ""; return 1; }
	exec 9<>"$lock_file" || { kpanel_f2b_manager_emit failed ""; return 1; }
	if ! flock -w 5 9; then kpanel_f2b_manager_emit conflict "$(kpanel_f2b_manager_current_version 2>/dev/null || true)"; return 2; fi
	case "$action" in
		set-profile|add-trusted|remove-trusted|unban) kpanel_f2b_manager_run_locked "$action" "$expected" "$value" ;;
		unban-all) kpanel_f2b_manager_run_locked "$action" "$expected" ;;
		*) kpanel_f2b_manager_run_locked "$action" ;;
	esac
}

KPANEL_SYSTEM_TUNING_PROTOCOL_VERSION="1"
KPANEL_SYSTEM_TUNING_MIRROR_COMMIT="649e948763042e485e411be540d21c32cface1c1"
KPANEL_SYSTEM_TUNING_MIRROR_SHA256="2e3b78a460f10ef291f30e3cbf3d3b28a9521d6615364f11b36e4a70ec97d18d"

kpanel_system_tuning_error() { printf '错误: %s\n' "$1" >&2; }

kpanel_system_tuning_valid_item() {
	case "$1" in
		system-update|system-cleanup|swap-1g|ssh-port-5522|ssh-defense|firewall-open-all|bbr|timezone-shanghai|dns-auto|ipv4-preferred|basic-tools) return 0 ;;
		*) return 1 ;;
	esac
}

kpanel_system_tuning_run_command() {
	(
		unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
		"$@"
	)
}

kpanel_system_tuning_curl() {
	kpanel_system_tuning_run_command curl --proxy '' --noproxy '*' "$@"
}

kpanel_system_tuning_download_verified() {
	local url="$1" expected="$2" output="$3" actual size
	kpanel_system_tuning_curl --fail --silent --show-error --location --max-time 120 --output "$output" "$url" || return 1
	[ -f "$output" ] && [ ! -L "$output" ] || return 1
	size="$(wc -c < "$output" | tr -d '[:space:]')"
	[[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ] && [ "$size" -le 1048576 ] || return 1
	actual="$(sha256sum -- "$output" | awk '{print $1}')"
	[ "$actual" = "$expected" ]
}

kpanel_system_tuning_switch_mirror() {
	local script country url
	script="$(mktemp /tmp/kejilion-system-tuning-mirror.XXXXXX)" || return 1
	url="https://raw.githubusercontent.com/SuperManito/LinuxMirrors/${KPANEL_SYSTEM_TUNING_MIRROR_COMMIT}/ChangeMirrors.sh"
	kpanel_system_tuning_download_verified "$url" "$KPANEL_SYSTEM_TUNING_MIRROR_SHA256" "$script" || { rm -f -- "$script"; return 1; }
	country="$(kpanel_system_tuning_curl --fail --silent --show-error --max-time 10 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n' || true)"
	if [ "$country" = CN ]; then
		kpanel_system_tuning_run_command bash "$script" --source mirrors.huaweicloud.com --protocol https --use-intranet-source false --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --install-epel false --pure-mode
	elif grep -qi oracle /etc/os-release 2>/dev/null; then
		kpanel_system_tuning_run_command bash "$script" --source mirrors.xtom.com --protocol https --use-intranet-source false --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --install-epel false --pure-mode
	else
		kpanel_system_tuning_run_command bash "$script" --use-official-source true --protocol https --use-intranet-source false --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --install-epel false --pure-mode
	fi
	local result=$?
	rm -f -- "$script"
	return "$result"
}

kpanel_system_tuning_firewall_open_all() {
	local version
	if ! command -v iptables >/dev/null 2>&1 ||
		! command -v iptables-save >/dev/null 2>&1 ||
		! command -v iptables-restore >/dev/null 2>&1; then
		install iptables || {
			kpanel_system_tuning_error "iptables 兼容工具安装失败"
			return 1
		}
	fi
	check_crontab_installed || {
		kpanel_system_tuning_error "iptables 持久化依赖 crontab/crond 不可用"
		return 1
	}
	version="$(kpanel_system_resource_firewall_version)" || return 1
	kpanel_system_resource_firewall_action open-all "$version" >&2
}

kpanel_system_tuning_swap_1g_ready() {
	local swapfile="${1:-/swapfile}" swaps="${2:-/proc/swaps}" fstab="${3:-/etc/fstab}" size
	[ -f "$swapfile" ] && [ ! -L "$swapfile" ] || return 1
	size="$(stat -c '%s' -- "$swapfile" 2>/dev/null)"
	[ "$size" = 1073741824 ] || return 1
	awk -v path="$swapfile" 'NR > 1 && $1 == path { found=1 } END { exit !found }' "$swaps" 2>/dev/null || return 1
	awk -v path="$swapfile" '$1 == path && $2 == "swap" { found=1 } END { exit !found }' "$fstab" 2>/dev/null
}

kpanel_system_tuning_dns_auto() {
	local country dns1_ipv4 dns2_ipv4 dns1_ipv6 dns2_ipv6
	local dns=()
	if ! command -v chattr >/dev/null 2>&1; then
		install e2fsprogs || {
			kpanel_system_tuning_error "DNS 依赖 e2fsprogs/chattr 安装失败"
			return 1
		}
	fi
	country="$(curl --fail --silent --show-error --max-time 10 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n' || true)"
	if [ "$country" = CN ]; then
		dns1_ipv4="223.5.5.5"
		dns2_ipv4="183.60.83.19"
		dns1_ipv6="2400:3200::1"
		dns2_ipv6="2400:da00::6666"
	else
		dns1_ipv4="1.1.1.1"
		dns2_ipv4="8.8.8.8"
		dns1_ipv6="2606:4700:4700::1111"
		dns2_ipv6="2001:4860:4860::8888"
	fi
	ip_address
	[ -n "$ipv4_address" ] && dns+=("$dns1_ipv4" "$dns2_ipv4")
	[ -n "$ipv6_address" ] && dns+=("$dns1_ipv6" "$dns2_ipv6")
	[ "${#dns[@]}" -gt 0 ] || dns=("$dns1_ipv4" "$dns2_ipv4")
	KJ_DNS_NONINTERACTIVE=1 kpanel_set_dns_noninteractive "${dns[@]}"
}

kpanel_system_tuning_has_package_manager() {
	local mode="$1" command_name
	local commands=(dnf yum apt apk pacman zypper opkg)
	[ "$mode" = cleanup ] && commands+=(pkg)
	for command_name in "${commands[@]}"; do
		command -v "$command_name" >/dev/null 2>&1 && return 0
	done
	return 1
}

kpanel_system_tuning_ssh_server_ready() {
	local config="${KPANEL_SYSTEM_TUNING_SSHD_CONFIG:-/etc/ssh/sshd_config}"
	[ -f "$config" ] && [ ! -L "$config" ] &&
		command -v sshd >/dev/null 2>&1 && command -v ss >/dev/null 2>&1
}

kpanel_system_tuning_prepare_ssh_service() {
	local run_dir="${KPANEL_SYSTEM_TUNING_SSHD_RUN_DIR:-/run/sshd}"
	local systemd_dir="${KPANEL_SYSTEM_TUNING_SYSTEMD_DIR:-/run/systemd/system}"
	local alias_path="${KPANEL_SYSTEM_TUNING_SSHD_UNIT_ALIAS:-/etc/systemd/system/sshd.service}"
	local fragment systemctl_bin
	mkdir -p -- "$run_dir" && chmod 0755 "$run_dir" || return 1
	systemctl_bin="$(type -P systemctl 2>/dev/null || true)"
	if [ -n "$systemctl_bin" ] && [ -d "$systemd_dir" ]; then
		if "$systemctl_bin" cat ssh.service >/dev/null 2>&1; then
			if ! "$systemctl_bin" cat sshd.service >/dev/null 2>&1; then
				fragment="$("$systemctl_bin" show -p FragmentPath --value ssh.service 2>/dev/null)"
				case "$fragment" in /lib/systemd/system/*|/usr/lib/systemd/system/*) ;; *) return 1 ;; esac
				ln -sfn -- "$fragment" "$alias_path" || return 1
				"$systemctl_bin" daemon-reload || return 1
			fi
			if "$systemctl_bin" cat ssh.socket >/dev/null 2>&1; then
				"$systemctl_bin" disable ssh.socket >/dev/null 2>&1 || return 1
				"$systemctl_bin" stop ssh.socket >/dev/null 2>&1 || return 1
				if ! "$systemctl_bin" enable --now ssh.service >/dev/null 2>&1; then
					"$systemctl_bin" enable --now ssh.socket >/dev/null 2>&1 || true
					return 1
				fi
			else
				"$systemctl_bin" enable --now ssh.service >/dev/null 2>&1 || return 1
			fi
		else
			"$systemctl_bin" enable --now sshd.service >/dev/null 2>&1 || return 1
		fi
	elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
		rc-update add sshd default >/dev/null 2>&1 || return 1
		rc-service sshd start >/dev/null 2>&1 || return 1
	else
		return 1
	fi
}

kpanel_system_tuning_ensure_ssh_server() {
	local package_name
	if ! kpanel_system_tuning_ssh_server_ready; then
		if command -v apt >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 ||
			command -v yum >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1 ||
			command -v opkg >/dev/null 2>&1; then
			package_name=openssh-server
		elif command -v apk >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1; then
			package_name=openssh
		else
			kpanel_system_tuning_error "当前系统没有受支持的 OpenSSH Server 安装适配器"
			return 1
		fi
		install "$package_name" || {
			kpanel_system_tuning_error "OpenSSH Server 安装失败"
			return 1
		}
	fi
	kpanel_system_tuning_ssh_server_ready || {
		kpanel_system_tuning_error "OpenSSH Server 安装后配置或工具仍不可用"
		return 1
	}
	kpanel_system_tuning_prepare_ssh_service || {
		kpanel_system_tuning_error "OpenSSH Server 运行环境准备失败"
		return 1
	}
}

kpanel_system_tuning_item_ready() {
	local item="$1" command_name
	case "$item" in
		swap-1g) kpanel_system_tuning_swap_1g_ready ;;
		ssh-port-5522) sshd -T 2>/dev/null | grep -Eq '^port 5522$' ;;
		ssh-defense) kpanel_f2b_enabled >/dev/null 2>&1 ;;
		firewall-open-all) iptables-save 2>/dev/null | awk '$0=="*filter"{f=1;next} f&&$0=="COMMIT"{exit} f&&/^:INPUT /{i=$2} f&&/^:FORWARD /{w=$2} END{exit !(i=="ACCEPT"&&w=="ACCEPT")}' ;;
		bbr) [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = bbr ] && [ "$(sysctl -n net.core.default_qdisc 2>/dev/null)" = fq ] ;;
		timezone-shanghai) [ "$(timedatectl show -p Timezone --value 2>/dev/null)" = Asia/Shanghai ] ;;
		ipv4-preferred) grep -Eq '^precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]|$)' /etc/gai.conf 2>/dev/null ;;
		basic-tools) for command_name in docker wget sudo tar unzip socat btop nano vim; do command -v "$command_name" >/dev/null 2>&1 || return 1; done ;;
		*) return 1 ;;
	esac
}

kpanel_system_tuning_collect() {
	local canonical item state
	TUNING_ITEMS=()
	for item in system-update system-cleanup swap-1g ssh-port-5522 ssh-defense firewall-open-all bbr timezone-shanghai dns-auto ipv4-preferred basic-tools; do
		state=pending
		kpanel_system_tuning_item_ready "$item" && state=ready
		TUNING_ITEMS+=("$item:$state")
	done
	canonical="$(mktemp /tmp/kejilion-system-tuning-version.XXXXXX)" || return 1
	printf '%s\n' "${TUNING_ITEMS[@]}" > "$canonical"
	TUNING_VERSION="$(sha256sum -- "$canonical" 2>/dev/null | awk '{print $1}')"
	rm -f -- "$canonical"
	[[ "$TUNING_VERSION" =~ ^[0-9a-f]{64}$ ]]
}

kpanel_system_tuning_emit() {
	local status="$1" selected="${2:-}" item
	kpanel_system_tuning_collect || { TUNING_VERSION="$(kpanel_system_resource_zero_version)"; TUNING_ITEMS=(); }
	printf 'KPANEL_SYSTEM_TUNING_STATUS=%s\n' "$status"
	printf 'KPANEL_SYSTEM_TUNING_VERSION=%s\n' "$TUNING_VERSION"
	[ -z "$selected" ] || printf 'KPANEL_SYSTEM_TUNING_SELECTED=%s\n' "$selected"
	for item in "${TUNING_ITEMS[@]}"; do printf 'KPANEL_SYSTEM_TUNING_ITEM=%s\n' "$item"; done
}

kpanel_system_tuning_run_item() {
	case "$1" in
		system-update)
			kpanel_system_tuning_has_package_manager update || { kpanel_system_tuning_error "当前系统没有受支持的软件包管理器"; return 1; }
			# 更新源优化保持尽力执行，不因其返回码中断一条龙调优。
			kpanel_system_tuning_switch_mirror || true
			kpanel_system_tuning_run_command linux_update || { kpanel_system_tuning_error "系统软件包更新失败"; return 1; }
			;;
		system-cleanup)
			kpanel_system_tuning_has_package_manager cleanup || { kpanel_system_tuning_error "当前系统没有受支持的清理适配器"; return 1; }
			linux_clean || { kpanel_system_tuning_error "系统清理失败"; return 1; }
			;;
		swap-1g) add_swap 1024 ;;
		ssh-port-5522) kpanel_system_tuning_ensure_ssh_server && KJ_SSH_PORT_NONINTERACTIVE=1 kpanel_ssh_port_noninteractive 5522 ;;
		ssh-defense) kpanel_f2b_manager_service_action enable && kpanel_f2b_enabled ;;
		firewall-open-all) kpanel_system_tuning_firewall_open_all ;;
		bbr) bbr_on ;;
		timezone-shanghai) set_timedate Asia/Shanghai ;;
		dns-auto) kpanel_system_tuning_dns_auto ;;
		ipv4-preferred) prefer_ipv4 ;;
		basic-tools) install_docker && install wget sudo tar unzip socat btop nano vim ;;
		*) return 2 ;;
	esac
}

kpanel_system_tuning_menu_item() {
	local item="$1" index="$2" label="$3"
	echo "------------------------------------------------"
	if ! kpanel_system_tuning_run_item "$item"; then
		echo -e "[${gl_hong}FAIL${gl_bai}] ${index}/11. ${label}，一条龙调优已停止"
		return 1
	fi
	case "$item" in system-update|system-cleanup|dns-auto) ;; *)
		if ! kpanel_system_tuning_item_ready "$item"; then
			echo -e "[${gl_hong}FAIL${gl_bai}] ${index}/11. ${label}，完成态回读失败，一条龙调优已停止"
			return 1
		fi
	;; esac
	echo -e "[${gl_lv}OK${gl_bai}] ${index}/11. ${label}"
}

kpanel_system_tuning_apply_item() {
	local item="$1" status=applied
	if kpanel_system_tuning_item_ready "$item"; then
		status=unchanged
	elif ! kpanel_system_tuning_run_item "$item" >&2; then
		kpanel_system_tuning_emit needs-attention "$item"
		return 1
	fi
	case "$item" in system-update|system-cleanup|dns-auto) ;; *)
		kpanel_system_tuning_item_ready "$item" || { kpanel_system_tuning_emit needs-attention "$item"; return 1; }
	;; esac
	kpanel_system_tuning_emit "$status" "$item"
}

kpanel_system_tuning_dispatch() {
	local action="${1:-status}" item lock_file
	shift || true
	printf '%s\n' "KPANEL_SYSTEM_TUNING_PROTOCOL 1"
	[ "${KJ_SYSTEM_TUNING_NONINTERACTIVE:-}" = 1 ] || { kpanel_system_tuning_error "KPanel system-tuning 协议环境未启用"; return 2; }
	[ "$EUID" -eq 0 ] || { kpanel_system_tuning_error "KPanel system-tuning 协议必须以 root 运行"; return 1; }
	[ "$(uname -s)" = Linux ] || { kpanel_system_tuning_error "KPanel system-tuning 协议仅支持 Linux"; return 1; }
	case "$action" in
		status) [ "$#" -eq 0 ] || return 2; kpanel_system_tuning_emit ok; return $? ;;
		apply-item) [ "$#" -eq 1 ] && kpanel_system_tuning_valid_item "$1" || return 2; item="$1" ;;
		*) kpanel_system_tuning_error "用法: k kpanel system-tuning <status|apply-item item>"; return 2 ;;
	esac
	lock_file="$(kpanel_system_resource_prepare_lock_file)" || { kpanel_system_tuning_emit failed "$item"; return 1; }
	exec 9<>"$lock_file" || { kpanel_system_tuning_emit failed "$item"; return 1; }
	if ! flock -w 5 9; then kpanel_system_tuning_emit conflict "$item"; return 2; fi
	kpanel_system_tuning_apply_item "$item"
}

f2b_sshd() {
	if grep -q 'Alpine' /etc/issue; then
		xxx=alpine-sshd
		f2b_status_xxx
	else
		xxx=sshd
		f2b_status_xxx
	fi
}

# 基础参数配置：封禁时长(bantime)、时间窗口(findtime)、重试次数(maxretry)
# 说明：
# - 优先写入 /etc/fail2ban/jail.d/sshd.local（覆盖默认 jail 配置，升级不易丢）
# - 若是 Alpine 且 jail 名称不同，依然写 sshd.local；Fail2Ban 会按 jail 名称匹配
f2b_basic_config() {
	root_use
	install nano

	if ! command -v fail2ban-client >/dev/null 2>&1; then
		echo -e "${gl_hui}未检测到 fail2ban-client，请先安装 fail2ban。${gl_bai}"
		return
	fi

	local jail_name="sshd"
	if grep -qi 'Alpine' /etc/issue 2>/dev/null; then
		# Alpine 默认 jail 通常为 sshd；仅当检测到自定义 alpine-sshd 规则时才切换
		if [ -f /etc/fail2ban/filter.d/alpine-sshd.conf ] || [ -f /etc/fail2ban/jail.d/alpine-ssh.conf ] || [ -f /etc/fail2ban/jail.d/alpine-sshd.local ]; then
			jail_name="alpine-sshd"
		fi
	fi

	echo "即将配置 SSH jail：$jail_name"
	read -e -p "封禁时长 bantime (秒/分钟/小时，如 3600 或 1h) [默认 1h]: " bantime
	read -e -p "时间窗口 findtime (秒/分钟/小时，如 600 或 10m) [默认 10m]: " findtime
	read -e -p "重试次数 maxretry (整数) [默认 5]: " maxretry

	bantime=${bantime:-1h}
	findtime=${findtime:-10m}
	maxretry=${maxretry:-5}

	mkdir -p /etc/fail2ban/jail.d
	cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[$jail_name]
# Managed by kejilion.sh
# Note: enable the jail so these parameters take effect
enabled = true
bantime = $bantime
findtime = $findtime
maxretry = $maxretry
EOF

	# Ensure a logfile exists for sshd jail on Debian/Ubuntu minimal images
	# (without it, fail2ban-server may refuse to start)
	if [ "$jail_name" = "sshd" ]; then
		if [ -f /etc/fail2ban/jail.d/sshd.local ]; then
			grep -qE '^\s*logpath\s*=' /etc/fail2ban/jail.d/sshd.local || echo 'logpath = /var/log/auth.log' >> /etc/fail2ban/jail.d/sshd.local
		fi
	fi

	echo -e "${gl_lv}已写入配置${gl_bai}: /etc/fail2ban/jail.d/sshd.local"
	fail2ban-client reload >/dev/null 2>&1 || true
	sleep 2
	fail2ban-client status $jail_name || true
}

# 直接打开主配置/覆盖配置编辑（nano）
# 优先编辑 /etc/fail2ban/jail.d/sshd.local（更安全），若不存在则创建
f2b_edit_config() {
	root_use
	install nano

	if [ ! -d /etc/fail2ban ]; then
		echo -e "${gl_hui}/etc/fail2ban 不存在，请先安装 fail2ban。${gl_bai}"
		return
	fi

	mkdir -p /etc/fail2ban/jail.d
	local cfg="/etc/fail2ban/jail.d/sshd.local"
	[ -f "$cfg" ] || printf "[sshd]\n# bantime/findtime/maxretry\n" > "$cfg"

	nano "$cfg"
	echo -e "${gl_lv}已保存${gl_bai}，正在 reload fail2ban..."
	fail2ban-client reload >/dev/null 2>&1 || true
}



server_reboot() {

	read -e -p "$(echo -e "${gl_huang}提示: ${gl_bai}现在重启服务器吗？(Y/N): ")" rboot
	case "$rboot" in
	  [Yy])
		echo "已重启"
		reboot
		;;
	  *)
		echo "已取消"
		;;
	esac


}





output_status() {
	output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
		$1 ~ /^(eth|ens|enp|eno)[0-9]+/ {
			rx_total += $2
			tx_total += $10
		}
		END {
			rx_units = "Bytes";
			tx_units = "Bytes";
			if (rx_total > 1024) { rx_total /= 1024; rx_units = "K"; }
			if (rx_total > 1024) { rx_total /= 1024; rx_units = "M"; }
			if (rx_total > 1024) { rx_total /= 1024; rx_units = "G"; }

			if (tx_total > 1024) { tx_total /= 1024; tx_units = "K"; }
			if (tx_total > 1024) { tx_total /= 1024; tx_units = "M"; }
			if (tx_total > 1024) { tx_total /= 1024; tx_units = "G"; }

			printf("%.2f%s %.2f%s\n", rx_total, rx_units, tx_total, tx_units);
		}' /proc/net/dev)

	rx=$(echo "$output" | awk '{print $1}')
	tx=$(echo "$output" | awk '{print $2}')

}

current_timezone() {
	if grep -q 'Alpine' /etc/issue; then
	   date +"%Z %z"
	else
	   timedatectl | grep "Time zone" | awk '{print $3}'
	fi

}


set_timedate() {
	local shiqu="$1"
	if grep -q 'Alpine' /etc/issue; then
		install tzdata
		cp /usr/share/zoneinfo/${shiqu} /etc/localtime
		hwclock --systohc
	else
		timedatectl set-timezone ${shiqu}
	fi
}



# 修复dpkg中断问题
fix_dpkg() {
	pkill -9 -f 'apt|dpkg'
	rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
	DEBIAN_FRONTEND=noninteractive dpkg --configure -a
}


linux_update() {
	echo -e "${gl_kjlan}正在系统更新...${gl_bai}"
	if command -v dnf &>/dev/null; then
		dnf -y update
	elif command -v yum &>/dev/null; then
		yum -y update
	elif command -v apt &>/dev/null; then
		fix_dpkg
		DEBIAN_FRONTEND=noninteractive apt update -y
		DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
	elif command -v apk &>/dev/null; then
		apk update && apk upgrade
	elif command -v pacman &>/dev/null; then
		pacman -Syu --noconfirm
	elif command -v zypper &>/dev/null; then
		zypper refresh
		zypper update
	elif command -v opkg &>/dev/null; then
		opkg update
	else
		echo "未知的包管理器!"
		return
	fi
}



linux_clean() {
	echo -e "${gl_kjlan}正在系统清理...${gl_bai}"
	if command -v dnf &>/dev/null; then
		rpm --rebuilddb
		dnf autoremove -y
		dnf clean all
		dnf makecache
		journalctl --rotate
		journalctl --vacuum-time=1s
		journalctl --vacuum-size=500M

	elif command -v yum &>/dev/null; then
		rpm --rebuilddb
		yum autoremove -y
		yum clean all
		yum makecache
		journalctl --rotate
		journalctl --vacuum-time=1s
		journalctl --vacuum-size=500M

	elif command -v apt &>/dev/null; then
		fix_dpkg
		apt autoremove --purge -y
		apt clean -y
		apt autoclean -y
		journalctl --rotate
		journalctl --vacuum-time=1s
		journalctl --vacuum-size=500M

	elif command -v apk &>/dev/null; then
		echo "清理包管理器缓存..."
		apk cache clean
		echo "删除系统日志..."
		rm -rf /var/log/*
		echo "删除APK缓存..."
		rm -rf /var/cache/apk/*
		echo "删除临时文件..."
		rm -rf /tmp/*

	elif command -v pacman &>/dev/null; then
		pacman -Rns $(pacman -Qdtq) --noconfirm
		pacman -Scc --noconfirm
		journalctl --rotate
		journalctl --vacuum-time=1s
		journalctl --vacuum-size=500M

	elif command -v zypper &>/dev/null; then
		zypper clean --all
		zypper refresh
		journalctl --rotate
		journalctl --vacuum-time=1s
		journalctl --vacuum-size=500M

	elif command -v opkg &>/dev/null; then
		echo "删除系统日志..."
		rm -rf /var/log/*
		echo "删除临时文件..."
		rm -rf /tmp/*

	elif command -v pkg &>/dev/null; then
		echo "清理未使用的依赖..."
		pkg autoremove -y
		echo "清理包管理器缓存..."
		pkg clean -y
		echo "删除系统日志..."
		rm -rf /var/log/*
		echo "删除临时文件..."
		rm -rf /tmp/*

	else
		echo "未知的包管理器!"
		return
	fi
	return
}



bbr_on() {

# 统一写入到 sysctl.d 以防与内核调优模块打架
local CONF="/etc/sysctl.d/99-kejilion-bbr.conf"
mkdir -p /etc/sysctl.d
echo "net.core.default_qdisc=fq" > "$CONF"
echo "net.ipv4.tcp_congestion_control=bbr" >> "$CONF"

# 清理可能导致冲突的旧版 sysctl.conf 残留
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null

sysctl -p "$CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1

}


set_dns() {

ip_address

chattr -i /etc/resolv.conf
> /etc/resolv.conf

if [ -n "$ipv4_address" ]; then
	echo "nameserver $dns1_ipv4" >> /etc/resolv.conf
	echo "nameserver $dns2_ipv4" >> /etc/resolv.conf
fi

if [ -n "$ipv6_address" ]; then
	echo "nameserver $dns1_ipv6" >> /etc/resolv.conf
	echo "nameserver $dns2_ipv6" >> /etc/resolv.conf
fi

if [ ! -s /etc/resolv.conf ]; then
	echo "nameserver 223.5.5.5" >> /etc/resolv.conf
	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

chattr +i /etc/resolv.conf

}

kpanel_dns_is_ipv4() {
	local value="$1"
	local first second third fourth extra octet
	IFS=. read -r first second third fourth extra <<< "$value"
	[ -z "$extra" ] || return 1
	for octet in "$first" "$second" "$third" "$fourth"; do
		[[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
		[ "$((10#$octet))" -le 255 ] || return 1
	done
}

kpanel_dns_is_ipv6() {
	local value="$1"
	[ ${#value} -le 45 ] &&
	[[ "$value" == *:* ]] &&
	[[ "$value" =~ ^[0-9A-Fa-f:.]+$ ]]
}

kpanel_dns_wsl_environment() {
	grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null ||
		uname -r 2>/dev/null | grep -qiE '(microsoft|wsl)'
}

kpanel_dns_wsl_persist_resolver() {
	local expected="$1" config="/etc/wsl.conf" state_dir="/etc/kpanel"
	local state_file="/etc/kpanel/resolv.conf" unit="/etc/systemd/system/kpanel-wsl-resolvconf.service"
	local desired

	desired="$(mktemp /etc/.wsl.conf.kpanel.XXXXXX)" || return 1
	if [ -f "$config" ]; then
		awk '
			BEGIN { in_network=0; inserted=0 }
			/^\[network\][[:space:]]*$/ {
				in_network=1; print
				if (!inserted) { print "generateResolvConf = false"; inserted=1 }
				next
			}
			/^\[/ { in_network=0; print; next }
			in_network && /^[[:space:]]*generateResolvConf[[:space:]]*=/ { next }
			{ print }
			END { if (!inserted) print "\n[network]\ngenerateResolvConf = false" }
		' "$config" > "$desired" || { rm -f "$desired"; return 1; }
	else
		printf '[network]\ngenerateResolvConf = false\n' > "$desired" || { rm -f "$desired"; return 1; }
	fi
	grep -q '^\[boot\][[:space:]]*$' "$desired" ||
		printf '\n[boot]\nsystemd = true\n' >> "$desired" || { rm -f "$desired"; return 1; }
	chmod 644 "$desired" && mv -f "$desired" "$config" || { rm -f "$desired"; return 1; }
	mkdir -p "$state_dir" || return 1
	printf '%s' "$expected" > "$state_file" || return 1
	chmod 644 "$state_file" || return 1
	printf '%s\n' \
		'[Unit]' \
		'Description=Restore KPanel managed WSL DNS' \
		'After=local-fs.target' \
		'Before=network-pre.target' \
		'' \
		'[Service]' \
		'Type=oneshot' \
		'ExecStart=/usr/bin/cp -f /etc/kpanel/resolv.conf /etc/resolv.conf' \
		'' \
		'[Install]' \
		'WantedBy=multi-user.target' > "$unit" || return 1
	chmod 644 "$unit" || return 1
	mkdir -p /etc/systemd/system/multi-user.target.wants || return 1
	ln -sfn "$unit" /etc/systemd/system/multi-user.target.wants/kpanel-wsl-resolvconf.service || return 1
	if systemctl daemon-reload >/dev/null 2>&1; then
		systemctl enable --now kpanel-wsl-resolvconf.service >/dev/null 2>&1 || return 1
	fi
}

kpanel_dns_restore_file() {
	local target="$1"
	local backup="$2"
	local existed="$3"
	local immutable="$4"

	chattr -i "$target" >/dev/null 2>&1 || true
	if [ "$existed" = "true" ]; then
		cp -p "$backup" "$target" || return 1
	else
		rm -f "$target" || return 1
	fi
	if [ "$immutable" = "true" ]; then
		chattr +i "$target" >/dev/null 2>&1 || return 1
	fi
}

kpanel_dns_write_static() {
	local target="/etc/resolv.conf"
	local parent desired backup old_mode old_immutable="false" existed="false" lock_dns="true"
	local expected="" value

	if [ -L "$target" ]; then
		target="$(readlink -f "$target")"
		[ -n "$target" ] || {
			echo "错误: /etc/resolv.conf 是失效的符号链接"
			return 1
		}
	fi
	parent="$(dirname "$target")"
	[ -d "$parent" ] || {
		echo "错误: DNS 配置目录不存在"
		return 1
	}
	kpanel_dns_wsl_environment && lock_dns="false"
	if [ "$lock_dns" = "true" ] && ! command -v chattr >/dev/null 2>&1; then
		kpanel_dns_wsl_environment || {
			echo "错误: chattr 不可用，无法保持 kejilion.sh DNS 生命周期语义"
			return 1
		}
		lock_dns="false"
	fi

	desired="$(mktemp "${parent}/.resolv.conf.kpanel.XXXXXX")" || return 1
	backup="$(mktemp "${parent}/.resolv.conf.backup.XXXXXX")" || {
		rm -f "$desired"
		return 1
	}
	for value in "$@"; do
		expected="${expected}nameserver ${value}"$'\n'
	done
	if [ "$lock_dns" = "false" ] && ! kpanel_dns_wsl_persist_resolver "$expected"; then
		rm -f "$desired" "$backup"
		echo "错误: WSL DNS 持久化配置失败"
		return 1
	fi
	printf '%s' "$expected" > "$desired" || {
		rm -f "$desired" "$backup"
		return 1
	}

	if [ -f "$target" ]; then
		existed="true"
		cp -p "$target" "$backup" || {
			rm -f "$desired" "$backup"
			return 1
		}
		old_mode="$(stat -c '%a' "$target" 2>/dev/null || printf '644')"
		chmod "$old_mode" "$desired" || {
			rm -f "$desired" "$backup"
			return 1
		}
		chown --reference="$target" "$desired" >/dev/null 2>&1 || true
		if [ "$lock_dns" = "true" ] && lsattr -d "$target" 2>/dev/null | awk '{print $1}' | grep -q 'i'; then
			old_immutable="true"
		fi
		if [ "$(cat "$target")"$'\n' = "$expected" ]; then
			if [ "$lock_dns" = "true" ] && ! chattr +i "$target" >/dev/null 2>&1; then
				if kpanel_dns_wsl_environment; then
					lock_dns="false"
				else
					rm -f "$desired" "$backup"
					echo "错误: 无法锁定 DNS 配置"
					return 1
				fi
			fi
			rm -f "$desired" "$backup"
			echo "KPANEL_DNS_MANAGER resolv.conf"
			echo "KPANEL_DNS_RESULT unchanged"
			return 0
		fi
		if [ "$lock_dns" = "true" ] && ! chattr -i "$target" >/dev/null 2>&1; then
			if kpanel_dns_wsl_environment; then
				lock_dns="false"
			else
				rm -f "$desired" "$backup"
				echo "错误: 无法解除现有 DNS 配置锁定"
				return 1
			fi
		fi
	else
		chmod 644 "$desired" || {
			rm -f "$desired" "$backup"
			return 1
		}
	fi

	if ! mv -f "$desired" "$target"; then
		kpanel_dns_restore_file "$target" "$backup" "$existed" "$old_immutable" || {
			rm -f "$desired" "$backup"
			echo "错误: DNS 写入失败且回滚失败，需要人工检查"
			return 1
		}
		rm -f "$desired" "$backup"
		echo "错误: DNS 写入或回读验证失败，已恢复原配置"
		return 1
	fi
	if [ "$lock_dns" = "true" ] && ! chattr +i "$target" >/dev/null 2>&1; then
		if kpanel_dns_wsl_environment; then
			lock_dns="false"
		else
			kpanel_dns_restore_file "$target" "$backup" "$existed" "$old_immutable" || {
				rm -f "$desired" "$backup"
				echo "错误: DNS 写入失败且回滚失败，需要人工检查"
				return 1
			}
			rm -f "$desired" "$backup"
			echo "错误: DNS 写入或回读验证失败，已恢复原配置"
			return 1
		fi
	fi
	if [ "$(cat "$target")"$'\n' != "$expected" ]; then
		kpanel_dns_restore_file "$target" "$backup" "$existed" "$old_immutable" || {
			rm -f "$desired" "$backup"
			echo "错误: DNS 写入失败且回滚失败，需要人工检查"
			return 1
		}
		rm -f "$desired" "$backup"
		echo "错误: DNS 写入或回读验证失败，已恢复原配置"
		return 1
	fi
	rm -f "$backup"
	echo "KPANEL_DNS_MANAGER resolv.conf"
	echo "KPANEL_DNS_RESULT applied"
}

kpanel_dns_write_systemd_resolved() {
	local config="/etc/systemd/resolved.conf.d/90-kpanel.conf"
	local parent desired backup existed="false" expected

	command -v systemctl >/dev/null 2>&1 || {
		echo "错误: systemctl 不可用"
		return 1
	}
	parent="$(dirname "$config")"
	mkdir -p "$parent" || return 1
	desired="$(mktemp "${parent}/.90-kpanel.conf.kpanel.XXXXXX")" || return 1
	backup="$(mktemp "${parent}/.90-kpanel.conf.backup.XXXXXX")" || {
		rm -f "$desired"
		return 1
	}
	expected="[Resolve]"$'\n'"DNS=$*"$'\n'"FallbackDNS="$'\n'
	printf '%s' "$expected" > "$desired" || {
		rm -f "$desired" "$backup"
		return 1
	}
	chmod 644 "$desired" || {
		rm -f "$desired" "$backup"
		return 1
	}
	if [ -f "$config" ]; then
		existed="true"
		cp -p "$config" "$backup" || {
			rm -f "$desired" "$backup"
			return 1
		}
		if [ "$(cat "$config")"$'\n' = "$expected" ]; then
			rm -f "$desired" "$backup"
			echo "KPANEL_DNS_MANAGER systemd-resolved"
			echo "KPANEL_DNS_RESULT unchanged"
			return 0
		fi
	fi
	if ! mv -f "$desired" "$config" ||
		! systemctl reload-or-restart systemd-resolved.service >/dev/null 2>&1 ||
		[ "$(cat "$config")"$'\n' != "$expected" ]; then
		if [ "$existed" = "true" ]; then
			cp -p "$backup" "$config" || {
				rm -f "$desired" "$backup"
				echo "错误: systemd-resolved DNS 回滚失败，需要人工检查"
				return 1
			}
		else
			rm -f "$config"
		fi
		systemctl reload-or-restart systemd-resolved.service >/dev/null 2>&1 || {
			rm -f "$desired" "$backup"
			echo "错误: systemd-resolved DNS 已恢复文件，但服务重载失败，需要人工检查"
			return 1
		}
		rm -f "$desired" "$backup"
		echo "错误: systemd-resolved DNS 写入或回读验证失败，已恢复原配置"
		return 1
	fi
	rm -f "$backup"
	echo "KPANEL_DNS_MANAGER systemd-resolved"
	echo "KPANEL_DNS_RESULT applied"
}

kpanel_set_dns_noninteractive() {
	[ "${KJ_DNS_NONINTERACTIVE:-}" = "1" ] || return 2
	[ "$EUID" -eq 0 ] || {
		echo "错误: KPanel DNS 协议必须以 root 运行"
		return 1
	}
	[ "$#" -ge 1 ] && [ "$#" -le 4 ] || {
		echo "错误: DNS 地址数量必须为 1-4 个"
		return 1
	}

	local ipv4_count=0 ipv6_count=0 value previous
	local normalized=()
	for value in "$@"; do
		[ -n "$value" ] && [ ${#value} -le 45 ] || {
			echo "错误: DNS 地址为空或过长"
			return 1
		}
		if kpanel_dns_is_ipv4 "$value"; then
			ipv4_count=$((ipv4_count + 1))
			[ "$ipv4_count" -le 2 ] || {
				echo "错误: IPv4 DNS 地址最多 2 个"
				return 1
			}
		elif kpanel_dns_is_ipv6 "$value"; then
			ipv6_count=$((ipv6_count + 1))
			[ "$ipv6_count" -le 2 ] || {
				echo "错误: IPv6 DNS 地址最多 2 个"
				return 1
			}
		else
			echo "错误: 无效的 DNS 地址"
			return 1
		fi
		for previous in "${normalized[@]}"; do
			[ "$previous" = "$value" ] && {
				echo "错误: DNS 地址不能重复"
				return 1
			}
		done
		normalized+=("$value")
	done

	local resolver_target
	resolver_target="$(readlink /etc/resolv.conf 2>/dev/null || true)"
	if [[ "${resolver_target,,}" == *systemd/resolve* ]]; then
		kpanel_dns_write_systemd_resolved "${normalized[@]}"
	else
		kpanel_dns_write_static "${normalized[@]}"
	fi
}


set_dns_ui() {
root_use
while true; do
	clear
	echo "优化DNS地址"
	echo "------------------------"
	echo "当前DNS地址"
	cat /etc/resolv.conf
	echo "------------------------"
	echo ""
	echo "1. 国外DNS优化: "
	echo " v4: 1.1.1.1 8.8.8.8"
	echo " v6: 2606:4700:4700::1111 2001:4860:4860::8888"
	echo "2. 国内DNS优化: "
	echo " v4: 223.5.5.5 183.60.83.19"
	echo " v6: 2400:3200::1 2400:da00::6666"
	echo "3. 手动编辑DNS配置"
	echo "------------------------"
	echo "0. 返回上一级选单"
	echo "------------------------"
	read -e -p "请输入你的选择: " Limiting
	case "$Limiting" in
	  1)
		local dns1_ipv4="1.1.1.1"
		local dns2_ipv4="8.8.8.8"
		local dns1_ipv6="2606:4700:4700::1111"
		local dns2_ipv6="2001:4860:4860::8888"
		set_dns
		;;
	  2)
		local dns1_ipv4="223.5.5.5"
		local dns2_ipv4="183.60.83.19"
		local dns1_ipv6="2400:3200::1"
		local dns2_ipv6="2400:da00::6666"
		set_dns
		;;
	  3)
		install nano
		chattr -i /etc/resolv.conf
		nano /etc/resolv.conf
		chattr +i /etc/resolv.conf
		;;
	  *)
		break
		;;
	esac
done

}



restart_ssh() {
	restart sshd ssh > /dev/null 2>&1

}



correct_ssh_config() {

	local sshd_config="/etc/ssh/sshd_config"


	if grep -Eq "^\s*PasswordAuthentication\s+no" "$sshd_config"; then
		sed -i -e 's/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin prohibit-password/' \
			   -e 's/^\s*#\?\s*PasswordAuthentication .*/PasswordAuthentication no/' \
			   -e 's/^\s*#\?\s*PubkeyAuthentication .*/PubkeyAuthentication yes/' \
			   -e 's/^\s*#\?\s*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "$sshd_config"
	else
		sed -i -e 's/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin yes/' \
			   -e 's/^\s*#\?\s*PasswordAuthentication .*/PasswordAuthentication yes/' \
			   -e 's/^\s*#\?\s*PubkeyAuthentication .*/PubkeyAuthentication yes/' "$sshd_config"
	fi

	rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
}


new_ssh_port() {

  local new_port=$1

  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

  sed -i '/^\s*#\?\s*Port\s\+/d' /etc/ssh/sshd_config
  sed -i "1i Port $new_port" /etc/ssh/sshd_config

  correct_ssh_config

  restart_ssh || return 1
  open_port "$new_port" || return 1
  remove iptables-persistent ufw firewalld iptables-services > /dev/null 2>&1

  echo "SSH 端口已修改为: $new_port"

  sleep 1

}


kpanel_ssh_port_noninteractive() {
	[ "${KJ_SSH_PORT_NONINTERACTIVE:-}" = "1" ] || return 2
	[ "$EUID" -eq 0 ] || {
		echo "错误: KPanel SSH 端口协议必须以 root 运行"
		return 1
	}
	[ "$#" -eq 1 ] || {
		echo "错误: SSH 端口协议需要一个端口号"
		return 1
	}

	local new_port="$1"
	[[ "$new_port" =~ ^[0-9]{1,5}$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ] || {
		echo "错误: SSH 端口必须为 1-65535"
		return 1
	}
	[ -f /etc/ssh/sshd_config ] && [ ! -L /etc/ssh/sshd_config ] || {
		echo "错误: 未找到可管理的 OpenSSH 配置"
		return 1
	}
	command -v sshd >/dev/null 2>&1 && command -v ss >/dev/null 2>&1 || {
		echo "错误: SSH 配置校验或监听检查工具不可用"
		return 1
	}
	sshd -t || {
		echo "错误: 当前 SSH 配置语法验证失败"
		return 1
	}

	local configured_ports
	configured_ports="$({
		grep -Eh '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null
		grep -Eh '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
	} | awk '{print $2}' | sort -nu)"
	if [ "$configured_ports" = "$new_port" ]; then
		echo "KPANEL_SSH_PORT $new_port"
		echo "KPANEL_SSH_RESULT unchanged"
		return 0
	fi

	# 复用现有 SSH 修改主业务；适配层只负责非交互校验和机器可读结果。
	new_ssh_port "$new_port" || return 1
	if ! grep -Eq "^[[:space:]]*Port[[:space:]]+${new_port}([[:space:]]|$)" /etc/ssh/sshd_config; then
		echo "错误: SSH 端口修改后回读验证失败"
		return 1
	fi
	if ! sshd -t; then
		echo "错误: SSH 配置语法验证失败"
		return 1
	fi
	local listening="false"
	local attempt
	for attempt in {1..10}; do
		if ss -H -ltn 2>/dev/null | awk -v port="${new_port}" '
			{
				address=$4
				sub(/^.*:/, "", address)
				if (address == port) found=1
			}
			END { exit(found ? 0 : 1) }
		'; then
			listening="true"
			break
		fi
		sleep 0.2
	done
	[ "${listening}" = "true" ] || {
		echo "错误: SSH 新端口未进入监听状态"
		return 1
	}

	echo "KPANEL_SSH_PORT $new_port"
	echo "KPANEL_SSH_RESULT applied"
}



sshkey_on() {

	sed -i -e 's/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin prohibit-password/' \
		   -e 's/^\s*#\?\s*PasswordAuthentication .*/PasswordAuthentication no/' \
		   -e 's/^\s*#\?\s*PubkeyAuthentication .*/PubkeyAuthentication yes/' \
		   -e 's/^\s*#\?\s*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
	rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
	restart_ssh
	echo -e "${gl_lv}用户密钥登录模式已开启，已关闭密码登录模式，重连将会生效${gl_bai}"

}



add_sshkey() {
	chmod 700 "${HOME}"
	mkdir -p "${HOME}/.ssh"
	chmod 700 "${HOME}/.ssh"
	touch "${HOME}/.ssh/authorized_keys"

	ssh-keygen -t ed25519 -C "xxxx@gmail.com" -f "${HOME}/.ssh/sshkey" -N ""

	cat "${HOME}/.ssh/sshkey.pub" >> "${HOME}/.ssh/authorized_keys"
	chmod 600 "${HOME}/.ssh/authorized_keys"

	ip_address
	echo -e "私钥信息已生成，务必复制保存，可保存成 ${gl_huang}${ipv4_address}_ssh.key${gl_bai} 文件，用于以后的SSH登录"

	echo "--------------------------------"
	cat "${HOME}/.ssh/sshkey"
	echo "--------------------------------"

	sshkey_on
}





import_sshkey() {

	local public_key="$1"
	local base_dir="${2:-$HOME}"
	local ssh_dir="${base_dir}/.ssh"
	local auth_keys="${ssh_dir}/authorized_keys"

	if [[ -z "$public_key" ]]; then
		read -e -p "请输入您的SSH公钥内容（通常以 'ssh-rsa' 或 'ssh-ed25519' 开头）: " public_key
	fi

	if [[ -z "$public_key" ]]; then
		echo -e "${gl_hong}错误：未输入公钥内容。${gl_bai}"
		return 1
	fi

	if [[ ! "$public_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
		echo -e "${gl_hong}错误：看起来不像合法的 SSH 公钥。${gl_bai}"
		return 1
	fi

	if grep -Fxq "$public_key" "$auth_keys" 2>/dev/null; then
		echo "该公钥已存在，无需重复添加"
		return 0
	fi

	mkdir -p "$ssh_dir"
	chmod 700 "$ssh_dir"
	touch "$auth_keys"
	echo "$public_key" >> "$auth_keys"
	chmod 600 "$auth_keys"

	sshkey_on
}



fetch_remote_ssh_keys() {

	local keys_url="$1"
	local base_dir="${2:-$HOME}"
	local ssh_dir="${base_dir}/.ssh"
	local authorized_keys="${ssh_dir}/authorized_keys"
	local temp_file

	if [[ -z "${keys_url}" ]]; then
		read -e -p "请输入您的远端公钥URL： " keys_url
	fi

	echo "此脚本将从远程 URL 拉取 SSH 公钥，并添加到 ${authorized_keys}"
	echo ""
	echo "远程公钥地址："
	echo "  ${keys_url}"
	echo ""

	# 创建临时文件
	temp_file=$(mktemp)

	# 下载公钥
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 10 "${keys_url}" -o "${temp_file}" || {
			echo "错误：无法从 URL 下载公钥（网络问题或地址无效）" >&2
			rm -f "${temp_file}"
			return 1
		}
	elif command -v wget >/dev/null 2>&1; then
		wget -q --timeout=10 -O "${temp_file}" "${keys_url}" || {
			echo "错误：无法从 URL 下载公钥（网络问题或地址无效）" >&2
			rm -f "${temp_file}"
			return 1
		}
	else
		echo "错误：系统中未找到 curl 或 wget，无法下载公钥" >&2
		rm -f "${temp_file}"
		return 1
	fi

	# 检查内容是否有效
	if [[ ! -s "${temp_file}" ]]; then
		echo "错误：下载到的文件为空，URL 可能不包含任何公钥" >&2
		rm -f "${temp_file}"
		return 1
	fi

	mkdir -p "${ssh_dir}"
	chmod 700 "${ssh_dir}"
	touch "${authorized_keys}"
	chmod 600 "${authorized_keys}"

	# 备份原有 authorized_keys
	if [[ -f "${authorized_keys}" ]]; then
		cp "${authorized_keys}" "${authorized_keys}.bak.$(date +%Y%m%d-%H%M%S)"
		echo "已备份原有 authorized_keys 文件"
	fi

	# 追加公钥（避免重复）
	local added=0
	while IFS= read -r line; do
		[[ -z "${line}" || "${line}" =~ ^# ]] && continue

		if ! grep -Fxq "${line}" "${authorized_keys}" 2>/dev/null; then
			echo "${line}" >> "${authorized_keys}"
			((added++))
		fi
	done < "${temp_file}"

	rm -f "${temp_file}"

	echo ""
	if (( added > 0 )); then
		echo "成功添加 ${added} 条新的公钥到 ${authorized_keys}"
		sshkey_on
	else
		echo "没有新的公钥需要添加（可能已全部存在）"
	fi

	echo ""
}




fetch_github_ssh_keys() {

	local username="$1"
	local base_dir="${2:-$HOME}"

	echo "操作前，请确保您已在 GitHub 账户中添加了 SSH 公钥："
	echo "  1. 登录 ${gh_https_url}github.com/settings/keys"
	echo "  2. 点击 New SSH key 或 Add SSH key"
	echo "  3. Title 可随意填写（例如：Home Laptop 2026）"
	echo "  4. 将本地公钥内容（通常是 ~/.ssh/id_ed25519.pub 或 id_rsa.pub 的全部内容）粘贴到 Key 字段"
	echo "  5. 点击 Add SSH key 完成添加"
	echo ""
	echo "添加完成后，GitHub 会公开提供您的所有公钥，地址为："
	echo "  ${gh_https_url}github.com/您的用户名.keys"
	echo ""


	if [[ -z "${username}" ]]; then
		read -e -p "请输入您的 GitHub 用户名（username，不含 @）： " username
	fi

	if [[ -z "${username}" ]]; then
		echo "错误：GitHub 用户名不能为空" >&2
		return 1
	fi

	keys_url="${gh_https_url}github.com/${username}.keys"

	fetch_remote_ssh_keys "${keys_url}" "${base_dir}"

}


sshkey_panel() {
  root_use
  while true; do
	  clear
	  local REAL_STATUS=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config | tr '[:upper:]' '[:lower:]')
	  if [[ "$REAL_STATUS" =~ "yes" ]]; then
		  IS_KEY_ENABLED="${gl_lv}已启用${gl_bai}"
	  else
	  	  IS_KEY_ENABLED="${gl_hui}未启用${gl_bai}"
	  fi
  	  echo -e "用户密钥登录模式 ${IS_KEY_ENABLED}"
  	  echo "------------------------------------------------"
  	  echo "将会生成密钥对，更安全的方式SSH登录"
	  echo "------------------------"
	  echo "1. 生成新密钥对                  2. 手动输入已有公钥"
	  echo "3. 从GitHub导入已有公钥          4. 从URL导入已有公钥"
	  echo "5. 编辑公钥文件                  6. 查看本机密钥"
	  echo "------------------------"
	  echo "0. 返回上一级选单"
	  echo "------------------------"
	  read -e -p "请输入你的选择: " host_dns
	  case $host_dns in
		  1)
	  		add_sshkey
			break_end
			  ;;
		  2)
			import_sshkey
			break_end
			  ;;
		  3)
			fetch_github_ssh_keys
			break_end
			  ;;
		  4)
			read -e -p "请输入您的远端公钥URL： " keys_url
			fetch_remote_ssh_keys "${keys_url}"
			break_end
			  ;;

		  5)
			install nano
			nano ${HOME}/.ssh/authorized_keys
			break_end
			  ;;

		  6)
			echo "------------------------"
			echo "公钥信息"
			cat ${HOME}/.ssh/authorized_keys
			echo "------------------------"
			echo "私钥信息"
			cat ${HOME}/.ssh/sshkey
			echo "------------------------"
			break_end
			  ;;
		  *)
			  break  # 跳出循环，退出菜单
			  ;;
	  esac
  done


}






add_sshpasswd() {

	root_use
	echo "设置密码登录模式"

	local target_user="$1"

	# 如果没有通过参数传入，则交互输入
	if [[ -z "$target_user" ]]; then
		read -e -p "请输入要修改密码的用户名（默认 root）: " target_user
	fi

	# 回车不输入，默认 root
	target_user=${target_user:-root}

	# 校验用户是否存在
	if ! id "$target_user" >/dev/null 2>&1; then
		echo "错误：用户 $target_user 不存在"
		return 1
	fi

	passwd "$target_user"

	if [[ "$target_user" == "root" ]]; then
		sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
	fi

	sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
	rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*

	restart_ssh

	echo -e "${gl_lv}密码设置完毕，已更改为密码登录模式！${gl_bai}"
}














root_use() {
clear
[ "$EUID" -ne 0 ] && echo -e "${gl_huang}提示: ${gl_bai}该功能需要root用户才能运行！" && break_end && kejilion
}












dd_xitong() {
		dd_xitong_MollyLau() {
			wget --no-check-certificate -qO InstallNET.sh "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" && chmod a+x InstallNET.sh

		}

		dd_xitong_bin456789() {
			curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
		}

		dd_xitong_1() {
		  echo -e "重装后初始用户名: ${gl_huang}root${gl_bai}  初始密码: ${gl_huang}LeitboGi0ro${gl_bai}  初始端口: ${gl_huang}22${gl_bai}"
		  echo -e "${gl_huang}重装后请及时修改初始密码，防止暴力入侵。命令行输入passwd修改密码${gl_bai}"
		  echo -e "按任意键继续..."
		  read -n 1 -s -r -p ""
		  install wget
		  dd_xitong_MollyLau
		}

		dd_xitong_2() {
		  echo -e "重装后初始用户名: ${gl_huang}Administrator${gl_bai}  初始密码: ${gl_huang}Teddysun.com${gl_bai}  初始端口: ${gl_huang}3389${gl_bai}"
		  echo -e "按任意键继续..."
		  read -n 1 -s -r -p ""
		  install wget
		  dd_xitong_MollyLau
		}

		dd_xitong_3() {
		  echo -e "重装后初始用户名: ${gl_huang}root${gl_bai}  初始密码: ${gl_huang}123@@@${gl_bai}  初始端口: ${gl_huang}22${gl_bai}"
		  echo -e "按任意键继续..."
		  read -n 1 -s -r -p ""
		  dd_xitong_bin456789
		}

		dd_xitong_4() {
		  echo -e "重装后初始用户名: ${gl_huang}Administrator${gl_bai}  初始密码: ${gl_huang}123@@@${gl_bai}  初始端口: ${gl_huang}3389${gl_bai}"
		  echo -e "按任意键继续..."
		  read -n 1 -s -r -p ""
		  dd_xitong_bin456789
		}

		  while true; do
			root_use
			echo "重装系统"
			echo "--------------------------------"
			echo -e "${gl_hong}注意: ${gl_bai}重装有风险失联，不放心者慎用。重装预计花费15分钟，请提前备份数据。"
			echo -e "${gl_hui}感谢bin456789大佬和leitbogioro大佬的脚本支持！${gl_bai} "
			echo -e "${gl_hui}bin456789项目地址: ${gh_https_url}github.com/bin456789/reinstall${gl_bai}"
			echo -e "${gl_hui}leitbogioro项目地址: ${gh_https_url}github.com/leitbogioro/Tools${gl_bai}"
			echo "------------------------"
			echo "1. Debian 13                  2. Debian 12"
			echo "3. Debian 11                  4. Debian 10"
			echo "------------------------"
			echo "11. Ubuntu 26.04              12. Ubuntu 24.04"
			echo "13. Ubuntu 22.04              14. Ubuntu 20.04"
			echo "------------------------"
			echo "21. Rocky Linux 10            22. Rocky Linux 9"
			echo "23. Alma Linux 10             24. Alma Linux 9"
			echo "25. oracle Linux 10           26. oracle Linux 9"
			echo "27. Fedora Linux 44           28. Fedora Linux 43"
			echo "29. CentOS 10                 30. CentOS 9"
			echo "------------------------"
			echo "31. Alpine Linux              32. Arch Linux"
			echo "33. Kali Linux                34. openEuler"
			echo "35. openSUSE Tumbleweed       36. fnos飞牛公测版"
			echo "------------------------"
			echo "41. Windows 11                42. Windows 10"
			echo "43. Windows 7                 44. Windows Server 2025"
			echo "45. Windows Server 2022       46. Windows Server 2019"
			echo "47. Windows 11 ARM"
			echo "------------------------"
			echo "0. 返回上一级选单"
			echo "------------------------"
			read -e -p "请选择要重装的系统: " sys_choice
			case "$sys_choice" in


			  1)
				dd_xitong_3
				bash reinstall.sh debian 13
				reboot
				exit
				;;

			  2)
				dd_xitong_3
				bash reinstall.sh debian 12
				reboot
				exit
				;;
			  3)
				dd_xitong_3
				bash reinstall.sh debian 11
				reboot
				exit
				;;
			  4)
				dd_xitong_3
				bash reinstall.sh debian 10
				reboot
				exit
				;;
			  11)
				dd_xitong_3
				bash reinstall.sh ubuntu 26.04
				reboot
				exit
				;;
			  12)
				dd_xitong_3
				bash reinstall.sh ubuntu 24.04
				reboot
				exit
				;;
			  13)
				dd_xitong_3
				bash reinstall.sh ubuntu 22.04
				reboot
				exit
				;;
			  14)
				dd_xitong_3
				bash reinstall.sh ubuntu 20.04
				reboot
				exit
				;;

			  21)
				dd_xitong_3
				bash reinstall.sh rocky
				reboot
				exit
				;;

			  22)
				dd_xitong_3
				bash reinstall.sh rocky 9
				reboot
				exit
				;;

			  23)
				dd_xitong_3
				bash reinstall.sh almalinux
				reboot
				exit
				;;

			  24)
				dd_xitong_3
				bash reinstall.sh almalinux 9
				reboot
				exit
				;;

			  25)
				dd_xitong_3
				bash reinstall.sh oracle
				reboot
				exit
				;;

			  26)
				dd_xitong_3
				bash reinstall.sh oracle 9
				reboot
				exit
				;;

			  27)
				dd_xitong_3
				bash reinstall.sh fedora 44
				reboot
				exit
				;;

			  28)
				dd_xitong_3
				bash reinstall.sh fedora 43
				reboot
				exit
				;;

			  29)
				dd_xitong_3
				bash reinstall.sh centos 10
				reboot
				exit
				;;

			  30)
				dd_xitong_3
				bash reinstall.sh centos 9
				reboot
				exit
				;;

			  31)
				dd_xitong_1
				bash InstallNET.sh -alpine
				reboot
				exit
				;;

			  32)
				dd_xitong_3
				bash reinstall.sh arch
				reboot
				exit
				;;

			  33)
				dd_xitong_3
				bash reinstall.sh kali
				reboot
				exit
				;;

			  34)
				dd_xitong_3
				bash reinstall.sh openeuler
				reboot
				exit
				;;

			  35)
				dd_xitong_3
				bash reinstall.sh opensuse
				reboot
				exit
				;;

			  36)
				dd_xitong_3
				bash reinstall.sh fnos
				reboot
				exit
				;;

			  41)
				dd_xitong_2
				bash InstallNET.sh -windows 11 -lang "cn"
				reboot
				exit
				;;

			  42)
				dd_xitong_2
				bash InstallNET.sh -windows 10 -lang "cn"
				reboot
				exit
				;;

			  43)
				dd_xitong_4
				bash reinstall.sh windows --iso="https://archive.org/download/en_windows_7_professional_with_sp1_x64_dvd_u_676939_201906/en_windows_7_professional_with_sp1_x64_dvd_u_676939.iso" --image-name='windows 7 professional'
				reboot
				exit
				;;

			  44)
				dd_xitong_2
				bash InstallNET.sh -windows 2025 -lang "cn"
				reboot
				exit
				;;

			  45)
				dd_xitong_2
				bash InstallNET.sh -windows 2022 -lang "cn"
				reboot
				exit
				;;

			  46)
				dd_xitong_2
				bash InstallNET.sh -windows 2019 -lang "cn"
				reboot
				exit
				;;

			  47)
				dd_xitong_4
				bash reinstall.sh dd --img https://r2.hotdog.eu.org/win11-arm-with-pagefile-15g.xz
				reboot
				exit
				;;

			  *)
				break
				;;
			esac
		  done
}


kpanel_bbrv3_status() {
	local architecture os_id codename running_kernel installed_kernel installed=false active=false supported=false
	local congestion qdisc reboot_required=false reason=""
	architecture=$(uname -m 2>/dev/null | tr -cd 'A-Za-z0-9._-')
	running_kernel=$(uname -r 2>/dev/null | tr -cd 'A-Za-z0-9+._-')
	os_id=""
	codename=""
	if [ -r /etc/os-release ]; then
		os_id=$(. /etc/os-release && printf '%s' "${ID:-}" | tr -cd 'A-Za-z0-9._-')
		codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}" | tr -cd 'A-Za-z0-9._-')
	fi
	if command -v lsb_release >/dev/null 2>&1; then
		codename=$(lsb_release -sc 2>/dev/null | tr -cd 'A-Za-z0-9._-')
	fi
	installed_kernel=$(
		for module_dir in /lib/modules/*xanmod*; do
			[ -d "$module_dir" ] && basename "$module_dir"
		done 2>/dev/null | sort -V | tail -n 1 | tr -cd 'A-Za-z0-9+._-'
	)
	congestion=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null | tr -cd 'A-Za-z0-9._-')
	qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null | tr -cd 'A-Za-z0-9._-')
	xanmod_installed && installed=true
	if printf '%s' "$running_kernel" | grep -qi 'xanmod' &&
		[ "$congestion" = "bbr" ] && [ "$qdisc" = "fq" ]; then
		active=true
	fi
	if { [ "$architecture" = "x86_64" ] || [ "$architecture" = "amd64" ]; } &&
		{ [ "$os_id" = "debian" ] || [ "$os_id" = "ubuntu" ]; } &&
		command -v apt >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1; then
		case "$codename" in
			bookworm|trixie|forky|sid|noble|plucky|questing|resolute)
				supported=true
				;;
			*)
				reason="unsupported_release"
				;;
		esac
	elif [ "$architecture" = "aarch64" ] || [ "$architecture" = "arm64" ]; then
		reason="arm64_external_installer_untrusted"
	elif [ "$os_id" != "debian" ] && [ "$os_id" != "ubuntu" ]; then
		reason="unsupported_distribution"
	else
		reason="missing_dependencies"
	fi
	if { [ "$installed" = "true" ] && [ -n "$installed_kernel" ] &&
			[ "$running_kernel" != "$installed_kernel" ]; } ||
		{ [ "$installed" = "false" ] && printf '%s' "$running_kernel" | grep -qi 'xanmod'; } ||
		[ -f /var/run/reboot-required ]; then
		reboot_required=true
	fi
	printf 'KPANEL_BBRV3_STATUS {"supported":%s,"installed":%s,"active":%s,"architecture":"%s","os":"%s","codename":"%s","runningKernel":"%s","installedKernel":"%s","congestionControl":"%s","defaultQDisc":"%s","rebootRequired":%s,"reason":"%s"}\n' \
		"$supported" "$installed" "$active" "$architecture" "$os_id" "$codename" \
		"$running_kernel" "$installed_kernel" "$congestion" "$qdisc" "$reboot_required" "$reason"
}

kpanel_bbrv3_dispatch() {
	local command="${1:-status}" changed=false status_line reboot_required=false
	printf '%s\n' "KPANEL_BBRV3_PROTOCOL 1"
	case "$command" in
		status)
			kpanel_bbrv3_status
			;;
		install|update|uninstall)
			root_use
			status_line=$(kpanel_bbrv3_status)
			if ! printf '%s' "$status_line" | grep -q '"supported":true' &&
				{ [ "$command" != "uninstall" ] ||
				  ! printf '%s' "$status_line" | grep -q '"installed":true'; }; then
				printf '%s\n' "$status_line"
				echo "当前主机不支持 KPanel BBRv3 受控执行" >&2
				return 1
			fi
			case "$command" in
				install)
					if xanmod_installed; then
						printf '%s' "$status_line" | grep -q '"rebootRequired":true' &&
							reboot_required=true
						printf 'KPANEL_BBRV3_RESULT {"action":"install","changed":false,"rebootRequired":%s}\n' \
							"$reboot_required"
						printf '%s\n' "$status_line"
						return 0
					fi
					xanmod_install_or_update install || return 1
					changed=true
					;;
				update)
					xanmod_installed || {
						echo "尚未安装 XanMod BBRv3 内核，不能执行更新" >&2
						return 1
					}
					xanmod_install_or_update update || return 1
					changed=true
					;;
				uninstall)
					if ! xanmod_installed; then
						printf '%s' "$status_line" | grep -q '"rebootRequired":true' &&
							reboot_required=true
						printf 'KPANEL_BBRV3_RESULT {"action":"uninstall","changed":false,"rebootRequired":%s}\n' \
							"$reboot_required"
						printf '%s\n' "$status_line"
						return 0
					fi
					xanmod_uninstall || return 1
					changed=true
					;;
			esac
			status_line=$(kpanel_bbrv3_status)
			printf '%s' "$status_line" | grep -q '"rebootRequired":true' &&
				reboot_required=true
			printf 'KPANEL_BBRV3_RESULT {"action":"%s","changed":%s,"rebootRequired":%s}\n' \
				"$command" "$changed" "$reboot_required"
			printf '%s\n' "$status_line"
			;;
		*)
			echo "用法: k bbrv3 [status|install|update|uninstall]" >&2
			return 2
			;;
	esac
}

bbrv3() {
		  if [ "${KJ_BBRV3_NONINTERACTIVE:-}" != "1" ]; then
			  root_use
		  fi

		  xanmod_add_repo() {
				local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
				local list_file="/etc/apt/sources.list.d/xanmod-release.list"
				local key_url="https://dl.xanmod.org/archive.key"
				local fallback_key_url="https://raw.githubusercontent.com/howi3c/sh/main/archive.key"
				local os_codename=""

				if command -v lsb_release >/dev/null 2>&1; then
					os_codename=$(lsb_release -sc)
				elif [ -r /etc/os-release ]; then
					os_codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
				fi

				# 兼容官方已移除的老系统代号（回退使用 releases 尝试旧包库）
				if ! echo "bookworm trixie forky sid noble plucky questing resolute faye gigi wilma xia zara zena" | grep -qw "$os_codename"; then
					os_codename="releases"
				fi

				# 官方已彻底移除对 jammy, focal, bullseye 等老系统的 apt 支持
				if echo "jammy focal bullseye buster" | grep -qw "$os_codename" || [ "$os_codename" = "releases" ]; then
					echo -e "${gl_hong}XanMod 官方已停止对当前系统($os_codename)的 APT 源支持，请升级至 Debian12 / Ubuntu24 或更高版本。${gl_bai}"
					return 1
				fi

				if [ -z "$os_codename" ]; then
					echo "无法获取系统代号，无法配置XanMod源"
					return 1
				fi

				install wget gnupg ca-certificates
				mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
				if ! wget -qO - "$key_url" | gpg --dearmor -o "$keyring" --yes; then
					echo "官方密钥下载失败，尝试备用下载源..."
					wget -qO - "$fallback_key_url" | gpg --dearmor -o "$keyring" --yes || return 1
				fi
				chmod 644 "$keyring"
				echo "deb [signed-by=$keyring] http://deb.xanmod.org $os_codename main" > "$list_file"
		  }

		  xanmod_detect_psabi_level() {
				local psabi_output=""
				psabi_output=$(awk 'BEGIN {
					while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
					if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
					if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
					if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
					if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
					if (level > 0) { print level; exit }
					exit 1
				}' /proc/cpuinfo 2>/dev/null) || return 1
				printf '%s' "$psabi_output" | tr -dc '0-9' | head -c 1
		  }

		  xanmod_package_available() {
				local package="$1"
				apt-cache policy "$package" 2>/dev/null | grep -q 'Candidate: [^ ]'
		  }

		  xanmod_detect_package() {
				local psabi_level=""
				local level=""
				local package=""
				local prefix_list="linux-xanmod linux-xanmod-lts"

				psabi_level=$(xanmod_detect_psabi_level) || return 1
				[ -n "$psabi_level" ] || return 1
				[ "$psabi_level" -gt 3 ] && psabi_level=3

				apt update -y >/dev/null 2>&1

				for prefix in $prefix_list; do
					level="$psabi_level"
					while [ "$level" -ge 1 ]; do
						package="${prefix}-x64v${level}"
						if xanmod_package_available "$package"; then
							if [ "$level" != "$psabi_level" ] || [ "$prefix" = "linux-xanmod-lts" ]; then
								echo "已自动匹配合适安装包: $package" >&2
							fi
							printf '%s\n' "$package"
							return 0
						fi
						level=$((level - 1))
					done
				done

				echo "软件源中未找到适配此CPU的XanMod内核包" >&2
				return 1
		  }

		  xanmod_installed() {
				dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep -q '^linux-.*xanmod'
		  }

		  xanmod_install_or_update() {
				local action="$1"
				local package=""

				check_disk_space 3
				check_swap
				xanmod_add_repo || {
					echo "XanMod官方仓库配置失败，请稍后重试"
					return 1
				}

				package=$(xanmod_detect_package) || {
					echo "无法识别当前CPU或找不到匹配内核包，已取消安装"
					return 1
				}

				apt update -y
				if [ "$action" = "update" ]; then
					apt install -y --only-upgrade "$package" || apt install -y "$package" || {
						echo "XanMod内核更新失败，请检查软件源或稍后重试"
						return 1
					}
				else
					apt install -y "$package" || {
						echo "XanMod内核安装失败，请检查软件源或稍后重试"
						return 1
					}
				fi

				bbr_on || {
					echo "BBR3参数写入失败，请检查系统配置"
					return 1
				}
				echo "XanMod BBRv3内核处理完成。重启后生效"
				[ "${KJ_BBRV3_NONINTERACTIVE:-}" = "1" ] || server_reboot
		  }

		  xanmod_uninstall() {
				apt purge -y 'linux-*xanmod*'
				apt autoremove -y
				update-grub 2>/dev/null || true
				rm -f /etc/apt/sources.list.d/xanmod-release.list
				rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
				echo "XanMod内核已卸载。重启后生效"
				[ "${KJ_BBRV3_NONINTERACTIVE:-}" = "1" ] || server_reboot
		  }

		  if [ "${KJ_BBRV3_NONINTERACTIVE:-}" = "1" ]; then
			  kpanel_bbrv3_dispatch "$@"
			  return
		  fi

		  local cpu_arch=$(uname -m)
		  if [ "$cpu_arch" = "aarch64" ]; then
			bash <(curl -sL jhb.ovh/jb/bbrv3arm.sh)
			break_end
			linux_Settings
		  fi

		  if [ -r /etc/os-release ]; then
			. /etc/os-release
			if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
				echo "当前环境不支持，仅支持Debian和Ubuntu系统"
				break_end
				linux_Settings
			fi
		  else
			echo "无法确定操作系统类型"
			break_end
			linux_Settings
		  fi

		  if xanmod_installed; then
			while true; do
				  clear
				  local kernel_version=$(uname -r)
				  echo "您已安装xanmod的BBRv3内核"
				  echo "当前内核版本: $kernel_version"

				  echo ""
				  echo "内核管理"
				  echo "------------------------"
				  echo "1. 更新BBRv3内核              2. 卸载BBRv3内核"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
						xanmod_install_or_update update
						;;
					  2)
						xanmod_uninstall
						;;
					  *)
						break
						;;

				  esac
			done
		else

		  clear
		  echo "设置BBR3加速"
		  echo "视频介绍: https://www.bilibili.com/video/BV14K421x7BS?t=0.1"
		  echo "------------------------------------------------"
		  echo "仅支持Debian/Ubuntu"
		  echo "请备份数据，将为你升级Linux内核开启BBR3"
		  echo "------------------------------------------------"
		  read -e -p "确定继续吗？(Y/N): " choice

		  case "$choice" in
			[Yy])
			xanmod_install_or_update install
			  ;;
			[Nn])
			  echo "已取消"
			  ;;
			*)
			  echo "无效的选择，请输入 Y 或 N。"
			  ;;
		  esac
		fi

}

elrepo_install() {
	# 导入 ELRepo GPG 公钥
	echo "导入 ELRepo GPG 公钥..."
	rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
	# 检测系统版本
	local os_version=$(rpm -q --qf "%{VERSION}" $(rpm -qf /etc/os-release) 2>/dev/null | awk -F '.' '{print $1}')
	local os_name=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
	# 确保我们在一个支持的操作系统上运行
	if [[ "$os_name" != *"Red Hat"* && "$os_name" != *"AlmaLinux"* && "$os_name" != *"Rocky"* && "$os_name" != *"Oracle"* && "$os_name" != *"CentOS"* ]]; then
		echo "不支持的操作系统：$os_name"
		break_end
		linux_Settings
	fi
	# 打印检测到的操作系统信息
	echo "检测到的操作系统: $os_name $os_version"
	# 根据系统版本安装对应的 ELRepo 仓库配置
	if [[ "$os_version" == 8 ]]; then
		echo "安装 ELRepo 仓库配置 (版本 8)..."
		yum -y install https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
	elif [[ "$os_version" == 9 ]]; then
		echo "安装 ELRepo 仓库配置 (版本 9)..."
		yum -y install https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
	elif [[ "$os_version" == 10 ]]; then
		echo "安装 ELRepo 仓库配置 (版本 10)..."
		yum -y install https://www.elrepo.org/elrepo-release-10.el10.elrepo.noarch.rpm
	else
		echo "不支持的系统版本：$os_version"
		break_end
		linux_Settings
	fi
	# 启用 ELRepo 内核仓库并安装最新的主线内核
	echo "启用 ELRepo 内核仓库并安装最新的主线内核..."
	# yum -y --enablerepo=elrepo-kernel install kernel-ml
	yum --nogpgcheck -y --enablerepo=elrepo-kernel install kernel-ml
	echo "已安装 ELRepo 仓库配置并更新到最新主线内核。"
	server_reboot

}


elrepo() {
		  root_use
		  if uname -r | grep -q 'elrepo'; then
			while true; do
				  clear
				  kernel_version=$(uname -r)
				  echo "您已安装elrepo内核"
				  echo "当前内核版本: $kernel_version"

				  echo ""
				  echo "内核管理"
				  echo "------------------------"
				  echo "1. 更新elrepo内核              2. 卸载elrepo内核"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
						dnf remove -y elrepo-release
						rpm -qa | grep elrepo | grep kernel | xargs rpm -e --nodeps
						elrepo_install
						server_reboot

						  ;;
					  2)
						dnf remove -y elrepo-release
						rpm -qa | grep elrepo | grep kernel | xargs rpm -e --nodeps
						echo "elrepo内核已卸载。重启后生效"
						server_reboot

						  ;;
					  *)
						  break  # 跳出循环，退出菜单
						  ;;

				  esac
			done
		else

		  clear
		  echo "请备份数据，将为你升级Linux内核"
		  echo "视频介绍: https://www.bilibili.com/video/BV1mH4y1w7qA?t=529.2"
		  echo "------------------------------------------------"
		  echo "仅支持红帽系列发行版 CentOS/RedHat/Alma/Rocky/oracle "
		  echo "升级Linux内核可提升系统性能和安全，建议有条件的尝试，生产环境谨慎升级！"
		  echo "------------------------------------------------"
		  read -e -p "确定继续吗？(Y/N): " choice

		  case "$choice" in
			[Yy])
			  check_swap
			  elrepo_install
			  server_reboot
			  ;;
			[Nn])
			  echo "已取消"
			  ;;
			*)
			  echo "无效的选择，请输入 Y 或 N。"
			  ;;
		  esac
		fi

}




KPANEL_VIRUS_SCAN_PROTOCOL_VERSION="1"

kpanel_virus_scan_emit() {
	local status="$1" mode="${2:-}" report="/home/docker/clamav/log/scan.log"
	local scanned=0 infected=0 errors=0
	if [ -f "$report" ] && [ ! -L "$report" ]; then
		scanned="$(awk -F: '/^Scanned files:/ { gsub(/^[[:space:]]+/, "", $2); value=$2 } END { print value+0 }' "$report" 2>/dev/null)"
		infected="$(awk -F: '/^Infected files:/ { gsub(/^[[:space:]]+/, "", $2); value=$2 } END { print value+0 }' "$report" 2>/dev/null)"
		errors="$(awk -F: '/^Total errors:/ { gsub(/^[[:space:]]+/, "", $2); value=$2 } END { print value+0 }' "$report" 2>/dev/null)"
	fi
	printf '%s\n' \
		"KPANEL_VIRUS_SCAN_PROTOCOL $KPANEL_VIRUS_SCAN_PROTOCOL_VERSION" \
		"KPANEL_VIRUS_SCAN_STATUS=$status" \
		"KPANEL_VIRUS_SCAN_MODE=$mode" \
		"KPANEL_VIRUS_SCAN_SCANNED=$scanned" \
		"KPANEL_VIRUS_SCAN_INFECTED=$infected" \
		"KPANEL_VIRUS_SCAN_ERRORS=$errors" \
		"KPANEL_VIRUS_SCAN_REPORT=$report"
}

kpanel_virus_scan_prepare_log() {
	local root="/home/docker/clamav" log_dir
	log_dir="$root/log"
	[ ! -L "$root" ] && { [ ! -e "$root" ] || [ -d "$root" ]; } || return 1
	[ ! -L "$log_dir" ] && { [ ! -e "$log_dir" ] || [ -d "$log_dir" ]; } || return 1
	install -d -m 700 "$log_dir" || return 1
	[ ! -L "$log_dir/scan.log" ] && { [ ! -e "$log_dir/scan.log" ] || [ -f "$log_dir/scan.log" ]; } || return 1
	: > "$log_dir/scan.log" || return 1
	chmod 600 "$log_dir/scan.log" || return 1
}

clamav_freshclam() {
	echo -e "${gl_kjlan}正在更新病毒库...${gl_bai}"
	docker run --rm \
		--name clamav \
		--mount source=clam_db,target=/var/lib/clamav \
		clamav/clamav-debian:latest \
		freshclam
}

kpanel_virus_scan_update_db() {
	docker volume create clam_db >/dev/null || return 1
	docker run --rm \
		--name "kpanel-clamav-update-$$" \
		--mount source=clam_db,target=/var/lib/clamav,volume-nocopy \
		--security-opt no-new-privileges \
		--cap-drop ALL \
		--cap-add SETUID \
		--cap-add SETGID \
		--pids-limit 256 \
		--tmpfs /var/log/clamav:rw,noexec,nosuid,nodev,size=16m,mode=0750 \
		--entrypoint freshclam \
		clamav/clamav-debian:latest \
		--user root
}

kpanel_virus_scan_valid_path() {
	local path="$1"
	[[ "$path" == /* ]] || return 1
	[[ "$path" != *','* && "$path" != *[[:cntrl:]]* ]] || return 1
	if [ "$path" != / ]; then
		[[ "$path" != */ && "$path" != *'//'* && "$path" != *'/./'* && "$path" != *'/../'* && "$path" != */. && "$path" != */.. ]] || return 1
	fi
	[ -d "$path" ]
}

kpanel_virus_scan_run() {
	local mode="$1" rc status index=0 path
	shift
	local -a paths=() mounts=() targets=()
	local -A seen_paths=()
	case "$mode" in
		full) [ "$#" -eq 0 ] || return 2; paths=(/) ;;
		important) [ "$#" -eq 0 ] || return 2; paths=(/etc /var /usr /home /root) ;;
		custom) [ "$#" -ge 1 ] && [ "$#" -le 8 ] || return 2; paths=("$@") ;;
		*) return 2 ;;
	esac
	for path in "${paths[@]}"; do
		kpanel_virus_scan_valid_path "$path" || return 2
		[ -z "${seen_paths[$path]:-}" ] || return 2
		seen_paths["$path"]=1
		mounts+=(--mount "type=bind,source=$path,target=/mnt/scan/$index,readonly")
		targets+=("/mnt/scan/$index")
		index=$((index + 1))
	done
	kpanel_virus_scan_prepare_log || return 1
	docker volume create clam_db >/dev/null || return 1
	docker run --rm \
		--name "kpanel-clamav-scan-$$" \
		--network none \
		--read-only \
		--security-opt no-new-privileges \
		--cap-drop ALL \
		--pids-limit 256 \
		--mount source=clam_db,target=/var/lib/clamav,readonly \
		"${mounts[@]}" \
		--mount type=bind,source=/home/docker/clamav/log,target=/var/log/clamav \
		--tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
		--entrypoint clamscan \
		clamav/clamav-debian:latest \
		-r --infected --log=/var/log/clamav/scan.log "${targets[@]}"
	rc=$?
	case "$rc" in
		0) status=clean ;;
		1) status=infected ;;
		*) kpanel_virus_scan_emit failed "$mode"; return "$rc" ;;
	esac
	kpanel_virus_scan_emit "$status" "$mode"
}

kpanel_virus_scan_dispatch() {
	local action="${1:-probe}" lock_file
	shift || true
	[ "${KJ_VIRUS_SCAN_NONINTERACTIVE:-}" = "1" ] || { echo "KPanel virus-scan 协议环境未启用" >&2; return 2; }
	[ "$EUID" -eq 0 ] || { echo "KPanel virus-scan 协议必须以 root 运行" >&2; return 1; }
	[ "$(uname -s)" = Linux ] || { echo "KPanel virus-scan 协议仅支持 Linux" >&2; return 1; }
	command -v docker >/dev/null 2>&1 || { echo "Docker 不可用" >&2; return 1; }
	case "$action" in
		probe) [ "$#" -eq 0 ] || return 2; kpanel_virus_scan_emit ready; return 0 ;;
		update-db) [ "$#" -eq 0 ] || return 2 ;;
		scan) [ "$#" -ge 1 ] || return 2 ;;
		*) echo "用法: k kpanel virus-scan <probe|update-db|scan mode [paths...]>" >&2; return 2 ;;
	esac
	lock_file="/var/lock/kejilion-virus-scan.lock"
	install -d -m 755 /var/lock || return 1
	[ ! -L "$lock_file" ] || return 1
	exec 9>"$lock_file" || return 1
	flock -w 5 9 || { echo "病毒扫描任务正在运行" >&2; return 2; }
	if [ "$action" = update-db ]; then
		if kpanel_virus_scan_update_db; then kpanel_virus_scan_emit updated; else kpanel_virus_scan_emit failed; return 1; fi
	else
		kpanel_virus_scan_run "$@"
	fi
}

clamav_scan() {
	if [ $# -eq 0 ]; then
		echo "请指定要扫描的目录。"
		return
	fi

	echo -e "${gl_kjlan}正在扫描目录$@... ${gl_bai}"

	# 构建 mount 参数
	local MOUNT_PARAMS=""
	for dir in "$@"; do
		MOUNT_PARAMS+="--mount type=bind,source=${dir},target=/mnt/host${dir} "
	done

	# 构建 clamscan 命令参数
	local SCAN_PARAMS=""
	for dir in "$@"; do
		SCAN_PARAMS+="/mnt/host${dir} "
	done

	mkdir -p /home/docker/clamav/log/ > /dev/null 2>&1
	> /home/docker/clamav/log/scan.log > /dev/null 2>&1

	# 执行 Docker 命令
	docker run --rm \
		--name clamav \
		--mount source=clam_db,target=/var/lib/clamav \
		$MOUNT_PARAMS \
		-v /home/docker/clamav/log/:/var/log/clamav/ \
		clamav/clamav-debian:latest \
		clamscan -r --log=/var/log/clamav/scan.log $SCAN_PARAMS

	echo -e "${gl_lv}$@ 扫描完成，病毒报告存放在${gl_huang}/home/docker/clamav/log/scan.log${gl_bai}"
	echo -e "${gl_lv}如果有病毒请在${gl_huang}scan.log${gl_lv}文件中搜索FOUND关键字确认病毒位置 ${gl_bai}"

}







clamav() {
		  root_use
		  while true; do
				clear
				echo "clamav病毒扫描工具"
				echo "视频介绍: https://www.bilibili.com/video/BV1TqvZe4EQm?t=0.1"
				echo "------------------------"
				echo "是一个开源的防病毒软件工具，主要用于检测和删除各种类型的恶意软件。"
				echo "包括病毒、特洛伊木马、间谍软件、恶意脚本和其他有害软件。"
				echo "------------------------"
				echo -e "${gl_lv}1. 全盘扫描 ${gl_bai}             ${gl_huang}2. 重要目录扫描 ${gl_bai}            ${gl_kjlan} 3. 自定义目录扫描 ${gl_bai}"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "请输入你的选择: " sub_choice
				case $sub_choice in
					1)
					  install_docker
					  docker volume create clam_db > /dev/null 2>&1
					  clamav_freshclam
					  clamav_scan /
					  break_end

						;;
					2)
					  install_docker
					  docker volume create clam_db > /dev/null 2>&1
					  clamav_freshclam
					  clamav_scan /etc /var /usr /home /root
					  break_end
						;;
					3)
					  read -e -p "请输入要扫描的目录，用空格分隔（例如：/etc /var /usr /home /root）: " directories
					  install_docker
					  clamav_freshclam
					  clamav_scan $directories
					  break_end
						;;
					*)
					  break  # 跳出循环，退出菜单
						;;
				esac
		  done

}


# ============================================================================
# Linux 内核调优模块（重构版）
# 统一核心函数 + 场景差异化参数 + 持久化到配置文件 + 硬件自适应
# 替换原 optimize_high_performance / optimize_balanced / optimize_web_server
# ============================================================================

# 获取内存大小（MB）
_get_mem_mb() {
	awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo
}

# 统一内核调优核心函数
# 参数: $1 = 模式名称, $2 = 场景 (high/balanced/web/stream/game)
_kernel_optimize_core() {
	local mode_name="$1"
	local scene="${2:-high}"
	local CONF="/etc/sysctl.d/99-kejilion-optimize.conf"
	local MEM_MB=$(_get_mem_mb)

	echo -e "${gl_lv}切换到${mode_name}...${gl_bai}"

	# ── 根据场景设定参数 ──
	local SWAPPINESS DIRTY_RATIO DIRTY_BG_RATIO OVERCOMMIT MIN_FREE_KB VFS_PRESSURE
	local RMEM_MAX WMEM_MAX TCP_RMEM TCP_WMEM
	local SOMAXCONN BACKLOG SYN_BACKLOG
	local PORT_RANGE SCHED_AUTOGROUP THP NUMA FIN_TIMEOUT
	local KEEPALIVE_TIME KEEPALIVE_INTVL KEEPALIVE_PROBES

	case "$scene" in
		high|stream|game)
			# 高性能/直播/游戏：激进参数
			SWAPPINESS=10
			DIRTY_RATIO=15
			DIRTY_BG_RATIO=5
			OVERCOMMIT=1
			VFS_PRESSURE=50
			RMEM_MAX=67108864
			WMEM_MAX=67108864
			TCP_RMEM="4096 262144 67108864"
			TCP_WMEM="4096 262144 67108864"
			SOMAXCONN=8192
			BACKLOG=250000
			SYN_BACKLOG=8192
			PORT_RANGE="1024 65535"
			SCHED_AUTOGROUP=0
			THP="never"
			NUMA=0
			FIN_TIMEOUT=10
			KEEPALIVE_TIME=300
			KEEPALIVE_INTVL=30
			KEEPALIVE_PROBES=5
			;;
		web)
			# 网站服务器：高并发优先
			SWAPPINESS=10
			DIRTY_RATIO=20
			DIRTY_BG_RATIO=10
			OVERCOMMIT=1
			VFS_PRESSURE=50
			RMEM_MAX=33554432
			WMEM_MAX=33554432
			TCP_RMEM="4096 131072 33554432"
			TCP_WMEM="4096 131072 33554432"
			SOMAXCONN=16384
			BACKLOG=10000
			SYN_BACKLOG=16384
			PORT_RANGE="1024 65535"
			SCHED_AUTOGROUP=0
			THP="never"
			NUMA=0
			FIN_TIMEOUT=15
			KEEPALIVE_TIME=600
			KEEPALIVE_INTVL=60
			KEEPALIVE_PROBES=5
			;;
		balanced)
			# 均衡模式：适度优化
			SWAPPINESS=30
			DIRTY_RATIO=20
			DIRTY_BG_RATIO=10
			OVERCOMMIT=0
			VFS_PRESSURE=75
			RMEM_MAX=16777216
			WMEM_MAX=16777216
			TCP_RMEM="4096 87380 16777216"
			TCP_WMEM="4096 65536 16777216"
			SOMAXCONN=4096
			BACKLOG=5000
			SYN_BACKLOG=4096
			PORT_RANGE="1024 49151"
			SCHED_AUTOGROUP=1
			THP="always"
			NUMA=1
			FIN_TIMEOUT=30
			KEEPALIVE_TIME=600
			KEEPALIVE_INTVL=60
			KEEPALIVE_PROBES=5
			;;
	esac

	# ── 根据内存大小自适应调整 ──
	if [ "$MEM_MB" -ge 16384 ]; then
		MIN_FREE_KB=131072
		[ "$scene" != "balanced" ] && SWAPPINESS=5
	elif [ "$MEM_MB" -ge 4096 ]; then
		MIN_FREE_KB=65536
	elif [ "$MEM_MB" -ge 1024 ]; then
		MIN_FREE_KB=32768
		# 小内存缩小缓冲区
		if [ "$scene" != "balanced" ]; then
			RMEM_MAX=16777216
			WMEM_MAX=16777216
			TCP_RMEM="4096 87380 16777216"
			TCP_WMEM="4096 65536 16777216"
		fi
	else
		MIN_FREE_KB=16384
		SWAPPINESS=30
		OVERCOMMIT=0
		RMEM_MAX=4194304
		WMEM_MAX=4194304
		TCP_RMEM="4096 32768 4194304"
		TCP_WMEM="4096 32768 4194304"
		SOMAXCONN=1024
		BACKLOG=1000
	fi

	# ── 直播场景额外：UDP 缓冲区加大 ──
	local STREAM_EXTRA=""
	if [ "$scene" = "stream" ]; then
		STREAM_EXTRA="
# 直播推流 UDP 优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384"
	fi

	# ── 游戏服场景额外：低延迟优先 ──
	local GAME_EXTRA=""
	if [ "$scene" = "game" ]; then
		GAME_EXTRA="
# 游戏服低延迟优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0"
	fi

	# ── 加载 BBR 模块 ──
	local CC="bbr"
	local QDISC="fq"
	local KVER
	KVER=$(uname -r | grep -oP '^\d+\.\d+')
	if printf '%s\n%s' "4.9" "$KVER" | sort -V -C; then
		if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
			modprobe tcp_bbr 2>/dev/null
		fi
		if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
			CC="cubic"
			QDISC="fq_codel"
		fi
	else
		CC="cubic"
		QDISC="fq_codel"
	fi

	# ── 备份已有配置 ──
	[ -f "$CONF" ] && cp "$CONF" "${CONF}.bak.$(date +%s)"

	# ── 写入配置文件（持久化） ──
	echo -e "${gl_lv}写入优化配置...${gl_bai}"
	cat > "$CONF" << SYSCTL
# kejilion 内核调优配置
# 模式: $mode_name | 场景: $scene
# 内存: ${MEM_MB}MB | 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# ── TCP 拥塞控制 ──
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# ── TCP 缓冲区 ──
net.core.rmem_max = $RMEM_MAX
net.core.wmem_max = $WMEM_MAX
net.core.rmem_default = $(echo "$TCP_RMEM" | awk '{print $2}')
net.core.wmem_default = $(echo "$TCP_WMEM" | awk '{print $2}')
net.ipv4.tcp_rmem = $TCP_RMEM
net.ipv4.tcp_wmem = $TCP_WMEM

# ── 连接队列 ──
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $BACKLOG
net.ipv4.tcp_max_syn_backlog = $SYN_BACKLOG

# ── TCP 连接优化 ──
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = $FIN_TIMEOUT
net.ipv4.tcp_keepalive_time = $KEEPALIVE_TIME
net.ipv4.tcp_keepalive_intvl = $KEEPALIVE_INTVL
net.ipv4.tcp_keepalive_probes = $KEEPALIVE_PROBES
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# ── 端口与内存 ──
net.ipv4.ip_local_port_range = $PORT_RANGE
net.ipv4.tcp_mem = $((MEM_MB * 1024 / 8)) $((MEM_MB * 1024 / 4)) $((MEM_MB * 1024 / 2))
net.ipv4.tcp_max_orphans = 32768

# ── 虚拟内存 ──
vm.swappiness = $SWAPPINESS
vm.dirty_ratio = $DIRTY_RATIO
vm.dirty_background_ratio = $DIRTY_BG_RATIO
vm.overcommit_memory = $OVERCOMMIT
vm.min_free_kbytes = $MIN_FREE_KB
vm.vfs_cache_pressure = $VFS_PRESSURE

# ── CPU/内核调度 ──
kernel.sched_autogroup_enabled = $SCHED_AUTOGROUP
$([ -f /proc/sys/kernel/numa_balancing ] && echo "kernel.numa_balancing = $NUMA" || echo "# numa_balancing 不支持")

# ── 安全防护 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 连接跟踪 ──
$(if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
echo "net.netfilter.nf_conntrack_max = $((SOMAXCONN * 32))"
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"
echo "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"
echo "net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15"
echo "net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15"
else
echo "# conntrack 未启用"
fi)
$STREAM_EXTRA
$GAME_EXTRA
SYSCTL

	# ── 应用配置（逐行，跳过不支持的参数） ──
	echo -e "${gl_lv}应用优化参数...${gl_bai}"
	local applied=0 skipped=0
	while IFS= read -r line; do
		# 跳过注释和空行
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${line// /}" ]] && continue
		if sysctl -w "$line" >/dev/null 2>&1; then
			applied=$((applied + 1))
		else
			skipped=$((skipped + 1))
		fi
	done < "$CONF"
	echo -e "${gl_lv}已应用 ${applied} 项参数${skipped:+，跳过 ${skipped} 项不支持的参数}${gl_bai}"

	# ── 透明大页面 ──
	if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
		echo "$THP" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
	fi

	# ── 文件描述符限制 ──
	if ! grep -q "# kejilion-optimize" /etc/security/limits.conf 2>/dev/null; then
		cat >> /etc/security/limits.conf << 'LIMITS'

# kejilion-optimize
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
	fi

	# ── BBR 持久化 ──
	if [ "$CC" = "bbr" ]; then
		echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null
		# 清理旧的 sysctl.conf 里的 bbr 配置（避免冲突）
		sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
	fi

	echo -e "${gl_lv}${mode_name} 优化完成！配置已持久化到 ${CONF}${gl_bai}"
	echo -e "${gl_lv}内存: ${MEM_MB}MB | 拥塞算法: ${CC} | 队列: ${QDISC}${gl_bai}"
}

# ── 各模式入口函数（保持原有调用接口不变） ──

optimize_high_performance() {
	_kernel_optimize_core "${tiaoyou_moshi:-高性能优化模式}" "high"
}

optimize_balanced() {
	_kernel_optimize_core "均衡优化模式" "balanced"
}

optimize_web_server() {
	_kernel_optimize_core "网站搭建优化模式" "web"
}

# ── 内核调优场景化参数 ──


Kernel_optimize() {
	root_use
	while true; do
	  clear
	  local current_mode=$(grep "^# 模式:" /etc/sysctl.d/99-kejilion-optimize.conf 2>/dev/null | sed 's/# 模式: //' | awk -F'|' '{print $1}' | xargs)
	  echo "Linux系统内核参数优化"
	  if [ -n "$current_mode" ]; then
		  echo -e "当前模式: ${gl_lv}${current_mode}${gl_bai}"
	  else
		  echo -e "当前模式: ${gl_hui}未优化${gl_bai}"
	  fi
	  echo "视频介绍: https://www.bilibili.com/video/BV1Kb421J7yg?t=0.1"
	  echo "------------------------------------------------"
	  echo "提供多种系统参数调优模式，用户可以根据自身使用场景进行选择切换。"
	  echo -e "${gl_huang}提示: ${gl_bai}生产环境请谨慎使用！"
	  echo -e "--------------------"
	  echo -e "1. 高性能优化模式：     最大化系统性能，激进的内存和网络参数。"
	  echo -e "2. 均衡优化模式：       在性能与资源消耗之间取得平衡，适合日常使用。"
	  echo -e "3. 网站优化模式：       针对网站服务器优化，超高并发连接队列。"
	  echo -e "4. 直播优化模式：       针对直播推流优化，UDP 缓冲区加大，减少延迟。"
	  echo -e "5. 游戏服优化模式：     针对游戏服务器优化，低延迟优先。"
	  echo "--------------------"
	  echo "0. 返回上一级选单"
	  echo "--------------------"
	  read -e -p "请输入你的选择: " sub_choice
	  case $sub_choice in
		  1)
			  cd ~
			  clear
			  local tiaoyou_moshi="高性能优化模式"
			  optimize_high_performance
			  ;;
		  2)
			  cd ~
			  clear
			  optimize_balanced
			  ;;
		  3)
			  cd ~
			  clear
			  optimize_web_server
			  ;;
		  4)
			  cd ~
			  clear
			  _kernel_optimize_core "直播优化模式" "stream"
			  ;;
		  5)
			  cd ~
			  clear
			  _kernel_optimize_core "游戏服优化模式" "game"
			  ;;

		  *)
			  break
			  ;;
	  esac
	  break_end
	done
}







update_locale() {
	local lang=$1
	local locale_file=$2

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		case $ID in
			debian|ubuntu|kali)
				install locales
				sed -i "s/^\s*#\?\s*${locale_file}/${locale_file}/" /etc/locale.gen
				locale-gen
				echo "LANG=${lang}" > /etc/default/locale
				export LANG=${lang}
				echo -e "${gl_lv}系统语言已经修改为: $lang 重新连接SSH生效。${gl_bai}"
				hash -r
				break_end

				;;
			centos|rhel|almalinux|rocky|fedora)
				install glibc-langpack-zh
				localectl set-locale LANG=${lang}
				echo "LANG=${lang}" | tee /etc/locale.conf
				echo -e "${gl_lv}系统语言已经修改为: $lang 重新连接SSH生效。${gl_bai}"
				hash -r
				break_end
				;;
			*)
				echo "不支持的系统: $ID"
				break_end
				;;
		esac
	else
		echo "不支持的系统，无法识别系统类型。"
		break_end
	fi
}




linux_language() {
root_use
while true; do
  clear
  echo "当前系统语言: $LANG"
  echo "------------------------"
  echo "1. 英文          2. 简体中文          3. 繁体中文"
  echo "------------------------"
  echo "0. 返回上一级选单"
  echo "------------------------"
  read -e -p "输入你的选择: " choice

  case $choice in
	  1)
		  update_locale "en_US.UTF-8" "en_US.UTF-8"
		  ;;
	  2)
		  update_locale "zh_CN.UTF-8" "zh_CN.UTF-8"
		  ;;
	  3)
		  update_locale "zh_TW.UTF-8" "zh_TW.UTF-8"
		  ;;
	  *)
		  break
		  ;;
  esac
done
}



shell_bianse_profile() {

if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
	sed -i '/^PS1=/d' ~/.bashrc
	echo "${bianse}" >> ~/.bashrc
	# source ~/.bashrc
else
	sed -i '/^PS1=/d' ~/.profile
	echo "${bianse}" >> ~/.profile
	# source ~/.profile
fi
echo -e "${gl_lv}变更完成。重新连接SSH后可查看变化！${gl_bai}"

hash -r
break_end

}



shell_bianse() {
  root_use
  while true; do
	clear
	echo "命令行美化工具"
	echo "------------------------"
	echo -e "1. \033[1;32mroot \033[1;34mlocalhost \033[1;31m~ \033[0m${gl_bai}#"
	echo -e "2. \033[1;35mroot \033[1;36mlocalhost \033[1;33m~ \033[0m${gl_bai}#"
	echo -e "3. \033[1;31mroot \033[1;32mlocalhost \033[1;34m~ \033[0m${gl_bai}#"
	echo -e "4. \033[1;36mroot \033[1;33mlocalhost \033[1;37m~ \033[0m${gl_bai}#"
	echo -e "5. \033[1;37mroot \033[1;31mlocalhost \033[1;32m~ \033[0m${gl_bai}#"
	echo -e "6. \033[1;33mroot \033[1;34mlocalhost \033[1;35m~ \033[0m${gl_bai}#"
	echo -e "7. root localhost ~ #"
	echo "------------------------"
	echo "0. 返回上一级选单"
	echo "------------------------"
	read -e -p "输入你的选择: " choice

	case $choice in
	  1)
		local bianse="PS1='\[\033[1;32m\]\u\[\033[0m\]@\[\033[1;34m\]\h\[\033[0m\] \[\033[1;31m\]\w\[\033[0m\] # '"
		shell_bianse_profile

		;;
	  2)
		local bianse="PS1='\[\033[1;35m\]\u\[\033[0m\]@\[\033[1;36m\]\h\[\033[0m\] \[\033[1;33m\]\w\[\033[0m\] # '"
		shell_bianse_profile
		;;
	  3)
		local bianse="PS1='\[\033[1;31m\]\u\[\033[0m\]@\[\033[1;32m\]\h\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\] # '"
		shell_bianse_profile
		;;
	  4)
		local bianse="PS1='\[\033[1;36m\]\u\[\033[0m\]@\[\033[1;33m\]\h\[\033[0m\] \[\033[1;37m\]\w\[\033[0m\] # '"
		shell_bianse_profile
		;;
	  5)
		local bianse="PS1='\[\033[1;37m\]\u\[\033[0m\]@\[\033[1;31m\]\h\[\033[0m\] \[\033[1;32m\]\w\[\033[0m\] # '"
		shell_bianse_profile
		;;
	  6)
		local bianse="PS1='\[\033[1;33m\]\u\[\033[0m\]@\[\033[1;34m\]\h\[\033[0m\] \[\033[1;35m\]\w\[\033[0m\] # '"
		shell_bianse_profile
		;;
	  7)
		local bianse=""
		shell_bianse_profile
		;;
	  *)
		break
		;;
	esac

  done
}




linux_trash() {
  root_use

  local bashrc_profile="/root/.bashrc"
  local TRASH_DIR="$HOME/.local/share/Trash/files"

  while true; do

	local trash_status
	if ! grep -q "trash-put" "$bashrc_profile"; then
		trash_status="${gl_hui}未启用${gl_bai}"
	else
		trash_status="${gl_lv}已启用${gl_bai}"
	fi

	clear
	echo -e "当前回收站 ${trash_status}"
	echo -e "启用后rm删除的文件先进入回收站，防止误删重要文件！"
	echo "------------------------------------------------"
	ls -l --color=auto "$TRASH_DIR" 2>/dev/null || echo "回收站为空"
	echo "------------------------"
	echo "1. 启用回收站          2. 关闭回收站"
	echo "3. 还原内容            4. 清空回收站"
	echo "------------------------"
	echo "0. 返回上一级选单"
	echo "------------------------"
	read -e -p "输入你的选择: " choice

	case $choice in
	  1)
		install trash-cli
		sed -i '/alias rm/d' "$bashrc_profile"
		echo "alias rm='trash-put'" >> "$bashrc_profile"
		source "$bashrc_profile"
		echo "回收站已启用，删除的文件将移至回收站。"
		sleep 2
		;;
	  2)
		remove trash-cli
		sed -i '/alias rm/d' "$bashrc_profile"
		echo "alias rm='rm -i'" >> "$bashrc_profile"
		source "$bashrc_profile"
		echo "回收站已关闭，文件将直接删除。"
		sleep 2
		;;
	  3)
		read -e -p "输入要还原的文件名: " file_to_restore
		if [ -e "$TRASH_DIR/$file_to_restore" ]; then
		  mv "$TRASH_DIR/$file_to_restore" "$HOME/"
		  echo "$file_to_restore 已还原到主目录。"
		else
		  echo "文件不存在。"
		fi
		;;
	  4)
		read -e -p "确认清空回收站？[y/n]: " confirm
		if [[ "$confirm" == "y" ]]; then
		  trash-empty
		  echo "回收站已清空。"
		fi
		;;
	  *)
		break
		;;
	esac
  done
}

linux_fav() {
bash <(curl -l -s https://raw.githubusercontent.com/byJoey/cmdbox/refs/heads/main/install.sh)
}

# 创建备份
create_backup() {
	local TIMESTAMP=$(date +"%Y%m%d%H%M%S")

	# 提示用户输入备份目录
	echo "创建备份示例："
	echo "  - 备份单个目录: /var/www"
	echo "  - 备份多个目录: /etc /home /var/log"
	echo "  - 直接回车将使用默认目录 (/etc /usr /home)"
	read -e -p "请输入要备份的目录（多个目录用空格分隔，直接回车则使用默认目录）：" input

	# 如果用户没有输入目录，则使用默认目录
	if [ -z "$input" ]; then
		BACKUP_PATHS=(
			"/etc"              # 配置文件和软件包配置
			"/usr"              # 已安装的软件文件
			"/home"             # 用户数据
		)
	else
		# 将用户输入的目录按空格分隔成数组
		IFS=' ' read -r -a BACKUP_PATHS <<< "$input"
	fi

	# 生成备份文件前缀
	local PREFIX=""
	for path in "${BACKUP_PATHS[@]}"; do
		# 提取目录名称并去除斜杠
		dir_name=$(basename "$path")
		PREFIX+="${dir_name}_"
	done

	# 去除最后一个下划线
	local PREFIX=${PREFIX%_}

	# 生成备份文件名
	local BACKUP_NAME="${PREFIX}_$TIMESTAMP.tar.gz"

	# 打印用户选择的目录
	echo "您选择的备份目录为："
	for path in "${BACKUP_PATHS[@]}"; do
		echo "- $path"
	done

	# 创建备份
	echo "正在创建备份 $BACKUP_NAME..."
	install tar
	tar -czvf "$BACKUP_DIR/$BACKUP_NAME" "${BACKUP_PATHS[@]}"

	# 检查命令是否成功
	if [ $? -eq 0 ]; then
		echo "备份创建成功: $BACKUP_DIR/$BACKUP_NAME"
	else
		echo "备份创建失败！"
		exit 1
	fi
}

# 恢复备份
restore_backup() {
	# 选择要恢复的备份
	read -e -p "请输入要恢复的备份文件名: " BACKUP_NAME

	# 检查备份文件是否存在
	if [ ! -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
		echo "备份文件不存在！"
		exit 1
	fi

	echo "正在恢复备份 $BACKUP_NAME..."
	tar -xzvf "$BACKUP_DIR/$BACKUP_NAME" -C /

	if [ $? -eq 0 ]; then
		echo "备份恢复成功！"
	else
		echo "备份恢复失败！"
		exit 1
	fi
}

# 列出备份
list_backups() {
	echo "可用的备份："
	ls -1 "$BACKUP_DIR"
}

# 删除备份
delete_backup() {

	read -e -p "请输入要删除的备份文件名: " BACKUP_NAME

	# 检查备份文件是否存在
	if [ ! -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
		echo "备份文件不存在！"
		exit 1
	fi

	# 删除备份
	rm -f "$BACKUP_DIR/$BACKUP_NAME"

	if [ $? -eq 0 ]; then
		echo "备份删除成功！"
	else
		echo "备份删除失败！"
		exit 1
	fi
}

# 备份主菜单
linux_backup() {
	BACKUP_DIR="/backups"
	mkdir -p "$BACKUP_DIR"
	while true; do
		clear
		echo "系统备份功能"
		echo "------------------------"
		list_backups
		echo "------------------------"
		echo "1. 创建备份        2. 恢复备份        3. 删除备份"
		echo "------------------------"
		echo "0. 返回上一级选单"
		echo "------------------------"
		read -e -p "请输入你的选择: " choice
		case $choice in
			1) create_backup ;;
			2) restore_backup ;;
			3) delete_backup ;;
			*) break ;;
		esac
		read -e -p "按回车键继续..."
	done
}









# SSH 输入标准化函数
kj_ssh_validate_host() {
	local host="$1"
	[[ -n "$host" && ! "$host" =~ [[:space:]] && "$host" =~ ^[A-Za-z0-9._:-]+$ ]]
}

kj_ssh_validate_port() {
	local port="$1"
	[[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

kj_ssh_validate_user() {
	local user="$1"
	[[ -n "$user" && "$user" =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]]
}

kj_ssh_read_host_port() {
	local host_prompt="$1"
	local port_prompt="$2"
	local default_port="${3:-22}"

	while true; do
		read -e -p "$host_prompt" KJ_SSH_HOST
		if kj_ssh_validate_host "$KJ_SSH_HOST"; then
			break
		fi
		echo "错误: 请输入有效的服务器地址。"
	done

	while true; do
		read -e -p "$port_prompt" KJ_SSH_PORT
		KJ_SSH_PORT=${KJ_SSH_PORT:-$default_port}
		if kj_ssh_validate_port "$KJ_SSH_PORT"; then
			break
		fi
		echo "错误: 端口必须是 1-65535 之间的数字。"
	done
}

kj_ssh_read_host_user_port() {
	local host_prompt="$1"
	local user_prompt="$2"
	local port_prompt="$3"
	local default_user="${4:-root}"
	local default_port="${5:-22}"

	kj_ssh_read_host_port "$host_prompt" "$port_prompt" "$default_port"

	while true; do
		read -e -p "$user_prompt" KJ_SSH_USER
		KJ_SSH_USER=${KJ_SSH_USER:-$default_user}
		if kj_ssh_validate_user "$KJ_SSH_USER"; then
			break
		fi
		echo "错误: 用户名格式不正确。"
	done
}

kj_ssh_parse_remote() {
	local remote_raw="$1"
	local default_user="${2:-root}"
	local remote_user remote_host

	if [[ "$remote_raw" == *@* ]]; then
		remote_user="${remote_raw%@*}"
		remote_host="${remote_raw#*@}"
	else
		remote_user="$default_user"
		remote_host="$remote_raw"
	fi

	if ! kj_ssh_validate_user "$remote_user"; then
		echo "错误: SSH 用户名格式不正确。"
		return 1
	fi

	if ! kj_ssh_validate_host "$remote_host"; then
		echo "错误: SSH 主机地址格式不正确。"
		return 1
	fi

	KJ_SSH_USER="$remote_user"
	KJ_SSH_HOST="$remote_host"
	KJ_SSH_REMOTE="$remote_user@$remote_host"
}

kj_ssh_read_auth() {
	local key_file="$1"
	local password_or_key=""

	echo "请选择身份验证方式:"
	echo "1. 密码"
	echo "2. 密钥"
	read -e -p "请输入选择 (1/2): " auth_choice

	case $auth_choice in
		1)
			read -s -p "请输入密码: " password_or_key
			echo
			if [ -z "$password_or_key" ]; then
				echo "错误: 密码不能为空。"
				return 1
			fi
			KJ_SSH_AUTH_METHOD="password"
			KJ_SSH_AUTH_SECRET="$password_or_key"
			;;
		2)
			echo "请粘贴密钥内容 (粘贴完成后按两次回车)："
			while IFS= read -r line; do
				if [[ -z "$line" && "$password_or_key" == *"-----BEGIN"* ]]; then
					break
				fi
				if [[ -n "$line" || "$password_or_key" == *"-----BEGIN"* ]]; then
					password_or_key+="${line}"$'\n'
				fi
			done

			if [[ "$password_or_key" != *"-----BEGIN"* || "$password_or_key" != *"PRIVATE KEY-----"* ]]; then
				echo "无效的密钥内容！"
				return 1
			fi

			mkdir -p "$(dirname "$key_file")"
			echo -n "$password_or_key" > "$key_file"
			chmod 600 "$key_file"
			KJ_SSH_AUTH_METHOD="key"
			KJ_SSH_AUTH_SECRET="$key_file"
			;;
		*)
			echo "无效的选择！"
			return 1
			;;
	esac
}

kj_ssh_read_password() {
	local prompt="${1:-请输入密码: }"
	while true; do
		read -e -s -p "$prompt" KJ_SSH_PASSWORD
		echo
		[ -n "$KJ_SSH_PASSWORD" ] && break
		echo "错误: 密码不能为空。"
	done
}

kj_ssh_read_port() {
	local port_prompt="$1"
	local default_port="${2:-22}"
	while true; do
		read -e -p "$port_prompt" KJ_SSH_PORT
		KJ_SSH_PORT=${KJ_SSH_PORT:-$default_port}
		if kj_ssh_validate_port "$KJ_SSH_PORT"; then
			return 0
		fi
		echo "错误: 端口必须是 1-65535 之间的数字。"
	done
}

# 显示连接列表
list_connections() {
	echo "已保存的连接:"
	echo "------------------------"
	cat "$CONFIG_FILE" | awk -F'|' '{print NR " - " $1 " (" $2 ")"}'
	echo "------------------------"
}


# 添加新连接
add_connection() {
	echo "创建新连接示例："
	echo "  - 连接名称: my_server"
	echo "  - IP地址: 192.168.1.100"
	echo "  - 用户名: root"
	echo "  - 端口: 22"
	echo "------------------------"
	read -e -p "请输入连接名称: " name

	kj_ssh_read_host_user_port "请输入IP地址: " "请输入用户名 (默认: root): " "请输入端口号 (默认: 22): " "root" "22"
	if ! kj_ssh_read_auth "$KEY_DIR/$name.key"; then
		return
	fi

	echo "$name|$KJ_SSH_HOST|$KJ_SSH_USER|$KJ_SSH_PORT|$KJ_SSH_AUTH_SECRET" >> "$CONFIG_FILE"
	echo "连接已保存!"
}



# 删除连接
delete_connection() {
	read -e -p "请输入要删除的连接编号: " num

	local connection=$(sed -n "${num}p" "$CONFIG_FILE")
	if [[ -z "$connection" ]]; then
		echo "错误：未找到对应的连接。"
		return
	fi

	IFS='|' read -r name ip user port password_or_key <<< "$connection"

	# 如果连接使用的是密钥文件，则删除该密钥文件
	if [[ "$password_or_key" == "$KEY_DIR"* ]]; then
		rm -f "$password_or_key"
	fi

	sed -i "${num}d" "$CONFIG_FILE"
	echo "连接已删除!"
}

# 使用连接
use_connection() {
	read -e -p "请输入要使用的连接编号: " num

	local connection=$(sed -n "${num}p" "$CONFIG_FILE")
	if [[ -z "$connection" ]]; then
		echo "错误：未找到对应的连接。"
		return
	fi

	IFS='|' read -r name ip user port password_or_key <<< "$connection"

	echo "正在连接到 $name ($ip)..."
	if [[ -f "$password_or_key" ]]; then
		# 使用密钥连接
		ssh -o StrictHostKeyChecking=no -i "$password_or_key" -p "$port" "$user@$ip"
		if [[ $? -ne 0 ]]; then
			echo "连接失败！请检查以下内容："
			echo "1. 密钥文件路径是否正确：$password_or_key"
			echo "2. 密钥文件权限是否正确（应为 600）。"
			echo "3. 目标服务器是否允许使用密钥登录。"
		fi
	else
		# 使用密码连接
		if ! command -v sshpass &> /dev/null; then
			echo "错误：未安装 sshpass，请先安装 sshpass。"
			echo "安装方法："
			echo "  - Ubuntu/Debian: apt install sshpass"
			echo "  - CentOS/RHEL: yum install sshpass"
			return
		fi
		sshpass -p "$password_or_key" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$ip"
		if [[ $? -ne 0 ]]; then
			echo "连接失败！请检查以下内容："
			echo "1. 用户名和密码是否正确。"
			echo "2. 目标服务器是否允许密码登录。"
			echo "3. 目标服务器的 SSH 服务是否正常运行。"
		fi
	fi
}


ssh_manager() {

	CONFIG_FILE="$HOME/.ssh_connections"
	KEY_DIR="$HOME/.ssh/ssh_manager_keys"

	# 检查配置文件和密钥目录是否存在，如果不存在则创建
	if [[ ! -f "$CONFIG_FILE" ]]; then
		touch "$CONFIG_FILE"
	fi

	if [[ ! -d "$KEY_DIR" ]]; then
		mkdir -p "$KEY_DIR"
		chmod 700 "$KEY_DIR"
	fi

	while true; do
		clear
		echo "SSH 远程连接工具"
		echo "可以通过SSH连接到其他Linux系统上"
		echo "------------------------"
		list_connections
		echo "1. 创建新连接        2. 使用连接        3. 删除连接"
		echo "------------------------"
		echo "0. 返回上一级选单"
		echo "------------------------"
		read -e -p "请输入你的选择: " choice
		case $choice in
			1) add_connection ;;
			2) use_connection ;;
			3) delete_connection ;;
			0) break ;;
			*) echo "无效的选择，请重试。" ;;
		esac
	done
}












# 列出可用的硬盘分区
list_partitions() {
	echo "可用的硬盘分区："
	lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v "sr\|loop"
}


# 持久化挂载分区
mount_partition() {
	read -e -p "请输入要挂载的分区名称（例如 sda1）: " PARTITION

	DEVICE="/dev/$PARTITION"
	MOUNT_POINT="/mnt/$PARTITION"

	# 检查分区是否存在
	if ! lsblk -no NAME | grep -qw "$PARTITION"; then
		echo "分区不存在！"
		return 1
	fi

	# 检查是否已挂载
	if mount | grep -qw "$DEVICE"; then
		echo "分区已经挂载！"
		return 1
	fi

	# 获取 UUID
	UUID=$(blkid -s UUID -o value "$DEVICE")
	if [ -z "$UUID" ]; then
		echo "无法获取 UUID！"
		return 1
	fi

	# 获取文件系统类型
	FSTYPE=$(blkid -s TYPE -o value "$DEVICE")
	if [ -z "$FSTYPE" ]; then
		echo "无法获取文件系统类型！"
		return 1
	fi

	# 创建挂载点
	mkdir -p "$MOUNT_POINT"

	# 挂载
	if ! mount "$DEVICE" "$MOUNT_POINT"; then
		echo "分区挂载失败！"
		rmdir "$MOUNT_POINT"
		return 1
	fi

	echo "分区已成功挂载到 $MOUNT_POINT"

	# 检查 /etc/fstab 是否已经存在 UUID 或挂载点
	if grep -qE "UUID=$UUID|[[:space:]]$MOUNT_POINT[[:space:]]" /etc/fstab; then
		echo "/etc/fstab 中已存在该分区记录，跳过写入"
		return 0
	fi

	# 写入 /etc/fstab
	echo "UUID=$UUID $MOUNT_POINT $FSTYPE defaults,nofail 0 2" >> /etc/fstab

	echo "已写入 /etc/fstab，实现持久化挂载"
}


# 卸载分区
unmount_partition() {
	read -e -p "请输入要卸载的分区名称（例如 sda1）: " PARTITION

	# 检查分区是否已经挂载
	MOUNT_POINT=$(lsblk -o MOUNTPOINT | grep -w "$PARTITION")
	if [ -z "$MOUNT_POINT" ]; then
		echo "分区未挂载！"
		return
	fi

	# 卸载分区
	umount "/dev/$PARTITION"

	if [ $? -eq 0 ]; then
		echo "分区卸载成功: $MOUNT_POINT"
		rmdir "$MOUNT_POINT"
	else
		echo "分区卸载失败！"
	fi
}

# 列出已挂载的分区
list_mounted_partitions() {
	echo "已挂载的分区："
	df -h | grep -v "tmpfs\|udev\|overlay"
}

# 格式化分区
format_partition() {
	read -e -p "请输入要格式化的分区名称（例如 sda1）: " PARTITION

	# 检查分区是否存在
	if ! lsblk -o NAME | grep -w "$PARTITION" > /dev/null; then
		echo "分区不存在！"
		return
	fi

	# 检查分区是否已经挂载
	if lsblk -o MOUNTPOINT | grep -w "$PARTITION" > /dev/null; then
		echo "分区已经挂载，请先卸载！"
		return
	fi

	# 选择文件系统类型
	echo "请选择文件系统类型："
	echo "1. ext4"
	echo "2. xfs"
	echo "3. ntfs"
	echo "4. vfat"
	read -e -p "请输入你的选择: " FS_CHOICE

	case $FS_CHOICE in
		1) FS_TYPE="ext4" ;;
		2) FS_TYPE="xfs" ;;
		3) FS_TYPE="ntfs" ;;
		4) FS_TYPE="vfat" ;;
		*) echo "无效的选择！"; return ;;
	esac

	# 确认格式化
	read -e -p "确认格式化分区 /dev/$PARTITION 为 $FS_TYPE 吗？(y/n): " CONFIRM
	if [ "$CONFIRM" != "y" ]; then
		echo "操作已取消。"
		return
	fi

	# 格式化分区
	echo "正在格式化分区 /dev/$PARTITION 为 $FS_TYPE ..."
	mkfs.$FS_TYPE "/dev/$PARTITION"

	if [ $? -eq 0 ]; then
		echo "分区格式化成功！"
	else
		echo "分区格式化失败！"
	fi
}

# 检查分区状态
check_partition() {
	read -e -p "请输入要检查的分区名称（例如 sda1）: " PARTITION

	# 检查分区是否存在
	if ! lsblk -o NAME | grep -w "$PARTITION" > /dev/null; then
		echo "分区不存在！"
		return
	fi

	# 检查分区状态
	echo "检查分区 /dev/$PARTITION 的状态："
	fsck "/dev/$PARTITION"
}

# 主菜单
disk_manager() {
	while true; do
		clear
		echo "硬盘分区管理"
		echo -e "${gl_huang}该功能内部测试阶段，请勿在生产环境使用。${gl_bai}"
		echo "------------------------"
		list_partitions
		echo "------------------------"
		echo "1. 挂载分区        2. 卸载分区        3. 查看已挂载分区"
		echo "4. 格式化分区      5. 检查分区状态"
		echo "------------------------"
		echo "0. 返回上一级选单"
		echo "------------------------"
		read -e -p "请输入你的选择: " choice
		case $choice in
			1) mount_partition ;;
			2) unmount_partition ;;
			3) list_mounted_partitions ;;
			4) format_partition ;;
			5) check_partition ;;
			*) break ;;
		esac
		read -e -p "按回车键继续..."
	done
}




# 显示任务列表
list_tasks() {
	echo "已保存的同步任务:"
	echo "---------------------------------"
	awk -F'|' '{print NR " - " $1 " ( " $2 " -> " $3":"$4 " )"}' "$CONFIG_FILE"
	echo "---------------------------------"
}

# 添加新任务
add_task() {
	echo "创建新同步任务示例："
	echo "  - 任务名称: backup_www"
	echo "  - 本地目录: /var/www"
	echo "  - 远程地址: user@192.168.1.100"
	echo "  - 远程目录: /backup/www"
	echo "  - 端口号 (默认 22)"
	echo "---------------------------------"
	read -e -p "请输入任务名称: " name
	read -e -p "请输入本地目录: " local_path
	read -e -p "请输入远程目录: " remote_path

	while true; do
		read -e -p "请输入远程用户@IP: " remote
		if kj_ssh_parse_remote "$remote" "root"; then
			remote="$KJ_SSH_REMOTE"
			break
		fi
	done

	kj_ssh_read_port "请输入 SSH 端口 (默认 22): " "22"
	port="$KJ_SSH_PORT"

	if ! kj_ssh_read_auth "$KEY_DIR/${name}_sync.key"; then
		return
	fi
	auth_method="$KJ_SSH_AUTH_METHOD"
	password_or_key="$KJ_SSH_AUTH_SECRET"

	echo "请选择同步模式:"
	echo "1. 标准模式 (-avz)"
	echo "2. 删除目标文件 (-avz --delete)"
	read -e -p "请选择 (1/2): " mode
	case $mode in
		1) options="-avz" ;;
		2) options="-avz --delete" ;;
		*) echo "无效选择，使用默认 -avz"; options="-avz" ;;
	esac

	echo "$name|$local_path|$remote|$remote_path|$port|$options|$auth_method|$password_or_key" >> "$CONFIG_FILE"

	install rsync rsync

	echo "任务已保存!"
}


# 删除任务
delete_task() {
	read -e -p "请输入要删除的任务编号: " num

	local task=$(sed -n "${num}p" "$CONFIG_FILE")
	if [[ -z "$task" ]]; then
		echo "错误：未找到对应的任务。"
		return
	fi

	IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"

	# 如果任务使用的是密钥文件，则删除该密钥文件
	if [[ "$auth_method" == "key" && "$password_or_key" == "$KEY_DIR"* ]]; then
		rm -f "$password_or_key"
	fi

	sed -i "${num}d" "$CONFIG_FILE"
	echo "任务已删除!"
}


run_task() {

	CONFIG_FILE="$HOME/.rsync_tasks"
	CRON_FILE="$HOME/.rsync_cron"

	# 解析参数
	local direction="push"  # 默认是推送到远端
	local num

	if [[ "$1" == "push" || "$1" == "pull" ]]; then
		direction="$1"
		num="$2"
	else
		num="$1"
	fi

	# 如果没有传入任务编号，提示用户输入
	if [[ -z "$num" ]]; then
		read -e -p "请输入要执行的任务编号: " num
	fi

	local task=$(sed -n "${num}p" "$CONFIG_FILE")
	if [[ -z "$task" ]]; then
		echo "错误: 未找到该任务!"
		return
	fi

	IFS='|' read -r name local_path remote remote_path port options auth_method password_or_key <<< "$task"

	# 根据同步方向调整源和目标路径
	if [[ "$direction" == "pull" ]]; then
		echo "正在拉取同步到本地: $remote:$local_path -> $remote_path"
		source="$remote:$local_path"
		destination="$remote_path"
	else
		echo "正在推送同步到远端: $local_path -> $remote:$remote_path"
		source="$local_path"
		destination="$remote:$remote_path"
	fi

	# 添加 SSH 连接通用参数
	local ssh_options="-p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

	if [[ "$auth_method" == "password" ]]; then
		if ! command -v sshpass &> /dev/null; then
			echo "错误：未安装 sshpass，请先安装 sshpass。"
			echo "安装方法："
			echo "  - Ubuntu/Debian: apt install sshpass"
			echo "  - CentOS/RHEL: yum install sshpass"
			return
		fi
		sshpass -p "$password_or_key" rsync $options -e "ssh $ssh_options" "$source" "$destination"
	else
		# 检查密钥文件是否存在和权限是否正确
		if [[ ! -f "$password_or_key" ]]; then
			echo "错误：密钥文件不存在：$password_or_key"
			return
		fi

		if [[ "$(stat -c %a "$password_or_key")" != "600" ]]; then
			echo "警告：密钥文件权限不正确，正在修复..."
			chmod 600 "$password_or_key"
		fi

		rsync $options -e "ssh -i $password_or_key $ssh_options" "$source" "$destination"
	fi

	if [[ $? -eq 0 ]]; then
		echo "同步完成!"
	else
		echo "同步失败! 请检查以下内容："
		echo "1. 网络连接是否正常"
		echo "2. 远程主机是否可访问"
		echo "3. 认证信息是否正确"
		echo "4. 本地和远程目录是否有正确的访问权限"
	fi
}


# 创建定时任务
schedule_task() {

	read -e -p "请输入要定时同步的任务编号: " num
	if ! [[ "$num" =~ ^[0-9]+$ ]]; then
		echo "错误: 请输入有效的任务编号！"
		return
	fi

	echo "请选择定时执行间隔："
	echo "1) 每小时执行一次"
	echo "2) 每天执行一次"
	echo "3) 每周执行一次"
	read -e -p "请输入选项 (1/2/3): " interval

	local random_minute=$(shuf -i 0-59 -n 1)  # 生成 0-59 之间的随机分钟数
	local cron_time=""
	case "$interval" in
		1) cron_time="$random_minute * * * *" ;;  # 每小时，随机分钟执行
		2) cron_time="$random_minute 0 * * *" ;;  # 每天，随机分钟执行
		3) cron_time="$random_minute 0 * * 1" ;;  # 每周，随机分钟执行
		*) echo "错误: 请输入有效的选项！" ; return ;;
	esac

	local cron_job="$cron_time k rsync_run $num"
	local cron_job="$cron_time k rsync_run $num"

	# 检查是否已存在相同任务
	if crontab -l | grep -q "k rsync_run $num"; then
		echo "错误: 该任务的定时同步已存在！"
		return
	fi

	# 创建到用户的 crontab
	(crontab -l 2>/dev/null; echo "$cron_job") | crontab -
	echo "定时任务已创建: $cron_job"
}

# 查看定时任务
view_tasks() {
	echo "当前的定时任务:"
	echo "---------------------------------"
	crontab -l | grep "k rsync_run"
	echo "---------------------------------"
}

# 删除定时任务
delete_task_schedule() {
	read -e -p "请输入要删除的任务编号: " num
	if ! [[ "$num" =~ ^[0-9]+$ ]]; then
		echo "错误: 请输入有效的任务编号！"
		return
	fi

	crontab -l | grep -v "k rsync_run $num" | crontab -
	echo "已删除任务编号 $num 的定时任务"
}


# 任务管理主菜单
rsync_manager() {
	CONFIG_FILE="$HOME/.rsync_tasks"
	CRON_FILE="$HOME/.rsync_cron"

	while true; do
		clear
		echo "Rsync 远程同步工具"
		echo "远程目录之间同步，支持增量同步，高效稳定。"
		echo "---------------------------------"
		list_tasks
		echo
		view_tasks
		echo
		echo "1. 创建新任务                 2. 删除任务"
		echo "3. 执行本地同步到远端         4. 执行远端同步到本地"
		echo "5. 创建定时任务               6. 删除定时任务"
		echo "---------------------------------"
		echo "0. 返回上一级选单"
		echo "---------------------------------"
		read -e -p "请输入你的选择: " choice
		case $choice in
			1) add_task ;;
			2) delete_task ;;
			3) run_task push;;
			4) run_task pull;;
			5) schedule_task ;;
			6) delete_task_schedule ;;
			0) break ;;
			*) echo "无效的选择，请重试。" ;;
		esac
		read -e -p "按回车键继续..."
	done
}









linux_info() {



	clear
	echo -e "${gl_kjlan}正在查询系统信息……${gl_bai}"

	ip_address

	local cpu_info=$(lscpu | awk -F': +' '/Model name:/ {print $2; exit}')

	local cpu_usage_percent=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f\n", (($2+$4-u1) * 100 / (t-t1))}' \
		<(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat))

	local cpu_cores=$(nproc)

	local cpu_freq=$(cat /proc/cpuinfo | grep "MHz" | head -n 1 | awk '{printf "%.1f GHz\n", $4/1000}')

	local mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2fM (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')

	local disk_info=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')

	local ipinfo=$(curl -s ipinfo.io)
	local country=$(echo "$ipinfo" | grep 'country' | awk -F': ' '{print $2}' | tr -d '",')
	local city=$(echo "$ipinfo" | grep 'city' | awk -F': ' '{print $2}' | tr -d '",')
	local isp_info=$(echo "$ipinfo" | grep 'org' | awk -F': ' '{print $2}' | tr -d '",')

	local load=$(uptime | awk '{print $(NF-2), $(NF-1), $NF}')
	local dns_addresses=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf)


	local cpu_arch=$(uname -m)

	local hostname=$(uname -n)

	local kernel_version=$(uname -r)

	local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
	local queue_algorithm=$(sysctl -n net.core.default_qdisc)

	local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')

	output_status

	local current_time=$(date "+%Y-%m-%d %I:%M %p")


	local swap_info=$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')

	local runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')

	local timezone=$(current_timezone)

	local tcp_count=$(ss -t | wc -l)
	local udp_count=$(ss -u | wc -l)

	clear
	echo -e "系统信息查询"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}主机名:         ${gl_bai}$hostname"
	echo -e "${gl_kjlan}系统版本:       ${gl_bai}$os_info"
	echo -e "${gl_kjlan}Linux版本:      ${gl_bai}$kernel_version"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}CPU架构:        ${gl_bai}$cpu_arch"
	echo -e "${gl_kjlan}CPU型号:        ${gl_bai}$cpu_info"
	echo -e "${gl_kjlan}CPU核心数:      ${gl_bai}$cpu_cores"
	echo -e "${gl_kjlan}CPU频率:        ${gl_bai}$cpu_freq"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}CPU占用:        ${gl_bai}$cpu_usage_percent%"
	echo -e "${gl_kjlan}系统负载:       ${gl_bai}$load"
	echo -e "${gl_kjlan}TCP|UDP连接数:  ${gl_bai}$tcp_count|$udp_count"
	echo -e "${gl_kjlan}物理内存:       ${gl_bai}$mem_info"
	echo -e "${gl_kjlan}虚拟内存:       ${gl_bai}$swap_info"
	echo -e "${gl_kjlan}硬盘占用:       ${gl_bai}$disk_info"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}总接收:         ${gl_bai}$rx"
	echo -e "${gl_kjlan}总发送:         ${gl_bai}$tx"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}网络算法:       ${gl_bai}$congestion_algorithm $queue_algorithm"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}运营商:         ${gl_bai}$isp_info"
	if [ -n "$ipv4_address" ]; then
		echo -e "${gl_kjlan}IPv4地址:       ${gl_bai}$ipv4_address"
	fi

	if [ -n "$ipv6_address" ]; then
		echo -e "${gl_kjlan}IPv6地址:       ${gl_bai}$ipv6_address"
	fi
	echo -e "${gl_kjlan}DNS地址:        ${gl_bai}$dns_addresses"
	echo -e "${gl_kjlan}地理位置:       ${gl_bai}$country $city"
	echo -e "${gl_kjlan}系统时间:       ${gl_bai}$timezone $current_time"
	echo -e "${gl_kjlan}-------------"
	echo -e "${gl_kjlan}运行时长:       ${gl_bai}$runtime"
	echo



}



linux_tools() {

  while true; do
	  clear
	  echo -e "基础工具"

	  tools=(
		curl wget sudo socat htop iftop unzip tar tmux ffmpeg
		btop ranger ncdu fzf cmatrix sl bastet nsnake ninvaders
		vim nano git
	  )

	  if command -v apt >/dev/null 2>&1; then
		PM="apt"
	  elif command -v dnf >/dev/null 2>&1; then
		PM="dnf"
	  elif command -v yum >/dev/null 2>&1; then
		PM="yum"
	  elif command -v pacman >/dev/null 2>&1; then
		PM="pacman"
	  elif command -v apk >/dev/null 2>&1; then
		PM="apk"
	  elif command -v zypper >/dev/null 2>&1; then
		PM="zypper"
	  elif command -v opkg >/dev/null 2>&1; then
		PM="opkg"
	  elif command -v pkg >/dev/null 2>&1; then
		PM="pkg"
	  else
		echo "❌ 未识别的包管理器"
		exit 1
	  fi

	  echo "📦 使用包管理器: $PM"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"

	  for ((i=0; i<${#tools[@]}; i+=2)); do
		# 左列
		if command -v "${tools[i]}" >/dev/null 2>&1; then
		  left=$(printf "✅ %-12s 已安装" "${tools[i]}")
		else
		  left=$(printf "❌ %-12s 未安装" "${tools[i]}")
		fi

		# 右列（防止数组越界）
		if [[ -n "${tools[i+1]}" ]]; then
		  if command -v "${tools[i+1]}" >/dev/null 2>&1; then
			right=$(printf "✅ %-12s 已安装" "${tools[i+1]}")
		  else
			right=$(printf "❌ %-12s 未安装" "${tools[i+1]}")
		  fi
		  printf "%-42s %s\n" "$left" "$right"
		else
		  printf "%s\n" "$left"
		fi
	  done

	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}1.   ${gl_bai}curl 下载工具 ${gl_huang}★${gl_bai}                   ${gl_kjlan}2.   ${gl_bai}wget 下载工具 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}3.   ${gl_bai}sudo 超级管理权限工具             ${gl_kjlan}4.   ${gl_bai}socat 通信连接工具"
	  echo -e "${gl_kjlan}5.   ${gl_bai}htop 系统监控工具                 ${gl_kjlan}6.   ${gl_bai}iftop 网络流量监控工具"
	  echo -e "${gl_kjlan}7.   ${gl_bai}unzip ZIP压缩解压工具             ${gl_kjlan}8.   ${gl_bai}tar GZ压缩解压工具"
	  echo -e "${gl_kjlan}9.   ${gl_bai}tmux 多路后台运行工具             ${gl_kjlan}10.  ${gl_bai}ffmpeg 视频编码直播推流工具"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}11.  ${gl_bai}btop 现代化监控工具 ${gl_huang}★${gl_bai}             ${gl_kjlan}12.  ${gl_bai}ranger 文件管理工具"
	  echo -e "${gl_kjlan}13.  ${gl_bai}ncdu 磁盘占用查看工具             ${gl_kjlan}14.  ${gl_bai}fzf 全局搜索工具"
	  echo -e "${gl_kjlan}15.  ${gl_bai}vim 文本编辑器                    ${gl_kjlan}16.  ${gl_bai}nano 文本编辑器 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}17.  ${gl_bai}git 版本控制系统"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}21.  ${gl_bai}黑客帝国屏保                      ${gl_kjlan}22.  ${gl_bai}跑火车屏保"
	  echo -e "${gl_kjlan}26.  ${gl_bai}俄罗斯方块小游戏                  ${gl_kjlan}27.  ${gl_bai}贪吃蛇小游戏"
	  echo -e "${gl_kjlan}28.  ${gl_bai}太空入侵者小游戏"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}31.  ${gl_bai}全部安装                          ${gl_kjlan}32.  ${gl_bai}全部安装（不含屏保和游戏）${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}33.  ${gl_bai}全部卸载"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}41.  ${gl_bai}安装指定工具                      ${gl_kjlan}42.  ${gl_bai}卸载指定工具"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}0.   ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in
		  1)
			  clear
			  install curl
			  clear
			  echo "工具已安装，使用方法如下："
			  curl --help
			  ;;
		  2)
			  clear
			  install wget
			  clear
			  echo "工具已安装，使用方法如下："
			  wget --help
			  ;;
			3)
			  clear
			  install sudo
			  clear
			  echo "工具已安装，使用方法如下："
			  sudo --help
			  ;;
			4)
			  clear
			  install socat
			  clear
			  echo "工具已安装，使用方法如下："
			  socat -h
			  ;;
			5)
			  clear
			  install htop
			  clear
			  htop
			  ;;
			6)
			  clear
			  install iftop
			  clear
			  iftop
			  ;;
			7)
			  clear
			  install unzip
			  clear
			  echo "工具已安装，使用方法如下："
			  unzip
			  ;;
			8)
			  clear
			  install tar
			  clear
			  echo "工具已安装，使用方法如下："
			  tar --help
			  ;;
			9)
			  clear
			  install tmux
			  clear
			  echo "工具已安装，使用方法如下："
			  tmux --help
			  ;;
			10)
			  clear
			  install ffmpeg
			  clear
			  echo "工具已安装，使用方法如下："
			  ffmpeg --help
			  ;;

			11)
			  clear
			  install btop
			  clear
			  btop
			  ;;
			12)
			  clear
			  install ranger
			  cd /
			  clear
			  ranger
			  cd ~
			  ;;
			13)
			  clear
			  install ncdu
			  cd /
			  clear
			  ncdu
			  cd ~
			  ;;
			14)
			  clear
			  install fzf
			  cd /
			  clear
			  fzf
			  cd ~
			  ;;
			15)
			  clear
			  install vim
			  cd /
			  clear
			  vim -h
			  cd ~
			  ;;
			16)
			  clear
			  install nano
			  cd /
			  clear
			  nano -h
			  cd ~
			  ;;


			17)
			  clear
			  install git
			  cd /
			  clear
			  git --help
			  cd ~
			  ;;

			21)
			  clear
			  install cmatrix
			  clear
			  cmatrix
			  ;;
			22)
			  clear
			  install sl
			  clear
			  sl
			  ;;
			26)
			  clear
			  install bastet
			  clear
			  bastet
			  ;;
			27)
			  clear
			  install nsnake
			  clear
			  nsnake
			  ;;

			28)
			  clear
			  install ninvaders
			  clear
			  ninvaders
			  ;;

		  31)
			  clear
			  install curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger ncdu fzf cmatrix sl bastet nsnake ninvaders vim nano git
			  ;;

		  32)
			  clear
			  install curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger ncdu fzf vim nano git
			  ;;


		  33)
			  clear
			  remove htop iftop tmux ffmpeg btop ranger ncdu fzf cmatrix sl bastet nsnake ninvaders vim nano git
			  ;;

		  41)
			  clear
			  read -e -p "请输入安装的工具名（wget curl sudo htop）: " installname
			  install $installname
			  ;;
		  42)
			  clear
			  read -e -p "请输入卸载的工具名（htop ufw tmux cmatrix）: " removename
			  remove $removename
			  ;;

		  0)
			  kejilion
			  ;;

		  *)
			  echo "无效的输入!"
			  ;;
	  esac
	  break_end
  done




}


linux_bbr() {
	clear
	if [ -f "/etc/alpine-release" ]; then
		while true; do
			  clear
			  local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
			  local queue_algorithm=$(sysctl -n net.core.default_qdisc)
			  echo "当前TCP阻塞算法: $congestion_algorithm $queue_algorithm"

			  echo ""
			  echo "BBR管理"
			  echo "------------------------"
			  echo "1. 开启BBRv3              2. 关闭BBRv3（会重启）"
			  echo "------------------------"
			  echo "0. 返回上一级选单"
			  echo "------------------------"
			  read -e -p "请输入你的选择: " sub_choice

			  case $sub_choice in
				  1)
					bbr_on
					  ;;
				  2)
					sed -i '/net.ipv4.tcp_congestion_control=/d' /etc/sysctl.conf
					sysctl -p
					server_reboot
					  ;;
				  *)
					  break  # 跳出循环，退出菜单
					  ;;

			  esac
		done
	else
		install wget
		wget --no-check-certificate -O tcpx.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh
		chmod +x tcpx.sh
		./tcpx.sh
	fi


}





docker_ssh_migration() {

	is_compose_container() {
		local container=$1
		docker inspect "$container" | jq -e '.[0].Config.Labels["com.docker.compose.project"]' >/dev/null 2>&1
	}

	list_backups() {
		local BACKUP_ROOT="/tmp"
		echo -e "${gl_kjlan}当前备份列表:${gl_bai}"
		ls -1dt ${BACKUP_ROOT}/docker_backup_* 2>/dev/null || echo "无备份"
	}



	# ----------------------------
	# 备份
	# ----------------------------
	backup_docker() {

		echo -e "${gl_kjlan}正在备份 Docker 容器...${gl_bai}"
		docker ps --format '{{.Names}}'
		read -e -p  "请输入要备份的容器名（多个空格分隔，回车备份全部运行中容器）: " containers

		install tar jq gzip
		install_docker

		local BACKUP_ROOT="/tmp"
		local DATE_STR=$(date +%Y%m%d_%H%M%S)
		local TARGET_CONTAINERS=()
		if [ -z "$containers" ]; then
			mapfile -t TARGET_CONTAINERS < <(docker ps --format '{{.Names}}')
		else
			read -ra TARGET_CONTAINERS <<< "$containers"
		fi
		[[ ${#TARGET_CONTAINERS[@]} -eq 0 ]] && { echo -e "${gl_hong}没有找到容器${gl_bai}"; return; }

		local BACKUP_DIR="${BACKUP_ROOT}/docker_backup_${DATE_STR}"
		mkdir -p "$BACKUP_DIR"

		local RESTORE_SCRIPT="${BACKUP_DIR}/docker_restore.sh"
		echo "#!/bin/bash" > "$RESTORE_SCRIPT"
		echo "set -e" >> "$RESTORE_SCRIPT"
		echo "# 自动生成的还原脚本" >> "$RESTORE_SCRIPT"

		# 记录已打包过的 Compose 项目路径，避免重复打包
		declare -A PACKED_COMPOSE_PATHS=()

		for c in "${TARGET_CONTAINERS[@]}"; do
			echo -e "${gl_lv}备份容器: $c${gl_bai}"
			local inspect_file="${BACKUP_DIR}/${c}_inspect.json"
			docker inspect "$c" > "$inspect_file"

			if is_compose_container "$c"; then
				echo -e "${gl_kjlan}检测到 $c 是 docker-compose 容器${gl_bai}"
				local project_dir=$(docker inspect "$c" | jq -r '.[0].Config.Labels["com.docker.compose.project.working_dir"] // empty')
				local project_name=$(docker inspect "$c" | jq -r '.[0].Config.Labels["com.docker.compose.project"] // empty')

				if [ -z "$project_dir" ]; then
					read -e -p  "未检测到 compose 目录，请手动输入路径: " project_dir
				fi

				# 如果该 Compose 项目已经打包过，跳过
				if [[ -n "${PACKED_COMPOSE_PATHS[$project_dir]}" ]]; then
					echo -e "${gl_huang}Compose 项目 [$project_name] 已备份过，跳过重复打包...${gl_bai}"
					continue
				fi

				if [ -f "$project_dir/docker-compose.yml" ]; then
					echo "compose" > "${BACKUP_DIR}/backup_type_${project_name}"
					echo "$project_dir" > "${BACKUP_DIR}/compose_path_${project_name}.txt"
					tar -czf "${BACKUP_DIR}/compose_project_${project_name}.tar.gz" -C "$project_dir" .
					echo "# docker-compose 恢复: $project_name" >> "$RESTORE_SCRIPT"
					echo "cd \"$project_dir\" && docker compose up -d" >> "$RESTORE_SCRIPT"
					PACKED_COMPOSE_PATHS["$project_dir"]=1
					echo -e "${gl_lv}Compose 项目 [$project_name] 已打包: ${project_dir}${gl_bai}"
				else
					echo -e "${gl_hong}未找到 docker-compose.yml，跳过此容器...${gl_bai}"
				fi
			else
				# 普通容器备份卷
				local VOL_PATHS
				VOL_PATHS=$(docker inspect "$c" --format '{{range .Mounts}}{{.Source}} {{end}}')
				for path in $VOL_PATHS; do
					echo "打包卷: $path"
					tar -czpf "${BACKUP_DIR}/${c}_$(basename $path).tar.gz" -C / "$(echo $path | sed 's/^\///')"
				done

				# 端口
				local PORT_ARGS=""
				mapfile -t PORTS < <(jq -r '.[0].HostConfig.PortBindings | to_entries[] | "\(.value[0].HostPort):\(.key | split("/")[0])"' "$inspect_file" 2>/dev/null)
				for p in "${PORTS[@]}"; do PORT_ARGS+="-p $p "; done

				# 环境变量
				local ENV_VARS=""
				mapfile -t ENVS < <(jq -r '.[0].Config.Env[] | @sh' "$inspect_file")
				for e in "${ENVS[@]}"; do ENV_VARS+="-e $e "; done

				# 卷映射
				local VOL_ARGS=""
				for path in $VOL_PATHS; do VOL_ARGS+="-v $path:$path "; done

				# 镜像
				local IMAGE
				IMAGE=$(jq -r '.[0].Config.Image' "$inspect_file")

				echo -e "\n# 还原容器: $c" >> "$RESTORE_SCRIPT"
				echo "docker run -d --name $c $PORT_ARGS $VOL_ARGS $ENV_VARS $IMAGE" >> "$RESTORE_SCRIPT"
			fi
		done


		# 备份 /home/docker 下的所有文件（不含子目录）
		if [ -d "/home/docker" ]; then
			echo -e "${gl_kjlan}备份 /home/docker 下的文件...${gl_bai}"
			find /home/docker -maxdepth 1 -type f | tar -czf "${BACKUP_DIR}/home_docker_files.tar.gz" -T -
			echo -e "${gl_lv}/home/docker 下的文件已打包到: ${BACKUP_DIR}/home_docker_files.tar.gz${gl_bai}"
		fi

		chmod +x "$RESTORE_SCRIPT"
		echo -e "${gl_lv}备份完成: ${BACKUP_DIR}${gl_bai}"
		echo -e "${gl_lv}可用还原脚本: ${RESTORE_SCRIPT}${gl_bai}"


	}

	# ----------------------------
	# 还原
	# ----------------------------
	restore_docker() {

		read -e -p  "请输入要还原的备份目录: " BACKUP_DIR
		[[ ! -d "$BACKUP_DIR" ]] && { echo -e "${gl_hong}备份目录不存在${gl_bai}"; return; }

		echo -e "${gl_kjlan}开始执行还原操作...${gl_bai}"

		install tar jq gzip
		install_docker

		# --------- 优先还原 Compose 项目 ---------
		for f in "$BACKUP_DIR"/backup_type_*; do
			[[ ! -f "$f" ]] && continue
			if grep -q "compose" "$f"; then
				project_name=$(basename "$f" | sed 's/backup_type_//')
				path_file="$BACKUP_DIR/compose_path_${project_name}.txt"
				[[ -f "$path_file" ]] && original_path=$(cat "$path_file") || original_path=""
				[[ -z "$original_path" ]] && read -e -p  "未找到原始路径，请输入还原目录路径: " original_path

				# 检查该 compose 项目的容器是否已经在运行
				running_count=$(docker ps --filter "label=com.docker.compose.project=$project_name" --format '{{.Names}}' | wc -l)
				if [[ "$running_count" -gt 0 ]]; then
					echo -e "${gl_huang}Compose 项目 [$project_name] 已有容器在运行，跳过还原...${gl_bai}"
					continue
				fi

				read -e -p  "确认还原 Compose 项目 [$project_name] 到路径 [$original_path] ? (y/n): " confirm
				[[ "$confirm" != "y" ]] && read -e -p  "请输入新的还原路径: " original_path

				mkdir -p "$original_path"
				tar -xzf "$BACKUP_DIR/compose_project_${project_name}.tar.gz" -C "$original_path"
				echo -e "${gl_lv}Compose 项目 [$project_name] 已解压到: $original_path${gl_bai}"

				cd "$original_path" || return
				docker compose down || true
				docker compose up -d
				echo -e "${gl_lv}Compose 项目 [$project_name] 还原完成！${gl_bai}"
			fi
		done

		# --------- 继续还原普通容器 ---------
		echo -e "${gl_kjlan}检查并还原普通 Docker 容器...${gl_bai}"
		local has_container=false
		for json in "$BACKUP_DIR"/*_inspect.json; do
			[[ ! -f "$json" ]] && continue
			has_container=true
			container=$(basename "$json" | sed 's/_inspect.json//')
			echo -e "${gl_lv}处理容器: $container${gl_bai}"

			# 检查容器是否已经存在且正在运行
			if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
				echo -e "${gl_huang}容器 [$container] 已在运行，跳过还原...${gl_bai}"
				continue
			fi

			IMAGE=$(jq -r '.[0].Config.Image' "$json")
			[[ -z "$IMAGE" || "$IMAGE" == "null" ]] && { echo -e "${gl_hong}未找到镜像信息，跳过: $container${gl_bai}"; continue; }

			# 端口映射
			PORT_ARGS=""
			mapfile -t PORTS < <(jq -r '.[0].HostConfig.PortBindings | to_entries[]? | "\(.value[0].HostPort):\(.key | split("/")[0])"' "$json")
			for p in "${PORTS[@]}"; do
				[[ -n "$p" ]] && PORT_ARGS="$PORT_ARGS -p $p"
			done

			# 环境变量
			ENV_ARGS=""
			mapfile -t ENVS < <(jq -r '.[0].Config.Env[]' "$json")
			for e in "${ENVS[@]}"; do
				ENV_ARGS="$ENV_ARGS -e \"$e\""
			done

			# 卷映射 + 卷数据恢复
			VOL_ARGS=""
			mapfile -t VOLS < <(jq -r '.[0].Mounts[] | "\(.Source):\(.Destination)"' "$json")
			for v in "${VOLS[@]}"; do
				VOL_SRC=$(echo "$v" | cut -d':' -f1)
				VOL_DST=$(echo "$v" | cut -d':' -f2)
				mkdir -p "$VOL_SRC"
				VOL_ARGS="$VOL_ARGS -v $VOL_SRC:$VOL_DST"

				VOL_FILE="$BACKUP_DIR/${container}_$(basename $VOL_SRC).tar.gz"
				if [[ -f "$VOL_FILE" ]]; then
					echo "恢复卷数据: $VOL_SRC"
					tar -xzf "$VOL_FILE" -C /
				fi
			done

			# 删除已存在但未运行的容器
			if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
				echo -e "${gl_huang}容器 [$container] 存在但未运行，删除旧容器...${gl_bai}"
				docker rm -f "$container"
			fi

			# 启动容器
			echo "执行还原命令: docker run -d --name \"$container\" $PORT_ARGS $VOL_ARGS $ENV_ARGS \"$IMAGE\""
			eval "docker run -d --name \"$container\" $PORT_ARGS $VOL_ARGS $ENV_ARGS \"$IMAGE\""
		done

		[[ "$has_container" == false ]] && echo -e "${gl_huang}未找到普通容器的备份信息${gl_bai}"

		# 还原 /home/docker 下的文件
		if [ -f "$BACKUP_DIR/home_docker_files.tar.gz" ]; then
			echo -e "${gl_kjlan}正在还原 /home/docker 下的文件...${gl_bai}"
			mkdir -p /home/docker
			tar -xzf "$BACKUP_DIR/home_docker_files.tar.gz" -C /
			echo -e "${gl_lv}/home/docker 下的文件已还原完成${gl_bai}"
		else
			echo -e "${gl_huang}未找到 /home/docker 下文件的备份，跳过...${gl_bai}"
		fi


	}


	# ----------------------------
	# 迁移
	# ----------------------------
	migrate_docker() {
		install jq
		read -e -p  "请输入要迁移的备份目录: " BACKUP_DIR
		[[ ! -d "$BACKUP_DIR" ]] && { echo -e "${gl_hong}备份目录不存在${gl_bai}"; return; }

		kj_ssh_read_host_user_port "目标服务器IP: " "目标服务器SSH用户名 [默认root]: " "目标服务器SSH端口 [默认22]: " "root" "22"
		local TARGET_IP="$KJ_SSH_HOST"
		local TARGET_USER="$KJ_SSH_USER"
		local TARGET_PORT="$KJ_SSH_PORT"

		local LATEST_TAR="$BACKUP_DIR"

		echo -e "${gl_huang}传输备份中...${gl_bai}"
		if [[ -z "$TARGET_PASS" ]]; then
			# 使用密钥登录
			scp -P "$TARGET_PORT" -o StrictHostKeyChecking=no -r "$LATEST_TAR" "$TARGET_USER@$TARGET_IP:/tmp/"
		fi

	}

	# ----------------------------
	# 删除备份
	# ----------------------------
	delete_backup() {
		read -e -p  "请输入要删除的备份目录: " BACKUP_DIR
		[[ ! -d "$BACKUP_DIR" ]] && { echo -e "${gl_hong}备份目录不存在${gl_bai}"; return; }
		rm -rf "$BACKUP_DIR"
		echo -e "${gl_lv}已删除备份: ${BACKUP_DIR}${gl_bai}"
	}

	# ----------------------------
	# 主菜单
	# ----------------------------
	main_menu() {
		while true; do
			clear
			echo "------------------------"
			echo -e "Docker备份/迁移/还原工具"
			echo "------------------------"
			list_backups
			echo -e ""
			echo "------------------------"
			echo -e "1. 备份docker项目"
			echo -e "2. 迁移docker项目"
			echo -e "3. 还原docker项目"
			echo -e "4. 删除docker项目的备份文件"
			echo "5. 通用加密备份与恢复 (.kpb，与 KPanel 互通)"
			echo "------------------------"
			echo -e "0. 返回上一级选单"
			echo "------------------------"
			read -e -p  "请选择: " choice
			case $choice in
				1) backup_docker ;;
				2) migrate_docker ;;
				3) restore_docker ;;
				4) delete_backup ;;
				5) kpanel_backup_center_dispatch menu docker ;;
				0) return ;;
				*) echo -e "${gl_hong}无效选项${gl_bai}" ;;
			esac
		break_end
		done
	}

	main_menu
}





linux_docker() {

	while true; do
	  clear
	  echo -e "Docker管理"
	  docker_tato
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}1.   ${gl_bai}安装更新Docker环境 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}2.   ${gl_bai}查看Docker全局状态 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}3.   ${gl_bai}Docker容器管理 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}4.   ${gl_bai}Docker镜像管理"
	  echo -e "${gl_kjlan}5.   ${gl_bai}Docker网络管理"
	  echo -e "${gl_kjlan}6.   ${gl_bai}Docker卷管理"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}7.   ${gl_bai}清理无用的docker容器和镜像网络数据卷"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}8.   ${gl_bai}更换Docker源"
	  echo -e "${gl_kjlan}9.   ${gl_bai}编辑daemon.json文件"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}11.  ${gl_bai}开启Docker-ipv6访问"
	  echo -e "${gl_kjlan}12.  ${gl_bai}关闭Docker-ipv6访问"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}19.  ${gl_bai}备份/迁移/还原Docker环境"
	  echo -e "${gl_kjlan}20.  ${gl_bai}卸载Docker环境"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}0.   ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in
		  1)
			clear
			install_add_docker

			  ;;
		  2)
			  clear
			  local container_count=$(docker ps -a -q 2>/dev/null | wc -l)
			  local image_count=$(docker images -q 2>/dev/null | wc -l)
			  local network_count=$(docker network ls -q 2>/dev/null | wc -l)
			  local volume_count=$(docker volume ls -q 2>/dev/null | wc -l)

			  echo "Docker版本"
			  docker -v
			  docker compose version

			  echo ""
			  echo -e "Docker镜像: ${gl_lv}$image_count${gl_bai} "
			  docker image ls
			  echo ""
			  echo -e "Docker容器: ${gl_lv}$container_count${gl_bai}"
			  docker ps -a
			  echo ""
			  echo -e "Docker卷: ${gl_lv}$volume_count${gl_bai}"
			  docker volume ls
			  echo ""
			  echo -e "Docker网络: ${gl_lv}$network_count${gl_bai}"
			  docker network ls
			  echo ""

			  ;;
		  3)
			  docker_ps
			  ;;
		  4)
			  docker_image
			  ;;

		  5)
			  while true; do
				  clear
				  echo "Docker网络列表"
				  echo "------------------------------------------------------------"
				  docker network ls
				  echo ""

				  echo "------------------------------------------------------------"
				  container_ids=$(docker ps -q)
				  printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"

				  for container_id in $container_ids; do
					  local container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")

					  local container_name=$(echo "$container_info" | awk '{print $1}')
					  local network_info=$(echo "$container_info" | cut -d' ' -f2-)

					  while IFS= read -r line; do
						  local network_name=$(echo "$line" | awk '{print $1}')
						  local ip_address=$(echo "$line" | awk '{print $2}')

						  printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
					  done <<< "$network_info"
				  done

				  echo ""
				  echo "网络操作"
				  echo "------------------------"
				  echo "1. 创建网络"
				  echo "2. 加入网络"
				  echo "3. 退出网络"
				  echo "4. 删除网络"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
						  read -e -p "设置新网络名: " dockernetwork
						  docker network create $dockernetwork
						  ;;
					  2)
						  read -e -p "加入网络名: " dockernetwork
						  read -e -p "那些容器加入该网络（多个容器名请用空格分隔）: " dockernames

						  for dockername in $dockernames; do
							  docker network connect $dockernetwork $dockername
						  done
						  ;;
					  3)
						  read -e -p "退出网络名: " dockernetwork
						  read -e -p "那些容器退出该网络（多个容器名请用空格分隔）: " dockernames

						  for dockername in $dockernames; do
							  docker network disconnect $dockernetwork $dockername
						  done

						  ;;

					  4)
						  read -e -p "请输入要删除的网络名: " dockernetwork
						  docker network rm $dockernetwork
						  ;;

					  *)
						  break  # 跳出循环，退出菜单
						  ;;
				  esac
			  done
			  ;;

		  6)
			  while true; do
				  clear
				  echo "Docker卷列表"
				  docker volume ls
				  echo ""
				  echo "卷操作"
				  echo "------------------------"
				  echo "1. 创建新卷"
				  echo "2. 删除指定卷"
				  echo "3. 删除所有卷"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
						  read -e -p "设置新卷名: " dockerjuan
						  docker volume create $dockerjuan

						  ;;
					  2)
						  read -e -p "输入删除卷名（多个卷名请用空格分隔）: " dockerjuans

						  for dockerjuan in $dockerjuans; do
							  docker volume rm $dockerjuan
						  done

						  ;;

					   3)
						  read -e -p "$(echo -e "${gl_hong}注意: ${gl_bai}确定删除所有未使用的卷吗？(Y/N): ")" choice
						  case "$choice" in
							[Yy])
							  docker volume prune -f
							  ;;
							[Nn])
							  ;;
							*)
							  echo "无效的选择，请输入 Y 或 N。"
							  ;;
						  esac
						  ;;

					  *)
						  break  # 跳出循环，退出菜单
						  ;;
				  esac
			  done
			  ;;
		  7)
			  clear
			  read -e -p "$(echo -e "${gl_huang}提示: ${gl_bai}将清理无用的镜像容器网络，包括停止的容器，确定清理吗？(Y/N): ")" choice
			  case "$choice" in
				[Yy])
				  docker system prune -af --volumes
				  ;;
				[Nn])
				  ;;
				*)
				  echo "无效的选择，请输入 Y 或 N。"
				  ;;
			  esac
			  ;;
		  8)
			  clear
			  bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
			  ;;

		  9)
			  clear
			  install nano
			  mkdir -p /etc/docker && nano /etc/docker/daemon.json
			  restart docker
			  ;;




		  11)
			  clear
			  docker_ipv6_on
			  ;;

		  12)
			  clear
			  docker_ipv6_off
			  ;;

		  19)
			  docker_ssh_migration
			  ;;


		  20)
			  clear
			  read -e -p "$(echo -e "${gl_hong}注意: ${gl_bai}确定卸载docker环境吗？(Y/N): ")" choice
			  case "$choice" in
				[Yy])
				  docker ps -a -q | xargs -r docker rm -f && docker images -q | xargs -r docker rmi && docker network prune -f && docker volume prune -f
				  remove docker docker-compose docker-ce docker-ce-cli containerd.io
				  rm -f /etc/docker/daemon.json
				  hash -r
				  ;;
				[Nn])
				  ;;
				*)
				  echo "无效的选择，请输入 Y 或 N。"
				  ;;
			  esac
			  ;;

		  0)
			  kejilion
			  ;;
		  *)
			  echo "无效的输入!"
			  ;;
	  esac
	  break_end


	done


}




kpanel_test_catalog() {
	cat <<'KPANEL_TEST_CATALOG'
KPANEL_TEST_CATEGORY	access	IP 与解锁
KPANEL_TEST_CATEGORY	network	网络线路
KPANEL_TEST_CATEGORY	hardware	硬件性能
KPANEL_TEST_CATEGORY	comprehensive	综合评测
KPANEL_TEST_ITEM	chatgpt	access	ChatGPT 解锁检测	检测当前出口 IP 的 ChatGPT 可用性	https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh	2	light
KPANEL_TEST_ITEM	region	access	Region 流媒体解锁	检测常见流媒体服务的地区解锁状态	https://check.unlock.media	5	network
KPANEL_TEST_ITEM	media	access	yeahwu 流媒体检测	检测常见流媒体与 AI 服务的可用区域	https://github.com/yeahwu/check/raw/main/check.sh	5	network
KPANEL_TEST_ITEM	ip-quality	access	IP 质量体检	检测 IP 风险、信誉、邮件与流媒体质量	https://IP.Check.Place	8	network
KPANEL_TEST_ITEM	besttrace	network	BestTrace 三网回程	检测三网回程延迟和路由	https://git.io/besttrace	8	network
KPANEL_TEST_ITEM	mtr	network	MTR 三网回程	使用 MTR 检测三网回程线路	https://github.com/zhucaidan/mtr_trace/raw/main/mtr_trace.sh	8	network
KPANEL_TEST_ITEM	superspeed	network	SuperSpeed 三网测速	执行国内三网节点带宽测试	https://git.io/superspeed_uxh	15	intensive
KPANEL_TEST_ITEM	nxtrace-fast	network	NextTrace 快速回程	执行 TCP 快速回程路由测试	https://nxtrace.org/nt	8	network
KPANEL_TEST_ITEM	backtrace	network	三网线路测试	检测电信、联通和移动回程线路	https://github.com/ludashi2020/backtrace/raw/main/install.sh	8	network
KPANEL_TEST_ITEM	speedtest	network	多功能测速	运行 i-abc 多节点网络测速	https://github.com/i-abc/Speedtest/raw/main/speedtest.sh	15	intensive
KPANEL_TEST_ITEM	net-quality	network	网络质量体检	检测延迟、抖动、丢包和网络质量	https://Net.Check.Place	10	network
KPANEL_TEST_ITEM	tcp-quality	network	TCP 重传探测	检测 TCP 重传和连接质量	https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh	10	network
KPANEL_TEST_ITEM	yabs	hardware	YABS 性能测试	测试 CPU、磁盘与网络；无 Swap 时按脚本创建 1 GiB /swapfile	https://yabs.sh	30	intensive
KPANEL_TEST_ITEM	cpu	hardware	CPU 性能测试	运行 Geekbench 5；无 Swap 时按脚本创建 1 GiB /swapfile	https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh	30	intensive
KPANEL_TEST_ITEM	bench	comprehensive	Bench 综合测试	输出系统信息、磁盘与网络综合结果	https://bench.sh	15	intensive
KPANEL_TEST_ITEM	ecs	comprehensive	融合怪综合测评	运行 spiritLHLS ECS 综合性能与质量测评	https://github.com/spiritLHLS/ecs/raw/main/ecs.sh	45	intensive
KPANEL_TEST_ITEM	nodequality	comprehensive	NodeQuality 综合测评	运行 NodeQuality 节点质量综合测试	https://run.NodeQuality.com	30	intensive
KPANEL_TEST_CATALOG
}

kpanel_run_remote_bash() {
	local source_url="${1:-}"
	shift || true
	[ -n "$source_url" ] || return 64

	local test_workspace test_script command_status
	test_workspace="$(mktemp -d)" || return 1
	test_script="$test_workspace/test.sh"
	curl -fsSL "$source_url" -o "$test_script"
	command_status=$?
	if [ "$command_status" -ne 0 ]; then
		rm -f "$test_script"
		rmdir "$test_workspace" 2>/dev/null || true
		return "$command_status"
	fi
	chmod 700 "$test_script"
	bash "$test_script" "$@"
	command_status=$?
	rm -f "$test_script"
	rmdir "$test_workspace" 2>/dev/null || true
	return "$command_status"
}

kpanel_run_test_noninteractive() {
	[ "${KJ_TEST_NONINTERACTIVE:-}" = "1" ] || return 2

	local action="${1:-list}"
	local selector="${2:-}"
	case "$action" in
		list)
			[ "$#" -eq 1 ] || {
				echo "KPANEL_TEST_ERROR list does not accept arguments" >&2
				return 64
			}
			kpanel_test_catalog
			;;
		run)
			[ "$#" -eq 2 ] || {
				echo "KPANEL_TEST_ERROR run requires one fixed test selector" >&2
				return 64
			}
			echo "KPANEL_TEST_START ${selector}"
			(
				set -o pipefail
				case "$selector" in
				chatgpt)
					kpanel_run_remote_bash https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh
					;;
				region)
					kpanel_run_remote_bash https://check.unlock.media
					;;
				media)
					kpanel_run_remote_bash https://github.com/yeahwu/check/raw/main/check.sh
					;;
				ip-quality)
					kpanel_run_remote_bash https://IP.Check.Place
					;;
				besttrace)
					kpanel_run_remote_bash https://git.io/besttrace
					;;
				mtr)
					kpanel_run_remote_bash https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh
					;;
				superspeed)
					kpanel_run_remote_bash https://git.io/superspeed_uxh
					;;
				nxtrace-fast)
					kpanel_run_remote_bash https://nxtrace.org/nt
					nexttrace --fast-trace --tcp
					;;
				backtrace)
					kpanel_run_remote_bash https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh
					;;
				speedtest)
					kpanel_run_remote_bash https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh
					;;
				net-quality)
					kpanel_run_remote_bash https://Net.Check.Place
					;;
				tcp-quality)
					kpanel_run_remote_bash https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh
					;;
				yabs)
					check_swap
					kpanel_run_remote_bash https://yabs.sh -i -5
					;;
				cpu)
					check_swap
					kpanel_run_remote_bash https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh
					;;
				bench)
					kpanel_run_remote_bash https://bench.sh
					;;
				ecs)
					local test_workspace
					test_workspace="$(mktemp -d)"
					(
						cd "$test_workspace" &&
						curl -fsSL https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh &&
						chmod +x ecs.sh &&
						bash ecs.sh
					)
					local ecs_status=$?
					rm -f "$test_workspace/ecs.sh"
					rmdir "$test_workspace" 2>/dev/null || true
					[ "$ecs_status" -eq 0 ] || return "$ecs_status"
					;;
				nodequality)
					kpanel_run_remote_bash https://run.NodeQuality.com
					;;
				*)
					echo "KPANEL_TEST_ERROR unsupported test selector" >&2
					exit 64
					;;
				esac
			)
			local command_status=$?
			if [ "$command_status" -ne 0 ]; then
				echo "KPANEL_TEST_RESULT failed ${selector}" >&2
				return "$command_status"
			fi
			echo "KPANEL_TEST_RESULT succeeded ${selector}"
			;;
		*)
			echo "KPANEL_TEST_ERROR unsupported action" >&2
			return 64
			;;
	esac
}


linux_test() {

	while true; do
	  clear
	  echo -e "测试脚本合集"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}IP及解锁状态检测"
	  echo -e "${gl_kjlan}1.   ${gl_bai}ChatGPT 解锁状态检测"
	  echo -e "${gl_kjlan}2.   ${gl_bai}Region 流媒体解锁测试"
	  echo -e "${gl_kjlan}3.   ${gl_bai}yeahwu 流媒体解锁检测"
	  echo -e "${gl_kjlan}4.   ${gl_bai}xykt IP质量体检脚本 ${gl_huang}★${gl_bai}"

	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}网络线路测速"
	  echo -e "${gl_kjlan}11.  ${gl_bai}besttrace 三网回程延迟路由测试"
	  echo -e "${gl_kjlan}12.  ${gl_bai}mtr_trace 三网回程线路测试"
	  echo -e "${gl_kjlan}13.  ${gl_bai}Superspeed 三网测速"
	  echo -e "${gl_kjlan}14.  ${gl_bai}nxtrace 快速回程测试脚本"
	  echo -e "${gl_kjlan}15.  ${gl_bai}nxtrace 指定IP回程测试脚本"
	  echo -e "${gl_kjlan}16.  ${gl_bai}ludashi2020 三网线路测试"
	  echo -e "${gl_kjlan}17.  ${gl_bai}i-abc 多功能测速脚本"
	  echo -e "${gl_kjlan}18.  ${gl_bai}NetQuality 网络质量体检脚本 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}19.  ${gl_bai}TcpQuality TCP重传探测脚本 ${gl_huang}★${gl_bai}"

	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}硬件性能测试"
	  echo -e "${gl_kjlan}21.  ${gl_bai}yabs 性能测试"
	  echo -e "${gl_kjlan}22.  ${gl_bai}icu/gb5 CPU性能测试脚本"

	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}综合性测试"
	  echo -e "${gl_kjlan}31.  ${gl_bai}bench 性能测试"
	  echo -e "${gl_kjlan}32.  ${gl_bai}spiritysdx 融合怪测评 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}33.  ${gl_bai}nodequality 融合怪测评 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}0.   ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in
		  1)
			  clear
			  bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh)
			  ;;
		  2)
			  clear
			  bash <(curl -L -s check.unlock.media)
			  ;;
		  3)
			  clear
			  install wget
			  wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash
			  ;;
		  4)
			  clear
			  bash <(curl -Ls IP.Check.Place)
			  ;;


		  11)
			  clear
			  install wget
			  wget -qO- git.io/besttrace | bash
			  ;;
		  12)
			  clear
			  curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash
			  ;;
		  13)
			  clear
			  bash <(curl -Lso- https://git.io/superspeed_uxh)
			  ;;
		  14)
			  clear
			  curl nxtrace.org/nt |bash
			  nexttrace --fast-trace --tcp
			  ;;
		  15)
			  clear
			  echo "可参考的IP列表"
			  echo "------------------------"
			  echo "北京电信: 219.141.136.12"
			  echo "北京联通: 202.106.50.1"
			  echo "北京移动: 221.179.155.161"
			  echo "上海电信: 202.96.209.133"
			  echo "上海联通: 210.22.97.1"
			  echo "上海移动: 211.136.112.200"
			  echo "广州电信: 58.60.188.222"
			  echo "广州联通: 210.21.196.6"
			  echo "广州移动: 120.196.165.24"
			  echo "成都电信: 61.139.2.69"
			  echo "成都联通: 119.6.6.6"
			  echo "成都移动: 211.137.96.205"
			  echo "湖南电信: 36.111.200.100"
			  echo "湖南联通: 42.48.16.100"
			  echo "湖南移动: 39.134.254.6"
			  echo "------------------------"

			  read -e -p "输入一个指定IP: " testip
			  curl nxtrace.org/nt |bash
			  nexttrace $testip
			  ;;

		  16)
			  clear
			  curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh
			  ;;

		  17)
			  clear
			  bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh)
			  ;;

		  18)
			  clear
			  bash <(curl -sL Net.Check.Place)
			  ;;

		  19)
			  clear
			  bash <(curl -sL https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh)
			  ;;

		  21)
			  clear
			  check_swap
			  curl -sL yabs.sh | bash -s -- -i -5
			  ;;
		  22)
			  clear
			  check_swap
			  bash <(curl -fsSL https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh)
			  ;;

		  31)
			  clear
			  curl -Lso- bench.sh | bash
			  ;;
		  32)
			  clear
			  curl -L https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
			  ;;

		  33)
			  clear
			  bash <(curl -sL https://run.NodeQuality.com)
			  ;;



		  0)
			  kejilion

			  ;;
		  *)
			  echo "无效的输入!"
			  ;;
	  esac
	  break_end

	done


}




docker_tato() {

	local container_count=$(docker ps -a -q 2>/dev/null | wc -l)
	local image_count=$(docker images -q 2>/dev/null | wc -l)
	local network_count=$(docker network ls -q 2>/dev/null | wc -l)
	local volume_count=$(docker volume ls -q 2>/dev/null | wc -l)

	if command -v docker &> /dev/null; then
		echo -e "${gl_kjlan}------------------------"
		echo -e "${gl_lv}环境已经安装${gl_bai}  容器: ${gl_lv}$container_count${gl_bai}  镜像: ${gl_lv}$image_count${gl_bai}  网络: ${gl_lv}$network_count${gl_bai}  卷: ${gl_lv}$volume_count${gl_bai}"
	fi
}



linux_work() {

	while true; do
	  clear
	  echo -e "后台工作区"
	  echo -e "系统将为你提供可以后台常驻运行的工作区，你可以用来执行长时间的任务"
	  echo -e "即使你断开SSH，工作区中的任务也不会中断，后台常驻任务。"
	  echo -e "${gl_huang}提示: ${gl_bai}进入工作区后使用Ctrl+b再单独按d，退出工作区！"
	  echo -e "${gl_kjlan}------------------------"
	  echo "当前已存在的工作区列表"
	  echo -e "${gl_kjlan}------------------------"
	  tmux list-sessions
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}1.   ${gl_bai}1号工作区"
	  echo -e "${gl_kjlan}2.   ${gl_bai}2号工作区"
	  echo -e "${gl_kjlan}3.   ${gl_bai}3号工作区"
	  echo -e "${gl_kjlan}4.   ${gl_bai}4号工作区"
	  echo -e "${gl_kjlan}5.   ${gl_bai}5号工作区"
	  echo -e "${gl_kjlan}6.   ${gl_bai}6号工作区"
	  echo -e "${gl_kjlan}7.   ${gl_bai}7号工作区"
	  echo -e "${gl_kjlan}8.   ${gl_bai}8号工作区"
	  echo -e "${gl_kjlan}9.   ${gl_bai}9号工作区"
	  echo -e "${gl_kjlan}10.  ${gl_bai}10号工作区"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}21.  ${gl_bai}SSH常驻模式 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}22.  ${gl_bai}创建/进入工作区"
	  echo -e "${gl_kjlan}23.  ${gl_bai}注入命令到后台工作区"
	  echo -e "${gl_kjlan}24.  ${gl_bai}删除指定工作区"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}0.   ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in

		  1)
			  clear
			  install tmux
			  local SESSION_NAME="work1"
			  tmux_run

			  ;;
		  2)
			  clear
			  install tmux
			  local SESSION_NAME="work2"
			  tmux_run
			  ;;
		  3)
			  clear
			  install tmux
			  local SESSION_NAME="work3"
			  tmux_run
			  ;;
		  4)
			  clear
			  install tmux
			  local SESSION_NAME="work4"
			  tmux_run
			  ;;
		  5)
			  clear
			  install tmux
			  local SESSION_NAME="work5"
			  tmux_run
			  ;;
		  6)
			  clear
			  install tmux
			  local SESSION_NAME="work6"
			  tmux_run
			  ;;
		  7)
			  clear
			  install tmux
			  local SESSION_NAME="work7"
			  tmux_run
			  ;;
		  8)
			  clear
			  install tmux
			  local SESSION_NAME="work8"
			  tmux_run
			  ;;
		  9)
			  clear
			  install tmux
			  local SESSION_NAME="work9"
			  tmux_run
			  ;;
		  10)
			  clear
			  install tmux
			  local SESSION_NAME="work10"
			  tmux_run
			  ;;

		  21)
			while true; do
			  clear
			  if grep -q 'tmux attach-session -t sshd || tmux new-session -s sshd' ~/.bashrc; then
				  local tmux_sshd_status="${gl_lv}开启${gl_bai}"
			  else
				  local tmux_sshd_status="${gl_hui}关闭${gl_bai}"
			  fi
			  echo -e "SSH常驻模式 ${tmux_sshd_status}"
			  echo "开启后SSH连接后会直接进入常驻模式，直接回到之前的工作状态。"
			  echo "------------------------"
			  echo "1. 开启            2. 关闭"
			  echo "------------------------"
			  echo "0. 返回上一级选单"
			  echo "------------------------"
			  read -e -p "请输入你的选择: " gongzuoqu_del
			  case "$gongzuoqu_del" in
				1)
			  	  install tmux
			  	  local SESSION_NAME="sshd"
				  grep -q "tmux attach-session -t sshd" ~/.bashrc || echo -e "\n# 自动进入 tmux 会话\nif [[ -z \"\$TMUX\" ]]; then\n    tmux attach-session -t sshd || tmux new-session -s sshd\nfi" >> ~/.bashrc
				  source ~/.bashrc
			  	  tmux_run
				  ;;
				2)
				  sed -i '/# 自动进入 tmux 会话/,+4d' ~/.bashrc
				  tmux kill-window -t sshd
				  ;;
				*)
				  break
				  ;;
			  esac
			done
			  ;;

		  22)
			  read -e -p "请输入你创建或进入的工作区名称，如1001 kj001 work1: " SESSION_NAME
			  tmux_run
			  ;;


		  23)
			  read -e -p "请输入你要后台执行的命令，如:curl -fsSL https://get.docker.com | sh: " tmuxd
			  tmux_run_d
			  ;;

		  24)
			  read -e -p "请输入要删除的工作区名称: " gongzuoqu_name
			  tmux kill-window -t $gongzuoqu_name
			  ;;

		  0)
			  kejilion
			  ;;
		  *)
			  echo "无效的输入!"
			  ;;
	  esac
	  break_end

	done


}










# 智能切换镜像源函数
switch_mirror() {
	# 可选参数，默认为 false
	local upgrade_software=${1:-false}
	local clean_cache=${2:-false}

	# 获取用户国家
	local country
	country=$(curl -s ipinfo.io/country)

	echo "检测到国家：$country"

	if [ "$country" = "CN" ]; then
		echo "使用国内镜像源..."
		bash <(curl -sSL https://linuxmirrors.cn/main.sh) \
		  --source mirrors.huaweicloud.com \
		  --protocol https \
		  --use-intranet-source false \
		  --backup true \
		  --upgrade-software "$upgrade_software" \
		  --clean-cache "$clean_cache" \
		  --ignore-backup-tips \
		  --install-epel false \
		  --pure-mode
	else
		echo "使用海外镜像源..."
		if [ -f /etc/os-release ] && grep -qi "oracle" /etc/os-release; then
			bash <(curl -sSL https://linuxmirrors.cn/main.sh) \
			  --source mirrors.xtom.com \
			  --protocol https \
			  --use-intranet-source false \
			  --backup true \
			  --upgrade-software "$upgrade_software" \
			  --clean-cache "$clean_cache" \
			  --ignore-backup-tips \
			  --install-epel false \
			  --pure-mode
		else
			bash <(curl -sSL https://linuxmirrors.cn/main.sh) \
				--use-official-source true \
				--protocol https \
				--use-intranet-source false \
				--backup true \
				--upgrade-software "$upgrade_software" \
				--clean-cache "$clean_cache" \
				--ignore-backup-tips \
				--install-epel false \
				--pure-mode
		fi
	fi
}


fail2ban_panel() {
		  root_use
		  while true; do

				check_f2b_status
				echo -e "SSH防御程序 $check_f2b_status"
				echo "fail2ban是一个SSH防止暴力破解工具"
				echo "官网介绍: https://github.com/fail2ban/fail2ban"
				echo "------------------------"
				echo "1. 安装防御程序"
				echo "------------------------"
				echo "2. 查看SSH拦截记录"
				echo "3. 日志实时监控"
				echo "------------------------"
				echo "4. 基础参数配置（封禁时长/时间窗口/重试次数）"
				echo "5. 编辑配置文件（nano）"
				echo "------------------------"
				echo "9. 卸载防御程序"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "请输入你的选择: " sub_choice
				case $sub_choice in
					1)
						f2b_install_sshd
						cd ~
						f2b_status
						break_end
						;;
					2)
						echo "------------------------"
						f2b_sshd
						echo "------------------------"
						break_end
						;;
					3)
						tail -f /var/log/fail2ban.log
						break
						;;
					4)
						f2b_basic_config
						break_end
						;;
					5)
						f2b_edit_config
						break_end
						;;
					9)
						remove fail2ban
						rm -rf /etc/fail2ban
						echo "Fail2Ban防御程序已卸载"
						break
						;;
					*)
						break
						;;
				esac
		  done

}





net_menu() {

	show_nics() {
		echo "================ 当前网卡信息 ================"
		printf "%-18s %-12s %-20s %-26s\n" "网卡名" "状态" "IP地址" "MAC地址"
		echo "------------------------------------------------"
		for nic in $(ls /sys/class/net); do
			state=$(cat /sys/class/net/$nic/operstate 2>/dev/null)
			ipaddr=$(ip -4 addr show $nic | awk '/inet /{print $2}' | head -n1)
			mac=$(cat /sys/class/net/$nic/address 2>/dev/null)
			printf "%-15s %-10s %-18s %-20s\n" "$nic" "$state" "${ipaddr:-无}" "$mac"
		done
		echo "================================================"
	}

	while true; do
		clear
		show_nics
		echo
		echo "=========== 网卡管理菜单 ==========="
		echo "1. 启用网卡"
		echo "2. 禁用网卡"
		echo "3. 查看网卡详细信息"
		echo "4. 刷新网卡信息"
		echo "0. 返回上一级选单"
		echo "===================================="
		read -erp "请选择操作: " choice

		case $choice in
			1)
				read -erp "请输入要启用的网卡名: " nic
				if ip link show "$nic" &>/dev/null; then
					ip link set "$nic" up && echo "✔ 网卡 $nic 已启用"
				else
					echo "✘ 网卡不存在"
				fi
				read -erp "按回车继续..."
				;;
			2)
				read -erp "请输入要禁用的网卡名: " nic
				if ip link show "$nic" &>/dev/null; then
					ip link set "$nic" down && echo "✔ 网卡 $nic 已禁用"
				else
					echo "✘ 网卡不存在"
				fi
				read -erp "按回车继续..."
				;;
			3)
				read -erp "请输入要查看的网卡名: " nic
				if ip link show "$nic" &>/dev/null; then
					echo "========== $nic 详细信息 =========="
					ip addr show "$nic"
					ethtool "$nic" 2>/dev/null | head -n 10
				else
					echo "✘ 网卡不存在"
				fi
				read -erp "按回车继续..."
				;;
			4)
				continue
				;;
			*)
				break
				;;
		esac
	done
}



# KPanel system resource protocol start
KPANEL_SYSTEM_RESOURCE_PROTOCOL_VERSION="3"

kpanel_system_resource_zero_version() {
	printf '%064d' 0
}

kpanel_system_resource_emit() {
	local status="$1"
	local version="$2"
	local backup="${3:-}"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || version="$(kpanel_system_resource_zero_version)"
	printf 'KPANEL_SYSTEM_RESOURCE_STATUS=%s\n' "$status"
	printf 'KPANEL_SYSTEM_RESOURCE_VERSION=%s\n' "$version"
	[ -z "$backup" ] || printf 'KPANEL_SYSTEM_RESOURCE_BACKUP=%s\n' "$backup"
}

kpanel_system_resource_error() {
	printf '错误: %s\n' "$1" >&2
}

kpanel_system_resource_valid_version() {
	[[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

kpanel_system_resource_single_line() {
	local value="$1"
	local maximum="$2"
	local bytes
	bytes="$(printf '%s' "$value" | wc -c)" || return 1
	[ "$bytes" -le "$maximum" ] &&
		[[ "$value" != *$'\n'* ]] &&
		[[ "$value" != *$'\r'* ]]
}

kpanel_system_resource_copy_identity() {
	local source="$1"
	local target="$2"
	local mode owner
	mode="$(stat -c '%a' "$source" 2>/dev/null)" || return 1
	owner="$(stat -c '%u:%g' "$source" 2>/dev/null)" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || return 1
	chown "$owner" "$target" >/dev/null 2>&1 &&
		chmod "$mode" "$target" >/dev/null 2>&1
}

kpanel_system_resource_file_within_bounds() {
	local path="$1"
	local maximum_bytes="$2"
	local maximum_lines="$3"
	local bytes lines
	bytes="$(wc -c < "$path" 2>/dev/null)" || return 1
	lines="$(awk 'END {print NR + 0}' "$path" 2>/dev/null)" || return 1
	[ "$bytes" -le "$maximum_bytes" ] && [ "$lines" -le "$maximum_lines" ]
}

kpanel_system_resource_hosts_file() {
	printf '%s\n' "/etc/hosts"
}

kpanel_system_resource_lock_dir() {
	printf '%s\n' "/run/kejilion-system-resource"
}

kpanel_system_resource_lock_owner_uid() {
	printf '0\n'
}

kpanel_system_resource_lock_stat_uid() {
	stat -c '%u' "$1" 2>/dev/null
}

kpanel_system_resource_lock_stat_mode() {
	stat -c '%a' "$1" 2>/dev/null
}

kpanel_system_resource_lock_file() {
	printf '%s/system-resource.lock\n' "$(kpanel_system_resource_lock_dir)"
}

kpanel_system_resource_interfaces_dir() {
	printf '%s\n' "/sys/class/net"
}

kpanel_system_resource_iptables_rules_file() {
	printf '%s\n' "/etc/iptables/rules.v4"
}

kpanel_system_resource_tempdir() {
	local resource="$1"
	local directory
	directory="$(mktemp -d "/tmp/kejilion-system-resource-${resource}.XXXXXX")" || return 1
	chmod 700 "$directory" || {
		rm -rf -- "$directory"
		return 1
	}
	printf '%s\n' "$directory"
}

kpanel_system_resource_state_root() {
	printf '%s\n' "/var/lib/kejilion-panel"
}

kpanel_system_resource_path_has_no_symlink() {
	local path="$1"
	local remainder current="" component
	local components=()

	[[ "$path" = /* ]] && [ "$path" != "/" ] || return 1
	remainder="${path#/}"
	IFS=/ read -r -a components <<< "$remainder"
	for component in "${components[@]}"; do
		[ -n "$component" ] && [ "$component" != "." ] && [ "$component" != ".." ] || return 1
		current="$current/$component"
		[ ! -L "$current" ] || return 1
	done
}

kpanel_system_resource_lock_path_secure() {
	local path="$1"
	local kind="$2"
	local required_mode="${3:-}"
	local uid expected_uid mode

	[ ! -L "$path" ] || return 1
	case "$kind" in
		directory) [ -d "$path" ] ;;
		file) [ -f "$path" ] ;;
		*) return 1 ;;
	esac || return 1
	uid="$(kpanel_system_resource_lock_stat_uid "$path")" || return 1
	expected_uid="$(kpanel_system_resource_lock_owner_uid)" || return 1
	[[ "$uid" =~ ^[0-9]+$ ]] && [[ "$expected_uid" =~ ^[0-9]+$ ]] &&
		[ "$uid" = "$expected_uid" ] || return 1
	mode="$(kpanel_system_resource_lock_stat_mode "$path")" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
	[ "$((8#$mode & 0022))" -eq 0 ] || return 1
	[ -z "$required_mode" ] || [ "$((8#$mode & 0777))" -eq "$((8#$required_mode))" ]
}

kpanel_system_resource_prepare_lock_file() {
	local lock_dir lock_parent lock_file

	lock_dir="$(kpanel_system_resource_lock_dir)" || return 1
	lock_file="$(kpanel_system_resource_lock_file)" || return 1
	kpanel_system_resource_single_line "$lock_dir" 1024 || return 1
	kpanel_system_resource_single_line "$lock_file" 1024 || return 1
	[[ "$lock_dir" = /* ]] && [ "$lock_file" = "$lock_dir/system-resource.lock" ] || return 1
	kpanel_system_resource_path_has_no_symlink "$lock_dir" || return 1
	lock_parent="$(dirname -- "$lock_dir")" || return 1
	kpanel_system_resource_lock_path_secure "$lock_parent" directory || return 1
	if [ -e "$lock_dir" ]; then
		kpanel_system_resource_lock_path_secure "$lock_dir" directory || return 1
	else
		(umask 077; mkdir -- "$lock_dir") >/dev/null 2>&1 || return 1
	fi
	chown 0:0 "$lock_dir" >/dev/null 2>&1 && chmod 700 "$lock_dir" >/dev/null 2>&1 || return 1
	kpanel_system_resource_lock_path_secure "$lock_dir" directory 700 || return 1
	[ ! -L "$lock_file" ] || return 1
	if [ -e "$lock_file" ]; then
		kpanel_system_resource_lock_path_secure "$lock_file" file || return 1
	else
		(umask 077; set -o noclobber; : > "$lock_file") >/dev/null 2>&1 || {
			[ -e "$lock_file" ] && [ ! -L "$lock_file" ] || return 1
		}
	fi
	kpanel_system_resource_lock_path_secure "$lock_file" file || return 1
	chown 0:0 "$lock_file" >/dev/null 2>&1 && chmod 600 "$lock_file" >/dev/null 2>&1 || return 1
	kpanel_system_resource_lock_path_secure "$lock_file" file 600 || return 1
	printf '%s\n' "$lock_file"
}

kpanel_system_resource_secure_directory() {
	local path="$1"
	[ ! -L "$path" ] || return 1
	if [ -e "$path" ]; then
		[ -d "$path" ] || return 1
	else
		mkdir -- "$path" >/dev/null 2>&1 || return 1
	fi
	[ -d "$path" ] && [ ! -L "$path" ] || return 1
	chown 0:0 "$path" >/dev/null 2>&1 && chmod 700 "$path" >/dev/null 2>&1
}

kpanel_system_resource_prepare_recovery_root() {
	local state_root path mode
	state_root="$(kpanel_system_resource_state_root)" || return 1
	kpanel_system_resource_single_line "$state_root" 1024 || return 1
	kpanel_system_resource_path_has_no_symlink "$state_root" || return 1
	if [ -e "$state_root" ]; then
		[ -d "$state_root" ] && [ ! -L "$state_root" ] || return 1
	else
		mkdir -- "$state_root" >/dev/null 2>&1 || return 1
		chmod 700 "$state_root" >/dev/null 2>&1 || return 1
	fi
	chown 0:0 "$state_root" >/dev/null 2>&1 || return 1
	mode="$(stat -c '%a' "$state_root" 2>/dev/null)" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
	[ "$((8#$mode & 0022))" -eq 0 ] || return 1
	path="$state_root"
	for component in system recovery system-resource; do
		path="$path/$component"
		kpanel_system_resource_secure_directory "$path" || return 1
	done
	printf '%s\n' "$path"
}

kpanel_system_resource_persist_recovery_snapshot() {
	local snapshot_dir="$1"
	local resource="$2"
	local recovery_root destination timestamp invalid

	[[ "$resource" =~ ^(hosts|cron|firewall|traffic-shutdown|account-management|ssh-defense)$ ]] || return 1
	[ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] || return 1
	invalid="$(find "$snapshot_dir" -mindepth 1 \( -type l -o ! -type f \) -print -quit 2>/dev/null)" || return 1
	[ -z "$invalid" ] || return 1
	recovery_root="$(kpanel_system_resource_prepare_recovery_root)" || return 1
	timestamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)" || return 1
	[[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || return 1
	destination="$(mktemp -d "$recovery_root/${timestamp}-${resource}.XXXXXX")" || return 1
	if ! chmod 700 "$destination" >/dev/null 2>&1 ||
		! cp -a -- "$snapshot_dir/." "$destination/" >/dev/null 2>&1; then
		rm -rf -- "$destination"
		return 1
	fi
	invalid="$(find "$destination" -mindepth 1 \( -type l -o ! -type f \) -print -quit 2>/dev/null)" || {
		rm -rf -- "$destination"
		return 1
	}
	if [ -n "$invalid" ] ||
		! chown -R -- 0:0 "$destination" >/dev/null 2>&1 ||
		! find "$destination" -type d -exec chmod 700 -- {} + >/dev/null 2>&1 ||
		! find "$destination" -type f -exec chmod 600 -- {} + >/dev/null 2>&1; then
		rm -rf -- "$destination"
		return 1
	fi
	rm -rf -- "$snapshot_dir" >/dev/null 2>&1 || true
	printf '%s\n' "$destination"
}

kpanel_system_resource_is_ipv4() {
	local value="$1"
	local first second third fourth extra octet
	IFS=. read -r first second third fourth extra <<< "$value"
	[ -z "$extra" ] || return 1
	for octet in "$first" "$second" "$third" "$fourth"; do
		[[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
		[ "$octet" = "0" ] || [[ "$octet" != 0* ]] || return 1
		[ "$((10#$octet))" -le 255 ] || return 1
	done
}

kpanel_system_resource_ipv6_side_count() {
	local side="$1"
	local part index count=0
	local parts=()
	[ -n "$side" ] || {
		printf '0\n'
		return 0
	}
	[[ "$side" != :* && "$side" != *: ]] || return 1
	IFS=: read -r -a parts <<< "$side"
	for index in "${!parts[@]}"; do
		part="${parts[$index]}"
		[ -n "$part" ] || return 1
		if [[ "$part" == *.* ]]; then
			[ "$index" -eq "$((${#parts[@]} - 1))" ] || return 1
			kpanel_system_resource_is_ipv4 "$part" || return 1
			count=$((count + 2))
		else
			[[ "$part" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
			count=$((count + 1))
		fi
	done
	printf '%s\n' "$count"
}

kpanel_system_resource_is_ipv6() {
	local value="$1"
	local left right left_count right_count total
	[ -n "$value" ] && [ "${#value}" -le 45 ] &&
		[[ "$value" == *:* ]] &&
		[[ "$value" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
	if [[ "$value" == *::* ]]; then
		[[ "${value/::/}" != *::* ]] || return 1
		left="${value%%::*}"
		right="${value#*::}"
		left_count="$(kpanel_system_resource_ipv6_side_count "$left")" || return 1
		right_count="$(kpanel_system_resource_ipv6_side_count "$right")" || return 1
		total=$((left_count + right_count))
		[ "$total" -lt 8 ]
	else
		[[ "$value" != :* && "$value" != *: ]] || return 1
		total="$(kpanel_system_resource_ipv6_side_count "$value")" || return 1
		[ "$total" -eq 8 ]
	fi
}

kpanel_system_resource_is_hostname() {
	local value="$1"
	local label
	local labels=()
	[ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
	value="${value%.}"
	[ -n "$value" ] || return 1
	IFS=. read -r -a labels <<< "$value"
	for label in "${labels[@]}"; do
		[ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
		[[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
	done
}

kpanel_system_resource_is_ipv4_cidr() {
	local value="$1"
	local address prefix
	if [[ "$value" == */* ]]; then
		[ "${value//[^\/]/}" = "/" ] || return 1
		address="${value%/*}"
		prefix="${value##*/}"
		[[ "$prefix" =~ ^[0-9]{1,2}$ ]] &&
			{ [ "$prefix" = "0" ] || [[ "$prefix" != 0* ]]; } &&
			[ "$((10#$prefix))" -le 32 ] || return 1
	else
		address="$value"
	fi
	kpanel_system_resource_is_ipv4 "$address"
}

kpanel_system_resource_hosts_version() {
	local path
	path="$(kpanel_system_resource_hosts_file)"
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	sha256sum -- "$path" 2>/dev/null | awk '{print $1}'
}

kpanel_system_resource_cron_capture() {
	local target="$1"
	local error_file="$target.error"
	local rc=0
	KPANEL_SYSTEM_RESOURCE_CRON_EXISTED=false
	LC_ALL=C crontab -l > "$target" 2>"$error_file" || rc=$?
	if [ "$rc" -eq 0 ]; then
		KPANEL_SYSTEM_RESOURCE_CRON_EXISTED=true
	elif grep -Fqi 'no crontab for' "$error_file"; then
		: > "$target" || {
			rm -f -- "$error_file"
			return 1
		}
	else
		rm -f -- "$error_file"
		return 1
	fi
	rm -f -- "$error_file"
	kpanel_system_resource_file_within_bounds "$target" 262144 512
}

kpanel_system_resource_cron_version() {
	local temporary version
	temporary="$(mktemp /tmp/kejilion-system-resource-cron-version.XXXXXX)" || return 1
	if ! kpanel_system_resource_cron_capture "$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	version="$(sha256sum -- "$temporary" 2>/dev/null | awk '{print $1}')"
	rm -f -- "$temporary"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$version"
}

kpanel_system_resource_interface_exists() {
	local name="$1"
	local root candidate
	root="$(kpanel_system_resource_interfaces_dir)"
	[ -d "$root" ] || return 1
	for candidate in "$root"/*; do
		[ -e "$candidate" ] || continue
		[ "$(basename -- "$candidate")" = "$name" ] && return 0
	done
	return 1
}

kpanel_system_resource_interface_version() {
	local name="$1"
	local root state mac
	kpanel_system_resource_interface_exists "$name" || return 1
	root="$(kpanel_system_resource_interfaces_dir)"
	state="$(kpanel_system_resource_interface_admin_state "$name")" || return 1
	mac="$(cat "$root/$name/address" 2>/dev/null)" || return 1
	printf '%s|%s|%s' "$name" "$state" "$mac" | sha256sum | awk '{print $1}'
}

kpanel_system_resource_firewall_canonicalize() {
	local source="$1"
	local target="$2"
	local bytes

	[ -f "$source" ] && [ ! -L "$source" ] || return 1
	bytes="$(wc -c < "$source" 2>/dev/null)" || return 1
	[ "$bytes" -le 524288 ] || return 1
	LC_ALL=C awk '
		{
			line=$0
			sub(/\r$/, "", line)
			if (index(line, "# Generated by iptables-save ") == 1 ||
				index(line, "# Completed on ") == 1) {
				next
			}
			if (line ~ /^:/) {
				sub(/ \[[0-9]+:[0-9]+\]$/, " [0:0]", line)
			}
			print line
		}
	' "$source" > "$target"
}

kpanel_system_resource_firewall_canonical_equal() {
	local left="$1"
	local right="$2"
	local left_canonical right_canonical result

	left_canonical="$(mktemp /tmp/kejilion-system-resource-firewall-left.XXXXXX)" || return 2
	right_canonical="$(mktemp /tmp/kejilion-system-resource-firewall-right.XXXXXX)" || {
		rm -f -- "$left_canonical"
		return 2
	}
	if ! kpanel_system_resource_firewall_canonicalize "$left" "$left_canonical" ||
		! kpanel_system_resource_firewall_canonicalize "$right" "$right_canonical"; then
		rm -f -- "$left_canonical" "$right_canonical"
		return 2
	fi
	if cmp -s -- "$left_canonical" "$right_canonical"; then
		result=0
	else
		result=$?
	fi
	rm -f -- "$left_canonical" "$right_canonical"
	case "$result" in
		0|1) return "$result" ;;
		*) return 2 ;;
	esac
}

kpanel_system_resource_firewall_version() {
	local raw canonical version
	raw="$(mktemp /tmp/kejilion-system-resource-firewall-version-raw.XXXXXX)" || return 1
	canonical="$(mktemp /tmp/kejilion-system-resource-firewall-version-canonical.XXXXXX)" || {
		rm -f -- "$raw"
		return 1
	}
	if ! kpanel_system_resource_firewall_capture "$raw" ||
		! kpanel_system_resource_firewall_canonicalize "$raw" "$canonical"; then
		rm -f -- "$raw" "$canonical"
		return 1
	fi
	version="$(sha256sum -- "$canonical" 2>/dev/null | awk '{print $1}')"
	rm -f -- "$raw" "$canonical"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$version"
}

kpanel_system_resource_firewall_capture() {
	local target="$1"
	local bytes
	iptables-save > "$target" 2>/dev/null || return 1
	bytes="$(wc -c < "$target" 2>/dev/null)" || return 1
	[ "$bytes" -le 524288 ]
}

kpanel_system_resource_best_version() {
	local resource="$1"
	local name="${2:-}"
	local version=""
	case "$resource" in
		hosts) version="$(kpanel_system_resource_hosts_version 2>/dev/null || true)" ;;
		cron) version="$(kpanel_system_resource_cron_version 2>/dev/null || true)" ;;
		network-interface)
			[ -z "$name" ] || version="$(kpanel_system_resource_interface_version "$name" 2>/dev/null || true)"
			;;
		firewall) version="$(kpanel_system_resource_firewall_version 2>/dev/null || true)" ;;
	esac
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || version="$(kpanel_system_resource_zero_version)"
	printf '%s\n' "$version"
}

kpanel_system_resource_check_expected() {
	local resource="$1"
	local expected="$2"
	local name="${3:-}"
	local current
	kpanel_system_resource_valid_version "$expected" || {
		kpanel_system_resource_error "expectedResourceVersion 必须为 64 位小写十六进制"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version "$resource" "$name")"
		return 2
	}
	case "$resource" in
		hosts) current="$(kpanel_system_resource_hosts_version 2>/dev/null)" ;;
		cron) current="$(kpanel_system_resource_cron_version 2>/dev/null)" ;;
		network-interface) current="$(kpanel_system_resource_interface_version "$name" 2>/dev/null)" ;;
		firewall) current="$(kpanel_system_resource_firewall_version 2>/dev/null)" ;;
		*) return 2 ;;
	esac || {
		kpanel_system_resource_error "无法读取当前资源版本"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 1
	}
	if [ "$current" != "$expected" ]; then
		kpanel_system_resource_error "资源版本已变化，请刷新后重试"
		kpanel_system_resource_emit conflict "$current"
		return 2
	fi
	KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION="$current"
}

kpanel_system_resource_require_platform() {
	local command_name
	if [ "${KJ_SYSTEM_RESOURCE_NONINTERACTIVE:-}" != "1" ]; then
		kpanel_system_resource_error "KPanel system-resource 协议环境未启用"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	fi
	if [ "$EUID" -ne 0 ]; then
		kpanel_system_resource_error "KPanel system-resource 协议必须以 root 运行"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	fi
	if [ "$(uname -s 2>/dev/null)" != "Linux" ]; then
		kpanel_system_resource_error "KPanel system-resource 协议仅支持 Linux"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	fi
	for command_name in sha256sum mktemp flock find date; do
		command -v "$command_name" >/dev/null 2>&1 || {
			kpanel_system_resource_error "缺少必要命令: $command_name"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
			return 2
		}
	done
}

kpanel_system_resource_hosts_build_line() {
	local address="$1"
	local hostnames_csv="$2"
	local comment="$3"
	local hostname joined
	local hostnames=()

	kpanel_system_resource_is_ipv4 "$address" ||
		kpanel_system_resource_is_ipv6 "$address" || return 1
	kpanel_system_resource_single_line "$hostnames_csv" 1024 &&
		[ -n "$hostnames_csv" ] || return 1
	[[ "$hostnames_csv" != ,* && "$hostnames_csv" != *, && "$hostnames_csv" != *,,* ]] || return 1
	IFS=, read -r -a hostnames <<< "$hostnames_csv"
	[ "${#hostnames[@]}" -ge 1 ] && [ "${#hostnames[@]}" -le 16 ] || return 1
	for hostname in "${hostnames[@]}"; do
		kpanel_system_resource_is_hostname "$hostname" || return 1
	done
	kpanel_system_resource_single_line "$comment" 256 || return 1
	joined="$(IFS=' '; printf '%s' "${hostnames[*]}")"
	KPANEL_SYSTEM_RESOURCE_HOSTS_LINE="$address"$'\t'"$joined"
	[ -z "$comment" ] ||
		KPANEL_SYSTEM_RESOURCE_HOSTS_LINE="$KPANEL_SYSTEM_RESOURCE_HOSTS_LINE # $comment"
}

kpanel_system_resource_restore_hosts() {
	local path="$1"
	local backup="$2"
	local expected_version="$3"
	local current
	current="$(kpanel_system_resource_hosts_version 2>/dev/null || true)"
	[ "$current" = "$expected_version" ] && return 0
	cp -p -- "$backup" "$path" >/dev/null 2>&1 || return 1
	current="$(kpanel_system_resource_hosts_version 2>/dev/null || true)"
	[ "$current" = "$expected_version" ]
}

kpanel_system_resource_hosts_failure() {
	local path="$1"
	local backup="$2"
	local snapshot_dir="$3"
	local original_version="$4"
	local message="$5"
	local version recovery_path

	kpanel_system_resource_error "$message"
	if kpanel_system_resource_restore_hosts "$path" "$backup" "$original_version"; then
		version="$(kpanel_system_resource_best_version hosts)"
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit failed "$version"
	else
		version="$(kpanel_system_resource_best_version hosts)"
		kpanel_system_resource_error "hosts 回滚失败，需要人工恢复"
		if recovery_path="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot_dir" hosts)"; then
			kpanel_system_resource_emit rollback-failed "$version" "$recovery_path"
		else
			kpanel_system_resource_error "hosts 失败快照持久化失败，未生成宿主可见备份路径"
			kpanel_system_resource_emit rollback-failed "$version"
		fi
	fi
	return 1
}

kpanel_system_resource_hosts_action() {
	local action="$1"
	shift
	local expected path line line_number snapshot_dir backup desired desired_version current_line
	local index=0 total_lines
	local address hostnames_csv comment
	local hosts_trailing_newline=true

	path="$(kpanel_system_resource_hosts_file)"
	[ -f "$path" ] && [ ! -L "$path" ] || {
		kpanel_system_resource_error "未找到可安全管理的 hosts 文件"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	kpanel_system_resource_file_within_bounds "$path" 262144 1024 || {
		kpanel_system_resource_error "hosts 超过 256KiB 或 1024 行协议上限"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
		return 2
	}
	case "$action" in
		add)
			[ "$#" -eq 4 ] || {
				kpanel_system_resource_error "hosts add 需要 expected,address,hostnamesCSV,comment"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
				return 2
			}
			expected="$1"
			address="$2"
			hostnames_csv="$3"
			comment="$4"
			kpanel_system_resource_hosts_build_line "$address" "$hostnames_csv" "$comment" || {
				kpanel_system_resource_error "hosts 地址、主机名或注释无效"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
				return 2
			}
			line="$KPANEL_SYSTEM_RESOURCE_HOSTS_LINE"
			;;
		delete)
			[ "$#" -eq 2 ] || {
				kpanel_system_resource_error "hosts delete 需要 expected,line"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
				return 2
			}
			expected="$1"
			line_number="$2"
			[[ "$line_number" =~ ^[0-9]{1,4}$ ]] &&
				[ "$((10#$line_number))" -ge 1 ] &&
				[ "$((10#$line_number))" -le 1024 ] || {
				kpanel_system_resource_error "hosts 行号必须为 1-1024"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
				return 2
			}
			line_number=$((10#$line_number))
			;;
		*)
			kpanel_system_resource_error "不支持的 hosts 动作"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version hosts)"
			return 2
			;;
	esac

	kpanel_system_resource_check_expected hosts "$expected" || return $?
	if [ "$action" = "add" ] && grep -Fqx -- "$line" "$path"; then
		kpanel_system_resource_emit unchanged "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 0
	fi
	if [ "$action" = "delete" ]; then
		total_lines="$(awk 'END {print NR + 0}' "$path")"
		if [ "$line_number" -gt "$total_lines" ]; then
			kpanel_system_resource_error "hosts 行号超出当前文件范围"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 2
		fi
		if [ -s "$path" ] && [ "$(tail -c 1 "$path" | wc -l)" -eq 0 ]; then
			hosts_trailing_newline=false
		fi
	fi

	snapshot_dir="$(kpanel_system_resource_tempdir hosts)" || {
		kpanel_system_resource_error "无法创建 hosts 事务目录"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	backup="$snapshot_dir/hosts.backup"
	cp -p -- "$path" "$backup" >/dev/null 2>&1 || {
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "无法备份 hosts"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	desired="$(mktemp "$(dirname -- "$path")/.hosts.kpanel.XXXXXX")" || {
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "无法创建 hosts 临时文件"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}

	if [ "$action" = "add" ]; then
		cp -- "$path" "$desired" >/dev/null 2>&1 || {
			rm -f -- "$desired"
			kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法复制 hosts"
			return $?
		}
		if [ -s "$desired" ] && [ "$(tail -c 1 "$desired" | wc -l)" -eq 0 ]; then
			printf '\n' >> "$desired" || {
				rm -f -- "$desired"
				kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法生成 hosts"
				return $?
			}
		fi
		printf '%s\n' "$line" >> "$desired" || {
			rm -f -- "$desired"
			kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法写入 hosts"
			return $?
		}
	else
		: > "$desired" || {
			rm -f -- "$desired"
			kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法生成 hosts"
			return $?
		}
		while IFS= read -r current_line || [ -n "$current_line" ]; do
			index=$((index + 1))
			if [ "$index" -eq "$line_number" ]; then
				continue
			fi
			if [ "$index" -eq "$total_lines" ] && [ "$hosts_trailing_newline" = false ]; then
				printf '%s' "$current_line" >> "$desired"
			else
				printf '%s\n' "$current_line" >> "$desired"
			fi || {
				rm -f -- "$desired"
				kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法重写 hosts"
				return $?
			}
		done < "$path"
	fi
	kpanel_system_resource_file_within_bounds "$desired" 262144 1024 || {
		rm -f -- "$desired"
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "修改后的 hosts 超过 256KiB 或 1024 行协议上限"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 2
	}

	kpanel_system_resource_copy_identity "$path" "$desired" || {
		rm -f -- "$desired"
		kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "无法保留 hosts 权限或属主"
		return $?
	}
	desired_version="$(sha256sum -- "$desired" 2>/dev/null | awk '{print $1}')"
	if ! kpanel_system_resource_valid_version "$desired_version"; then
		rm -f -- "$desired"
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "无法计算修改后的 hosts 版本"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	fi
	if ! mv -f -- "$desired" "$path" >/dev/null 2>&1 ||
		[ "$(kpanel_system_resource_hosts_version 2>/dev/null)" != "$desired_version" ]; then
		rm -f -- "$desired"
		kpanel_system_resource_hosts_failure "$path" "$backup" "$snapshot_dir" "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" "hosts 原子写入或回读验证失败"
		return $?
	fi
	rm -rf -- "$snapshot_dir"
	kpanel_system_resource_emit applied "$desired_version"
}

kpanel_system_resource_cron_number_in_range() {
	local value="$1"
	local minimum="$2"
	local maximum="$3"
	[[ "$value" =~ ^[0-9]{1,3}$ ]] &&
		[ "$((10#$value))" -ge "$minimum" ] &&
		[ "$((10#$value))" -le "$maximum" ]
}

kpanel_system_resource_cron_value_in_range() {
	local value="$1"
	local minimum="$2"
	local maximum="$3"
	local kind="$4"
	local numeric=""

	if [[ "$value" =~ ^[0-9]{1,3}$ ]]; then
		numeric=$((10#$value))
	else
		case "$kind:${value^^}" in
			month:JAN) numeric=1 ;; month:FEB) numeric=2 ;; month:MAR) numeric=3 ;;
			month:APR) numeric=4 ;; month:MAY) numeric=5 ;; month:JUN) numeric=6 ;;
			month:JUL) numeric=7 ;; month:AUG) numeric=8 ;; month:SEP) numeric=9 ;;
			month:OCT) numeric=10 ;; month:NOV) numeric=11 ;; month:DEC) numeric=12 ;;
			weekday:SUN) numeric=0 ;; weekday:MON) numeric=1 ;; weekday:TUE) numeric=2 ;;
			weekday:WED) numeric=3 ;; weekday:THU) numeric=4 ;; weekday:FRI) numeric=5 ;;
			weekday:SAT) numeric=6 ;;
			*) return 1 ;;
		esac
	fi
	[ "$numeric" -ge "$minimum" ] && [ "$numeric" -le "$maximum" ] || return 1
	KPANEL_SYSTEM_RESOURCE_CRON_NUMERIC_VALUE="$numeric"
}

kpanel_system_resource_cron_field() {
	local field="$1"
	local minimum="$2"
	local maximum="$3"
	local kind="$4"
	local item base step start end start_numeric end_numeric
	local items=()

	IFS=, read -r -a items <<< "$field"
	[ "${#items[@]}" -ge 1 ] || return 1
	for item in "${items[@]}"; do
		[ -n "$item" ] || return 1
		base="$item"
		if [[ "$item" == */* ]]; then
			base="${item%%/*}"
			step="${item#*/}"
			[[ "$step" != */* ]] &&
				kpanel_system_resource_cron_number_in_range "$step" 1 "$maximum" || return 1
		fi
		if [ "$base" = "*" ]; then
			continue
		elif [[ "$base" == *-* ]]; then
			start="${base%%-*}"
			end="${base#*-}"
			[[ "$end" != *-* ]] &&
				kpanel_system_resource_cron_value_in_range "$start" "$minimum" "$maximum" "$kind" || return 1
			start_numeric="$KPANEL_SYSTEM_RESOURCE_CRON_NUMERIC_VALUE"
			kpanel_system_resource_cron_value_in_range "$end" "$minimum" "$maximum" "$kind" || return 1
			end_numeric="$KPANEL_SYSTEM_RESOURCE_CRON_NUMERIC_VALUE"
			[ "$start_numeric" -le "$end_numeric" ] || return 1
		else
			kpanel_system_resource_cron_value_in_range "$base" "$minimum" "$maximum" "$kind" || return 1
		fi
	done
}

kpanel_system_resource_cron_expression() {
	local expression="$1"
	local fields=()

	kpanel_system_resource_single_line "$expression" 128 && [ -n "$expression" ] || return 1
	case "$expression" in
		@reboot|@yearly|@annually|@monthly|@weekly|@daily|@midnight|@hourly)
			KPANEL_SYSTEM_RESOURCE_CRON_EXPRESSION="$expression"
			return 0
			;;
	esac
	read -r -a fields <<< "$expression"
	[ "${#fields[@]}" -eq 5 ] || return 1
	kpanel_system_resource_cron_field "${fields[0]}" 0 59 numeric &&
		kpanel_system_resource_cron_field "${fields[1]}" 0 23 numeric &&
		kpanel_system_resource_cron_field "${fields[2]}" 1 31 numeric &&
		kpanel_system_resource_cron_field "${fields[3]}" 1 12 month &&
		kpanel_system_resource_cron_field "${fields[4]}" 0 7 weekday || return 1
	KPANEL_SYSTEM_RESOURCE_CRON_EXPRESSION="${fields[*]}"
}

kpanel_system_resource_cron_read_command() {
	local frame bytes line_feeds command_value
	KPANEL_SYSTEM_RESOURCE_CRON_COMMAND=""
	KPANEL_SYSTEM_RESOURCE_CRON_COMMAND_ERROR=operation
	frame="$(mktemp /tmp/kejilion-system-resource-cron-command.XXXXXX)" || return 1
	chmod 600 "$frame" >/dev/null 2>&1 || {
		rm -f -- "$frame"
		return 1
	}
	if ! head -c 2050 > "$frame" 2>/dev/null; then
		rm -f -- "$frame"
		return 1
	fi
	bytes="$(wc -c < "$frame" 2>/dev/null)" || {
		rm -f -- "$frame"
		return 1
	}
	KPANEL_SYSTEM_RESOURCE_CRON_COMMAND_ERROR=invalid
	if [ "$bytes" -lt 1 ] || [ "$bytes" -gt 2049 ] ||
		! LC_ALL=C tr -d '\000' < "$frame" | cmp -s - "$frame" ||
		LC_ALL=C grep -q $'\r' "$frame"; then
		rm -f -- "$frame"
		return 1
	fi
	line_feeds="$(LC_ALL=C tr -cd '\n' < "$frame" | wc -c)" || {
		rm -f -- "$frame"
		KPANEL_SYSTEM_RESOURCE_CRON_COMMAND_ERROR=operation
		return 1
	}
	if [ "$line_feeds" -ne 1 ] || [ "$(tail -c 1 "$frame" | wc -l)" -ne 1 ]; then
		rm -f -- "$frame"
		return 1
	fi
	IFS= read -r command_value < "$frame" || {
		rm -f -- "$frame"
		return 1
	}
	rm -f -- "$frame"
	KPANEL_SYSTEM_RESOURCE_CRON_COMMAND="$command_value"
	KPANEL_SYSTEM_RESOURCE_CRON_COMMAND_ERROR=""
}

kpanel_system_resource_cron_contains_line() {
	local path="$1"
	local expected_line="$2"
	local current_line
	while IFS= read -r current_line || [ -n "$current_line" ]; do
		[ "$current_line" = "$expected_line" ] && return 0
	done < "$path"
	return 1
}

kpanel_system_resource_cron_restore() {
	local backup="$1"
	local existed="$2"
	local verify="$3"

	if [ "$existed" = true ]; then
		crontab "$backup" >/dev/null 2>&1 || return 1
	else
		crontab -r >/dev/null 2>&1 || true
	fi
	kpanel_system_resource_cron_capture "$verify" || return 1
	cmp -s -- "$backup" "$verify"
}

kpanel_system_resource_cron_failure() {
	local snapshot_dir="$1"
	local backup="$2"
	local existed="$3"
	local message="$4"
	local verify="$snapshot_dir/rollback.verify"
	local version recovery_path

	kpanel_system_resource_error "$message"
	if kpanel_system_resource_cron_restore "$backup" "$existed" "$verify"; then
		version="$(kpanel_system_resource_best_version cron)"
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit failed "$version"
	else
		version="$(kpanel_system_resource_best_version cron)"
		kpanel_system_resource_error "crontab 回滚失败，需要人工恢复"
		if recovery_path="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot_dir" cron)"; then
			kpanel_system_resource_emit rollback-failed "$version" "$recovery_path"
		else
			kpanel_system_resource_error "crontab 失败快照持久化失败，未生成宿主可见备份路径"
			kpanel_system_resource_emit rollback-failed "$version"
		fi
	fi
	return 1
}

kpanel_system_resource_cron_action() {
	local action="$1"
	shift
	local expected line_number expression command_source command_value trimmed_command new_line snapshot_dir backup desired verify
	local cron_existed current_line index=0 total_lines
	local command_read_rc

	command -v crontab >/dev/null 2>&1 || {
		kpanel_system_resource_error "缺少 crontab 命令"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	case "$action" in
		add)
			[ "$#" -eq 3 ] || {
				kpanel_system_resource_error "cron add 需要 expected,expression,--command-stdin"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
				return 2
			}
			expected="$1"
			expression="$2"
			command_source="$3"
			;;
		update)
			[ "$#" -eq 4 ] || {
				kpanel_system_resource_error "cron update 需要 expected,line,expression,--command-stdin"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
				return 2
			}
			expected="$1"
			line_number="$2"
			expression="$3"
			command_source="$4"
			[[ "$line_number" =~ ^[0-9]{1,3}$ ]] &&
				[ "$((10#$line_number))" -ge 1 ] &&
				[ "$((10#$line_number))" -le 512 ] || {
				kpanel_system_resource_error "cron 行号必须为 1-512"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
				return 2
			}
			line_number=$((10#$line_number))
			;;
		delete)
			[ "$#" -eq 2 ] || {
				kpanel_system_resource_error "cron delete 需要 expected,line"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
				return 2
			}
			expected="$1"
			line_number="$2"
			[[ "$line_number" =~ ^[0-9]{1,3}$ ]] &&
				[ "$((10#$line_number))" -ge 1 ] &&
				[ "$((10#$line_number))" -le 512 ] || {
				kpanel_system_resource_error "cron 行号必须为 1-512"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
				return 2
			}
			line_number=$((10#$line_number))
			;;
		*)
			kpanel_system_resource_error "不支持的 cron 动作"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
			return 2
			;;
	esac

	if [ "$action" != "delete" ]; then
		[ "$command_source" = "--command-stdin" ] &&
			kpanel_system_resource_cron_expression "$expression" || {
			kpanel_system_resource_error "cron 表达式或命令输入方式无效"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version cron)"
			return 2
		}
	fi
	kpanel_system_resource_check_expected cron "$expected" || return $?
	if [ "$action" != "delete" ]; then
		kpanel_system_resource_cron_read_command
		command_read_rc=$?
		if [ "$command_read_rc" -ne 0 ]; then
			if [ "$KPANEL_SYSTEM_RESOURCE_CRON_COMMAND_ERROR" = invalid ]; then
				kpanel_system_resource_error "cron 命令 stdin 帧无效"
				kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
				return 2
			fi
			kpanel_system_resource_error "无法安全读取 cron 命令 stdin 帧"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 1
		fi
		command_value="$KPANEL_SYSTEM_RESOURCE_CRON_COMMAND"
		trimmed_command="$command_value"
		trimmed_command="${trimmed_command#"${trimmed_command%%[![:space:]]*}"}"
		trimmed_command="${trimmed_command%"${trimmed_command##*[![:space:]]}"}"
		[ -n "$trimmed_command" ] || {
			kpanel_system_resource_error "cron 命令 stdin 帧无效"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 2
		}
		new_line="$KPANEL_SYSTEM_RESOURCE_CRON_EXPRESSION $command_value"
	fi

	snapshot_dir="$(kpanel_system_resource_tempdir cron)" || {
		kpanel_system_resource_error "无法创建 cron 事务目录"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	backup="$snapshot_dir/crontab.backup"
	kpanel_system_resource_cron_capture "$backup" || {
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "无法读取当前 crontab"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	cron_existed="$KPANEL_SYSTEM_RESOURCE_CRON_EXISTED"

	if [ "$action" = "add" ] && kpanel_system_resource_cron_contains_line "$backup" "$new_line"; then
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit unchanged "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 0
	fi
	if [ "$action" != "add" ]; then
		total_lines="$(awk 'END {print NR + 0}' "$backup")"
		if [ "$line_number" -gt "$total_lines" ]; then
			rm -rf -- "$snapshot_dir"
			kpanel_system_resource_error "cron 行号超出当前 crontab 范围"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 2
		fi
	fi

	desired="$snapshot_dir/crontab.desired"
	if [ "$action" = "add" ]; then
		cp -- "$backup" "$desired" >/dev/null 2>&1 || {
			rm -rf -- "$snapshot_dir"
			kpanel_system_resource_error "无法复制当前 crontab"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 1
		}
		if [ -s "$desired" ] && [ "$(tail -c 1 "$desired" | wc -l)" -eq 0 ]; then
			printf '\n' >> "$desired" || {
				rm -rf -- "$snapshot_dir"
				kpanel_system_resource_error "无法生成 crontab"
				kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
				return 1
			}
		fi
		builtin printf '%s\n' "$new_line" >> "$desired" || {
			kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "无法生成 crontab"
			return $?
		}
	else
		: > "$desired" || {
			rm -rf -- "$snapshot_dir"
			kpanel_system_resource_error "无法创建 crontab 目标文件"
			kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
			return 1
		}
		while IFS= read -r current_line || [ -n "$current_line" ]; do
			index=$((index + 1))
			if [ "$index" -eq "$line_number" ]; then
				if [ "$action" != "delete" ] && ! builtin printf '%s\n' "$new_line" >> "$desired"; then
					rm -rf -- "$snapshot_dir"
					kpanel_system_resource_error "无法生成 crontab"
					kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
					return 1
				fi
				continue
			fi
			printf '%s\n' "$current_line" >> "$desired" || {
				kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "无法生成 crontab"
				return $?
			}
		done < "$backup"
	fi
	if ! kpanel_system_resource_file_within_bounds "$desired" 262144 512; then
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "修改后的 crontab 超过 256KiB 或 512 行协议上限"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 2
	fi
	if cmp -s -- "$backup" "$desired"; then
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit unchanged "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 0
	fi

	if ! crontab "$desired" >/dev/null 2>&1; then
		kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "crontab 安装失败"
		return $?
	fi
	verify="$snapshot_dir/crontab.verify"
	if ! kpanel_system_resource_cron_capture "$verify"; then
		kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "crontab 回读失败"
		return $?
	fi
	if ! cmp -s -- "$desired" "$verify"; then
		kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "crontab 回读验证失败"
		return $?
	fi
	local applied_version
	applied_version="$(sha256sum -- "$verify" 2>/dev/null | awk '{print $1}')"
	if ! kpanel_system_resource_valid_version "$applied_version"; then
		kpanel_system_resource_cron_failure "$snapshot_dir" "$backup" "$cron_existed" "无法计算 crontab 版本"
		return $?
	fi
	rm -rf -- "$snapshot_dir"
	kpanel_system_resource_emit applied "$applied_version"
}

kpanel_system_resource_interface_admin_state() {
	local name="$1"
	local root flags numeric
	root="$(kpanel_system_resource_interfaces_dir)"
	flags="$(cat "$root/$name/flags" 2>/dev/null)" || return 1
	[[ "$flags" =~ ^0x[0-9A-Fa-f]+$ ]] || return 1
	numeric=$((flags))
	if [ "$((numeric & 1))" -eq 1 ]; then
		printf 'up\n'
	else
		printf 'down\n'
	fi
}

kpanel_system_resource_interface_failure() {
	local name="$1"
	local old_state="$2"
	local message="$3"
	local current_state="" version attempt

	kpanel_system_resource_error "$message"
	current_state="$(kpanel_system_resource_interface_admin_state "$name" 2>/dev/null || true)"
	if [ "$current_state" != "$old_state" ]; then
		ip link set dev "$name" "$old_state" >/dev/null 2>&1 || true
		for attempt in 1 2 3 4 5; do
			current_state="$(kpanel_system_resource_interface_admin_state "$name" 2>/dev/null || true)"
			[ "$current_state" = "$old_state" ] && break
			sleep 0.1
		done
	fi
	version="$(kpanel_system_resource_best_version network-interface "$name")"
	if [ "$current_state" = "$old_state" ]; then
		kpanel_system_resource_emit failed "$version"
	else
		kpanel_system_resource_error "网卡状态回滚失败，需要人工恢复"
		kpanel_system_resource_emit rollback-failed "$version"
	fi
	return 1
}

kpanel_system_resource_interface_action() {
	local action="$1"
	shift
	local expected name desired old_state current_state version attempt

	[ "$action" = "state" ] || {
		kpanel_system_resource_error "不支持的 network-interface 动作"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	[ "$#" -eq 3 ] || {
		kpanel_system_resource_error "network-interface state 需要 expected,name,up|down"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	expected="$1"
	name="$2"
	desired="$3"
	[ "${#name}" -ge 1 ] && [ "${#name}" -le 15 ] &&
		kpanel_system_resource_single_line "$name" 15 &&
		kpanel_system_resource_interface_exists "$name" || {
		kpanel_system_resource_error "网卡名称不在系统枚举中"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	case "$desired" in up|down) ;; *)
		kpanel_system_resource_error "网卡状态必须为 up 或 down"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version network-interface "$name")"
		return 2
		;;
	esac
	command -v ip >/dev/null 2>&1 || {
		kpanel_system_resource_error "缺少 ip 命令"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version network-interface "$name")"
		return 2
	}
	kpanel_system_resource_check_expected network-interface "$expected" "$name" || return $?
	old_state="$(kpanel_system_resource_interface_admin_state "$name")" || {
		kpanel_system_resource_error "无法读取网卡管理状态"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	if [ "$old_state" = "$desired" ]; then
		kpanel_system_resource_emit unchanged "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 0
	fi
	if ! ip link set dev "$name" "$desired" >/dev/null 2>&1; then
		kpanel_system_resource_interface_failure "$name" "$old_state" "网卡状态修改失败，正在恢复"
		return 1
	fi
	current_state=""
	for attempt in 1 2 3 4 5; do
		current_state="$(kpanel_system_resource_interface_admin_state "$name" 2>/dev/null || true)"
		[ "$current_state" = "$desired" ] && break
		sleep 0.1
	done
	if [ "$current_state" != "$desired" ]; then
		kpanel_system_resource_interface_failure "$name" "$old_state" "网卡状态回读验证失败，正在恢复"
		return 1
	fi
	version="$(kpanel_system_resource_interface_version "$name" 2>/dev/null)" || {
		kpanel_system_resource_interface_failure "$name" "$old_state" "无法计算网卡资源版本，正在恢复"
		return 1
	}
	kpanel_system_resource_emit applied "$version"
}

kpanel_system_resource_iptables() {
	iptables -w 5 "$@" >/dev/null 2>&1
}

kpanel_system_resource_firewall_rule_exists() {
	local chain="$1"
	shift
	kpanel_system_resource_iptables -C "$chain" "$@"
}

kpanel_system_resource_firewall_delete_rule() {
	local chain="$1"
	shift
	while kpanel_system_resource_firewall_rule_exists "$chain" "$@"; do
		kpanel_system_resource_iptables -D "$chain" "$@" || return 1
		KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
	done
}

kpanel_system_resource_firewall_ensure_rule() {
	local placement="$1"
	local chain="$2"
	shift 2
	kpanel_system_resource_firewall_rule_exists "$chain" "$@" && return 0
	case "$placement" in
		insert) kpanel_system_resource_iptables -I "$chain" 1 "$@" ;;
		append) kpanel_system_resource_iptables -A "$chain" "$@" ;;
		*) return 1 ;;
	esac || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
}

kpanel_system_resource_firewall_chain_exists() {
	kpanel_system_resource_iptables -S "$1"
}

kpanel_system_resource_firewall_port() {
	local value="$1"
	[[ "$value" =~ ^[0-9]{1,5}$ ]] &&
		[ "$((10#$value))" -ge 1 ] &&
		[ "$((10#$value))" -le 65535 ]
}

kpanel_system_resource_ssh_ports() {
	get_ssh_ports
}

kpanel_system_resource_firewall_open_port_rules() {
	local port="$1" protocol
	for protocol in tcp udp; do
		kpanel_system_resource_firewall_delete_rule INPUT -p "$protocol" --dport "$port" -j DROP || return 1
		kpanel_system_resource_firewall_ensure_rule insert INPUT -p "$protocol" --dport "$port" -j ACCEPT || return 1
	done
	for protocol in tcp udp; do
		kpanel_system_resource_firewall_rule_exists INPUT -p "$protocol" --dport "$port" -j ACCEPT || return 1
		! kpanel_system_resource_firewall_rule_exists INPUT -p "$protocol" --dport "$port" -j DROP || return 1
	done
}

kpanel_system_resource_firewall_close_port_rules() {
	local port="$1" protocol
	for protocol in tcp udp; do
		kpanel_system_resource_firewall_delete_rule INPUT -p "$protocol" --dport "$port" -j ACCEPT || return 1
		kpanel_system_resource_firewall_ensure_rule insert INPUT -p "$protocol" --dport "$port" -j DROP || return 1
	done
	kpanel_system_resource_firewall_ensure_rule insert INPUT -i lo -j ACCEPT || return 1
	kpanel_system_resource_firewall_ensure_rule insert FORWARD -i lo -j ACCEPT || return 1
	for protocol in tcp udp; do
		kpanel_system_resource_firewall_rule_exists INPUT -p "$protocol" --dport "$port" -j DROP || return 1
		! kpanel_system_resource_firewall_rule_exists INPUT -p "$protocol" --dport "$port" -j ACCEPT || return 1
	done
}

kpanel_system_resource_firewall_allow_ip_rules() {
	local address="$1"
	kpanel_system_resource_firewall_delete_rule INPUT -s "$address" -j DROP || return 1
	kpanel_system_resource_firewall_ensure_rule insert INPUT -s "$address" -j ACCEPT || return 1
	kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j ACCEPT &&
		! kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j DROP
}

kpanel_system_resource_firewall_block_ip_rules() {
	local address="$1"
	kpanel_system_resource_firewall_delete_rule INPUT -s "$address" -j ACCEPT || return 1
	kpanel_system_resource_firewall_ensure_rule insert INPUT -s "$address" -j DROP || return 1
	kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j DROP &&
		! kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j ACCEPT
}

kpanel_system_resource_firewall_remove_ip_rules() {
	local address="$1"
	kpanel_system_resource_firewall_delete_rule INPUT -s "$address" -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule INPUT -s "$address" -j DROP || return 1
	! kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j ACCEPT &&
		! kpanel_system_resource_firewall_rule_exists INPUT -s "$address" -j DROP
}

kpanel_system_resource_firewall_enable_ping_rules() {
	kpanel_system_resource_firewall_delete_rule INPUT -p icmp --icmp-type echo-request -j DROP &&
		kpanel_system_resource_firewall_delete_rule OUTPUT -p icmp --icmp-type echo-reply -j DROP &&
		kpanel_system_resource_firewall_delete_rule INPUT -p icmp --icmp-type echo-request -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT || return 1
	kpanel_system_resource_iptables -I INPUT 1 -p icmp --icmp-type echo-request -j ACCEPT &&
		kpanel_system_resource_iptables -I OUTPUT 1 -p icmp --icmp-type echo-reply -j ACCEPT || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
	kpanel_system_resource_firewall_rule_exists INPUT -p icmp --icmp-type echo-request -j ACCEPT &&
		kpanel_system_resource_firewall_rule_exists OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
}

kpanel_system_resource_firewall_disable_ping_rules() {
	kpanel_system_resource_firewall_delete_rule INPUT -p icmp --icmp-type echo-request -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule INPUT -p icmp --icmp-type echo-request -j DROP &&
		kpanel_system_resource_firewall_delete_rule OUTPUT -p icmp --icmp-type echo-reply -j DROP || return 1
	kpanel_system_resource_iptables -I INPUT 1 -p icmp --icmp-type echo-request -j DROP &&
		kpanel_system_resource_iptables -I OUTPUT 1 -p icmp --icmp-type echo-reply -j DROP || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
	kpanel_system_resource_firewall_rule_exists INPUT -p icmp --icmp-type echo-request -j DROP &&
		kpanel_system_resource_firewall_rule_exists OUTPUT -p icmp --icmp-type echo-reply -j DROP
}

kpanel_system_resource_firewall_enable_ddos_chain() {
	local chain="$1"
	kpanel_system_resource_firewall_disable_ddos_chain "$chain" || return 1
	kpanel_system_resource_iptables -I "$chain" 1 -p udp -j DROP || return 1
	kpanel_system_resource_iptables -I "$chain" 1 -p udp -m limit --limit 3000/s -j ACCEPT || return 1
	kpanel_system_resource_iptables -I "$chain" 1 -p tcp --syn -j DROP || return 1
	kpanel_system_resource_iptables -I "$chain" 1 -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
	kpanel_system_resource_firewall_rule_exists "$chain" -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT &&
		kpanel_system_resource_firewall_rule_exists "$chain" -p tcp --syn -j DROP &&
		kpanel_system_resource_firewall_rule_exists "$chain" -p udp -m limit --limit 3000/s -j ACCEPT &&
		kpanel_system_resource_firewall_rule_exists "$chain" -p udp -j DROP
}

kpanel_system_resource_firewall_disable_ddos_chain() {
	local chain="$1"
	kpanel_system_resource_firewall_delete_rule "$chain" -p tcp --syn -m limit --limit 500/s --limit-burst 100 -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule "$chain" -p tcp --syn -j DROP &&
		kpanel_system_resource_firewall_delete_rule "$chain" -p udp -m limit --limit 3000/s -j ACCEPT &&
		kpanel_system_resource_firewall_delete_rule "$chain" -p udp -j DROP
}

kpanel_system_resource_firewall_enable_ddos_rules() {
	kpanel_system_resource_firewall_enable_ddos_chain INPUT || return 1
	if kpanel_system_resource_firewall_chain_exists DOCKER-USER; then
		kpanel_system_resource_firewall_enable_ddos_chain DOCKER-USER || return 1
	fi
}

kpanel_system_resource_firewall_disable_ddos_rules() {
	kpanel_system_resource_firewall_disable_ddos_chain INPUT || return 1
	if kpanel_system_resource_firewall_chain_exists DOCKER-USER; then
		kpanel_system_resource_firewall_disable_ddos_chain DOCKER-USER || return 1
	fi
}

kpanel_system_resource_firewall_base_rules() {
	local ssh_port
	kpanel_system_resource_firewall_ensure_rule append INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT &&
		kpanel_system_resource_firewall_ensure_rule append OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT &&
		kpanel_system_resource_firewall_ensure_rule append INPUT -i lo -j ACCEPT &&
		kpanel_system_resource_firewall_ensure_rule append FORWARD -i lo -j ACCEPT || return 1
	while IFS= read -r ssh_port; do
		[ -n "$ssh_port" ] || continue
		kpanel_system_resource_firewall_ensure_rule append INPUT -p tcp --dport "$ssh_port" -j ACCEPT || return 1
	done < <(kpanel_system_resource_ssh_ports)
}

kpanel_system_resource_firewall_all_rules() {
	local input_policy="$1"
	kpanel_system_resource_iptables -F &&
		kpanel_system_resource_iptables -X || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=true
	kpanel_system_resource_iptables -P OUTPUT ACCEPT || return 1
	if [ "$input_policy" = ACCEPT ]; then
		kpanel_system_resource_iptables -P INPUT ACCEPT &&
			kpanel_system_resource_iptables -P FORWARD ACCEPT || return 1
		kpanel_system_resource_firewall_base_rules || return 1
	else
		kpanel_system_resource_firewall_base_rules || return 1
		kpanel_system_resource_iptables -P INPUT DROP &&
			kpanel_system_resource_iptables -P FORWARD DROP || return 1
	fi
	iptables -w 5 -S INPUT 2>/dev/null | grep -Fqx -- "-P INPUT $input_policy" &&
		iptables -w 5 -S FORWARD 2>/dev/null | grep -Fqx -- "-P FORWARD $input_policy" &&
		iptables -w 5 -S OUTPUT 2>/dev/null | grep -Fqx -- "-P OUTPUT ACCEPT"
}

kpanel_system_resource_firewall_apply() {
	local action="$1"
	local value="${2:-}"
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CHANGED=false
	case "$action" in
		open-port) kpanel_system_resource_firewall_open_port_rules "$value" ;;
		close-port) kpanel_system_resource_firewall_close_port_rules "$value" ;;
		allow-ip) kpanel_system_resource_firewall_allow_ip_rules "$value" ;;
		block-ip) kpanel_system_resource_firewall_block_ip_rules "$value" ;;
		remove-ip) kpanel_system_resource_firewall_remove_ip_rules "$value" ;;
		open-all) kpanel_system_resource_firewall_all_rules ACCEPT ;;
		close-all) kpanel_system_resource_firewall_all_rules DROP ;;
		enable-ping) kpanel_system_resource_firewall_enable_ping_rules ;;
		disable-ping) kpanel_system_resource_firewall_disable_ping_rules ;;
		enable-ddos) kpanel_system_resource_firewall_enable_ddos_rules ;;
		disable-ddos) kpanel_system_resource_firewall_disable_ddos_rules ;;
		*) return 2 ;;
	esac
}

kpanel_system_resource_firewall_snapshot() {
	local snapshot_dir="$1"
	local rules_path="$2"

	kpanel_system_resource_firewall_capture "$snapshot_dir/iptables.rules" || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_RULES_EXISTED=false
	if [ -e "$rules_path" ]; then
		[ -f "$rules_path" ] && [ ! -L "$rules_path" ] || return 1
		cp -p -- "$rules_path" "$snapshot_dir/rules.v4" >/dev/null 2>&1 || return 1
		KPANEL_SYSTEM_RESOURCE_FIREWALL_RULES_EXISTED=true
	fi
	kpanel_system_resource_cron_capture "$snapshot_dir/crontab" || return 1
	KPANEL_SYSTEM_RESOURCE_FIREWALL_CRON_EXISTED="$KPANEL_SYSTEM_RESOURCE_CRON_EXISTED"
}

kpanel_system_resource_firewall_persist() {
	local snapshot_dir="$1"
	local rules_path parent desired_rules verify_rules
	local cron_current cron_desired cron_verify restore_line count current_line
	local comparison

	KPANEL_SYSTEM_RESOURCE_FIREWALL_PERSIST_CHANGED=false
	rules_path="$(kpanel_system_resource_iptables_rules_file)"
	parent="$(dirname -- "$rules_path")"
	mkdir -p -- "$parent" >/dev/null 2>&1 || return 1
	[ ! -L "$rules_path" ] || return 1
	desired_rules="$(mktemp "$parent/.rules.v4.kpanel.XXXXXX")" || return 1
	if ! kpanel_system_resource_firewall_capture "$desired_rules"; then
		rm -f -- "$desired_rules"
		return 1
	fi
	comparison=1
	if [ -f "$rules_path" ]; then
		if kpanel_system_resource_firewall_canonical_equal "$desired_rules" "$rules_path"; then
			comparison=0
		else
			comparison=$?
		fi
		if [ "$comparison" -gt 1 ]; then
			rm -f -- "$desired_rules"
			return 1
		fi
	fi
	if [ "$comparison" -eq 0 ]; then
		rm -f -- "$desired_rules"
	else
		if [ -f "$rules_path" ]; then
			kpanel_system_resource_copy_identity "$rules_path" "$desired_rules" || {
				rm -f -- "$desired_rules"
				return 1
			}
		else
			chmod 600 "$desired_rules" >/dev/null 2>&1 || {
				rm -f -- "$desired_rules"
				return 1
			}
		fi
		mv -f -- "$desired_rules" "$rules_path" >/dev/null 2>&1 || {
			rm -f -- "$desired_rules"
			return 1
		}
		KPANEL_SYSTEM_RESOURCE_FIREWALL_PERSIST_CHANGED=true
	fi
	verify_rules="$snapshot_dir/iptables.persist.verify"
	kpanel_system_resource_firewall_capture "$verify_rules" || return 1
	kpanel_system_resource_firewall_canonical_equal "$verify_rules" "$rules_path" || return 1

	restore_line='@reboot iptables-restore < /etc/iptables/rules.v4'
	cron_current="$snapshot_dir/crontab.persist.current"
	kpanel_system_resource_cron_capture "$cron_current" || return 1
	count="$(grep -Fxc -- "$restore_line" "$cron_current" 2>/dev/null || true)"
	if [ "$count" -ne 1 ]; then
		cron_desired="$snapshot_dir/crontab.persist.desired"
		: > "$cron_desired" || return 1
		while IFS= read -r current_line || [ -n "$current_line" ]; do
			[ "$current_line" = "$restore_line" ] && continue
			printf '%s\n' "$current_line" >> "$cron_desired" || return 1
		done < "$cron_current"
		if [ -s "$cron_desired" ] && [ "$(tail -c 1 "$cron_desired" | wc -l)" -eq 0 ]; then
			printf '\n' >> "$cron_desired" || return 1
		fi
		printf '%s\n' "$restore_line" >> "$cron_desired" || return 1
		kpanel_system_resource_file_within_bounds "$cron_desired" 262144 512 || return 1
		crontab "$cron_desired" >/dev/null 2>&1 || return 1
		cron_verify="$snapshot_dir/crontab.persist.verify"
		kpanel_system_resource_cron_capture "$cron_verify" || return 1
		cmp -s -- "$cron_desired" "$cron_verify" || return 1
		KPANEL_SYSTEM_RESOURCE_FIREWALL_PERSIST_CHANGED=true
	fi
}

kpanel_system_resource_firewall_restore() {
	local snapshot_dir="$1"
	local rules_path="$2"
	local rules_existed="$3"
	local cron_existed="$4"
	local verify="$snapshot_dir/rollback.iptables"
	local cron_verify="$snapshot_dir/rollback.crontab"
	local failed=false

	iptables-restore -w 5 < "$snapshot_dir/iptables.rules" >/dev/null 2>&1 || failed=true
	if [ "$rules_existed" = true ]; then
		cp -p -- "$snapshot_dir/rules.v4" "$rules_path" >/dev/null 2>&1 || failed=true
	else
		rm -f -- "$rules_path" >/dev/null 2>&1 || failed=true
	fi
	kpanel_system_resource_cron_restore "$snapshot_dir/crontab" "$cron_existed" "$cron_verify" || failed=true
	kpanel_system_resource_firewall_capture "$verify" || failed=true
	kpanel_system_resource_firewall_canonical_equal "$snapshot_dir/iptables.rules" "$verify" || failed=true
	if [ "$rules_existed" = true ]; then
		cmp -s -- "$snapshot_dir/rules.v4" "$rules_path" || failed=true
	else
		[ ! -e "$rules_path" ] || failed=true
	fi
	[ "$failed" = false ]
}

kpanel_system_resource_firewall_failure() {
	local snapshot_dir="$1"
	local rules_path="$2"
	local rules_existed="$3"
	local cron_existed="$4"
	local message="$5"
	local version recovery_path

	kpanel_system_resource_error "$message"
	if kpanel_system_resource_firewall_restore "$snapshot_dir" "$rules_path" "$rules_existed" "$cron_existed"; then
		version="$(kpanel_system_resource_best_version firewall)"
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit failed "$version"
	else
		version="$(kpanel_system_resource_best_version firewall)"
		kpanel_system_resource_error "iptables 回滚失败，需要人工恢复"
		if recovery_path="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot_dir" firewall)"; then
			kpanel_system_resource_emit rollback-failed "$version" "$recovery_path"
		else
			kpanel_system_resource_error "iptables 失败快照持久化失败，未生成宿主可见备份路径"
			kpanel_system_resource_emit rollback-failed "$version"
		fi
	fi
	return 1
}

kpanel_system_resource_firewall_action() {
	local action="$1"
	shift
	local expected value="" snapshot_dir rules_path rules_existed cron_existed final_version
	local command_name

	for command_name in iptables iptables-save iptables-restore crontab; do
		command -v "$command_name" >/dev/null 2>&1 || {
			kpanel_system_resource_error "缺少必要命令: $command_name"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
			return 2
		}
	done
	rules_path="$(kpanel_system_resource_iptables_rules_file)"
	[ ! -L "$rules_path" ] || {
		kpanel_system_resource_error "iptables 持久化文件不能是符号链接"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
		return 2
	}
	case "$action" in
		open-port|close-port)
			[ "$#" -eq 2 ] || {
				kpanel_system_resource_error "$action 需要 expected,value"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
				return 2
			}
			expected="$1"
			value="$2"
			kpanel_system_resource_firewall_port "$value" || {
				kpanel_system_resource_error "防火墙端口必须为 1-65535"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
				return 2
			}
			value=$((10#$value))
			;;
		allow-ip|block-ip|remove-ip)
			[ "$#" -eq 2 ] || {
				kpanel_system_resource_error "$action 需要 expected,value"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
				return 2
			}
			expected="$1"
			value="$2"
			kpanel_system_resource_is_ipv4_cidr "$value" || {
				kpanel_system_resource_error "防火墙地址必须为 IPv4 或 IPv4 CIDR"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
				return 2
			}
			;;
		open-all|close-all|enable-ping|disable-ping|enable-ddos|disable-ddos)
			[ "$#" -eq 1 ] || {
				kpanel_system_resource_error "$action 只需要 expected"
				kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
				return 2
			}
			expected="$1"
			;;
		*)
			kpanel_system_resource_error "不支持的 firewall 动作"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version firewall)"
			return 2
			;;
	esac

	kpanel_system_resource_check_expected firewall "$expected" || return $?
	snapshot_dir="$(kpanel_system_resource_tempdir firewall)" || {
		kpanel_system_resource_error "无法创建 firewall 事务目录"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	}
	if ! kpanel_system_resource_firewall_snapshot "$snapshot_dir" "$rules_path"; then
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_error "无法创建 iptables/crontab 快照"
		kpanel_system_resource_emit failed "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION"
		return 1
	fi
	rules_existed="$KPANEL_SYSTEM_RESOURCE_FIREWALL_RULES_EXISTED"
	cron_existed="$KPANEL_SYSTEM_RESOURCE_FIREWALL_CRON_EXISTED"
	if ! kpanel_system_resource_firewall_apply "$action" "$value"; then
		kpanel_system_resource_firewall_failure "$snapshot_dir" "$rules_path" "$rules_existed" "$cron_existed" "iptables 动作执行或回读验证失败"
		return $?
	fi
	if ! kpanel_system_resource_firewall_persist "$snapshot_dir"; then
		kpanel_system_resource_firewall_failure "$snapshot_dir" "$rules_path" "$rules_existed" "$cron_existed" "iptables 持久化失败"
		return $?
	fi
	final_version="$(kpanel_system_resource_firewall_version 2>/dev/null)" || {
		kpanel_system_resource_firewall_failure "$snapshot_dir" "$rules_path" "$rules_existed" "$cron_existed" "无法计算修改后的 iptables 版本"
		return $?
	}
	if [ "$final_version" = "$KPANEL_SYSTEM_RESOURCE_CURRENT_VERSION" ] &&
		[ "$KPANEL_SYSTEM_RESOURCE_FIREWALL_PERSIST_CHANGED" = false ]; then
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit unchanged "$final_version"
	else
		rm -rf -- "$snapshot_dir"
		kpanel_system_resource_emit applied "$final_version"
	fi
}

kpanel_system_resource_run_locked() (
	local resource="$1"
	local action="$2"
	local lock_file name=""
	shift 2

	[ "$resource" = "network-interface" ] && name="${2:-}"
	lock_file="$(kpanel_system_resource_prepare_lock_file)" || {
		kpanel_system_resource_error "system-resource 锁路径不安全或无法创建"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version "$resource" "$name")"
		return 1
	}
	exec 9<>"$lock_file" || {
		kpanel_system_resource_error "无法打开 system-resource 锁"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version "$resource" "$name")"
		return 1
	}
	kpanel_system_resource_lock_path_secure "$lock_file" file 600 || {
		exec 9>&-
		kpanel_system_resource_error "system-resource 锁文件打开后验证失败"
		kpanel_system_resource_emit failed "$(kpanel_system_resource_best_version "$resource" "$name")"
		return 1
	}
	if ! flock -w 5 -x 9 >/dev/null 2>&1; then
		kpanel_system_resource_error "system-resource 写锁等待超时"
		kpanel_system_resource_emit conflict "$(kpanel_system_resource_best_version "$resource" "$name")"
		return 2
	fi
	case "$resource" in
		hosts) kpanel_system_resource_hosts_action "$action" "$@" ;;
		cron) kpanel_system_resource_cron_action "$action" "$@" ;;
		network-interface) kpanel_system_resource_interface_action "$action" "$@" ;;
		firewall) kpanel_system_resource_firewall_action "$action" "$@" ;;
		*)
			kpanel_system_resource_error "不支持的 system-resource 资源"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
			return 2
			;;
	esac
)

kpanel_system_resource_dispatch() {
	local resource="${1:-}"
	local action="${2:-}"
	local rc

	kpanel_system_resource_require_platform
	rc=$?
	[ "$rc" -eq 0 ] || return "$rc"
	[ "$#" -ge 2 ] || {
		kpanel_system_resource_error "用法: kpanel system-resource <resource> <action> ..."
		kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
		return 2
	}
	case "$resource" in
		hosts|cron|network-interface|firewall) ;;
		*)
			kpanel_system_resource_error "不支持的 system-resource 资源"
			kpanel_system_resource_emit failed "$(kpanel_system_resource_zero_version)"
			return 2
			;;
	esac
	shift 2
	kpanel_system_resource_run_locked "$resource" "$action" "$@"
}

# KPanel system resource protocol end


# KPanel disk management protocol start
KPANEL_DISK_MANAGEMENT_PROTOCOL_VERSION="1"

kpanel_disk_management_hex_encode() {
	local value="${1-}" encoded="" byte decimal index
	local LC_ALL=C
	for ((index = 0; index < ${#value}; index++)); do
		byte="${value:index:1}"
		printf -v decimal '%d' "'$byte"
		printf -v byte '%02x' "$decimal"
		encoded+="$byte"
	done
	printf '%s' "$encoded"
}

kpanel_disk_management_emit() {
	local status="$1" device="${2:-}" message="${3:-}" backup="${4:-}"
	case "$status" in
		applied|unchanged|failed|conflict|needs-attention|rollback-failed) ;;
		*) status=failed ;;
	esac
	[[ "$device" =~ ^[0-9]+:[0-9]+$ ]] || device=""
	printf 'KPANEL_DISK_MANAGEMENT_STATUS=%s\n' "$status"
	printf 'KPANEL_DISK_MANAGEMENT_DEVICE=%s\n' "$device"
	printf 'KPANEL_DISK_MANAGEMENT_MESSAGE_HEX=%s\n' "$(kpanel_disk_management_hex_encode "$message")"
	printf 'KPANEL_DISK_MANAGEMENT_BACKUP_HEX=%s\n' "$(kpanel_disk_management_hex_encode "$backup")"
}

kpanel_disk_management_error() {
	printf '错误: %s\n' "$1" >&2
}

kpanel_disk_management_reply() {
	local status="$1" device="$2" message="$3" backup="$4" result="$5"
	case "$status" in applied|unchanged) ;; *) kpanel_disk_management_error "$message" ;; esac
	kpanel_disk_management_emit "$status" "$device" "$message" "$backup"
	return "$result"
}

kpanel_disk_management_lock_file() {
	printf '%s\n' "/run/lock/kejilion-kpanel-disk.lock"
}

kpanel_disk_management_lock_owner_uid() {
	printf '0\n'
}

kpanel_disk_management_lock_stat_uid() {
	stat -c '%u' "$1" 2>/dev/null
}

kpanel_disk_management_lock_stat_mode() {
	stat -c '%a' "$1" 2>/dev/null
}

kpanel_disk_management_lock_stat_gid() {
	stat -c '%g' "$1" 2>/dev/null
}

kpanel_disk_management_lock_stat_links() {
	stat -c '%h' "$1" 2>/dev/null
}

kpanel_disk_management_lock_parent_secure() {
	local parent="$1" uid expected_uid gid mode numeric_mode
	[ ! -L "$parent" ] && [ -d "$parent" ] || return 1
	uid="$(kpanel_disk_management_lock_stat_uid "$parent")" || return 1
	expected_uid="$(kpanel_disk_management_lock_owner_uid)" || return 1
	[[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" = "$expected_uid" ] || return 1
	mode="$(kpanel_disk_management_lock_stat_mode "$parent")" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
	numeric_mode=$((8#$mode))
	# A newly created private parent is 0700. Existing system-managed /run/lock
	# may be 0755/0775 or 1777; require root:root and sticky when world-writable.
	[ "$((numeric_mode & 0777))" -eq 448 ] && return 0
	gid="$(kpanel_disk_management_lock_stat_gid "$parent")" || return 1
	[[ "$gid" =~ ^[0-9]+$ ]] && [ "$gid" = 0 ] || return 1
	[ "$((numeric_mode & 0002))" -eq 0 ] || [ "$((numeric_mode & 01000))" -ne 0 ]
}

kpanel_disk_management_lock_file_secure() {
	local path="$1" uid expected_uid mode links
	[ ! -L "$path" ] && [ -f "$path" ] || return 1
	uid="$(kpanel_disk_management_lock_stat_uid "$path")" || return 1
	expected_uid="$(kpanel_disk_management_lock_owner_uid)" || return 1
	[[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" = "$expected_uid" ] || return 1
	mode="$(kpanel_disk_management_lock_stat_mode "$path")" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 0777))" -eq 384 ] || return 1
	links="$(kpanel_disk_management_lock_stat_links "$path")" || return 1
	[[ "$links" =~ ^[0-9]+$ ]] && [ "$links" -eq 1 ]
}

kpanel_disk_management_prepare_lock_file() {
	local lock_file parent parent_parent created=false
	lock_file="$(kpanel_disk_management_lock_file)" || return 1
	[[ "$lock_file" = /* ]] && [[ "$lock_file" != *$'\n'* ]] && [[ "$lock_file" != *$'\r'* ]] || return 1
	parent="$(dirname -- "$lock_file")" || return 1
	[ ! -L "$parent" ] || return 1
	if [ ! -e "$parent" ]; then
		parent_parent="$(dirname -- "$parent")" || return 1
		[ -d "$parent_parent" ] && [ ! -L "$parent_parent" ] || return 1
		(umask 077; mkdir -- "$parent") >/dev/null 2>&1 || return 1
		chown 0:0 "$parent" >/dev/null 2>&1 && chmod 700 "$parent" >/dev/null 2>&1 || return 1
	fi
	kpanel_disk_management_lock_parent_secure "$parent" || return 1
	[ ! -L "$lock_file" ] || return 1
	if [ ! -e "$lock_file" ]; then
		(umask 077; set -o noclobber; : > "$lock_file") >/dev/null 2>&1 || return 1
		created=true
	fi
	[ -f "$lock_file" ] && [ ! -L "$lock_file" ] || return 1
	if [ "$created" = true ]; then
		chown 0:0 "$lock_file" >/dev/null 2>&1 && chmod 600 "$lock_file" >/dev/null 2>&1 || return 1
	fi
	kpanel_disk_management_lock_file_secure "$lock_file" || return 1
	printf '%s\n' "$lock_file"
}

kpanel_disk_management_require_commands() {
	local command_name
	for command_name in "$@"; do
		command -v "$command_name" >/dev/null 2>&1 || {
			KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE="缺少必要命令: $command_name"
			return 1
		}
	done
}

kpanel_disk_management_command_available() {
	command -v "$1" >/dev/null 2>&1
}

kpanel_disk_management_require_platform() {
	KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE=""
	if [ "${KJ_DISK_MANAGEMENT_NONINTERACTIVE:-}" != "1" ]; then
		KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE="KPanel disk-management 协议环境未启用"
		return 2
	fi
	if [ "$EUID" -ne 0 ]; then
		KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE="KPanel disk-management 协议必须以 root 运行"
		return 2
	fi
	if ! command -v uname >/dev/null 2>&1; then
		KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE="缺少必要命令: uname"
		return 1
	fi
	if [ "$(uname -s 2>/dev/null)" != Linux ]; then
		KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE="KPanel disk-management 协议仅支持 Linux"
		return 2
	fi
	kpanel_disk_management_require_commands \
		awk basename blkid chmod chown cp date dirname find findmnt flock grep lsblk mkdir mktemp \
		mount mv readlink rm rmdir sha256sum stat sync umount uname wc
}

kpanel_disk_management_path_owner_uid() {
	printf '0\n'
}

kpanel_disk_management_path_stat_uid() {
	stat -c '%u' "$1" 2>/dev/null
}

kpanel_disk_management_path_stat_mode() {
	stat -c '%a' "$1" 2>/dev/null
}

kpanel_disk_management_path_chain_secure() {
	local path="$1" expected_uid remainder current component uid mode
	local components=()
	[[ "$path" = /* ]] && [ -d "$path" ] && [ ! -L "$path" ] || return 1
	[ "$path" = / ] || kpanel_system_resource_path_has_no_symlink "$path" || return 1
	expected_uid="$(kpanel_disk_management_path_owner_uid)" || return 1
	[[ "$expected_uid" =~ ^[0-9]+$ ]] || return 1
	current=/
	remainder="${path#/}"
	IFS=/ read -r -a components <<< "$remainder"
	components=("/" "${components[@]}")
	for component in "${components[@]}"; do
		if [ "$component" != / ]; then
			[ -n "$component" ] && [ "$component" != . ] && [ "$component" != .. ] || return 1
			current="${current%/}/$component"
		fi
		[ -d "$current" ] && [ ! -L "$current" ] || return 1
		uid="$(kpanel_disk_management_path_stat_uid "$current")" || return 1
		mode="$(kpanel_disk_management_path_stat_mode "$current")" || return 1
		[[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" = "$expected_uid" ] || return 1
		[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 0022))" -eq 0 ] || return 1
	done
}

kpanel_disk_management_mountpoint_path_secure() {
	local mountpoint="$1" allow_missing="$2" parent
	kpanel_system_resource_path_has_no_symlink "$mountpoint" || return 1
	if [ -e "$mountpoint" ] || [ -L "$mountpoint" ]; then
		[ -d "$mountpoint" ] && [ ! -L "$mountpoint" ] || return 1
		kpanel_disk_management_path_chain_secure "$mountpoint"
		return $?
	fi
	[ "$allow_missing" = true ] || return 1
	parent="$(dirname -- "$mountpoint")" || return 1
	kpanel_disk_management_path_chain_secure "$parent"
}

kpanel_disk_management_mountpoint_parent_secure() {
	local mountpoint="$1" allow_missing="$2" parent
	kpanel_system_resource_path_has_no_symlink "$mountpoint" || return 1
	if [ -e "$mountpoint" ] || [ -L "$mountpoint" ]; then
		[ -d "$mountpoint" ] && [ ! -L "$mountpoint" ] || return 1
	else
		[ "$allow_missing" = true ] || return 1
	fi
	parent="$(dirname -- "$mountpoint")" || return 1
	kpanel_disk_management_path_chain_secure "$parent"
}

kpanel_disk_management_decode_mountpoint() {
	local encoded="$1" decoded="" canonical pair byte decimal index protected parent leaf canonical_parent
	local LC_ALL=C
	[ -n "$encoded" ] && [ "${#encoded}" -le 8192 ] && [ "$(( ${#encoded} % 2 ))" -eq 0 ] || return 1
	[[ "$encoded" =~ ^[0-9a-fA-F]+$ ]] || return 1
	for ((index = 0; index < ${#encoded}; index += 2)); do
		pair="${encoded:index:2}"
		decimal=$((16#$pair))
		[ "$decimal" -ge 32 ] && [ "$decimal" -ne 127 ] || return 1
		printf -v byte '%b' "\\x$pair"
		decoded+="$byte"
	done
	[ -n "$decoded" ] && [[ "$decoded" = /* ]] || return 1
	[[ "$decoded" != *$'\n'* ]] && [[ "$decoded" != *$'\r'* ]] || return 1
	if [ -e "$decoded" ] || [ -L "$decoded" ]; then
		canonical="$(readlink -f -- "$decoded" 2>/dev/null)" || return 1
	else
		parent="$(dirname -- "$decoded")" || return 1
		leaf="$(basename -- "$decoded")" || return 1
		[ -n "$leaf" ] && [ "$leaf" != . ] && [ "$leaf" != .. ] || return 1
		canonical_parent="$(readlink -f -- "$parent" 2>/dev/null)" || return 1
		[ -d "$canonical_parent" ] && [ ! -L "$canonical_parent" ] || return 1
		canonical="${canonical_parent%/}/$leaf"
	fi
	[ "$canonical" = "$decoded" ] || return 1
	[ "$decoded" != / ] || return 1
	for protected in /boot /boot/efi /home /var/lib/kejilion-panel /home/docker; do
		case "$decoded" in "$protected"|"$protected"/*) return 1 ;; esac
		case "$protected" in "$decoded"/*) return 1 ;; esac
	done
	KPANEL_DISK_MANAGEMENT_MOUNTPOINT="$decoded"
	KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX="$(kpanel_disk_management_hex_encode "$decoded")"
}

kpanel_disk_management_is_block_device() {
	[ -b "$1" ]
}

kpanel_disk_management_resolve_device() {
	local requested="$1" output line device_id device_path extra resolved verify matches=0 invalid=false
	[[ "$requested" =~ ^[0-9]+:[0-9]+$ ]] || return 2
	output="$(lsblk --noheadings --raw --paths --output MAJ:MIN,PATH 2>/dev/null)" || return 1
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		device_id=""; device_path=""; extra=""
		read -r device_id device_path extra <<< "$line"
		if [ -n "$extra" ] || [[ ! "$device_id" =~ ^[0-9]+:[0-9]+$ ]] || [[ "$device_path" != /dev/* ]]; then
			invalid=true
			continue
		fi
		if [ "$device_id" = "$requested" ]; then
			matches=$((matches + 1))
			KPANEL_DISK_MANAGEMENT_LISTED_PATH="$device_path"
		fi
	done <<< "$output"
	[ "$invalid" = false ] && [ "$matches" -eq 1 ] || return 1
	resolved="$(readlink -f -- "$KPANEL_DISK_MANAGEMENT_LISTED_PATH" 2>/dev/null)" || return 1
	[[ "$resolved" = /dev/* ]] && kpanel_disk_management_is_block_device "$resolved" || return 1
	verify="$(lsblk --nodeps --noheadings --raw --output MAJ:MIN -- "$resolved" 2>/dev/null)" || return 1
	[ "$verify" = "$requested" ] || return 1
	KPANEL_DISK_MANAGEMENT_DEVICE_PATH="$resolved"
	KPANEL_DISK_MANAGEMENT_DEVICE_ID="$requested"
}

kpanel_disk_management_lsblk_value() {
	local path="$1" column="$2" value
	case "$column" in TYPE|RO|FSTYPE) ;; *) return 1 ;; esac
	value="$(lsblk --nodeps --noheadings --raw --output "$column" -- "$path" 2>/dev/null)" || return 1
	[[ "$value" != *$'\n'* ]] && [[ "$value" != *$'\r'* ]] || return 1
	printf '%s' "$value"
}

kpanel_disk_management_swaps_file() {
	printf '%s\n' "/proc/swaps"
}

kpanel_disk_management_device_is_active_swap() {
	local device="$1" swaps source rest resolved
	swaps="$(kpanel_disk_management_swaps_file)" || return 2
	[ -r "$swaps" ] || return 2
	while read -r source rest; do
		[ -n "$source" ] || continue
		[ "$source" != Filename ] || continue
		case "$source" in
			/dev/*)
				resolved="$(readlink -f -- "$source" 2>/dev/null)" || return 2
				[ "$resolved" != "$device" ] || return 0
				;;
		esac
	done < "$swaps"
	return 1
}

kpanel_disk_management_validate_device_common() {
	local type ro fstype probed probe_rc swap_rc
	type="$(kpanel_disk_management_lsblk_value "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" TYPE)" || return 1
	ro="$(kpanel_disk_management_lsblk_value "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" RO)" || return 1
	fstype="$(kpanel_disk_management_lsblk_value "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" FSTYPE)" || return 1
	[[ "$type" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	[[ "$ro" =~ ^[01]$ ]] || return 1
	[ -z "$fstype" ] || [[ "$fstype" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	probed="$(blkid -p -c /dev/null -s TYPE -o value "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" 2>/dev/null)"
	probe_rc=$?
	case "$probe_rc" in
		0)
			[[ "$probed" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
			fstype="$probed"
			;;
		2) [ -z "$fstype" ] || return 1 ;;
		*) return 1 ;;
	esac
	[ "$ro" = 0 ] || return 3
	[ "$fstype" != swap ] || return 3
	kpanel_disk_management_device_is_active_swap "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH"
	swap_rc=$?
	[ "$swap_rc" -ne 0 ] || return 3
	[ "$swap_rc" -eq 1 ] || return 1
	KPANEL_DISK_MANAGEMENT_DEVICE_TYPE="$type"
	KPANEL_DISK_MANAGEMENT_FSTYPE="$fstype"
}

kpanel_disk_management_device_is_leaf() {
	local path="$1" expected="$2" output line count=0
	output="$(lsblk --noheadings --raw --output MAJ:MIN -- "$path" 2>/dev/null)" || return 2
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[[ "$line" =~ ^[0-9]+:[0-9]+$ ]] || return 2
		[ "$count" -ne 0 ] || [ "$line" = "$expected" ] || return 2
		count=$((count + 1))
	done <<< "$output"
	[ "$count" -eq 1 ]
}

kpanel_disk_management_holders_dir() {
	printf '/sys/dev/block/%s/holders\n' "$1"
}

kpanel_disk_management_device_has_holders() {
	local device_id="$1" directory first
	directory="$(kpanel_disk_management_holders_dir "$device_id")" || return 2
	[ -d "$directory" ] || return 2
	first="$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" || return 2
	[ -n "$first" ]
}

kpanel_disk_management_mount_ids() {
	local output line
	output="$(findmnt --kernel --raw --noheadings --output MAJ:MIN 2>/dev/null)" || return 2
	[ -n "$output" ] || return 2
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[[ "$line" =~ ^[0-9]+:[0-9]+$ ]] || return 2
		printf '%s\n' "$line"
	done <<< "$output"
}

kpanel_disk_management_device_is_mounted() {
	local requested="$1" output line
	output="$(kpanel_disk_management_mount_ids)" || return 2
	while IFS= read -r line; do
		[ "$line" != "$requested" ] || return 0
	done <<< "$output"
	return 1
}

kpanel_disk_management_target_device() {
	local mountpoint="$1" output rc
	output="$(findmnt --kernel --raw --noheadings --output MAJ:MIN --mountpoint "$mountpoint" 2>/dev/null)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		[ "$rc" -eq 1 ] && [ -z "$output" ] && return 1
		return 2
	fi
	[[ "$output" =~ ^[0-9]+:[0-9]+$ ]] || return 2
	printf '%s' "$output"
}

kpanel_disk_management_require_leaf_unmounted() {
	local leaf_rc holders_rc mounted_rc
	kpanel_disk_management_device_is_leaf "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" "$KPANEL_DISK_MANAGEMENT_DEVICE_ID"
	leaf_rc=$?
	[ "$leaf_rc" -eq 0 ] || { [ "$leaf_rc" -eq 1 ] && return 3; return 1; }
	kpanel_disk_management_device_has_holders "$KPANEL_DISK_MANAGEMENT_DEVICE_ID"
	holders_rc=$?
	[ "$holders_rc" -ne 0 ] || return 3
	[ "$holders_rc" -eq 1 ] || return 1
	kpanel_disk_management_device_is_mounted "$KPANEL_DISK_MANAGEMENT_DEVICE_ID"
	mounted_rc=$?
	[ "$mounted_rc" -ne 0 ] || return 3
	[ "$mounted_rc" -eq 1 ] || return 1
}

kpanel_disk_management_fstab_file() {
	printf '%s\n' "/etc/fstab"
}

kpanel_disk_management_state_root() {
	printf '%s/system/disk-management\n' "$(kpanel_system_resource_state_root)"
}

kpanel_disk_management_prepare_state_subdir() {
	local name="$1" root path
	case "$name" in mountpoints|recovery) ;; *) return 1 ;; esac
	root="$(kpanel_disk_management_state_root)" || return 1
	[[ "$root" = /* ]] && [ "$root" != / ] || return 1
	kpanel_system_resource_path_has_no_symlink "$root" || return 1
	if [ ! -e "$root" ]; then
		(umask 077; mkdir -p -- "$root") >/dev/null 2>&1 || return 1
	fi
	kpanel_system_resource_path_has_no_symlink "$root" &&
		kpanel_system_resource_secure_directory "$root" || return 1
	path="$root/$name"
	kpanel_system_resource_path_has_no_symlink "$path" || return 1
	if [ ! -e "$path" ]; then
		(umask 077; mkdir -- "$path") >/dev/null 2>&1 || return 1
	fi
	kpanel_system_resource_path_has_no_symlink "$path" &&
		kpanel_system_resource_secure_directory "$path" || return 1
	printf '%s\n' "$path"
}

kpanel_disk_management_fstab_escape() {
	local value="$1"
	value="${value//\\/\\134}"
	value="${value// /\\040}"
	printf '%s' "$value"
}

kpanel_disk_management_persistence_source() {
	local path="$1" value rc
	value="$(blkid -c /dev/null -s UUID -o value "$path" 2>/dev/null)"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		[[ "$value" =~ ^[A-Za-z0-9._:+-]+$ ]] || return 1
		KPANEL_DISK_MANAGEMENT_PERSISTENCE_SOURCE="UUID=$value"
		return 0
	fi
	[ "$rc" -eq 2 ] || return 1
	value="$(blkid -c /dev/null -s PARTUUID -o value "$path" 2>/dev/null)"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		[[ "$value" =~ ^[A-Za-z0-9._:+-]+$ ]] || return 1
		KPANEL_DISK_MANAGEMENT_PERSISTENCE_SOURCE="PARTUUID=$value"
		return 0
	fi
	[ "$rc" -eq 2 ] || return 1
	return 2
}

kpanel_disk_management_probe_fstype() {
	local path="$1" value
	value="$(blkid -p -c /dev/null -s TYPE -o value "$path" 2>/dev/null)" || return 1
	[[ "$value" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	printf '%s' "$value"
}

kpanel_disk_management_cleanup_incomplete_backup() {
	local snapshot="$1"
	[ -d "$snapshot" ] && [ ! -L "$snapshot" ] || return 1
	rm -f -- "$snapshot/fstab" "$snapshot/mode" "$snapshot/owner" >/dev/null 2>&1 || return 1
	rmdir -- "$snapshot" >/dev/null 2>&1
}

kpanel_disk_management_fstab_backup_valid() (
	local snapshot="$1" recovery="$2" name expected_uid uid mode links entry count=0 file saved_mode saved_owner
	local entries=()
	[ "$(dirname -- "$snapshot")" = "$recovery" ] || return 1
	name="${snapshot##*/}"
	[[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-fstab\.[A-Za-z0-9]{6}$ ]] || return 1
	kpanel_system_resource_path_has_no_symlink "$snapshot" || return 1
	[ -d "$snapshot" ] && [ ! -L "$snapshot" ] || return 1
	expected_uid="$(kpanel_disk_management_path_owner_uid)" || return 1
	uid="$(kpanel_disk_management_path_stat_uid "$snapshot")" || return 1
	mode="$(kpanel_disk_management_path_stat_mode "$snapshot")" || return 1
	[[ "$expected_uid" =~ ^[0-9]+$ ]] && [ "$uid" = "$expected_uid" ] || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 0777))" -eq 448 ] || return 1
	shopt -s nullglob dotglob
	entries=("$snapshot"/*)
	for entry in "${entries[@]}"; do
		case "$entry" in
			"$snapshot/fstab"|"$snapshot/mode"|"$snapshot/owner") ;;
			*) return 1 ;;
		esac
		count=$((count + 1))
	done
	[ "$count" -eq 3 ] || return 1
	for file in "$snapshot/fstab" "$snapshot/mode" "$snapshot/owner"; do
		[ -f "$file" ] && [ ! -L "$file" ] || return 1
		uid="$(kpanel_disk_management_path_stat_uid "$file")" || return 1
		mode="$(kpanel_disk_management_path_stat_mode "$file")" || return 1
		links="$(kpanel_disk_management_lock_stat_links "$file")" || return 1
		[ "$uid" = "$expected_uid" ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] && [[ "$links" =~ ^[0-9]+$ ]] &&
			[ "$((8#$mode & 0777))" -eq 384 ] && [ "$links" -eq 1 ] || return 1
	done
	kpanel_system_resource_file_within_bounds "$snapshot/fstab" 1048576 16384 || return 1
	saved_mode="$(<"$snapshot/mode")" || return 1
	saved_owner="$(<"$snapshot/owner")" || return 1
	[[ "$saved_mode" =~ ^[0-7]{3,4}$ ]] && [[ "$saved_owner" =~ ^[0-9]+:[0-9]+$ ]]
)

kpanel_disk_management_remove_fstab_backup() {
	local snapshot="$1" recovery="$2"
	kpanel_disk_management_fstab_backup_valid "$snapshot" "$recovery" || return 1
	rm -f -- "$snapshot/fstab" "$snapshot/mode" "$snapshot/owner" >/dev/null 2>&1 || return 1
	rmdir -- "$snapshot" >/dev/null 2>&1
}

kpanel_disk_management_prune_fstab_backups() (
	local limit="$1" protected="${2:-}" recovery="${3:-}" entry remaining index=0
	local entries=()
	local LC_ALL=C
	[[ "$limit" =~ ^[0-9]+$ ]] || return 1
	[ -n "$recovery" ] || recovery="$(kpanel_disk_management_prepare_state_subdir recovery)" || return 1
	[ -d "$recovery" ] && [ ! -L "$recovery" ] || return 1
	shopt -s nullglob dotglob
	entries=("$recovery"/*)
	for entry in "${entries[@]}"; do
		kpanel_disk_management_fstab_backup_valid "$entry" "$recovery" || return 1
	done
	if [ -n "$protected" ]; then
		kpanel_disk_management_fstab_backup_valid "$protected" "$recovery" || return 1
	fi
	remaining="${#entries[@]}"
	while [ "$remaining" -gt "$limit" ]; do
		[ "$index" -lt "${#entries[@]}" ] || return 1
		entry="${entries[$index]}"
		index=$((index + 1))
		[ "$entry" != "$protected" ] || continue
		kpanel_disk_management_remove_fstab_backup "$entry" "$recovery" || return 1
		remaining=$((remaining - 1))
	done
)

kpanel_disk_management_create_fstab_backup() {
	local fstab="$1" recovery timestamp snapshot mode owner
	recovery="$(kpanel_disk_management_prepare_state_subdir recovery)" || return 1
	kpanel_disk_management_prune_fstab_backups 15 "" "$recovery" || return 1
	timestamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)" || return 1
	[[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || return 1
	snapshot="$(mktemp -d "$recovery/${timestamp}-fstab.XXXXXX")" || return 1
	chmod 700 "$snapshot" >/dev/null 2>&1 && chown 0:0 "$snapshot" >/dev/null 2>&1 || {
		kpanel_disk_management_cleanup_incomplete_backup "$snapshot" >/dev/null 2>&1 || true
		return 1
	}
	mode="$(stat -c '%a' "$fstab" 2>/dev/null)" || { kpanel_disk_management_cleanup_incomplete_backup "$snapshot"; return 1; }
	owner="$(stat -c '%u:%g' "$fstab" 2>/dev/null)" || { kpanel_disk_management_cleanup_incomplete_backup "$snapshot"; return 1; }
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || {
		kpanel_disk_management_cleanup_incomplete_backup "$snapshot" >/dev/null 2>&1 || true
		return 1
	}
	cp -- "$fstab" "$snapshot/fstab" >/dev/null 2>&1 &&
		printf '%s\n' "$mode" > "$snapshot/mode" &&
		printf '%s\n' "$owner" > "$snapshot/owner" || {
		kpanel_disk_management_cleanup_incomplete_backup "$snapshot" >/dev/null 2>&1 || true
		return 1
	}
	chown 0:0 "$snapshot/fstab" "$snapshot/mode" "$snapshot/owner" >/dev/null 2>&1 &&
		chmod 600 "$snapshot/fstab" "$snapshot/mode" "$snapshot/owner" >/dev/null 2>&1 &&
		sync -f "$snapshot/fstab" >/dev/null 2>&1 && sync -f "$snapshot" >/dev/null 2>&1 || {
		kpanel_disk_management_cleanup_incomplete_backup "$snapshot" >/dev/null 2>&1 || true
		return 1
	}
	kpanel_disk_management_fstab_backup_valid "$snapshot" "$recovery" || {
		kpanel_disk_management_cleanup_incomplete_backup "$snapshot" >/dev/null 2>&1 || true
		return 1
	}
	printf '%s\n' "$snapshot"
}

kpanel_disk_management_restore_fstab() {
	local fstab="$1" snapshot="$2" directory temporary mode owner recovery
	recovery="$(kpanel_disk_management_prepare_state_subdir recovery)" || return 1
	kpanel_disk_management_fstab_backup_valid "$snapshot" "$recovery" || return 1
	mode="$(<"$snapshot/mode")" || return 1
	owner="$(<"$snapshot/owner")" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || return 1
	directory="$(dirname -- "$fstab")" || return 1
	temporary="$(mktemp "$directory/.fstab.kpanel-restore.XXXXXX")" || return 1
	cp -- "$snapshot/fstab" "$temporary" >/dev/null 2>&1 &&
		chown "$owner" "$temporary" >/dev/null 2>&1 && chmod "$mode" "$temporary" >/dev/null 2>&1 &&
		findmnt --verify --tab-file "$temporary" >&2 && sync -f "$temporary" >/dev/null 2>&1 &&
		mv -f -- "$temporary" "$fstab" >/dev/null 2>&1 && sync -f "$fstab" >/dev/null 2>&1 &&
		sync -f "$directory" >/dev/null 2>&1 || {
		rm -f -- "$temporary" >/dev/null 2>&1
		return 1
	}
	findmnt --verify --tab-file "$fstab" >&2
}

kpanel_disk_management_fstab_transaction() {
	local operation="$1" source="$2" mountpoint="$3" fstype="$4"
	local fstab directory escaped_target desired="" pass_number=0 analysis exact desired_count conflict extra temporary backup uid mode
	KPANEL_DISK_MANAGEMENT_FSTAB_CHANGED=false
	KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP=""
	KPANEL_DISK_MANAGEMENT_FSTAB_ROLLBACK_FAILED=false
	case "$operation" in ensure|remove) ;; *) return 1 ;; esac
	[[ "$source" =~ ^(UUID|PARTUUID)=[A-Za-z0-9._:+-]+$ ]] || return 1
	if [ "$operation" = ensure ]; then
		[[ "$fstype" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	fi
	fstab="$(kpanel_disk_management_fstab_file)" || return 1
	[ -f "$fstab" ] && [ ! -L "$fstab" ] || return 1
	kpanel_system_resource_path_has_no_symlink "$fstab" || return 1
	kpanel_system_resource_file_within_bounds "$fstab" 1048576 16384 || return 1
	uid="$(kpanel_disk_management_path_stat_uid "$fstab")" || return 1
	mode="$(kpanel_disk_management_path_stat_mode "$fstab")" || return 1
	[ "$uid" = "$(kpanel_disk_management_path_owner_uid)" ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
		[ "$((8#$mode & 0022))" -eq 0 ] || return 1
	directory="$(dirname -- "$fstab")" || return 1
	[ -d "$directory" ] && [ ! -L "$directory" ] || return 1
	escaped_target="$(kpanel_disk_management_fstab_escape "$mountpoint")" || return 1
	case "$fstype" in ext2|ext3|ext4) pass_number=2 ;; esac
	desired="$source $escaped_target $fstype defaults,nofail 0 $pass_number"
	analysis="$(awk -v source="$source" -v target="$escaped_target" -v desired="$desired" -v operation="$operation" '
		BEGIN { exact=0; desired_count=0; conflict=0 }
		{
			active=($0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/)
			if (active && NF >= 2) {
				if ($1 == source && $2 == target) {
					exact++
					if ($0 == desired) desired_count++
				} else if ($2 == target || (operation == "ensure" && $1 == source)) {
					conflict=1
				}
			}
		}
		END { printf "%d %d %d\n", exact, desired_count, conflict }
	' "$fstab" 2>/dev/null)" || return 1
	read -r exact desired_count conflict extra <<< "$analysis"
	[ -z "$extra" ] && [[ "$exact" =~ ^[0-9]+$ ]] && [[ "$desired_count" =~ ^[0-9]+$ ]] &&
		[[ "$conflict" =~ ^[01]$ ]] || return 1
	[ "$conflict" -eq 0 ] || return 2
	findmnt --verify --tab-file "$fstab" >&2 || return 1
	kpanel_disk_management_prune_fstab_backups 16 || return 1
	if [ "$operation" = ensure ] && [ "$exact" -eq 1 ] && [ "$desired_count" -eq 1 ]; then
		return 0
	fi
	if [ "$operation" = remove ] && [ "$exact" -eq 0 ]; then
		return 0
	fi
	temporary="$(mktemp "$directory/.fstab.kpanel.XXXXXX")" || return 1
	awk -v source="$source" -v target="$escaped_target" '
		{
			active=($0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/)
			if (active && NF >= 2 && $1 == source && $2 == target) next
			print
		}
	' "$fstab" > "$temporary" || { rm -f -- "$temporary"; return 1; }
	if [ "$operation" = ensure ]; then
		printf '%s\n' "$desired" >> "$temporary" || { rm -f -- "$temporary"; return 1; }
	fi
	kpanel_system_resource_copy_identity "$fstab" "$temporary" || { rm -f -- "$temporary"; return 1; }
	findmnt --verify --tab-file "$temporary" >&2 || { rm -f -- "$temporary"; return 1; }
	backup="$(kpanel_disk_management_create_fstab_backup "$fstab")" || { rm -f -- "$temporary"; return 1; }
	KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP="$backup"
	if ! sync -f "$temporary" >/dev/null 2>&1 ||
		! mv -f -- "$temporary" "$fstab" >/dev/null 2>&1 ||
		! sync -f "$fstab" >/dev/null 2>&1 ||
		! sync -f "$directory" >/dev/null 2>&1 ||
		! findmnt --verify --tab-file "$fstab" >&2; then
		rm -f -- "$temporary" >/dev/null 2>&1
		if ! kpanel_disk_management_restore_fstab "$fstab" "$backup"; then
			KPANEL_DISK_MANAGEMENT_FSTAB_ROLLBACK_FAILED=true
		fi
		return 1
	fi
	KPANEL_DISK_MANAGEMENT_FSTAB_CHANGED=true
}

kpanel_disk_management_mountpoint_marker_path() {
	local mountpoint="$1" directory digest
	directory="$(kpanel_disk_management_prepare_state_subdir mountpoints)" || return 1
	digest="$(printf '%s' "$mountpoint" | sha256sum 2>/dev/null | awk '{print $1}')" || return 1
	[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s/%s.mountpoint\n' "$directory" "$digest"
}

kpanel_disk_management_marker_valid() {
	local marker="$1" device_id="$2" mountpoint_hex="$3" uid mode links
	[ -f "$marker" ] && [ ! -L "$marker" ] || return 1
	uid="$(kpanel_disk_management_path_stat_uid "$marker")" || return 1
	mode="$(kpanel_disk_management_path_stat_mode "$marker")" || return 1
	links="$(kpanel_disk_management_lock_stat_links "$marker")" || return 1
	[ "$uid" = "$(kpanel_disk_management_path_owner_uid)" ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
		[[ "$links" =~ ^[0-9]+$ ]] && [ "$((8#$mode & 0777))" -eq 384 ] && [ "$links" -eq 1 ] || return 1
	kpanel_system_resource_file_within_bounds "$marker" 8192 8 || return 1
	grep -Fqx 'protocol=1' "$marker" &&
		grep -Fqx "device=$device_id" "$marker" &&
		grep -Fqx "mountpoint_hex=$mountpoint_hex" "$marker"
}

kpanel_disk_management_record_mountpoint() {
	local device_id="$1" mountpoint="$2" mountpoint_hex="$3" marker directory temporary
	marker="$(kpanel_disk_management_mountpoint_marker_path "$mountpoint")" || return 1
	directory="$(dirname -- "$marker")" || return 1
	[ ! -L "$marker" ] || return 1
	if [ -e "$marker" ]; then
		kpanel_disk_management_marker_valid "$marker" "$device_id" "$mountpoint_hex"
		return $?
	fi
	temporary="$(mktemp "$directory/.mountpoint.XXXXXX")" || return 1
	printf 'protocol=1\ndevice=%s\nmountpoint_hex=%s\n' "$device_id" "$mountpoint_hex" > "$temporary" || {
		rm -f -- "$temporary"
		return 1
	}
	chown 0:0 "$temporary" >/dev/null 2>&1 && chmod 600 "$temporary" >/dev/null 2>&1 &&
		sync -f "$temporary" >/dev/null 2>&1 && mv -f -- "$temporary" "$marker" >/dev/null 2>&1 &&
		sync -f "$directory" >/dev/null 2>&1 || {
		rm -f -- "$temporary"
		return 1
	}
	kpanel_disk_management_marker_valid "$marker" "$device_id" "$mountpoint_hex"
}

kpanel_disk_management_forget_mountpoint() {
	local device_id="$1" mountpoint="$2" mountpoint_hex="$3" marker directory content
	marker="$(kpanel_disk_management_mountpoint_marker_path "$mountpoint" 2>/dev/null)" || return 0
	kpanel_disk_management_marker_valid "$marker" "$device_id" "$mountpoint_hex" || return 0
	[ -d "$mountpoint" ] && [ ! -L "$mountpoint" ] || return 0
	content="$(find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" || return 0
	[ -z "$content" ] || return 0
	rmdir -- "$mountpoint" >/dev/null 2>&1 || return 0
	directory="$(dirname -- "$marker")" || return 0
	rm -f -- "$marker" >/dev/null 2>&1 || return 0
	sync -f "$directory" >/dev/null 2>&1 || true
}

kpanel_disk_management_cleanup_new_mountpoint() {
	local device_id="$1" mountpoint="$2" mountpoint_hex="$3" marker
	marker="$(kpanel_disk_management_mountpoint_marker_path "$mountpoint" 2>/dev/null || true)"
	if [ -n "$marker" ] && kpanel_disk_management_marker_valid "$marker" "$device_id" "$mountpoint_hex"; then
		rm -f -- "$marker" >/dev/null 2>&1 || true
	fi
	[ -d "$mountpoint" ] && [ ! -L "$mountpoint" ] && rmdir -- "$mountpoint" >/dev/null 2>&1 || true
}

kpanel_disk_management_prepare_device() {
	local device_id="$1" rc
	KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE=""
	kpanel_disk_management_resolve_device "$device_id"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE="无法按 MAJ:MIN 唯一解析安全块设备"
		return 1
	fi
	kpanel_disk_management_validate_device_common
	rc=$?
	case "$rc" in
		0) return 0 ;;
		3)
			KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE="设备为只读设备或 Swap，拒绝操作"
			return 3
			;;
		*)
			KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE="无法可靠读取设备属性"
			return 1
			;;
	esac
}

kpanel_disk_management_require_safe_leaf() {
	local rc
	kpanel_disk_management_require_leaf_unmounted
	rc=$?
	case "$rc" in
		0) return 0 ;;
		3)
			KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE="设备已挂载、存在子设备或仍被 holder 使用"
			return 3
			;;
		*)
			KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE="无法可靠确认设备拓扑或挂载状态"
			return 1
			;;
	esac
}

kpanel_disk_management_rollback_live_mount() {
	local device_id="$1" mountpoint="$2" created="$3" mountpoint_hex="$4" target rc
	target="$(kpanel_disk_management_target_device "$mountpoint")"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		[ "$target" = "$device_id" ] || return 1
		umount -- "$mountpoint" >&2 || return 1
		target="$(kpanel_disk_management_target_device "$mountpoint")"
		rc=$?
		[ "$rc" -eq 1 ] || return 1
	elif [ "$rc" -ne 1 ]; then
		return 1
	fi
	if [ "$created" = true ]; then
		kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$mountpoint" "$mountpoint_hex"
	fi
}

kpanel_disk_management_restore_live_mount() {
	local device_id="$1" device_path="$2" mountpoint="$3" target rc
	mount --source "$device_path" --target "$mountpoint" >&2 || return 1
	target="$(kpanel_disk_management_target_device "$mountpoint")"
	rc=$?
	[ "$rc" -eq 0 ] && [ "$target" = "$device_id" ]
}

kpanel_disk_management_mount_action() {
	local device_id="$1" mountpoint_hex="$2" persist="$3"
	local rc target mounted_rc content parent created=false source_rc fstab_rc backup=""
	if ! kpanel_disk_management_decode_mountpoint "$mountpoint_hex"; then
		kpanel_disk_management_reply failed "$device_id" "挂载点编码、规范路径或保护路径校验失败" "" 2
		return $?
	fi
	if ! kpanel_disk_management_mountpoint_parent_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" true; then
		kpanel_disk_management_reply needs-attention "$device_id" "挂载点路径包含符号链接、非 root 目录或可被非 root 写入" "" 3
		return $?
	fi
	kpanel_disk_management_prepare_device "$device_id"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	[ -n "$KPANEL_DISK_MANAGEMENT_FSTYPE" ] || {
		kpanel_disk_management_reply needs-attention "$device_id" "设备没有可挂载的已知文件系统" "" 3
		return $?
	}
	case "$KPANEL_DISK_MANAGEMENT_FSTYPE" in
		swap|LVM2_member|linux_raid_member|crypto_LUKS|zfs_member)
			kpanel_disk_management_reply needs-attention "$device_id" "设备签名不是可直接挂载的文件系统" "" 3
			return $?
			;;
	esac
	target="$(kpanel_disk_management_target_device "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT")"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		[ "$target" = "$device_id" ] || {
			kpanel_disk_management_reply needs-attention "$device_id" "目标已被其他设备占用" "" 3
			return $?
		}
		if [ "$persist" = 1 ]; then
			kpanel_disk_management_persistence_source "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH"
			source_rc=$?
			if [ "$source_rc" -ne 0 ]; then
				if [ "$source_rc" -eq 2 ]; then
					kpanel_disk_management_reply needs-attention "$device_id" "设备缺少 UUID/PARTUUID，无法安全持久化" "" 3
				else
					kpanel_disk_management_reply failed "$device_id" "无法读取设备持久化标识" "" 1
				fi
				return $?
			fi
			kpanel_disk_management_fstab_transaction ensure "$KPANEL_DISK_MANAGEMENT_PERSISTENCE_SOURCE" \
				"$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_FSTYPE"
			fstab_rc=$?
			backup="$KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP"
			if [ "$fstab_rc" -ne 0 ]; then
				if [ "$KPANEL_DISK_MANAGEMENT_FSTAB_ROLLBACK_FAILED" = true ]; then
					kpanel_disk_management_reply rollback-failed "$device_id" "fstab 更新失败且配置回滚失败，需要人工恢复" "$backup" 4
				elif [ "$fstab_rc" -eq 2 ]; then
					kpanel_disk_management_reply needs-attention "$device_id" "fstab 存在设备或挂载点冲突" "$backup" 3
				else
					kpanel_disk_management_reply failed "$device_id" "fstab 持久化失败，原有实时挂载保持不变" "$backup" 1
				fi
				return $?
			fi
			if [ "$KPANEL_DISK_MANAGEMENT_FSTAB_CHANGED" = true ]; then
				kpanel_disk_management_reply applied "$device_id" "实时挂载未变化，持久化配置已应用" "$backup" 0
			else
				kpanel_disk_management_reply unchanged "$device_id" "设备已经按目标挂载并持久化" "" 0
			fi
			return $?
		fi
		kpanel_disk_management_reply unchanged "$device_id" "设备已经按目标挂载" "" 0
		return $?
	elif [ "$rc" -ne 1 ]; then
		kpanel_disk_management_reply failed "$device_id" "无法可靠读取目标挂载状态" "" 1
		return $?
	fi
	if ! kpanel_disk_management_mountpoint_path_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" true; then
		kpanel_disk_management_reply needs-attention "$device_id" "未挂载目标不是 root 独占的安全目录路径" "" 3
		return $?
	fi
	kpanel_disk_management_device_is_mounted "$device_id"
	mounted_rc=$?
	if [ "$mounted_rc" -eq 0 ]; then
		kpanel_disk_management_reply needs-attention "$device_id" "设备已挂载在其他目标，拒绝重复挂载" "" 3
		return $?
	elif [ "$mounted_rc" -ne 1 ]; then
		kpanel_disk_management_reply failed "$device_id" "无法可靠读取设备挂载状态" "" 1
		return $?
	fi
	if [ -e "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" ] || [ -L "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" ]; then
		[ -d "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" ] && [ ! -L "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" ] || {
			kpanel_disk_management_reply needs-attention "$device_id" "目标不是安全的真实目录" "" 3
			return $?
		}
	else
		parent="$(dirname -- "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT")" || {
			kpanel_disk_management_reply failed "$device_id" "无法解析挂载点父目录" "" 1
			return $?
		}
		[ -d "$parent" ] && [ ! -L "$parent" ] || {
			kpanel_disk_management_reply needs-attention "$device_id" "挂载点父目录不存在或不安全" "" 3
			return $?
		}
		if ! (umask 077; mkdir -- "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT") >/dev/null 2>&1; then
			kpanel_disk_management_reply failed "$device_id" "创建挂载点失败" "" 1
			return $?
		fi
		created=true
		if ! chown 0:0 "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" >/dev/null 2>&1 ||
			! chmod 700 "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" >/dev/null 2>&1; then
			kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
			kpanel_disk_management_reply failed "$device_id" "无法设置新挂载点安全属性" "" 1
			return $?
		fi
		if ! kpanel_disk_management_mountpoint_path_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
			kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
			kpanel_disk_management_reply failed "$device_id" "新挂载点安全属性复核失败" "" 1
			return $?
		fi
		if ! kpanel_disk_management_record_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"; then
			kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
			kpanel_disk_management_reply failed "$device_id" "无法记录 KPanel 创建的挂载点" "" 1
			return $?
		fi
	fi
	content="$(find "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" || {
		[ "$created" = true ] && kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
		kpanel_disk_management_reply failed "$device_id" "无法安全检查挂载点内容" "" 1
		return $?
	}
	if [ -n "$content" ]; then
		[ "$created" = true ] && kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
		kpanel_disk_management_reply needs-attention "$device_id" "挂载点非空，拒绝覆盖现有内容" "" 3
		return $?
	fi
	if [ "$persist" = 1 ]; then
		kpanel_disk_management_persistence_source "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH"
		source_rc=$?
		if [ "$source_rc" -ne 0 ]; then
			[ "$created" = true ] && kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
			if [ "$source_rc" -eq 2 ]; then
				kpanel_disk_management_reply needs-attention "$device_id" "设备缺少 UUID/PARTUUID，无法安全持久化" "" 3
			else
				kpanel_disk_management_reply failed "$device_id" "无法读取设备持久化标识" "" 1
			fi
			return $?
		fi
	fi
	if ! kpanel_disk_management_mountpoint_path_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
		[ "$created" = true ] && kpanel_disk_management_cleanup_new_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
		kpanel_disk_management_reply needs-attention "$device_id" "挂载前安全复核失败" "" 3
		return $?
	fi
	if ! mount --source "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" --target "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" >&2; then
		if kpanel_disk_management_rollback_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$created" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"; then
			kpanel_disk_management_reply failed "$device_id" "挂载命令失败，未保留部分状态" "" 1
		else
			kpanel_disk_management_reply rollback-failed "$device_id" "挂载命令失败且无法确认或清理部分挂载" "" 4
		fi
		return $?
	fi
	if ! kpanel_disk_management_mountpoint_parent_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
		if kpanel_disk_management_rollback_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$created" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"; then
			kpanel_disk_management_reply failed "$device_id" "挂载后安全属性复核失败，已回滚" "" 1
		else
			kpanel_disk_management_reply rollback-failed "$device_id" "挂载后安全属性复核失败且回滚失败" "" 4
		fi
		return $?
	fi
	target="$(kpanel_disk_management_target_device "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT")"
	rc=$?
	if [ "$rc" -ne 0 ] || [ "$target" != "$device_id" ]; then
		if kpanel_disk_management_rollback_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$created" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"; then
			kpanel_disk_management_reply failed "$device_id" "挂载完成态回读失败，已回滚" "" 1
		else
			kpanel_disk_management_reply rollback-failed "$device_id" "挂载完成态回读失败且回滚失败" "" 4
		fi
		return $?
	fi
	if [ "$persist" = 1 ]; then
		kpanel_disk_management_fstab_transaction ensure "$KPANEL_DISK_MANAGEMENT_PERSISTENCE_SOURCE" \
			"$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_FSTYPE"
		fstab_rc=$?
		backup="$KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP"
		if [ "$fstab_rc" -ne 0 ]; then
			if ! kpanel_disk_management_rollback_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$created" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX" ||
				[ "$KPANEL_DISK_MANAGEMENT_FSTAB_ROLLBACK_FAILED" = true ]; then
				kpanel_disk_management_reply rollback-failed "$device_id" "fstab 持久化失败且回滚未完整完成" "$backup" 4
			elif [ "$fstab_rc" -eq 2 ]; then
				kpanel_disk_management_reply needs-attention "$device_id" "fstab 存在冲突，实时挂载已回滚" "$backup" 3
			else
				kpanel_disk_management_reply failed "$device_id" "fstab 持久化失败，实时挂载已回滚" "$backup" 1
			fi
			return $?
		fi
	fi
	backup="${KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP:-}"
	kpanel_disk_management_reply applied "$device_id" "设备已挂载并完成状态回读" "$backup" 0
}

kpanel_disk_management_unmount_action() {
	local device_id="$1" mountpoint_hex="$2" remove_persistence="$3"
	local rc target mounted_rc source_rc fstab_rc backup=""
	if ! kpanel_disk_management_decode_mountpoint "$mountpoint_hex"; then
		kpanel_disk_management_reply failed "$device_id" "挂载点编码、规范路径或保护路径校验失败" "" 2
		return $?
	fi
	if ! kpanel_disk_management_mountpoint_parent_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
		kpanel_disk_management_reply needs-attention "$device_id" "卸载目标路径包含符号链接、非 root 目录或可被非 root 写入" "" 3
		return $?
	fi
	kpanel_disk_management_prepare_device "$device_id"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	target="$(kpanel_disk_management_target_device "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT")"
	rc=$?
	if [ "$rc" -eq 1 ]; then
		kpanel_disk_management_device_is_mounted "$device_id"
		mounted_rc=$?
		if [ "$mounted_rc" -eq 0 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "设备挂载在其他目标，拒绝卸载" "" 3
		elif [ "$mounted_rc" -eq 1 ]; then
			kpanel_disk_management_reply unchanged "$device_id" "设备未挂载在指定目标" "" 0
		else
			kpanel_disk_management_reply failed "$device_id" "无法可靠读取设备挂载状态" "" 1
		fi
		return $?
	elif [ "$rc" -ne 0 ]; then
		kpanel_disk_management_reply failed "$device_id" "无法可靠读取目标挂载状态" "" 1
		return $?
	fi
	[ "$target" = "$device_id" ] || {
		kpanel_disk_management_reply needs-attention "$device_id" "指定目标由其他设备占用" "" 3
		return $?
	}
	if [ "$remove_persistence" = 1 ]; then
		kpanel_disk_management_persistence_source "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH"
		source_rc=$?
		if [ "$source_rc" -ne 0 ]; then
			if [ "$source_rc" -eq 2 ]; then
				kpanel_disk_management_reply needs-attention "$device_id" "设备缺少 UUID/PARTUUID，无法精确移除持久化记录" "" 3
			else
				kpanel_disk_management_reply failed "$device_id" "无法读取设备持久化标识" "" 1
			fi
			return $?
		fi
	fi
	if ! kpanel_disk_management_mountpoint_parent_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
		kpanel_disk_management_reply needs-attention "$device_id" "卸载前安全复核失败" "" 3
		return $?
	fi
	if ! umount -- "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" >&2; then
		kpanel_disk_management_reply needs-attention "$device_id" "普通卸载失败，设备可能正被使用" "" 3
		return $?
	fi
	target="$(kpanel_disk_management_target_device "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT")"
	rc=$?
	if [ "$rc" -ne 1 ]; then
		kpanel_disk_management_reply failed "$device_id" "卸载完成态回读失败" "" 1
		return $?
	fi
	if ! kpanel_disk_management_mountpoint_path_secure "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" false; then
		if kpanel_disk_management_restore_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT"; then
			kpanel_disk_management_reply failed "$device_id" "卸载后安全属性复核失败，实时挂载已恢复" "" 1
		else
			kpanel_disk_management_reply rollback-failed "$device_id" "卸载后安全属性复核失败且实时挂载恢复失败" "" 4
		fi
		return $?
	fi
	if [ "$remove_persistence" = 1 ]; then
		kpanel_disk_management_fstab_transaction remove "$KPANEL_DISK_MANAGEMENT_PERSISTENCE_SOURCE" \
			"$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_FSTYPE"
		fstab_rc=$?
		backup="$KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP"
		if [ "$fstab_rc" -ne 0 ]; then
			if ! kpanel_disk_management_restore_live_mount "$device_id" "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" ||
				[ "$KPANEL_DISK_MANAGEMENT_FSTAB_ROLLBACK_FAILED" = true ]; then
				kpanel_disk_management_reply rollback-failed "$device_id" "持久化移除失败且实时挂载回滚失败" "$backup" 4
			elif [ "$fstab_rc" -eq 2 ]; then
				kpanel_disk_management_reply needs-attention "$device_id" "fstab 存在冲突，实时挂载已恢复" "$backup" 3
			else
				kpanel_disk_management_reply failed "$device_id" "持久化移除失败，实时挂载已恢复" "$backup" 1
			fi
			return $?
		fi
	fi
	kpanel_disk_management_forget_mountpoint "$device_id" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT" "$KPANEL_DISK_MANAGEMENT_MOUNTPOINT_HEX"
	backup="${KPANEL_DISK_MANAGEMENT_FSTAB_BACKUP:-}"
	kpanel_disk_management_reply applied "$device_id" "设备已从指定目标卸载" "$backup" 0
}

kpanel_disk_management_format_action() {
	local device_id="$1" requested_fstype="$2" command_name rc actual
	kpanel_disk_management_prepare_device "$device_id"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	kpanel_disk_management_require_safe_leaf
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	case "$requested_fstype" in
		ext4) command_name=mkfs.ext4 ;;
		xfs) command_name=mkfs.xfs ;;
		ntfs)
			if kpanel_disk_management_command_available mkfs.ntfs; then
				command_name=mkfs.ntfs
			elif kpanel_disk_management_command_available mkntfs; then
				command_name=mkntfs
			else
				command_name=""
			fi
			;;
		vfat)
			if kpanel_disk_management_command_available mkfs.vfat; then
				command_name=mkfs.vfat
			elif kpanel_disk_management_command_available mkfs.fat; then
				command_name=mkfs.fat
			else
				command_name=""
			fi
			;;
	esac
	if [ -z "$command_name" ] || ! kpanel_disk_management_command_available "$command_name"; then
		kpanel_disk_management_reply needs-attention "$device_id" "缺少所选文件系统的格式化工具" "" 3
		return $?
	fi
	case "$requested_fstype" in
		ext4) mkfs.ext4 -F "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		xfs) mkfs.xfs -f "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		ntfs)
			case "$command_name" in
				mkfs.ntfs) mkfs.ntfs -F "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
				mkntfs) mkntfs -F "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
			esac
			;;
		vfat)
			case "$command_name" in
				mkfs.vfat) mkfs.vfat "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
				mkfs.fat) mkfs.fat "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
			esac
			;;
	esac
	rc=$?
	if [ "$rc" -ne 0 ]; then
		kpanel_disk_management_reply failed "$device_id" "格式化命令失败，未声明可回滚" "" 1
		return $?
	fi
	command -v udevadm >/dev/null 2>&1 && udevadm settle >&2 || true
	actual="$(kpanel_disk_management_probe_fstype "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH")" || {
		kpanel_disk_management_reply failed "$device_id" "格式化后无法重读文件系统类型" "" 1
		return $?
	}
	[ "$actual" = "$requested_fstype" ] || {
		kpanel_disk_management_reply failed "$device_id" "格式化后文件系统类型回读不一致" "" 1
		return $?
	}
	kpanel_disk_management_reply applied "$device_id" "格式化已完成并通过文件系统类型回读" "" 0
}

kpanel_disk_management_check_action() {
	local device_id="$1" mode="$2" fstype command_name rc
	kpanel_disk_management_prepare_device "$device_id"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	kpanel_disk_management_require_safe_leaf
	rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$rc" -eq 3 ]; then
			kpanel_disk_management_reply needs-attention "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 3
		else
			kpanel_disk_management_reply failed "$device_id" "$KPANEL_DISK_MANAGEMENT_PREPARE_MESSAGE" "" 1
		fi
		return $?
	fi
	fstype="$(kpanel_disk_management_probe_fstype "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH")" || {
		kpanel_disk_management_reply needs-attention "$device_id" "无法识别可检查的文件系统" "" 3
		return $?
	}
	case "$fstype" in
		ext4) command_name=e2fsck ;;
		xfs) command_name=xfs_repair ;;
		ntfs) command_name=ntfsfix ;;
		vfat)
			if kpanel_disk_management_command_available fsck.vfat; then
				command_name=fsck.vfat
			elif kpanel_disk_management_command_available fsck.fat; then
				command_name=fsck.fat
			else
				command_name=""
			fi
			;;
		*)
			kpanel_disk_management_reply needs-attention "$device_id" "当前文件系统不在 v1 检查支持范围" "" 3
			return $?
			;;
	esac
	if [ -z "$command_name" ] || ! kpanel_disk_management_command_available "$command_name"; then
		kpanel_disk_management_reply needs-attention "$device_id" "缺少当前文件系统的检查工具" "" 3
		return $?
	fi
	case "$fstype:$mode" in
		ext4:readonly) e2fsck -fn "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		ext4:repair) e2fsck -fy "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		xfs:readonly) xfs_repair -n "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		xfs:repair) xfs_repair "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		ntfs:readonly) ntfsfix -n "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		ntfs:repair) ntfsfix "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
		vfat:readonly)
			case "$command_name" in
				fsck.vfat) fsck.vfat -n "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
				fsck.fat) fsck.fat -n "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
			esac
			;;
		vfat:repair)
			case "$command_name" in
				fsck.vfat) fsck.vfat -a "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
				fsck.fat) fsck.fat -a "$KPANEL_DISK_MANAGEMENT_DEVICE_PATH" >&2 ;;
			esac
			;;
	esac
	rc=$?
	if [ "$mode" = readonly ]; then
		if [ "$rc" -eq 0 ]; then
			kpanel_disk_management_reply unchanged "$device_id" "只读文件系统检查完成，未执行修复" "" 0
		else
			kpanel_disk_management_reply needs-attention "$device_id" "只读检查发现问题或检查工具未能完整执行" "" 3
		fi
		return $?
	fi
	case "$fstype:$rc" in
		ext4:0|ext4:1|ext4:2|ext4:3|vfat:0|vfat:1|xfs:0|ntfs:0)
			kpanel_disk_management_reply applied "$device_id" "文件系统修复命令已成功完成" "" 0
			;;
		*)
			kpanel_disk_management_reply failed "$device_id" "文件系统修复命令失败" "" 1
			;;
	esac
}

kpanel_disk_management_run_locked() (
	local action="$1"
	shift
	case "$action" in
		mount) kpanel_disk_management_mount_action "$@" ;;
		unmount) kpanel_disk_management_unmount_action "$@" ;;
		format) kpanel_disk_management_format_action "$@" ;;
		check) kpanel_disk_management_check_action "$@" ;;
		*) kpanel_disk_management_reply failed "" "不支持的 disk-management 动作" "" 2 ;;
	esac
)

kpanel_disk_management_dispatch() {
	local action="${1:-}" device_id="" lock_file rc
	shift || true
	[[ "${1:-}" =~ ^[0-9]+:[0-9]+$ ]] && device_id="$1"
	printf 'KPANEL_DISK_MANAGEMENT_PROTOCOL %s\n' "$KPANEL_DISK_MANAGEMENT_PROTOCOL_VERSION"
	kpanel_disk_management_require_platform
	rc=$?
	if [ "$rc" -ne 0 ]; then
		kpanel_disk_management_reply failed "" "$KPANEL_DISK_MANAGEMENT_REQUIRE_MESSAGE" "" "$rc"
		return $?
	fi
	case "$action" in
		mount|unmount)
			[ "$#" -eq 3 ] && [[ "$1" =~ ^[0-9]+:[0-9]+$ ]] &&
				[[ "$2" =~ ^[0-9a-fA-F]+$ ]] && [ "$(( ${#2} % 2 ))" -eq 0 ] &&
				[[ "$3" =~ ^[01]$ ]] || {
				kpanel_disk_management_reply failed "$device_id" "mount/unmount 参数无效" "" 2
				return $?
			}
			;;
		format)
			[ "$#" -eq 2 ] && [[ "$1" =~ ^[0-9]+:[0-9]+$ ]] && [[ "$2" =~ ^(ext4|xfs|ntfs|vfat)$ ]] || {
				kpanel_disk_management_reply failed "$device_id" "format 参数无效" "" 2
				return $?
			}
			;;
		check)
			[ "$#" -eq 2 ] && [[ "$1" =~ ^[0-9]+:[0-9]+$ ]] && [[ "$2" =~ ^(readonly|repair)$ ]] || {
				kpanel_disk_management_reply failed "$device_id" "check 参数无效" "" 2
				return $?
			}
			;;
		*)
			kpanel_disk_management_reply failed "$device_id" "用法: k kpanel disk-management <mount|unmount|format|check> ..." "" 2
			return $?
			;;
	esac
	lock_file="$(kpanel_disk_management_prepare_lock_file)" || {
		kpanel_disk_management_reply failed "$device_id" "disk-management 锁路径不安全或无法创建" "" 1
		return $?
	}
	exec 9<>"$lock_file" || {
		kpanel_disk_management_reply failed "$device_id" "无法打开 disk-management 锁" "" 1
		return $?
	}
	kpanel_disk_management_lock_file_secure "$lock_file" || {
		exec 9>&-
		kpanel_disk_management_reply failed "$device_id" "disk-management 锁文件打开后验证失败" "" 1
		return $?
	}
	if ! flock -w 5 -x 9 >/dev/null 2>&1; then
		exec 9>&-
		kpanel_disk_management_reply conflict "$device_id" "disk-management 写锁等待超时" "" 2
		return $?
	fi
	kpanel_disk_management_run_locked "$action" "$@"
}

# KPanel disk management protocol end


# KPanel network operations protocol start
KPANEL_NETWORK_OPERATIONS_PROTOCOL_VERSION="1"

kpanel_network_operations_script_file() {
	printf '%s\n' "/root/Limiting_Shut_down.sh"
}

kpanel_network_operations_net_dev_file() {
	printf '%s\n' "/proc/net/dev"
}

kpanel_network_operations_emit() {
	local status="$1"
	local version="${2:-}"
	local backup="${3:-}"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || version="$(kpanel_system_resource_zero_version)"
	printf 'KPANEL_NETWORK_OPERATIONS_STATUS=%s\n' "$status"
	printf 'KPANEL_NETWORK_OPERATIONS_VERSION=%s\n' "$version"
	[ -z "$backup" ] || printf 'KPANEL_NETWORK_OPERATIONS_BACKUP=%s\n' "$backup"
}

kpanel_network_operations_error() {
	printf '错误: %s\n' "$1" >&2
}

kpanel_network_operations_require() {
	local needs_root="$1"
	shift
	[ "${KJ_NETWORK_OPERATIONS_NONINTERACTIVE:-}" = "1" ] || {
		kpanel_network_operations_error "KPanel network-operations 协议环境未启用"
		kpanel_network_operations_emit failed
		return 2
	}
	[ "$(uname -s 2>/dev/null)" = "Linux" ] || {
		kpanel_network_operations_error "KPanel network-operations 协议仅支持 Linux"
		kpanel_network_operations_emit failed
		return 2
	}
	if [ "$needs_root" = true ] && [ "$(id -u)" -ne 0 ]; then
		kpanel_network_operations_error "限流关机管理必须以 root 运行"
		kpanel_network_operations_emit failed
		return 2
	fi
	for command_name in "$@"; do
		command -v "$command_name" >/dev/null 2>&1 || {
			kpanel_network_operations_error "缺少必要命令: $command_name"
			kpanel_network_operations_emit failed
			return 2
		}
	done
}

kpanel_network_operations_port_usage() {
	local temporary total truncated=false version line hex count=0
	kpanel_network_operations_require false ss awk wc sha256sum od tr mktemp || return $?
	[ "$#" -eq 0 ] || {
		kpanel_network_operations_error "port-usage list 不接受额外参数"
		kpanel_network_operations_emit failed
		return 2
	}
	temporary="$(mktemp /tmp/kejilion-network-ports.XXXXXX)" || {
		kpanel_network_operations_error "无法创建端口占用快照"
		kpanel_network_operations_emit failed
		return 1
	}
	if ! LC_ALL=C ss -H -lntup > "$temporary" 2>/dev/null; then
		rm -f -- "$temporary"
		kpanel_network_operations_error "无法读取监听端口"
		kpanel_network_operations_emit failed
		return 1
	fi
	if ! kpanel_system_resource_file_within_bounds "$temporary" 4194304 4096 ||
		! awk 'length($0) > 4096 { exit 1 }' "$temporary"; then
		rm -f -- "$temporary"
		kpanel_network_operations_error "端口占用结果超过协议上限"
		kpanel_network_operations_emit failed
		return 1
	fi
	total="$(awk 'END { print NR + 0 }' "$temporary")" || total=0
	[ "$total" -le 512 ] || truncated=true
	version="$(sha256sum -- "$temporary" 2>/dev/null | awk '{print $1}')"
	kpanel_network_operations_emit ok "$version"
	printf 'KPANEL_NETWORK_OPERATIONS_TOTAL=%s\n' "$total"
	printf 'KPANEL_NETWORK_OPERATIONS_TRUNCATED=%s\n' "$truncated"
	while IFS= read -r line && [ "$count" -lt 512 ]; do
		hex="$(printf '%s' "$line" | od -An -v -tx1 | tr -d ' \n')" || {
			rm -f -- "$temporary"
			return 1
		}
		printf 'KPANEL_NETWORK_OPERATIONS_PORT_HEX=%s\n' "$hex"
		count=$((count + 1))
	done < "$temporary"
	rm -f -- "$temporary"
}

kpanel_network_operations_traffic_bytes() {
	local path
	path="$(kpanel_network_operations_net_dev_file)"
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	awk '
		BEGIN { rx = 0; tx = 0 }
		$1 ~ /^(eth|ens|enp|eno)[0-9]+:/ { rx += $2; tx += $10 }
		END { printf "%.0f %.0f\n", rx, tx }
	' "$path"
}

kpanel_network_operations_script_safe() {
	local path="$1" uid expected_uid mode
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	kpanel_system_resource_file_within_bounds "$path" 65536 256 || return 1
	uid="$(stat -c '%u' "$path" 2>/dev/null)" || return 1
	expected_uid="$(kpanel_system_resource_lock_owner_uid)" || return 1
	[ "$uid" = "$expected_uid" ] || return 1
	mode="$(stat -c '%a' "$path" 2>/dev/null)" || return 1
	[[ "$mode" =~ ^[0-7]{3,4}$ ]] && [ "$((8#$mode & 0022))" -eq 0 ]
}

kpanel_network_operations_cron_relevant() {
	local source="$1"
	awk '
		$0 == "# kejilion traffic shutdown start" { managed = 1; print; next }
		managed { print; if ($0 == "# kejilion traffic shutdown end") managed = 0; next }
		$0 == "* * * * * ~/Limiting_Shut_down.sh" ||
		$0 == "* * * * * /root/Limiting_Shut_down.sh" { print }
	' "$source"
}

kpanel_network_operations_traffic_version() {
	local script_path cron_path canonical version
	script_path="$(kpanel_network_operations_script_file)"
	[ ! -L "$script_path" ] || return 1
	cron_path="$(mktemp /tmp/kejilion-network-traffic-cron.XXXXXX)" || return 1
	canonical="$(mktemp /tmp/kejilion-network-traffic-version.XXXXXX)" || {
		rm -f -- "$cron_path"
		return 1
	}
	if ! kpanel_system_resource_cron_capture "$cron_path"; then
		rm -f -- "$cron_path" "$canonical"
		return 1
	fi
	if [ -e "$script_path" ]; then
		kpanel_network_operations_script_safe "$script_path" || {
			rm -f -- "$cron_path" "$canonical"
			return 1
		}
		printf 'script=present\n' > "$canonical"
		sha256sum -- "$script_path" >> "$canonical" || {
			rm -f -- "$cron_path" "$canonical"
			return 1
		}
	else
		printf 'script=absent\n' > "$canonical"
	fi
	printf 'cron:\n' >> "$canonical"
	kpanel_network_operations_cron_relevant "$cron_path" >> "$canonical" || {
		rm -f -- "$cron_path" "$canonical"
		return 1
	}
	version="$(sha256sum -- "$canonical" 2>/dev/null | awk '{print $1}')"
	rm -f -- "$cron_path" "$canonical"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$version"
}

kpanel_network_operations_parse_script() {
	local path="$1" rx tx
	grep -Fqx '# KEJILION_TRAFFIC_SHUTDOWN_MANAGED_V1' "$path" || return 1
	rx="$(sed -n 's/^rx_threshold_gb=\([0-9][0-9]*\)$/\1/p' "$path")"
	tx="$(sed -n 's/^tx_threshold_gb=\([0-9][0-9]*\)$/\1/p' "$path")"
	[[ "$rx" =~ ^[0-9]+$ ]] && [[ "$tx" =~ ^[0-9]+$ ]] || return 1
	[ "$(printf '%s\n' "$rx" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$tx" | wc -l)" -eq 1 ] || return 1
	KPANEL_NETWORK_TRAFFIC_RX="$rx"
	KPANEL_NETWORK_TRAFFIC_TX="$tx"
}

kpanel_network_operations_traffic_status() {
	local script_path cron_path version bytes rx_bytes tx_bytes enabled=false health=disabled
	local rx_threshold=0 tx_threshold=0 reset_day=0 invocation_count reset_line_count start_count end_count expected_script
	kpanel_network_operations_require false awk crontab grep sed sha256sum stat wc mktemp cmp || return $?
	[ "$#" -eq 0 ] || {
		kpanel_network_operations_error "traffic-shutdown status 不接受额外参数"
		kpanel_network_operations_emit failed
		return 2
	}
	script_path="$(kpanel_network_operations_script_file)"
	cron_path="$(mktemp /tmp/kejilion-network-traffic-status.XXXXXX)" || {
		kpanel_network_operations_emit failed
		return 1
	}
	if ! kpanel_system_resource_cron_capture "$cron_path"; then
		rm -f -- "$cron_path"
		kpanel_network_operations_error "无法读取 root crontab"
		kpanel_network_operations_emit failed
		return 1
	fi
	version="$(kpanel_network_operations_traffic_version)" || {
		rm -f -- "$cron_path"
		kpanel_network_operations_error "限流关机配置不安全或无法计算版本"
		kpanel_network_operations_emit failed
		return 1
	}
	bytes="$(kpanel_network_operations_traffic_bytes)" || {
		rm -f -- "$cron_path"
		kpanel_network_operations_error "无法读取累计网络流量"
		kpanel_network_operations_emit failed "$version"
		return 1
	}
	read -r rx_bytes tx_bytes <<< "$bytes"
	if [ -e "$script_path" ]; then
		enabled=true
		if kpanel_network_operations_script_safe "$script_path" &&
			kpanel_network_operations_parse_script "$script_path"; then
			rx_threshold="$KPANEL_NETWORK_TRAFFIC_RX"
			tx_threshold="$KPANEL_NETWORK_TRAFFIC_TX"
			expected_script="$(mktemp /tmp/kejilion-network-traffic-expected.XXXXXX)" || {
				rm -f -- "$cron_path"
				kpanel_network_operations_emit failed "$version"
				return 1
			}
			if ! kpanel_network_operations_build_script "$expected_script" "$rx_threshold" "$tx_threshold" ||
				! cmp -s -- "$expected_script" "$script_path"; then
				rx_threshold=0
				tx_threshold=0
			fi
			rm -f -- "$expected_script"
		fi
	fi
	start_count="$(grep -Fxc '# kejilion traffic shutdown start' "$cron_path")"
	end_count="$(grep -Fxc '# kejilion traffic shutdown end' "$cron_path")"
	invocation_count="$(grep -Fxc "* * * * * $script_path" "$cron_path")"
	reset_line_count="$(sed -n '/^# kejilion traffic shutdown start$/,/^# kejilion traffic shutdown end$/p' "$cron_path" | grep -Ec '^0 1 ([1-9]|[12][0-9]|3[01]) \* \* reboot$')"
	if [ "$enabled" = true ] && [ "$rx_threshold" -gt 0 ] && [ "$tx_threshold" -gt 0 ] &&
		[ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [ "$invocation_count" -eq 1 ] && [ "$reset_line_count" -eq 1 ]; then
		reset_day="$(sed -n '/^# kejilion traffic shutdown start$/,/^# kejilion traffic shutdown end$/s/^0 1 \([0-9][0-9]*\) \* \* reboot$/\1/p' "$cron_path")"
		if [[ "$reset_day" =~ ^([1-9]|[12][0-9]|3[01])$ ]]; then
			health=ready
		else
			health=inconsistent
		fi
	elif [ "$enabled" = false ] && [ "$start_count" -eq 0 ] && [ "$end_count" -eq 0 ] && [ "$invocation_count" -eq 0 ]; then
		health=disabled
	else
		health=inconsistent
	fi
	rm -f -- "$cron_path"
	kpanel_network_operations_emit ok "$version"
	printf 'KPANEL_NETWORK_OPERATIONS_ENABLED=%s\n' "$enabled"
	printf 'KPANEL_NETWORK_OPERATIONS_HEALTH=%s\n' "$health"
	printf 'KPANEL_NETWORK_OPERATIONS_RX_BYTES=%s\n' "$rx_bytes"
	printf 'KPANEL_NETWORK_OPERATIONS_TX_BYTES=%s\n' "$tx_bytes"
	printf 'KPANEL_NETWORK_OPERATIONS_RX_THRESHOLD_GIB=%s\n' "$rx_threshold"
	printf 'KPANEL_NETWORK_OPERATIONS_TX_THRESHOLD_GIB=%s\n' "$tx_threshold"
	printf 'KPANEL_NETWORK_OPERATIONS_RESET_DAY=%s\n' "$reset_day"
}

kpanel_network_operations_valid_threshold() {
	[[ "$1" =~ ^[0-9]+$ ]] && [ "$1" != 0 ] && [ "$((10#$1))" -le 8388607 ]
}

kpanel_network_operations_build_script() {
	local target="$1" rx="$2" tx="$3"
	cat > "$target" <<EOF
#!/bin/bash
# KEJILION_TRAFFIC_SHUTDOWN_MANAGED_V1
set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
rx_threshold_gb=$rx
tx_threshold_gb=$tx
read -r rx_bytes tx_bytes <<TRAFFIC
\$(awk 'BEGIN { rx = 0; tx = 0 } \$1 ~ /^(eth|ens|enp|eno)[0-9]+:/ { rx += \$2; tx += \$10 } END { printf "%.0f %.0f\\n", rx, tx }' /proc/net/dev)
TRAFFIC
rx_threshold_bytes=\$((rx_threshold_gb * 1024 * 1024 * 1024))
tx_threshold_bytes=\$((tx_threshold_gb * 1024 * 1024 * 1024))
if [ "\$rx_bytes" -ge "\$rx_threshold_bytes" ] || [ "\$tx_bytes" -ge "\$tx_threshold_bytes" ]; then
	shutdown -h now
fi
EOF
}

kpanel_network_operations_build_cron() {
	local source="$1" target="$2" action="$3" script_path="$4" reset_day="$5"
	awk '
		$0 == "# kejilion traffic shutdown start" { managed = 1; next }
		managed && $0 == "# kejilion traffic shutdown end" { managed = 0; next }
		managed { next }
		$0 == "* * * * * ~/Limiting_Shut_down.sh" { next }
		$0 == "* * * * * /root/Limiting_Shut_down.sh" { next }
		{ print }
	' "$source" > "$target" || return 1
	if [ "$action" = enable ]; then
		{
			printf '%s\n' '# kejilion traffic shutdown start'
			printf '* * * * * %s\n' "$script_path"
			printf '0 1 %s * * reboot\n' "$reset_day"
			printf '%s\n' '# kejilion traffic shutdown end'
		} >> "$target" || return 1
	fi
	kpanel_system_resource_file_within_bounds "$target" 262144 512
}

kpanel_network_operations_restore_traffic() {
	local snapshot="$1" script_path="$2" script_existed="$3" cron_existed="$4" verify version="$5"
	if [ "$script_existed" = true ]; then
		cp -p -- "$snapshot/script" "$script_path" >/dev/null 2>&1 || return 1
	else
		rm -f -- "$script_path" >/dev/null 2>&1 || return 1
	fi
	verify="$snapshot/cron.verify"
	kpanel_system_resource_cron_restore "$snapshot/crontab" "$cron_existed" "$verify" || return 1
	[ "$(kpanel_network_operations_traffic_version 2>/dev/null)" = "$version" ]
}

kpanel_network_operations_traffic_failure() {
	local snapshot="$1" script_path="$2" script_existed="$3" cron_existed="$4" original_version="$5" message="$6"
	local version recovery_path
	kpanel_network_operations_error "$message"
	if kpanel_network_operations_restore_traffic "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$original_version"; then
		version="$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
		rm -rf -- "$snapshot"
		kpanel_network_operations_emit failed "$version"
		return 1
	else
		version="$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
		if recovery_path="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot" traffic-shutdown)"; then
			kpanel_network_operations_emit rollback-failed "$version" "$recovery_path"
		else
			kpanel_network_operations_emit rollback-failed "$version"
		fi
		return 1
	fi
}

kpanel_network_operations_traffic_action() {
	local action="$1" expected="${2:-}" rx="${3:-}" tx="${4:-}" reset_day="${5:-}"
	local script_path current_version snapshot cron_existed script_existed=false
	local desired_script desired_cron install_temp final_version
	case "$action" in
		enable)
			[ "$#" -eq 5 ] && kpanel_system_resource_valid_version "$expected" &&
				kpanel_network_operations_valid_threshold "$rx" &&
				kpanel_network_operations_valid_threshold "$tx" &&
				[[ "$reset_day" =~ ^([1-9]|[12][0-9]|3[01])$ ]] || {
				kpanel_network_operations_error "enable 需要 expectedVersion、正整数 GiB 阈值和 1-31 重置日"
				kpanel_network_operations_emit failed "$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
				return 2
			}
			;;
		disable)
			[ "$#" -eq 2 ] && kpanel_system_resource_valid_version "$expected" || {
				kpanel_network_operations_error "disable 只需要 expectedVersion"
				kpanel_network_operations_emit failed "$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
				return 2
			}
			;;
		*)
			kpanel_network_operations_error "不支持的 traffic-shutdown 动作"
			kpanel_network_operations_emit failed
			return 2
			;;
	esac
	script_path="$(kpanel_network_operations_script_file)"
	[ ! -L "$script_path" ] || {
		kpanel_network_operations_error "限流关机脚本不能是符号链接"
		kpanel_network_operations_emit failed
		return 1
	}
	current_version="$(kpanel_network_operations_traffic_version)" || {
		kpanel_network_operations_error "无法读取当前限流关机配置"
		kpanel_network_operations_emit failed
		return 1
	}
	if [ "$current_version" != "$expected" ]; then
		kpanel_network_operations_error "资源版本已变化，请刷新后重试"
		kpanel_network_operations_emit conflict "$current_version"
		return 2
	fi
	snapshot="$(kpanel_system_resource_tempdir traffic-shutdown)" || {
		kpanel_network_operations_emit failed "$current_version"
		return 1
	}
	if [ -e "$script_path" ]; then
		kpanel_network_operations_script_safe "$script_path" || {
			rm -rf -- "$snapshot"
			kpanel_network_operations_emit failed "$current_version"
			return 1
		}
		cp -p -- "$script_path" "$snapshot/script" || {
			rm -rf -- "$snapshot"
			kpanel_network_operations_emit failed "$current_version"
			return 1
		}
		script_existed=true
	fi
	kpanel_system_resource_cron_capture "$snapshot/crontab" || {
		rm -rf -- "$snapshot"
		kpanel_network_operations_emit failed "$current_version"
		return 1
	}
	cron_existed="$KPANEL_SYSTEM_RESOURCE_CRON_EXISTED"
	printf '%s\n' "$script_existed" > "$snapshot/script.existed"
	printf '%s\n' "$cron_existed" > "$snapshot/cron.existed"
	desired_script="$snapshot/script.desired"
	desired_cron="$snapshot/cron.desired"
	if [ "$action" = enable ]; then
		kpanel_network_operations_build_script "$desired_script" "$rx" "$tx" || {
			kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法生成限流关机脚本"
			return $?
		}
	fi
	kpanel_network_operations_build_cron "$snapshot/crontab" "$desired_cron" "$action" "$script_path" "$reset_day" || {
		kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法生成限流关机 crontab"
		return $?
	}
	if { [ "$action" = enable ] && [ "$script_existed" = true ] &&
		cmp -s -- "$desired_script" "$script_path" && cmp -s -- "$desired_cron" "$snapshot/crontab"; } ||
		{ [ "$action" = disable ] && [ "$script_existed" = false ] && cmp -s -- "$desired_cron" "$snapshot/crontab"; }; then
		rm -rf -- "$snapshot"
		kpanel_network_operations_emit unchanged "$current_version"
		return 0
	fi
	if [ "$action" = enable ]; then
		install_temp="$(mktemp "$(dirname -- "$script_path")/.Limiting_Shut_down.sh.XXXXXX")" || {
			kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法创建限流关机临时文件"
			return $?
		}
		if ! cp -- "$desired_script" "$install_temp" || ! chown 0:0 "$install_temp" 2>/dev/null ||
			! chmod 700 "$install_temp" || ! mv -f -- "$install_temp" "$script_path"; then
			rm -f -- "$install_temp"
			kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法原子安装限流关机脚本"
			return $?
		fi
	else
		rm -f -- "$script_path" || {
			kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法删除限流关机脚本"
			return $?
		}
	fi
	if ! crontab "$desired_cron"; then
		kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "无法安装限流关机 crontab"
		return $?
	fi
	final_version="$(kpanel_network_operations_traffic_version)" || {
		kpanel_network_operations_traffic_failure "$snapshot" "$script_path" "$script_existed" "$cron_existed" "$current_version" "限流关机配置回读失败"
		return $?
	}
	if [ "$final_version" = "$current_version" ]; then
		rm -rf -- "$snapshot"
		kpanel_network_operations_emit unchanged "$final_version"
	else
		rm -rf -- "$snapshot"
		kpanel_network_operations_emit applied "$final_version"
	fi
}

kpanel_network_operations_traffic_run_locked() (
	local action="$1" lock_file
	shift
	lock_file="$(kpanel_system_resource_prepare_lock_file)" || {
		kpanel_network_operations_error "network-operations 锁路径不安全或无法创建"
		kpanel_network_operations_emit failed "$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
		return 1
	}
	exec 9<>"$lock_file" || return 1
	kpanel_system_resource_lock_path_secure "$lock_file" file 600 || return 1
	if ! flock -w 5 -x 9 >/dev/null 2>&1; then
		kpanel_network_operations_error "network-operations 写锁等待超时"
		kpanel_network_operations_emit conflict "$(kpanel_network_operations_traffic_version 2>/dev/null || true)"
		return 2
	fi
	kpanel_network_operations_traffic_action "$action" "$@"
)

kpanel_network_operations_dispatch() {
	local resource="${1:-}" action="${2:-}"
	[ "$#" -ge 2 ] || {
		kpanel_network_operations_error "用法: kpanel network-operations <port-usage|traffic-shutdown> <action> ..."
		kpanel_network_operations_emit failed
		return 2
	}
	shift 2
	case "$resource:$action" in
		port-usage:list) kpanel_network_operations_port_usage "$@" ;;
		traffic-shutdown:status)
			kpanel_network_operations_traffic_status "$@"
			;;
		traffic-shutdown:enable|traffic-shutdown:disable)
			kpanel_network_operations_require true awk crontab grep sed sha256sum stat wc mktemp flock cmp cp mv chmod chown || return $?
			kpanel_network_operations_traffic_run_locked "$action" "$@"
			;;
		*)
			kpanel_network_operations_error "不支持的 network-operations 资源或动作"
			kpanel_network_operations_emit failed
			return 2
			;;
	esac
}

# KPanel network operations protocol end


# KPanel account management protocol start
KPANEL_ACCOUNT_MANAGEMENT_PROTOCOL_VERSION="1"

kpanel_account_error() {
	printf '%s\n' "$*" >&2
}

kpanel_account_emit() {
	local status="$1" version="${2:-}" backup="${3:-}"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_STATUS=%s\n' "$status"
	[ -z "$version" ] || printf 'KPANEL_ACCOUNT_MANAGEMENT_VERSION=%s\n' "$version"
	[ -z "$backup" ] || printf 'KPANEL_ACCOUNT_MANAGEMENT_BACKUP=%s\n' "$backup"
}

kpanel_account_root_path() {
	local path="$1"
	printf '%s%s\n' "${KPANEL_ACCOUNT_TEST_ROOT:-}" "$path"
}

kpanel_account_passwd_file() { kpanel_account_root_path /etc/passwd; }
kpanel_account_group_file() { kpanel_account_root_path /etc/group; }
kpanel_account_shadow_file() { kpanel_account_root_path /etc/shadow; }
kpanel_account_gshadow_file() { kpanel_account_root_path /etc/gshadow; }
kpanel_account_login_defs_file() { kpanel_account_root_path /etc/login.defs; }
kpanel_account_sudoers_file() { kpanel_account_root_path /etc/sudoers; }
kpanel_account_sudoers_dir() { kpanel_account_root_path /etc/sudoers.d; }
kpanel_account_sshd_config() { kpanel_account_root_path /etc/ssh/sshd_config; }
kpanel_account_sshd_fragment() { kpanel_account_root_path /etc/ssh/sshd_config.d/00-kejilion-account-management.conf; }

kpanel_account_host_path() {
	local path="$1"
	if [ -n "${KPANEL_ACCOUNT_TEST_ROOT:-}" ]; then
		printf '%s%s\n' "$KPANEL_ACCOUNT_TEST_ROOT" "$path"
	else
		printf '%s\n' "$path"
	fi
}

kpanel_account_valid_username() {
	[[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ "$1" != *'$' ]]
}

kpanel_account_require() {
	local write="$1" command
	shift
	[ "${KJ_ACCOUNT_MANAGEMENT_NONINTERACTIVE:-}" = "1" ] || {
		kpanel_account_error "KPanel account-management 协议环境未启用"
		return 2
	}
	[ "$EUID" -eq 0 ] || {
		kpanel_account_error "KPanel account-management 协议必须以 root 运行"
		return 1
	}
	[ "$(uname -s 2>/dev/null)" = Linux ] || {
		kpanel_account_error "KPanel account-management 协议仅支持 Linux"
		return 2
	}
	for command in "$@"; do
		command -v "$command" >/dev/null 2>&1 || {
			kpanel_account_error "缺少 account-management 依赖: $command"
			return 2
		}
	done
	if [ "$write" = true ]; then
		for command in flock cp mv chmod chown mktemp; do
			command -v "$command" >/dev/null 2>&1 || {
				kpanel_account_error "缺少 account-management 写入依赖: $command"
				return 2
			}
		done
	fi
}

kpanel_account_file_safe() {
	local path="$1" max_bytes="$2" max_lines="$3"
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	kpanel_system_resource_file_within_bounds "$path" "$max_bytes" "$max_lines"
}

kpanel_account_find_record() {
	local username="$1" passwd_file
	passwd_file="$(kpanel_account_passwd_file)"
	awk -F: -v username="$username" '$1 == username { print; found=1; exit } END { exit(found ? 0 : 1) }' "$passwd_file"
}

kpanel_account_exists() {
	kpanel_account_find_record "$1" >/dev/null 2>&1
}

kpanel_account_home() {
	local record
	record="$(kpanel_account_find_record "$1")" || return 1
	printf '%s\n' "$record" | awk -F: '{print $6}'
}

kpanel_account_authorized_keys() {
	local username="$1" home
	home="$(kpanel_account_home "$username")" || return 1
	[[ "$home" = /* ]] && [ "$home" != / ] || return 1
	printf '%s/.ssh/authorized_keys\n' "$(kpanel_account_host_path "$home")"
}

kpanel_account_capture_keys() {
	local username="$1" target="$2" path
	path="$(kpanel_account_authorized_keys "$username")" || return 1
	: > "$target" || return 1
	[ ! -e "$path" ] && return 0
	[ -f "$path" ] && [ ! -L "$path" ] || return 1
	if [ -n "${KPANEL_ACCOUNT_TEST_ROOT:-}" ]; then
		cat -- "$path" > "$target" || return 1
	else
		runuser -u "$username" -- cat -- "$path" > "$target" 2>/dev/null || return 1
	fi
	kpanel_system_resource_file_within_bounds "$target" 131072 128
}

kpanel_account_key_valid() {
	local key="$1" temporary LC_ALL=C
	[ -n "$key" ] && [ "${#key}" -le 4096 ] && [[ "$key" != *$'\n'* ]] && [[ "$key" != *$'\r'* ]] || return 1
	case "$key" in
		ssh-rsa\ *|ssh-ed25519\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
		*) return 1 ;;
	esac
	temporary="$(mktemp /tmp/kejilion-account-key.XXXXXX)" || return 1
	chmod 600 "$temporary" || { rm -f -- "$temporary"; return 1; }
	printf '%s\n' "$key" > "$temporary" || { rm -f -- "$temporary"; return 1; }
	ssh-keygen -lf "$temporary" >/dev/null 2>&1
	local result=$?
	rm -f -- "$temporary"
	return "$result"
}

kpanel_account_key_id() {
	printf '%s' "$1" | sha256sum | awk '{print $1}'
}

kpanel_account_install_keys() {
	local username="$1" desired="$2" path ssh_dir temp uid gid
	path="$(kpanel_account_authorized_keys "$username")" || return 1
	ssh_dir="$(dirname -- "$path")" || return 1
	[ ! -L "$ssh_dir" ] && [ ! -L "$path" ] || return 1
	uid="$(kpanel_account_find_record "$username" | awk -F: '{print $3}')" || return 1
	gid="$(kpanel_account_find_record "$username" | awk -F: '{print $4}')" || return 1
	if [ -n "${KPANEL_ACCOUNT_TEST_ROOT:-}" ]; then
		mkdir -p -- "$ssh_dir" || return 1
		chmod 700 "$ssh_dir" || return 1
		temp="$(mktemp "$ssh_dir/.authorized_keys.XXXXXX")" || return 1
		cp -- "$desired" "$temp" && chmod 600 "$temp" && mv -f -- "$temp" "$path" || { rm -f -- "$temp"; return 1; }
		return 0
	fi
	runuser -u "$username" -- mkdir -p -- "$ssh_dir" >/dev/null 2>&1 || return 1
	runuser -u "$username" -- chmod 700 "$ssh_dir" >/dev/null 2>&1 || return 1
	temp="$ssh_dir/.authorized_keys.kpanel.$$.$RANDOM"
	runuser -u "$username" -- tee "$temp" < "$desired" >/dev/null 2>&1 || return 1
	if ! runuser -u "$username" -- chmod 600 "$temp" >/dev/null 2>&1 ||
		! runuser -u "$username" -- mv -f -- "$temp" "$path" >/dev/null 2>&1; then
		runuser -u "$username" -- rm -f -- "$temp" >/dev/null 2>&1 || true
		return 1
	fi
	chown "$uid:$gid" "$ssh_dir" "$path" >/dev/null 2>&1 || return 1
}

kpanel_account_password_status() {
	local username="$1" status
	status="$(passwd -S "$username" 2>/dev/null | awk '{print $2}')" || return 1
	case "$status" in
		P) printf '%s\n' enabled ;;
		L|LK) printf '%s\n' locked ;;
		NP) printf '%s\n' unset ;;
		*) printf '%s\n' unknown ;;
	esac
}

kpanel_account_admin_group() {
	if getent group sudo >/dev/null 2>&1; then
		printf '%s\n' sudo
	elif getent group wheel >/dev/null 2>&1; then
		printf '%s\n' wheel
	else
		return 1
	fi
}

kpanel_account_sudo_file() {
	printf '%s/90-kejilion-%s\n' "$(kpanel_account_sudoers_dir)" "$1"
}

kpanel_account_role() {
	local username="$1" groups sudo_file
	[ "$username" = root ] && { printf '%s\n' root; return 0; }
	sudo_file="$(kpanel_account_sudo_file "$username")"
	if [ -f "$sudo_file" ] && [ ! -L "$sudo_file" ] &&
		grep -Fqx "$username ALL=(ALL:ALL) NOPASSWD:ALL" "$sudo_file"; then
		printf '%s\n' passwordless-admin
		return 0
	fi
	groups="$(id -nG "$username" 2>/dev/null)" || return 1
	case " $groups " in
		*' sudo '*|*' wheel '*) printf '%s\n' administrator ;;
		*) printf '%s\n' standard ;;
	esac
}

kpanel_account_sshd_effective() {
	local config password pubkey root
	config="$(kpanel_account_sshd_config)"
	[ -f "$config" ] && [ ! -L "$config" ] || return 1
	while read -r key value _; do
		case "$key" in
			passwordauthentication) password="$value" ;;
			pubkeyauthentication) pubkey="$value" ;;
			permitrootlogin) root="$value" ;;
		esac
	done < <(sshd -T -f "$config" 2>/dev/null)
	[ "$password" = yes ] || password=no
	[ "$pubkey" = yes ] || pubkey=no
	case "$root" in
		yes) root=enabled ;;
		prohibit-password|without-password) root=key-only ;;
		no) root=disabled ;;
		*) root=custom ;;
	esac
	printf '%s %s %s\n' "$password" "$pubkey" "$root"
}

kpanel_account_version() {
	local canonical file username auth sudo_file effective version
	canonical="$(mktemp /tmp/kejilion-account-version.XXXXXX)" || return 1
	chmod 600 "$canonical" || { rm -f -- "$canonical"; return 1; }
	for file in "$(kpanel_account_passwd_file)" "$(kpanel_account_group_file)" \
		"$(kpanel_account_shadow_file)" "$(kpanel_account_gshadow_file)" \
		"$(kpanel_account_sudoers_file)" "$(kpanel_account_sshd_config)" "$(kpanel_account_sshd_fragment)"; do
		if [ -e "$file" ]; then
			kpanel_account_file_safe "$file" 1048576 8192 || { rm -f -- "$canonical"; return 1; }
			printf 'file=%s ' "$file" >> "$canonical"
			sha256sum -- "$file" >> "$canonical" || { rm -f -- "$canonical"; return 1; }
		else
			printf 'file=%s absent\n' "$file" >> "$canonical"
		fi
	done
	effective="$(kpanel_account_sshd_effective)" || { rm -f -- "$canonical"; return 1; }
	printf 'sshd=%s\n' "$effective" >> "$canonical"
	while IFS=: read -r username _; do
		kpanel_account_valid_username "$username" || continue
		auth="$(mktemp /tmp/kejilion-account-auth.XXXXXX)" || { rm -f -- "$canonical"; return 1; }
		if kpanel_account_capture_keys "$username" "$auth"; then
			printf 'keys=%s ' "$username" >> "$canonical"
			sha256sum -- "$auth" | awk '{print $1}' >> "$canonical" || { rm -f -- "$canonical" "$auth"; return 1; }
		else
			printf 'keys=%s unreadable\n' "$username" >> "$canonical"
		fi
		rm -f -- "$auth"
		sudo_file="$(kpanel_account_sudo_file "$username")"
		if [ -e "$sudo_file" ]; then
			kpanel_account_file_safe "$sudo_file" 4096 16 || { rm -f -- "$canonical"; return 1; }
			printf 'sudo=%s ' "$username" >> "$canonical"
			sha256sum -- "$sudo_file" >> "$canonical" || { rm -f -- "$canonical"; return 1; }
		fi
	done < "$(kpanel_account_passwd_file)"
	version="$(sha256sum -- "$canonical" | awk '{print $1}')"
	rm -f -- "$canonical"
	[[ "$version" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$version"
}

kpanel_account_hex() {
	printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
}

kpanel_account_status() {
	local version effective password_auth pubkey_auth root_login passwd_file login_defs uid_min=1000
	local username _ uid gid gecos home shell groups password role kind account_record auth key key_id key_type fingerprint comment
	local total=0 emitted=0 truncated=false key_count key_temp
	kpanel_account_require false awk cat getent grep id mktemp od passwd runuser sha256sum ssh-keygen sshd stat tr wc || return $?
	[ "$#" -eq 0 ] || { kpanel_account_error "status 不接受额外参数"; kpanel_account_emit failed; return 2; }
	passwd_file="$(kpanel_account_passwd_file)"
	kpanel_account_file_safe "$passwd_file" 1048576 8192 || { kpanel_account_emit failed; return 1; }
	login_defs="$(kpanel_account_login_defs_file)"
	if [ -f "$login_defs" ] && [ ! -L "$login_defs" ]; then
		uid_min="$(awk '$1 == "UID_MIN" && $2 ~ /^[0-9]+$/ {print $2; exit}' "$login_defs")"
		[[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000
	fi
	version="$(kpanel_account_version)" || { kpanel_account_error "无法计算账户资源版本"; kpanel_account_emit failed; return 1; }
	effective="$(kpanel_account_sshd_effective)" || { kpanel_account_emit failed "$version"; return 1; }
	read -r password_auth pubkey_auth root_login <<< "$effective"
	while IFS=: read -r username _; do
		kpanel_account_valid_username "$username" || continue
		total=$((total + 1))
	done < "$passwd_file"
	[ "$total" -le 256 ] || truncated=true
	kpanel_account_emit ok "$version"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_PASSWORD_AUTH=%s\n' "$password_auth"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_PUBKEY_AUTH=%s\n' "$pubkey_auth"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_ROOT_LOGIN=%s\n' "$root_login"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_TOTAL=%s\n' "$total"
	printf 'KPANEL_ACCOUNT_MANAGEMENT_TRUNCATED=%s\n' "$truncated"
	while IFS=: read -r username _ uid gid gecos home shell; do
		[ "$emitted" -lt 256 ] || break
		kpanel_account_valid_username "$username" || continue
		groups="$(id -nG "$username" 2>/dev/null | tr ' ' ',')" || groups=""
		password="$(kpanel_account_password_status "$username")" || password=unknown
		role="$(kpanel_account_role "$username")" || role=standard
		if [ "$username" = root ]; then kind=root; elif [ "$uid" -ge "$uid_min" ] 2>/dev/null; then kind=human; else kind=system; fi
		key_temp="$(mktemp /tmp/kejilion-account-status-keys.XXXXXX)" || { kpanel_account_emit failed "$version"; return 1; }
		key_count=0
		if kpanel_account_capture_keys "$username" "$key_temp"; then
			while IFS= read -r key || [ -n "$key" ]; do
				[ -n "$key" ] || continue
				kpanel_account_key_valid "$key" || continue
				[ "$key_count" -lt 32 ] || break
				key_id="$(kpanel_account_key_id "$key")"
				key_type="${key%% *}"
				fingerprint="$(printf '%s\n' "$key" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')"
				comment="$(printf '%s\n' "$key" | awk '{ $1=""; $2=""; sub(/^  */, ""); print }' | tr '\t\r\n' '   ' | cut -c1-128)"
				printf 'KPANEL_ACCOUNT_MANAGEMENT_KEY_HEX=%s\n' "$(kpanel_account_hex "$username	$key_id	$key_type	$fingerprint	$comment")"
				key_count=$((key_count + 1))
			done < "$key_temp"
		fi
		rm -f -- "$key_temp"
		account_record="$username	$uid	$gid	$home	$shell	$kind	$password	$role	$groups	$key_count"
		printf 'KPANEL_ACCOUNT_MANAGEMENT_ACCOUNT_HEX=%s\n' "$(kpanel_account_hex "$account_record")"
		emitted=$((emitted + 1))
	done < "$passwd_file"
}

kpanel_account_read_secret() {
	local maximum="$1" frame bytes line_feeds
	KPANEL_ACCOUNT_SECRET=""
	frame="$(mktemp /tmp/kejilion-account-secret.XXXXXX)" || return 1
	chmod 600 "$frame" || { rm -f -- "$frame"; return 1; }
	head -c "$((maximum + 2))" > "$frame" 2>/dev/null || { rm -f -- "$frame"; return 1; }
	bytes="$(wc -c < "$frame")" || { rm -f -- "$frame"; return 1; }
	if [ "$bytes" -lt 2 ] || [ "$bytes" -gt "$((maximum + 1))" ] ||
		! LC_ALL=C tr -d '\000' < "$frame" | cmp -s - "$frame" || LC_ALL=C grep -q $'\r' "$frame"; then
		rm -f -- "$frame"; return 1
	fi
	line_feeds="$(LC_ALL=C tr -cd '\n' < "$frame" | wc -c)" || { rm -f -- "$frame"; return 1; }
	[ "$line_feeds" -eq 1 ] && [ "$(tail -c 1 "$frame" | wc -l)" -eq 1 ] || { rm -f -- "$frame"; return 1; }
	IFS= read -r KPANEL_ACCOUNT_SECRET < "$frame" || { rm -f -- "$frame"; return 1; }
	rm -f -- "$frame"
}

kpanel_account_snapshot_core() {
	local snapshot="$1" file name
	for name in passwd group shadow gshadow; do
		case "$name" in
			passwd) file="$(kpanel_account_passwd_file)" ;;
			group) file="$(kpanel_account_group_file)" ;;
			shadow) file="$(kpanel_account_shadow_file)" ;;
			gshadow) file="$(kpanel_account_gshadow_file)" ;;
		esac
		[ ! -e "$file" ] || cp -p -- "$file" "$snapshot/$name" || return 1
	done
}

kpanel_account_restore_core() {
	local snapshot="$1" file name
	for name in passwd group shadow gshadow; do
		[ -f "$snapshot/$name" ] || continue
		case "$name" in
			passwd) file="$(kpanel_account_passwd_file)" ;;
			group) file="$(kpanel_account_group_file)" ;;
			shadow) file="$(kpanel_account_shadow_file)" ;;
			gshadow) file="$(kpanel_account_gshadow_file)" ;;
		esac
		cp -p -- "$snapshot/$name" "$file" || return 1
	done
}

kpanel_account_snapshot_ssh() {
	local snapshot="$1" main fragment
	main="$(kpanel_account_sshd_config)"; fragment="$(kpanel_account_sshd_fragment)"
	[ ! -e "$main" ] || cp -p -- "$main" "$snapshot/sshd_config" || return 1
	if [ -e "$fragment" ]; then cp -p -- "$fragment" "$snapshot/sshd_fragment" || return 1; else : > "$snapshot/sshd_fragment.absent"; fi
}

kpanel_account_reload_ssh() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl reload sshd >/dev/null 2>&1 || systemctl reload ssh >/dev/null 2>&1
	elif command -v service >/dev/null 2>&1; then
		service sshd reload >/dev/null 2>&1 || service ssh reload >/dev/null 2>&1
	else
		return 1
	fi
}

kpanel_account_restore_ssh() {
	local snapshot="$1" main fragment
	main="$(kpanel_account_sshd_config)"; fragment="$(kpanel_account_sshd_fragment)"
	[ ! -f "$snapshot/sshd_config" ] || cp -p -- "$snapshot/sshd_config" "$main" || return 1
	if [ -f "$snapshot/sshd_fragment.absent" ]; then rm -f -- "$fragment" || return 1; else cp -p -- "$snapshot/sshd_fragment" "$fragment" || return 1; fi
	sshd -t -f "$main" >/dev/null 2>&1 && kpanel_account_reload_ssh
}

kpanel_account_apply_ssh_policy() {
	local password_auth="$1" root_login="$2" main fragment main_temp fragment_temp
	main="$(kpanel_account_sshd_config)"; fragment="$(kpanel_account_sshd_fragment)"
	[ -f "$main" ] && [ ! -L "$main" ] && [ ! -L "$fragment" ] || return 1
	mkdir -p -- "$(dirname -- "$fragment")" || return 1
	fragment_temp="$(mktemp "$(dirname -- "$fragment")/.00-kejilion-account-management.conf.XXXXXX")" || return 1
	{
		printf '%s\n' '# Managed by kejilion.sh account-management protocol v1'
		printf 'PubkeyAuthentication yes\n'
		[ "$password_auth" = enabled ] && printf 'PasswordAuthentication yes\n' || printf 'PasswordAuthentication no\n'
		printf 'KbdInteractiveAuthentication no\nChallengeResponseAuthentication no\nUsePAM yes\n'
		case "$root_login" in enabled) printf 'PermitRootLogin yes\n' ;; key-only) printf 'PermitRootLogin prohibit-password\n' ;; disabled) printf 'PermitRootLogin no\n' ;; *) rm -f -- "$fragment_temp"; return 1 ;; esac
	} > "$fragment_temp" || { rm -f -- "$fragment_temp"; return 1; }
	chmod 600 "$fragment_temp" && chown 0:0 "$fragment_temp" || { rm -f -- "$fragment_temp"; return 1; }
	main_temp="$(mktemp "$(dirname -- "$main")/.sshd_config.XXXXXX")" || { rm -f -- "$fragment_temp"; return 1; }
	awk '
		BEGIN { inserted=0 }
		/^[[:space:]]*Include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf([[:space:]]|$)/ { if (!inserted) { print "Include /etc/ssh/sshd_config.d/*.conf"; inserted=1 }; next }
		{ if (!inserted && $0 !~ /^[[:space:]]*(#|$)/) { print "Include /etc/ssh/sshd_config.d/*.conf"; inserted=1 }; print }
		END { if (!inserted) print "Include /etc/ssh/sshd_config.d/*.conf" }
	' "$main" > "$main_temp" || { rm -f -- "$fragment_temp" "$main_temp"; return 1; }
	chmod --reference="$main" "$main_temp" 2>/dev/null || chmod 600 "$main_temp"
	chown --reference="$main" "$main_temp" 2>/dev/null || chown 0:0 "$main_temp"
	mv -f -- "$fragment_temp" "$fragment" && mv -f -- "$main_temp" "$main" || { rm -f -- "$fragment_temp" "$main_temp"; return 1; }
	sshd -t -f "$main" >/dev/null 2>&1 && kpanel_account_reload_ssh
}

kpanel_account_set_role() {
	local username="$1" role="$2" admin_group sudo_file sudo_dir groups
	[ "$username" != root ] || return 1
	sudo_file="$(kpanel_account_sudo_file "$username")"; sudo_dir="$(dirname -- "$sudo_file")"
	[ ! -L "$sudo_dir" ] && [ ! -L "$sudo_file" ] || return 1
	mkdir -p -- "$sudo_dir" || return 1
	case "$role" in
		standard)
			gpasswd -d "$username" sudo >/dev/null 2>&1 || true
			gpasswd -d "$username" wheel >/dev/null 2>&1 || true
			rm -f -- "$sudo_file" || return 1
			;;
		administrator)
			admin_group="$(kpanel_account_admin_group)" || return 1
			[ "$(kpanel_account_password_status "$username")" = enabled ] || return 2
			usermod -a -G "$admin_group" "$username" || return 1
			rm -f -- "$sudo_file" || return 1
			;;
		passwordless-admin)
			admin_group="$(kpanel_account_admin_group)" || return 1
			usermod -a -G "$admin_group" "$username" || return 1
			printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$username" > "$sudo_file" || return 1
			chmod 440 "$sudo_file" && chown 0:0 "$sudo_file" || return 1
			visudo -cf "$sudo_file" >/dev/null 2>&1 || return 1
			;;
		*) return 2 ;;
	esac
	[ "$(kpanel_account_role "$username")" = "$role" ]
}

kpanel_account_create() {
	local username="$1" role="$2" credential="$3" secret="$4"
	local desired sudo_file LC_ALL=C
	kpanel_account_valid_username "$username" && [ "$username" != root ] && ! kpanel_account_exists "$username" || return 2
	case "$role" in standard|administrator|passwordless-admin) ;; *) return 2 ;; esac
	case "$credential" in
		password) [ "${#secret}" -ge 8 ] && [ "${#secret}" -le 256 ] || return 2 ;;
		key) kpanel_account_key_valid "$secret" || return 2; [ "$role" != administrator ] || return 2 ;;
		*) return 2 ;;
	esac
	useradd -m -s /bin/bash "$username" || return 1
	if [ "$credential" = password ]; then
		if ! printf '%s:%s\n' "$username" "$secret" | chpasswd; then
			userdel -r "$username" >/dev/null 2>&1 || true
			return 1
		fi
	else
		desired="$(mktemp /tmp/kejilion-account-create-key.XXXXXX)" || {
			userdel -r "$username" >/dev/null 2>&1 || true
			return 1
		}
		printf '%s\n' "$secret" > "$desired"
		if ! kpanel_account_install_keys "$username" "$desired"; then
			rm -f -- "$desired"
			userdel -r "$username" >/dev/null 2>&1 || true
			return 1
		fi
		rm -f -- "$desired"
		if ! passwd -l "$username" >/dev/null 2>&1; then
			userdel -r "$username" >/dev/null 2>&1 || true
			return 1
		fi
	fi
	if ! kpanel_account_set_role "$username" "$role"; then
		sudo_file="$(kpanel_account_sudo_file "$username")"
		rm -f -- "$sudo_file" >/dev/null 2>&1 || true
		userdel -r "$username" >/dev/null 2>&1 || true
		return 1
	fi
}

kpanel_account_write_failure() {
	local snapshot="$1" original_version="$2" message="$3" restore_core="${4:-false}" restore_ssh="${5:-false}"
	local version recovery restore_ok=true
	kpanel_account_error "$message"
	[ "$restore_core" != true ] || kpanel_account_restore_core "$snapshot" || restore_ok=false
	[ "$restore_ssh" != true ] || kpanel_account_restore_ssh "$snapshot" || restore_ok=false
	version="$(kpanel_account_version 2>/dev/null || true)"
	if [ "$restore_ok" = true ] && [ "$version" = "$original_version" ]; then
		rm -rf -- "$snapshot"
		kpanel_account_emit failed "$version"
		return 1
	fi
	if recovery="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot" account-management)"; then
		kpanel_account_emit rollback-failed "$version" "$recovery"
	else
		kpanel_account_emit rollback-failed "$version"
	fi
	return 1
}

kpanel_account_action() {
	local action="$1" expected="$2" current snapshot final recovery username role credential marker secret="" changed=true
	local LC_ALL=C
	shift 2
	kpanel_system_resource_valid_version "$expected" || { kpanel_account_emit failed; return 2; }
	current="$(kpanel_account_version)" || { kpanel_account_emit failed; return 1; }
	if [ "$current" != "$expected" ]; then kpanel_account_emit conflict "$current"; return 2; fi
	snapshot="$(kpanel_system_resource_tempdir account-management)" || { kpanel_account_emit failed "$current"; return 1; }
	case "$action" in
		create)
			[ "$#" -eq 4 ] && [ "$4" = --secret-stdin ] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; role="$2"; credential="$3"
			[ "$credential" = password ] && marker=256 || marker=4096
			kpanel_account_read_secret "$marker" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			secret="$KPANEL_ACCOUNT_SECRET"
			kpanel_account_snapshot_core "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if ! kpanel_account_create "$username" "$role" "$credential" "$secret"; then kpanel_account_write_failure "$snapshot" "$current" "创建账户失败，已尝试恢复账户数据库" true false; return $?; fi
			;;
		set-password)
			[ "$#" -eq 2 ] && [ "$2" = --secret-stdin ] && kpanel_account_exists "$1" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; kpanel_account_read_secret 256 || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			[ "${#KPANEL_ACCOUNT_SECRET}" -ge 8 ] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			kpanel_account_snapshot_core "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if ! printf '%s:%s\n' "$username" "$KPANEL_ACCOUNT_SECRET" | chpasswd; then kpanel_account_write_failure "$snapshot" "$current" "修改密码失败，已尝试恢复" true false; return $?; fi
			;;
		add-key)
			[ "$#" -eq 2 ] && [ "$2" = --secret-stdin ] && kpanel_account_exists "$1" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; kpanel_account_read_secret 4096 || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }; secret="$KPANEL_ACCOUNT_SECRET"
			kpanel_account_key_valid "$secret" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			local keys desired
			keys="$snapshot/authorized_keys"; desired="$snapshot/authorized_keys.desired"
			kpanel_account_capture_keys "$username" "$keys" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if grep -Fqx "$secret" "$keys"; then rm -rf -- "$snapshot"; kpanel_account_emit unchanged "$current"; return 0; fi
			cp -- "$keys" "$desired" && printf '%s\n' "$secret" >> "$desired" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if ! kpanel_account_install_keys "$username" "$desired"; then
				kpanel_account_install_keys "$username" "$keys" >/dev/null 2>&1 || true
				kpanel_account_write_failure "$snapshot" "$current" "添加 SSH 公钥失败，已尝试恢复" false false
				return $?
			fi
			;;
		delete-key)
			[ "$#" -eq 2 ] && kpanel_account_exists "$1" && [[ "$2" =~ ^[0-9a-f]{64}$ ]] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; local key_id="$2" keys="$snapshot/authorized_keys" desired="$snapshot/authorized_keys.desired" line found=false
			kpanel_account_capture_keys "$username" "$keys" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			: > "$desired"
			while IFS= read -r line || [ -n "$line" ]; do if [ -n "$line" ] && [ "$(kpanel_account_key_id "$line")" = "$key_id" ]; then found=true; else printf '%s\n' "$line" >> "$desired"; fi; done < "$keys"
			if [ "$found" = false ]; then rm -rf -- "$snapshot"; kpanel_account_emit unchanged "$current"; return 0; fi
			if ! kpanel_account_install_keys "$username" "$desired"; then
				kpanel_account_install_keys "$username" "$keys" >/dev/null 2>&1 || true
				kpanel_account_write_failure "$snapshot" "$current" "删除 SSH 公钥失败，已尝试恢复" false false
				return $?
			fi
			;;
		set-role)
			[ "$#" -eq 2 ] && kpanel_account_exists "$1" && [ "$1" != root ] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; role="$2"; [ "$(kpanel_account_role "$username")" != "$role" ] || { rm -rf -- "$snapshot"; kpanel_account_emit unchanged "$current"; return 0; }
			kpanel_account_snapshot_core "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			local sudo_file; sudo_file="$(kpanel_account_sudo_file "$username")"; if [ -e "$sudo_file" ]; then cp -p -- "$sudo_file" "$snapshot/sudo" || { rm -rf -- "$snapshot"; return 1; }; else : > "$snapshot/sudo.absent"; fi
			if ! kpanel_account_set_role "$username" "$role"; then
				if [ -f "$snapshot/sudo.absent" ]; then rm -f -- "$sudo_file" >/dev/null 2>&1 || true; else cp -p -- "$snapshot/sudo" "$sudo_file" >/dev/null 2>&1 || true; fi
				kpanel_account_write_failure "$snapshot" "$current" "调整账户角色失败，已尝试恢复" true false
				return $?
			fi
			;;
		set-ssh-policy)
			[ "$#" -eq 2 ] && [[ "$1" =~ ^(enabled|disabled)$ ]] && [[ "$2" =~ ^(enabled|key-only|disabled)$ ]] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			kpanel_account_snapshot_ssh "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if ! kpanel_account_apply_ssh_policy "$1" "$2"; then kpanel_account_write_failure "$snapshot" "$current" "SSH 登录策略应用失败，已尝试恢复" false true; return $?; fi
			;;
		disable-root)
			[ "$#" -eq 0 ] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			if [ "$(kpanel_account_password_status root)" = locked ] && [ "$(kpanel_account_sshd_effective | awk '{print $3}')" = disabled ]; then rm -rf -- "$snapshot"; kpanel_account_emit unchanged "$current"; return 0; fi
			kpanel_account_snapshot_core "$snapshot" && kpanel_account_snapshot_ssh "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if ! passwd -l root >/dev/null 2>&1 || ! kpanel_account_apply_ssh_policy "$(kpanel_account_sshd_effective | awk '{print $1 == "yes" ? "enabled" : "disabled"}')" disabled; then kpanel_account_write_failure "$snapshot" "$current" "禁用 Root 失败，已尝试恢复" true true; return $?; fi
			;;
		create-admin-disable-root)
			[ "$#" -eq 3 ] && [ "$3" = --secret-stdin ] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; credential="$2"; [ "$credential" = password ] && marker=256 || marker=4096
			kpanel_account_read_secret "$marker" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }; secret="$KPANEL_ACCOUNT_SECRET"
			kpanel_account_snapshot_core "$snapshot" && kpanel_account_snapshot_ssh "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			role=administrator; [ "$credential" = key ] && role=passwordless-admin
			if ! kpanel_account_create "$username" "$role" "$credential" "$secret"; then
				kpanel_account_write_failure "$snapshot" "$current" "替代管理员创建失败，已尝试恢复" true true
				return $?
			fi
			if ! passwd -l root >/dev/null 2>&1 ||
				! kpanel_account_apply_ssh_policy "$([ "$credential" = password ] && printf enabled || printf disabled)" disabled; then
				rm -f -- "$(kpanel_account_sudo_file "$username")" >/dev/null 2>&1 || true
				userdel -r "$username" >/dev/null 2>&1 || true
				kpanel_account_write_failure "$snapshot" "$current" "Root 安全迁移失败，已尝试恢复" true true
				return $?
			fi
			;;
		delete)
			[ "$#" -eq 2 ] && kpanel_account_valid_username "$1" && [ "$1" != root ] && [[ "$2" =~ ^(true|false)$ ]] || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2; }
			username="$1"; if ! kpanel_account_exists "$username"; then rm -rf -- "$snapshot"; kpanel_account_emit unchanged "$current"; return 0; fi
			local sudo_file; sudo_file="$(kpanel_account_sudo_file "$username")"
			kpanel_account_snapshot_core "$snapshot" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }
			if [ -e "$sudo_file" ]; then cp -p -- "$sudo_file" "$snapshot/sudo" || { rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 1; }; else : > "$snapshot/sudo.absent"; fi
			if ! { if [ "$2" = true ]; then userdel -r "$username"; else userdel "$username"; fi; }; then
				if [ "$2" = false ]; then
					kpanel_account_write_failure "$snapshot" "$current" "删除账户失败，已尝试恢复账户数据库" true false
					return $?
				fi
				kpanel_account_restore_core "$snapshot" >/dev/null 2>&1 || true
				final="$(kpanel_account_version 2>/dev/null || true)"
				recovery="$(kpanel_system_resource_persist_recovery_snapshot "$snapshot" account-management 2>/dev/null || true)"
				kpanel_account_error "删除账户及主目录失败，主目录可能已被部分删除，需要人工检查"
				kpanel_account_emit needs-attention "$final" "$recovery"
				return 1
			fi
			rm -f -- "$sudo_file" || { rm -rf -- "$snapshot"; kpanel_account_emit needs-attention "$(kpanel_account_version 2>/dev/null || true)"; return 1; }
			;;
		*) rm -rf -- "$snapshot"; kpanel_account_emit failed "$current"; return 2 ;;
	esac
	final="$(kpanel_account_version)" || { rm -rf -- "$snapshot"; kpanel_account_emit needs-attention; return 1; }
	[ "$final" != "$current" ] || changed=false
	rm -rf -- "$snapshot"
	[ "$changed" = true ] && kpanel_account_emit applied "$final" || kpanel_account_emit unchanged "$final"
}

kpanel_account_run_locked() (
	local action="$1" expected="$2" lock_file
	shift 2
	lock_file="$(kpanel_system_resource_prepare_lock_file)" || { kpanel_account_emit failed; return 1; }
	exec 9<>"$lock_file" || { kpanel_account_emit failed; return 1; }
	kpanel_system_resource_lock_path_secure "$lock_file" file 600 || { kpanel_account_emit failed; return 1; }
	if ! flock -w 5 -x 9 >/dev/null 2>&1; then kpanel_account_emit conflict "$(kpanel_account_version 2>/dev/null || true)"; return 2; fi
	kpanel_account_action "$action" "$expected" "$@"
)

kpanel_account_dispatch() {
	local action="${1:-}"
	[ "$#" -ge 1 ] || { kpanel_account_emit failed; return 2; }
	shift
	case "$action" in
		status) kpanel_account_status "$@" ;;
		create|set-password|add-key|delete-key|set-role|set-ssh-policy|disable-root|create-admin-disable-root|delete)
			[ "$#" -ge 1 ] || { kpanel_account_emit failed; return 2; }
			local expected="$1"; shift
			kpanel_account_require true awk cat chpasswd cmp cut getent gpasswd grep head id mkdir mktemp od passwd runuser sed sha256sum ssh-keygen sshd stat tail tr useradd userdel usermod visudo wc || { kpanel_account_emit failed; return $?; }
			kpanel_account_run_locked "$action" "$expected" "$@"
			;;
		*) kpanel_account_error "不支持的 account-management 动作"; kpanel_account_emit failed; return 2 ;;
	esac
}

# KPanel account management protocol end


log_menu() {

	show_log_overview() {
		echo "============= 系统日志概览 ============="
		echo "主机名: $(hostname)"
		echo "系统时间: $(date)"
		echo
		echo "[ /var/log 目录占用 ]"
		du -sh /var/log 2>/dev/null
		echo
		echo "[ journal 日志占用 ]"
		journalctl --disk-usage 2>/dev/null
		echo "========================================"
	}

	while true; do
		clear
		show_log_overview
		echo
		echo "=========== 系统日志管理菜单 ==========="
		echo "1. 查看最近系统日志（journal）"
		echo "2. 查看指定服务日志"
		echo "3. 查看登录/安全日志"
		echo "4. 实时跟踪日志"
		echo "5. 清理旧 journal 日志"
		echo "0. 返回上一级选单"
		echo "======================================="
		read -erp "请选择操作: " choice

		case $choice in
			1)
				read -erp "查看最近多少行日志？[默认 100]: " lines
				lines=${lines:-100}
				journalctl -n "$lines" --no-pager
				read -erp "按回车继续..."
				;;
			2)
				read -erp "请输入服务名（如 sshd、nginx）: " svc
				if systemctl list-unit-files | grep -q "^$svc"; then
					journalctl -u "$svc" -n 100 --no-pager
				else
					echo "✘ 服务不存在或无日志"
				fi
				read -erp "按回车继续..."
				;;
			3)
				echo "====== 最近登录日志 ======"
				last -n 10
				echo
				echo "====== 认证日志 ======"
				if [ -f /var/log/secure ]; then
					tail -n 20 /var/log/secure
				elif [ -f /var/log/auth.log ]; then
					tail -n 20 /var/log/auth.log
				else
					echo "未找到安全日志文件"
				fi
				read -erp "按回车继续..."
				;;
			4)
				echo "1) 系统日志"
				echo "2) 指定服务日志"
				read -erp "选择跟踪类型: " t
				if [ "$t" = "1" ]; then
					journalctl -f
				elif [ "$t" = "2" ]; then
					read -erp "输入服务名: " svc
					journalctl -u "$svc" -f
				else
					echo "无效选择"
				fi
				;;
			5)
				echo "⚠️ 清理 journal 日志（安全方式）"
				echo "1) 保留最近 7 天"
				echo "2) 保留最近 3 天"
				echo "3) 限制日志最大 500M"
				read -erp "请选择清理方式: " c
				case $c in
					1) journalctl --vacuum-time=7d ;;
					2) journalctl --vacuum-time=3d ;;
					3) journalctl --vacuum-size=500M ;;
					*) echo "无效选项" ;;
				esac
				echo "✔ journal 日志清理完成"
				sleep 2
				;;
			*)
				break
				;;
		esac
	done
}



env_menu() {

	BASHRC="$HOME/.bashrc"
	PROFILE="$HOME/.profile"


	show_env_vars() {
		clear
		echo "========== 当前已生效环境变量（节选） =========="
		printf "%-20s %s\n" "变量名" "值"
		echo "-----------------------------------------------"
		for v in USER HOME SHELL LANG PWD; do
			printf "%-20s %s\n" "$v" "${!v}"
		done

		echo
		echo "PATH:"
		echo "$PATH" | tr ':' '\n' | nl -ba

		echo
		echo "========== 配置文件中定义的变量（解析） =========="

		parse_file_vars() {
			local file="$1"
			[ -f "$file" ] || return

			echo
			echo ">>> 来源文件：$file"
			echo "-----------------------------------------------"

			# 提取 export VAR=xxx 或 VAR=xxx
			grep -Ev '^\s*#|^\s*$' "$file" \
			| grep -E '^(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' \
			| while read -r line; do
				var=$(echo "$line" | sed -E 's/^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\2/')
				val=$(echo "$line" | sed -E 's/^[^=]+=//')
				printf "%-20s %s\n" "$var" "$val"
			done
		}

		parse_file_vars "$HOME/.bashrc"
		parse_file_vars "$HOME/.profile"

		echo
		echo "==============================================="
		read -erp "按回车继续..."
	}


	view_file() {
		local file="$1"
		clear
		if [ -f "$file" ]; then
			echo "========== 查看文件：$file =========="
			cat -n "$file"
			echo "===================================="
		else
			echo "文件不存在：$file"
		fi
		read -erp "按回车继续..."
	}

	edit_file() {
		local file="$1"
		install nano
		nano "$file"
	}

	source_files() {
		echo "正在重新加载环境变量..."
		source "$BASHRC"
		source "$PROFILE"
		echo "✔ 环境变量已重新加载"
		read -erp "按回车继续..."
	}

	while true; do
		clear
		echo "=========== 系统环境变量管理 =========="
		echo "当前用户：$USER"
		echo "--------------------------------------"
		echo "1. 查看当前常用环境变量"
		echo "2. 查看 ~/.bashrc"
		echo "3. 查看 ~/.profile"
		echo "4. 编辑 ~/.bashrc"
		echo "5. 编辑 ~/.profile"
		echo "6. 重新加载环境变量（source）"
		echo "--------------------------------------"
		echo "0. 返回上一级选单"
		echo "--------------------------------------"
		read -erp "请选择操作: " choice

		case "$choice" in
			1)
				show_env_vars
				;;
			2)
				view_file "$BASHRC"
				;;
			3)
				view_file "$PROFILE"
				;;
			4)
				edit_file "$BASHRC"
				;;
			5)
				edit_file "$PROFILE"
				;;
			6)
				source_files
				;;
			0)
				break
				;;
			*)
				echo "无效选项"
				sleep 1
				;;
		esac
	done
}


create_user_with_sshkey() {
	local new_username="$1"
	local is_sudo="${2:-false}"
	local sshkey_vl

	if [[ -z "$new_username" ]]; then
		echo "用法：create_user_with_sshkey <用户名>"
		return 1
	fi

	# 创建用户
	useradd -m -s /bin/bash "$new_username" || return 1

	echo "导入公钥范例："
	echo "  - URL：      ${gh_https_url}github.com/torvalds.keys"
	echo "  - 直接粘贴： ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
	read -e -p "请导入 ${new_username} 的公钥: " sshkey_vl

	case "$sshkey_vl" in
		http://*|https://*)
			fetch_remote_ssh_keys "$sshkey_vl" "/home/$new_username"
			;;
		ssh-rsa*|ssh-ed25519*|ssh-ecdsa*)
			import_sshkey "$sshkey_vl" "/home/$new_username"
			;;
		*)
			echo "错误：未知参数 '$sshkey_vl'"
			return 1
			;;
	esac


	# 修正权限
	chown -R "$new_username:$new_username" "/home/$new_username/.ssh"

	install sudo

	# sudo 免密
	if [[ "$is_sudo" == "true" ]]; then
		cat >"/etc/sudoers.d/$new_username" <<EOF
$new_username ALL=(ALL) NOPASSWD:ALL
EOF
		chmod 440 "/etc/sudoers.d/$new_username"
	fi

	sed -i '/^\s*#\?\s*UsePAM\s\+/d' /etc/ssh/sshd_config
	echo 'UsePAM yes' >> /etc/ssh/sshd_config
	passwd -l "$new_username" &>/dev/null
	restart_ssh

	echo "用户 $new_username 创建完成"
}















linux_Settings() {

	while true; do
	  clear
	  echo -e "系统工具"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}1.   ${gl_bai}设置脚本启动快捷键                 ${gl_kjlan}2.   ${gl_bai}修改登录密码"
	  echo -e "${gl_kjlan}3.   ${gl_bai}用户密码登录模式                   ${gl_kjlan}4.   ${gl_bai}安装Python指定版本"
	  echo -e "${gl_kjlan}5.   ${gl_bai}开放所有端口                       ${gl_kjlan}6.   ${gl_bai}修改SSH连接端口"
	  echo -e "${gl_kjlan}7.   ${gl_bai}优化DNS地址                        ${gl_kjlan}8.   ${gl_bai}一键重装系统 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}9.   ${gl_bai}禁用ROOT账户创建新账户             ${gl_kjlan}10.  ${gl_bai}切换优先ipv4/ipv6"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}11.  ${gl_bai}查看端口占用状态                   ${gl_kjlan}12.  ${gl_bai}修改虚拟内存大小"
	  echo -e "${gl_kjlan}13.  ${gl_bai}用户管理                           ${gl_kjlan}14.  ${gl_bai}用户/密码生成器"
	  echo -e "${gl_kjlan}15.  ${gl_bai}系统时区调整                       ${gl_kjlan}16.  ${gl_bai}设置BBR3加速"
	  echo -e "${gl_kjlan}17.  ${gl_bai}防火墙高级管理器                   ${gl_kjlan}18.  ${gl_bai}修改主机名"
	  echo -e "${gl_kjlan}19.  ${gl_bai}切换系统更新源                     ${gl_kjlan}20.  ${gl_bai}定时任务管理"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}21.  ${gl_bai}本机host解析                       ${gl_kjlan}22.  ${gl_bai}SSH防御程序"
	  echo -e "${gl_kjlan}23.  ${gl_bai}限流自动关机                       ${gl_kjlan}24.  ${gl_bai}用户密钥登录模式"
	  echo -e "${gl_kjlan}25.  ${gl_bai}TG-bot系统监控预警                 ${gl_kjlan}26.  ${gl_bai}修复OpenSSH高危漏洞"
	  echo -e "${gl_kjlan}27.  ${gl_bai}红帽系Linux内核升级                ${gl_kjlan}28.  ${gl_bai}Linux系统内核参数优化 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}29.  ${gl_bai}病毒扫描工具 ${gl_huang}★${gl_bai}                     ${gl_kjlan}30.  ${gl_bai}文件管理器"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}31.  ${gl_bai}切换系统语言                       ${gl_kjlan}32.  ${gl_bai}命令行美化工具 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}33.  ${gl_bai}设置系统回收站                     ${gl_kjlan}34.  ${gl_bai}系统备份与恢复"
	  echo -e "${gl_kjlan}35.  ${gl_bai}ssh远程连接工具                    ${gl_kjlan}36.  ${gl_bai}硬盘分区管理工具"
	  echo -e "${gl_kjlan}37.  ${gl_bai}命令行历史记录                     ${gl_kjlan}38.  ${gl_bai}rsync远程同步工具"
	  echo -e "${gl_kjlan}39.  ${gl_bai}命令收藏夹 ${gl_huang}★${gl_bai}                       ${gl_kjlan}40.  ${gl_bai}网卡管理工具"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}41.  ${gl_bai}系统日志管理工具 ${gl_huang}★${gl_bai}                 ${gl_kjlan}42.  ${gl_bai}系统变量管理工具"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}66.  ${gl_bai}一条龙系统调优 ${gl_huang}★${gl_bai}"
	  echo -e "${gl_kjlan}99.  ${gl_bai}重启服务器"
	  echo -e "${gl_kjlan}101. ${gl_bai}k命令高级用法 ${gl_huang}★${gl_bai}                    ${gl_kjlan}102. ${gl_bai}卸载科技lion脚本"
	  echo -e "${gl_kjlan}------------------------"
	  echo -e "${gl_kjlan}0.   ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in
		  1)
			  while true; do
				  clear
				  read -e -p "请输入你的快捷按键（输入0退出）: " kuaijiejian
				  if [ "$kuaijiejian" == "0" ]; then
					   break_end
					   linux_Settings
				  fi
				  find /usr/local/bin/ -type l -exec bash -c 'test "$(readlink -f {})" = "/usr/local/bin/k" && rm -f {}' \;
				  if [ "$kuaijiejian" != "k" ]; then
					  ln -sf /usr/local/bin/k /usr/local/bin/$kuaijiejian
				  fi
				  ln -sf /usr/local/bin/k /usr/bin/$kuaijiejian > /dev/null 2>&1
				  echo "快捷键已设置"
				  break_end
				  linux_Settings
			  done
			  ;;

		  2)
			  clear
			  echo "设置你的登录密码"
			  passwd
			  ;;
		  3)
			  clear
			  add_sshpasswd
			  ;;

		  4)
			root_use
			echo "python版本管理"
			echo "视频介绍: https://www.bilibili.com/video/BV1Pm42157cK?t=0.1"
			echo "---------------------------------------"
			echo "该功能可无缝安装python官方支持的任何版本！"
			local VERSION=$(python3 -V 2>&1 | awk '{print $2}')
			echo -e "当前python版本号: ${gl_huang}$VERSION${gl_bai}"
			echo "------------"
			echo "推荐版本:  3.12    3.11    3.10    3.9    3.8    2.7"
			echo "查询更多版本: https://www.python.org/downloads/"
			echo "------------"
			read -e -p "输入你要安装的python版本号（输入0退出）: " py_new_v


			if [[ "$py_new_v" == "0" ]]; then
				break_end
				linux_Settings
			fi


			if ! grep -q 'export PYENV_ROOT="\$HOME/.pyenv"' ~/.bashrc; then
				if command -v yum &>/dev/null; then
					yum update -y && yum install git -y
					yum groupinstall "Development Tools" -y
					yum install openssl-devel bzip2-devel libffi-devel ncurses-devel zlib-devel readline-devel sqlite-devel xz-devel findutils -y

					curl -O https://www.openssl.org/source/openssl-1.1.1u.tar.gz
					tar -xzf openssl-1.1.1u.tar.gz
					cd openssl-1.1.1u
					./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
					make
					make install
					echo "/usr/local/openssl/lib" > /etc/ld.so.conf.d/openssl-1.1.1u.conf
					ldconfig -v
					cd ..

					export LDFLAGS="-L/usr/local/openssl/lib"
					export CPPFLAGS="-I/usr/local/openssl/include"
					export PKG_CONFIG_PATH="/usr/local/openssl/lib/pkgconfig"

				elif command -v apt &>/dev/null; then
					apt update -y && apt install git -y
					apt install build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev libgdbm-dev libnss3-dev libedit-dev -y
				elif command -v apk &>/dev/null; then
					apk update && apk add git
					apk add --no-cache bash gcc musl-dev libffi-dev openssl-dev bzip2-dev zlib-dev readline-dev sqlite-dev libc6-compat linux-headers make xz-dev build-base  ncurses-dev
				else
					echo "未知的包管理器!"
					return
				fi

				curl https://pyenv.run | bash
				cat << EOF >> ~/.bashrc

export PYENV_ROOT="\$HOME/.pyenv"
if [[ -d "\$PYENV_ROOT/bin" ]]; then
  export PATH="\$PYENV_ROOT/bin:\$PATH"
fi
eval "\$(pyenv init --path)"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"

EOF

			fi

			sleep 1
			source ~/.bashrc
			sleep 1
			pyenv install $py_new_v
			pyenv global $py_new_v

			rm -rf /tmp/python-build.*
			rm -rf $(pyenv root)/cache/*

			local VERSION=$(python -V 2>&1 | awk '{print $2}')
			echo -e "当前python版本号: ${gl_huang}$VERSION${gl_bai}"

			  ;;

		  5)
			  root_use
			  iptables_open
			  remove iptables-persistent ufw firewalld iptables-services > /dev/null 2>&1
			  echo "端口已全部开放"

			  ;;
		  6)
			root_use

			while true; do
				clear
				sed -i 's/^\s*#\?\s*Port/Port/' /etc/ssh/sshd_config

				# 读取当前的 SSH 端口号
				local current_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')

				# 打印当前的 SSH 端口号
				echo -e "当前的 SSH 端口号是:  ${gl_huang}$current_port ${gl_bai}"

				echo "------------------------"
				echo "端口号范围1到65535之间的数字。（输入0退出）"

				# 提示用户输入新的 SSH 端口号
				read -e -p "请输入新的 SSH 端口号: " new_port

				# 判断端口号是否在有效范围内
				if [[ $new_port =~ ^[0-9]+$ ]]; then  # 检查输入是否为数字
					if [[ $new_port -ge 1 && $new_port -le 65535 ]]; then
						new_ssh_port $new_port
					elif [[ $new_port -eq 0 ]]; then
						break
					else
						echo "端口号无效，请输入1到65535之间的数字。"
						break_end
					fi
				else
					echo "输入无效，请输入数字。"
					break_end
				fi
			done


			  ;;


		  7)
			set_dns_ui
			  ;;

		  8)

			dd_xitong
			  ;;
		  9)
			root_use
			read -e -p "请输入新用户名（输入0退出）: " new_username
			if [ "$new_username" == "0" ]; then
				break_end
				linux_Settings
			fi

			create_user_with_sshkey $new_username true

			ssh-keygen -l -f /home/$new_username/.ssh/authorized_keys &>/dev/null && {
				passwd -l root &>/dev/null
				sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
			}

			;;


		  10)
			root_use
			while true; do
				clear
				echo "设置v4/v6优先级"
				echo "------------------------"


				if grep -Eq '^\s*precedence\s+::ffff:0:0/96\s+100\s*$' /etc/gai.conf 2>/dev/null; then
					echo -e "当前网络优先级设置: ${gl_huang}IPv4${gl_bai} 优先"
				else
					echo -e "当前网络优先级设置: ${gl_huang}IPv6${gl_bai} 优先"
				fi

				echo ""
				echo "------------------------"
				echo "1. IPv4 优先          2. IPv6 优先          3. IPv6 修复工具"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "选择优先的网络: " choice

				case $choice in
					1)
						prefer_ipv4
						;;
					2)
						rm -f /etc/gai.conf
						echo "已切换为 IPv6 优先"
						;;

					3)
						clear
						bash <(curl -L -s jhb.ovh/jb/v6.sh)
						echo "该功能由jhb大神提供，感谢他！"
						;;

					*)
						break
						;;

				esac
			done
			;;

		  11)
			clear
			ss -tulnape
			;;

		  12)
			root_use
			while true; do
				clear
				echo "设置虚拟内存"
				local swap_used=$(free -m | awk 'NR==3{print $3}')
				local swap_total=$(free -m | awk 'NR==3{print $2}')
				local swap_info=$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')

				echo -e "当前虚拟内存: ${gl_huang}$swap_info${gl_bai}"
				echo "------------------------"
				echo "1. 分配1024M         2. 分配2048M         3. 分配4096M         4. 自定义大小"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "请输入你的选择: " choice

				case "$choice" in
				  1)
					add_swap 1024

					;;
				  2)
					add_swap 2048

					;;
				  3)
					add_swap 4096

					;;

				  4)
					read -e -p "请输入虚拟内存大小（单位M）: " new_swap
					add_swap "$new_swap"
					;;

				  *)
					break
					;;
				esac
			done
			;;

		  13)
			  while true; do
				root_use
				echo "用户列表"
				echo "----------------------------------------------------------------------------"
				printf "%-24s %-34s %-20s %-10s\n" "用户名" "用户权限" "用户组" "sudo权限"
				while IFS=: read -r username _ userid groupid _ _ homedir shell; do
					local groups=$(groups "$username" | cut -d : -f 2)
					local sudo_status
					if sudo -n -lU "$username" 2>/dev/null | grep -q "(ALL) \(NOPASSWD: \)\?ALL"; then
						sudo_status="Yes"
					else
						sudo_status="No"
					fi
					printf "%-20s %-30s %-20s %-10s\n" "$username" "$homedir" "$groups" "$sudo_status"
				done < /etc/passwd


				  echo ""
				  echo "账户操作"
				  echo "------------------------"
				  echo "1. 创建普通用户             2. 创建高级用户"
				  echo "------------------------"
				  echo "3. 赋予最高权限             4. 取消最高权限"
				  echo "------------------------"
				  echo "5. 删除账号"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
					   # 提示用户输入新用户名
					   read -e -p "请输入新用户名: " new_username
					   create_user_with_sshkey $new_username false

						  ;;

					  2)
					   # 提示用户输入新用户名
					   read -e -p "请输入新用户名: " new_username
					   create_user_with_sshkey $new_username true

						  ;;
					  3)
					   read -e -p "请输入用户名: " username
					   install sudo
					   cat >"/etc/sudoers.d/$username" <<EOF
$username ALL=(ALL) NOPASSWD:ALL
EOF
					  chmod 440 "/etc/sudoers.d/$username"

						  ;;
					  4)
					   read -e -p "请输入用户名: " username
				  	   if [[ -f "/etc/sudoers.d/$username" ]]; then
						   grep -lR "^$username" /etc/sudoers.d/ 2>/dev/null | xargs rm -f
					   fi
					   sed -i "/^$username\s*ALL=(ALL)/d" /etc/sudoers
						  ;;
					  5)
					   read -e -p "请输入要删除的用户名: " username
					   userdel -r "$username"
						  ;;

					  *)
						  break  # 跳出循环，退出菜单
						  ;;
				  esac

			  done
			  ;;

		  14)
			clear
			echo "随机用户名"
			echo "------------------------"
			for i in {1..5}; do
				username="user$(< /dev/urandom tr -dc _a-z0-9 | head -c6)"
				echo "随机用户名 $i: $username"
			done

			echo ""
			echo "随机姓名"
			echo "------------------------"
			local first_names=("John" "Jane" "Michael" "Emily" "David" "Sophia" "William" "Olivia" "James" "Emma" "Ava" "Liam" "Mia" "Noah" "Isabella")
			local last_names=("Smith" "Johnson" "Brown" "Davis" "Wilson" "Miller" "Jones" "Garcia" "Martinez" "Williams" "Lee" "Gonzalez" "Rodriguez" "Hernandez")

			# 生成5个随机用户姓名
			for i in {1..5}; do
				local first_name_index=$((RANDOM % ${#first_names[@]}))
				local last_name_index=$((RANDOM % ${#last_names[@]}))
				local user_name="${first_names[$first_name_index]} ${last_names[$last_name_index]}"
				echo "随机用户姓名 $i: $user_name"
			done

			echo ""
			echo "随机UUID"
			echo "------------------------"
			for i in {1..5}; do
				uuid=$(cat /proc/sys/kernel/random/uuid)
				echo "随机UUID $i: $uuid"
			done

			echo ""
			echo "16位随机密码"
			echo "------------------------"
			for i in {1..5}; do
				local password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
				echo "随机密码 $i: $password"
			done

			echo ""
			echo "32位随机密码"
			echo "------------------------"
			for i in {1..5}; do
				local password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
				echo "随机密码 $i: $password"
			done
			echo ""

			  ;;

		  15)
			root_use
			while true; do
				clear
				echo "系统时间信息"

				# 获取当前系统时区
				local timezone=$(current_timezone)

				# 获取当前系统时间
				local current_time=$(date +"%Y-%m-%d %H:%M:%S")

				# 显示时区和时间
				echo "当前系统时区：$timezone"
				echo "当前系统时间：$current_time"

				echo ""
				echo "时区切换"
				echo "------------------------"
				echo "亚洲"
				echo "1.  中国上海时间             2.  中国香港时间"
				echo "3.  日本东京时间             4.  韩国首尔时间"
				echo "5.  新加坡时间               6.  印度加尔各答时间"
				echo "7.  阿联酋迪拜时间           8.  澳大利亚悉尼时间"
				echo "9.  泰国曼谷时间"
				echo "------------------------"
				echo "欧洲"
				echo "11. 英国伦敦时间             12. 法国巴黎时间"
				echo "13. 德国柏林时间             14. 俄罗斯莫斯科时间"
				echo "15. 荷兰尤特赖赫特时间       16. 西班牙马德里时间"
				echo "------------------------"
				echo "美洲"
				echo "21. 美国西部时间             22. 美国东部时间"
				echo "23. 加拿大时间               24. 墨西哥时间"
				echo "25. 巴西时间                 26. 阿根廷时间"
				echo "------------------------"
				echo "31. UTC全球标准时间"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "请输入你的选择: " sub_choice


				case $sub_choice in
					1) set_timedate Asia/Shanghai ;;
					2) set_timedate Asia/Hong_Kong ;;
					3) set_timedate Asia/Tokyo ;;
					4) set_timedate Asia/Seoul ;;
					5) set_timedate Asia/Singapore ;;
					6) set_timedate Asia/Kolkata ;;
					7) set_timedate Asia/Dubai ;;
					8) set_timedate Australia/Sydney ;;
					9) set_timedate Asia/Bangkok ;;
					11) set_timedate Europe/London ;;
					12) set_timedate Europe/Paris ;;
					13) set_timedate Europe/Berlin ;;
					14) set_timedate Europe/Moscow ;;
					15) set_timedate Europe/Amsterdam ;;
					16) set_timedate Europe/Madrid ;;
					21) set_timedate America/Los_Angeles ;;
					22) set_timedate America/New_York ;;
					23) set_timedate America/Vancouver ;;
					24) set_timedate America/Mexico_City ;;
					25) set_timedate America/Sao_Paulo ;;
					26) set_timedate America/Argentina/Buenos_Aires ;;
					31) set_timedate UTC ;;
					*) break ;;
				esac
			done
			  ;;

		  16)

			bbrv3
			  ;;

		  17)
			  iptables_panel

			  ;;

		  18)
		  root_use

		  while true; do
			  clear
			  local current_hostname=$(uname -n)
			  echo -e "当前主机名: ${gl_huang}$current_hostname${gl_bai}"
			  echo "------------------------"
			  read -e -p "请输入新的主机名（输入0退出）: " new_hostname
			  if [ -n "$new_hostname" ] && [ "$new_hostname" != "0" ]; then
				  if [ -f /etc/alpine-release ]; then
					  # Alpine
					  echo "$new_hostname" > /etc/hostname
					  hostname "$new_hostname"
				  else
					  # 其他系统，如 Debian, Ubuntu, CentOS 等
					  hostnamectl set-hostname "$new_hostname"
					  sed -i "s/$current_hostname/$new_hostname/g" /etc/hostname
					  systemctl restart systemd-hostnamed
				  fi

				  if grep -q "127.0.0.1" /etc/hosts; then
					  sed -i "s/127.0.0.1 .*/127.0.0.1       $new_hostname localhost localhost.localdomain/g" /etc/hosts
				  else
					  echo "127.0.0.1       $new_hostname localhost localhost.localdomain" >> /etc/hosts
				  fi

				  if grep -q "^::1" /etc/hosts; then
					  sed -i "s/^::1 .*/::1             $new_hostname localhost localhost.localdomain ipv6-localhost ipv6-loopback/g" /etc/hosts
				  else
					  echo "::1             $new_hostname localhost localhost.localdomain ipv6-localhost ipv6-loopback" >> /etc/hosts
				  fi

				  echo "主机名已更改为: $new_hostname"
				  sleep 1
			  else
				  echo "已退出，未更改主机名。"
				  break
			  fi
		  done
			  ;;

		  19)
		  root_use
		  clear
		  echo "选择更新源区域"
		  echo "接入LinuxMirrors切换系统更新源"
		  echo "------------------------"
		  echo "1. 中国大陆【默认】          2. 中国大陆【教育网】          3. 海外地区          4. 智能切换更新源"
		  echo "------------------------"
		  echo "0. 返回上一级选单"
		  echo "------------------------"
		  read -e -p "输入你的选择: " choice

		  case $choice in
			  1)
				  bash <(curl -sSL https://linuxmirrors.cn/main.sh)
				  ;;
			  2)
				  bash <(curl -sSL https://linuxmirrors.cn/main.sh) --edu
				  ;;
			  3)
				  bash <(curl -sSL https://linuxmirrors.cn/main.sh) --abroad
				  ;;
			  4)
				  switch_mirror false false
				  ;;

			  *)
				  echo "已取消"
				  ;;

		  esac

			  ;;

		  20)
			  while true; do
				  clear
				  check_crontab_installed
				  clear
				  echo "定时任务列表"
				  crontab -l
				  echo ""
				  echo "操作"
				  echo "------------------------"
				  echo "1. 添加定时任务              2. 删除定时任务              3. 编辑定时任务"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " sub_choice

				  case $sub_choice in
					  1)
						  read -e -p "请输入新任务的执行命令: " newquest
						  echo "------------------------"
						  echo "1. 每月任务                 2. 每周任务"
						  echo "3. 每天任务                 4. 每小时任务"
						  echo "------------------------"
						  read -e -p "请输入你的选择: " dingshi

						  case $dingshi in
							  1)
								  read -e -p "选择每月的几号执行任务？ (1-30): " day
								  (crontab -l ; echo "0 0 $day * * $newquest") | crontab - > /dev/null 2>&1
								  ;;
							  2)
								  read -e -p "选择周几执行任务？ (0-6，0代表星期日): " weekday
								  (crontab -l ; echo "0 0 * * $weekday $newquest") | crontab - > /dev/null 2>&1
								  ;;
							  3)
								  read -e -p "选择每天几点执行任务？（小时，0-23）: " hour
								  (crontab -l ; echo "0 $hour * * * $newquest") | crontab - > /dev/null 2>&1
								  ;;
							  4)
								  read -e -p "输入每小时的第几分钟执行任务？（分钟，0-60）: " minute
								  (crontab -l ; echo "$minute * * * * $newquest") | crontab - > /dev/null 2>&1
								  ;;
							  *)
								  break  # 跳出
								  ;;
						  esac
						  ;;
					  2)
						  read -e -p "请输入需要删除任务的关键字: " kquest
						  crontab -l | grep -v "$kquest" | crontab -
						  ;;
					  3)
						  crontab -e
						  ;;
					  *)
						  break  # 跳出循环，退出菜单
						  ;;
				  esac
			  done

			  ;;

		  21)
			  root_use
			  while true; do
				  clear
				  echo "本机host解析列表"
				  echo "如果你在这里添加解析匹配，将不再使用动态解析了"
				  cat /etc/hosts
				  echo ""
				  echo "操作"
				  echo "------------------------"
				  echo "1. 添加新的解析              2. 删除解析地址"
				  echo "------------------------"
				  echo "0. 返回上一级选单"
				  echo "------------------------"
				  read -e -p "请输入你的选择: " host_dns

				  case $host_dns in
					  1)
						  read -e -p "请输入新的解析记录 格式: 110.25.5.33 kejilion.pro : " addhost
						  echo "$addhost" >> /etc/hosts

						  ;;
					  2)
						  read -e -p "请输入需要删除的解析内容关键字: " delhost
						  sed -i "/$delhost/d" /etc/hosts
						  ;;
					  *)
						  break  # 跳出循环，退出菜单
						  ;;
				  esac
			  done
			  ;;

		  22)
			fail2ban_panel
			  ;;


		  23)
			root_use
			while true; do
				clear
				echo "限流关机功能"
				echo "视频介绍: https://www.bilibili.com/video/BV1mC411j7Qd?t=0.1"
				echo "------------------------------------------------"
				echo "当前流量使用情况，重启服务器流量计算会清零！"
				output_status
				echo -e "${gl_kjlan}总接收: ${gl_bai}$rx"
				echo -e "${gl_kjlan}总发送: ${gl_bai}$tx"

				# 检查是否存在 Limiting_Shut_down.sh 文件
				if [ -f ~/Limiting_Shut_down.sh ]; then
					# 获取 threshold_gb 的值
					local rx_threshold_gb=$(grep -oP 'rx_threshold_gb=\K\d+' ~/Limiting_Shut_down.sh)
					local tx_threshold_gb=$(grep -oP 'tx_threshold_gb=\K\d+' ~/Limiting_Shut_down.sh)
					echo -e "${gl_lv}当前设置的进站限流阈值为: ${gl_huang}${rx_threshold_gb}${gl_lv}G${gl_bai}"
					echo -e "${gl_lv}当前设置的出站限流阈值为: ${gl_huang}${tx_threshold_gb}${gl_lv}GB${gl_bai}"
				else
					echo -e "${gl_hui}当前未启用限流关机功能${gl_bai}"
				fi

				echo
				echo "------------------------------------------------"
				echo "系统每分钟会检测实际流量是否到达阈值，到达后会自动关闭服务器！"
				echo "------------------------"
				echo "1. 开启限流关机功能          2. 停用限流关机功能"
				echo "------------------------"
				echo "0. 返回上一级选单"
				echo "------------------------"
				read -e -p "请输入你的选择: " Limiting

				case "$Limiting" in
				  1)
					# 输入新的虚拟内存大小
					echo "如果实际服务器就100G流量，可设置阈值为95G，提前关机，以免出现流量误差或溢出。"
					read -e -p "请输入进站流量阈值（单位为G，默认100G）: " rx_threshold_gb
					rx_threshold_gb=${rx_threshold_gb:-100}
					read -e -p "请输入出站流量阈值（单位为G，默认100G）: " tx_threshold_gb
					tx_threshold_gb=${tx_threshold_gb:-100}
					read -e -p "请输入流量重置日期（默认每月1日重置）: " cz_day
					cz_day=${cz_day:-1}

					check_crontab_installed
					local traffic_version
					traffic_version="$(kpanel_network_operations_traffic_version)"
					if KJ_NETWORK_OPERATIONS_NONINTERACTIVE=1 kpanel_network_operations_traffic_run_locked enable "$traffic_version" "$rx_threshold_gb" "$tx_threshold_gb" "$cz_day"; then
						echo "限流关机已设置"
					else
						echo "限流关机设置失败，请根据上方错误检查配置"
					fi
					;;
				  2)
					check_crontab_installed
					local traffic_version
					traffic_version="$(kpanel_network_operations_traffic_version)"
					if KJ_NETWORK_OPERATIONS_NONINTERACTIVE=1 kpanel_network_operations_traffic_run_locked disable "$traffic_version"; then
						echo "已关闭限流关机功能"
					else
						echo "关闭限流关机失败，请根据上方错误检查配置"
					fi
					;;
				  *)
					break
					;;
				esac
			done
			  ;;


		  24)
			sshkey_panel
			  ;;

		  25)
			  root_use
			  echo "TG-bot监控预警功能"
			  echo "视频介绍: https://youtu.be/vLL-eb3Z_TY"
			  echo "------------------------------------------------"
			  echo "您需要配置tg机器人API和接收预警的用户ID，即可实现本机CPU，内存，硬盘，流量，SSH登录的实时监控预警"
			  echo "到达阈值后会向用户发预警消息"
			  echo -e "${gl_hui}-关于流量，重启服务器将重新计算-${gl_bai}"
			  read -e -p "确定继续吗？(Y/N): " choice

			  case "$choice" in
				[Yy])
				  cd ~
				  install nano tmux bc jq
				  check_crontab_installed
				  if [ -f ~/TG-check-notify.sh ]; then
					  chmod +x ~/TG-check-notify.sh
					  nano ~/TG-check-notify.sh
				  else
					  curl -sS -O https://raw.githubusercontent.com/howi3c/sh/main/TG-check-notify.sh
					  chmod +x ~/TG-check-notify.sh
					  nano ~/TG-check-notify.sh
				  fi
				  tmux kill-session -t TG-check-notify > /dev/null 2>&1
				  tmux new -d -s TG-check-notify "~/TG-check-notify.sh"
				  crontab -l | grep -v '~/TG-check-notify.sh' | crontab - > /dev/null 2>&1
				  (crontab -l ; echo "@reboot tmux new -d -s TG-check-notify '~/TG-check-notify.sh'") | crontab - > /dev/null 2>&1

				  curl -sS -O https://raw.githubusercontent.com/howi3c/sh/main/TG-SSH-check-notify.sh > /dev/null 2>&1
				  sed -i "3i$(grep '^TELEGRAM_BOT_TOKEN=' ~/TG-check-notify.sh)" TG-SSH-check-notify.sh > /dev/null 2>&1
				  sed -i "4i$(grep '^CHAT_ID=' ~/TG-check-notify.sh)" TG-SSH-check-notify.sh
				  chmod +x ~/TG-SSH-check-notify.sh

				  # 添加到 ~/.profile 文件中
				  if ! grep -q 'bash ~/TG-SSH-check-notify.sh' ~/.profile > /dev/null 2>&1; then
					  echo 'bash ~/TG-SSH-check-notify.sh' >> ~/.profile
					  if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
						 echo 'source ~/.profile' >> ~/.bashrc
					  fi
				  fi

				  source ~/.profile

				  clear
				  echo "TG-bot预警系统已启动"
				  echo -e "${gl_hui}你还可以将root目录中的TG-check-notify.sh预警文件放到其他机器上直接使用！${gl_bai}"
				  ;;
				[Nn])
				  echo "已取消"
				  ;;
				*)
				  echo "无效的选择，请输入 Y 或 N。"
				  ;;
			  esac
			  ;;

		  26)
			  root_use
			  cd ~
			  curl -sS -O https://raw.githubusercontent.com/howi3c/sh/main/upgrade_openssh9.8p1.sh
			  chmod +x ~/upgrade_openssh9.8p1.sh
			  ~/upgrade_openssh9.8p1.sh
			  rm -f ~/upgrade_openssh9.8p1.sh
			  ;;

		  27)
			  elrepo
			  ;;
		  28)
			  Kernel_optimize
			  ;;

		  29)
			  clamav
			  ;;

		  30)
			  linux_file
			  ;;

		  31)
			  linux_language
			  ;;

		  32)
			  shell_bianse
			  ;;
		  33)
			  linux_trash
			  ;;
		  34)
			  linux_backup
			  ;;
		  35)
			  ssh_manager
			  ;;
		  36)
			  disk_manager
			  ;;
		  37)
			  clear
			  get_history_file() {
				  for file in "$HOME"/.bash_history "$HOME"/.ash_history "$HOME"/.zsh_history "$HOME"/.local/share/fish/fish_history; do
					  [ -f "$file" ] && { echo "$file"; return; }
				  done
				  return 1
			  }

			  history_file=$(get_history_file) && cat -n "$history_file"
			  ;;

		  38)
			  rsync_manager
			  ;;


		  39)
			  clear
			  linux_fav
			  ;;

		  40)
			  clear
			  net_menu
			  ;;

		  41)
			  clear
			  log_menu
			  ;;

		  42)
			  clear
			  env_menu
			  ;;


		  66)

			  root_use
			  echo "一条龙系统调优"
			  echo "------------------------------------------------"
			  echo "将对以下内容进行操作与优化"
			  echo "1. 优化系统更新源，更新系统到最新"
			  echo "2. 清理系统垃圾文件"
			  echo -e "3. 设置虚拟内存${gl_huang}1G${gl_bai}"
			  echo -e "4. 设置SSH端口号为${gl_huang}5522${gl_bai}"
			  echo -e "5. 启动fail2ban防御SSH暴力破解"
			  echo -e "6. 开放所有端口"
			  echo -e "7. 开启${gl_huang}BBR${gl_bai}加速"
			  echo -e "8. 设置时区到${gl_huang}上海${gl_bai}"
			  echo -e "9. 自动优化DNS地址${gl_huang}海外: 1.1.1.1 8.8.8.8  国内: 223.5.5.5 ${gl_bai}"
		  	  echo -e "10. 设置网络为${gl_huang}ipv4优先${gl_bai}"
			  echo -e "11. 安装基础工具${gl_huang}docker wget sudo tar unzip socat btop nano vim${gl_bai}"
			  echo "------------------------------------------------"
			  read -e -p "确定一键保养吗？(Y/N): " choice

			  case "$choice" in
				[Yy])
				  clear
				  kpanel_system_tuning_menu_item system-update 1 "更新系统到最新" || break
				  kpanel_system_tuning_menu_item system-cleanup 2 "清理系统垃圾文件" || break
				  kpanel_system_tuning_menu_item swap-1g 3 "设置虚拟内存${gl_huang}1G${gl_bai}" || break
				  kpanel_system_tuning_menu_item ssh-port-5522 4 "设置SSH端口号为${gl_huang}5522${gl_bai}" || break
				  kpanel_system_tuning_menu_item ssh-defense 5 "启动fail2ban防御SSH暴力破解" || break
				  cd ~
				  f2b_status
				  kpanel_system_tuning_menu_item firewall-open-all 6 "开放所有端口" || break
				  kpanel_system_tuning_menu_item bbr 7 "开启${gl_huang}BBR${gl_bai}加速" || break
				  kpanel_system_tuning_menu_item timezone-shanghai 8 "设置时区到${gl_huang}上海${gl_bai}" || break
				  kpanel_system_tuning_menu_item dns-auto 9 "自动优化DNS地址" || break
				  kpanel_system_tuning_menu_item ipv4-preferred 10 "设置网络为${gl_huang}IPv4优先${gl_bai}" || break
				  kpanel_system_tuning_menu_item basic-tools 11 "安装基础工具${gl_huang}docker wget sudo tar unzip socat btop nano vim${gl_bai}" || break
				  echo -e "${gl_lv}一条龙系统调优已完成${gl_bai}"

				  ;;
				[Nn])
				  echo "已取消"
				  ;;
				*)
				  echo "无效的选择，请输入 Y 或 N。"
				  ;;
			  esac

			  ;;

		  99)
			  clear
			  server_reboot
			  ;;
		  101)
			  clear
			  k_info
			  ;;

		  102)
			  clear
			  echo "卸载科技lion脚本"
			  echo "------------------------------------------------"
			  echo "将彻底卸载kejilion脚本，不影响你其他功能"
			  read -e -p "确定继续吗？(Y/N): " choice

			  case "$choice" in
				[Yy])
				  clear
				  (crontab -l | grep -v "kejilion.sh") | crontab -
				  rm -f /usr/local/bin/k
				  rm ~/kejilion.sh
				  echo "脚本已卸载，再见！"
				  break_end
				  clear
				  exit
				  ;;
				[Nn])
				  echo "已取消"
				  ;;
				*)
				  echo "无效的选择，请输入 Y 或 N。"
				  ;;
			  esac
			  ;;

		  0)
			  kejilion

			  ;;
		  *)
			  echo "无效的输入!"
			  ;;
	  esac
	  break_end

	done



}






linux_file() {
	root_use
	while true; do
		clear
		echo "文件管理器"
		echo "------------------------"
		echo "当前路径"
		pwd
		echo "------------------------"
		ls --color=auto -x
		echo "------------------------"
		echo "1.  进入目录           2.  创建目录             3.  修改目录权限         4.  重命名目录"
		echo "5.  删除目录           6.  返回上一级选单目录"
		echo "------------------------"
		echo "11. 创建文件           12. 编辑文件             13. 修改文件权限         14. 重命名文件"
		echo "15. 删除文件"
		echo "------------------------"
		echo "21. 压缩文件目录       22. 解压文件目录         23. 移动文件目录         24. 复制文件目录"
		echo "25. 传文件至其他服务器"
		echo "------------------------"
		echo "0.  返回上一级选单"
		echo "------------------------"
		read -e -p "请输入你的选择: " Limiting

		case "$Limiting" in
			1)  # 进入目录
				read -e -p "请输入目录名: " dirname
				cd "$dirname" 2>/dev/null || echo "无法进入目录"
				;;
			2)  # 创建目录
				read -e -p "请输入要创建的目录名: " dirname
				mkdir -p "$dirname" && echo "目录已创建" || echo "创建失败"
				;;
			3)  # 修改目录权限
				read -e -p "请输入目录名: " dirname
				read -e -p "请输入权限 (如 755): " perm
				chmod "$perm" "$dirname" && echo "权限已修改" || echo "修改失败"
				;;
			4)  # 重命名目录
				read -e -p "请输入当前目录名: " current_name
				read -e -p "请输入新目录名: " new_name
				mv "$current_name" "$new_name" && echo "目录已重命名" || echo "重命名失败"
				;;
			5)  # 删除目录
				read -e -p "请输入要删除的目录名: " dirname
				rm -rf "$dirname" && echo "目录已删除" || echo "删除失败"
				;;
			6)  # 返回上一级选单目录
				cd ..
				;;
			11) # 创建文件
				read -e -p "请输入要创建的文件名: " filename
				touch "$filename" && echo "文件已创建" || echo "创建失败"
				;;
			12) # 编辑文件
				read -e -p "请输入要编辑的文件名: " filename
				install nano
				nano "$filename"
				;;
			13) # 修改文件权限
				read -e -p "请输入文件名: " filename
				read -e -p "请输入权限 (如 755): " perm
				chmod "$perm" "$filename" && echo "权限已修改" || echo "修改失败"
				;;
			14) # 重命名文件
				read -e -p "请输入当前文件名: " current_name
				read -e -p "请输入新文件名: " new_name
				mv "$current_name" "$new_name" && echo "文件已重命名" || echo "重命名失败"
				;;
			15) # 删除文件
				read -e -p "请输入要删除的文件名: " filename
				rm -f "$filename" && echo "文件已删除" || echo "删除失败"
				;;
			21) # 压缩文件/目录
				read -e -p "请输入要压缩的文件/目录名: " name
				install tar
				tar -czvf "$name.tar.gz" "$name" && echo "已压缩为 $name.tar.gz" || echo "压缩失败"
				;;
			22) # 解压文件/目录
				read -e -p "请输入要解压的文件名 (.tar.gz): " filename
				install tar
				tar -xzvf "$filename" && echo "已解压 $filename" || echo "解压失败"
				;;

			23) # 移动文件或目录
				read -e -p "请输入要移动的文件或目录路径: " src_path
				if [ ! -e "$src_path" ]; then
					echo "错误: 文件或目录不存在。"
					continue
				fi

				read -e -p "请输入目标路径 (包括新文件名或目录名): " dest_path
				if [ -z "$dest_path" ]; then
					echo "错误: 请输入目标路径。"
					continue
				fi

				mv "$src_path" "$dest_path" && echo "文件或目录已移动到 $dest_path" || echo "移动文件或目录失败"
				;;


		   24) # 复制文件目录
				read -e -p "请输入要复制的文件或目录路径: " src_path
				if [ ! -e "$src_path" ]; then
					echo "错误: 文件或目录不存在。"
					continue
				fi

				read -e -p "请输入目标路径 (包括新文件名或目录名): " dest_path
				if [ -z "$dest_path" ]; then
					echo "错误: 请输入目标路径。"
					continue
				fi

				# 使用 -r 选项以递归方式复制目录
				cp -r "$src_path" "$dest_path" && echo "文件或目录已复制到 $dest_path" || echo "复制文件或目录失败"
				;;


			 25) # 传送文件至远端服务器
				read -e -p "请输入要传送的文件路径: " file_to_transfer
				if [ ! -f "$file_to_transfer" ]; then
					echo "错误: 文件不存在。"
					continue
				fi

				kj_ssh_read_host_user_port "请输入远端服务器IP: " "请输入远端服务器用户名 (默认root): " "请输入登录端口 (默认22): " "root" "22"
				local remote_ip="$KJ_SSH_HOST"
				local remote_user="$KJ_SSH_USER"
				local remote_port="$KJ_SSH_PORT"

				kj_ssh_read_password "请输入远端服务器密码: "
				local remote_password="$KJ_SSH_PASSWORD"

				# 清除已知主机的旧条目
				ssh-keygen -f "/root/.ssh/known_hosts" -R "$remote_ip"
				sleep 2  # 等待时间

				# 使用scp传输文件
				scp -P "$remote_port" -o StrictHostKeyChecking=no "$file_to_transfer" "$remote_user@$remote_ip:/home/" <<EOF
$remote_password
EOF

				if [ $? -eq 0 ]; then
					echo "文件已传送至远程服务器home目录。"
				else
					echo "文件传送失败。"
				fi

				break_end
				;;



			0)  # 返回上一级选单
				break
				;;
			*)  # 处理无效输入
				echo "无效的选择，请重新输入"
				;;
		esac
	done
}








run_commands_on_servers() {

	install sshpass

	local SERVERS_FILE="$HOME/cluster/servers.py"
	local SERVERS=$(grep -oP '{"name": "\K[^"]+|"hostname": "\K[^"]+|"port": \K[^,]+|"username": "\K[^"]+|"password": "\K[^"]+' "$SERVERS_FILE")

	# 将提取的信息转换为数组
	IFS=$'\n' read -r -d '' -a SERVER_ARRAY <<< "$SERVERS"

	# 遍历服务器并执行命令
	for ((i=0; i<${#SERVER_ARRAY[@]}; i+=5)); do
		local name=${SERVER_ARRAY[i]}
		local hostname=${SERVER_ARRAY[i+1]}
		local port=${SERVER_ARRAY[i+2]}
		local username=${SERVER_ARRAY[i+3]}
		local password=${SERVER_ARRAY[i+4]}
		echo
		echo -e "${gl_huang}连接到 $name ($hostname)...${gl_bai}"
		# sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$hostname" -p "$port" "$1"
		sshpass -p "$password" ssh -t -o StrictHostKeyChecking=no "$username@$hostname" -p "$port" "$1"
	done
	echo
	break_end

}


linux_cluster() {
mkdir cluster
if [ ! -f ~/cluster/servers.py ]; then
	cat > ~/cluster/servers.py << EOF
servers = [

]
EOF
fi

while true; do
	  clear
	  echo "服务器集群控制"
	  cat ~/cluster/servers.py
	  echo
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  echo -e "${gl_kjlan}服务器列表管理${gl_bai}"
	  echo -e "${gl_kjlan}1.  ${gl_bai}添加服务器               ${gl_kjlan}2.  ${gl_bai}删除服务器            ${gl_kjlan}3.  ${gl_bai}编辑服务器"
	  echo -e "${gl_kjlan}4.  ${gl_bai}备份集群                 ${gl_kjlan}5.  ${gl_bai}还原集群"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  echo -e "${gl_kjlan}批量执行任务${gl_bai}"
	  echo -e "${gl_kjlan}12. ${gl_bai}更新系统              ${gl_kjlan}13. ${gl_bai}清理系统"
	  echo -e "${gl_kjlan}14. ${gl_bai}安装docker               ${gl_kjlan}15. ${gl_bai}安装BBR3              ${gl_kjlan}16. ${gl_bai}设置1G虚拟内存"
	  echo -e "${gl_kjlan}17. ${gl_bai}设置时区到上海           ${gl_kjlan}18. ${gl_bai}开放所有端口	       ${gl_kjlan}51. ${gl_bai}自定义指令"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  echo -e "${gl_kjlan}0.  ${gl_bai}返回主菜单"
	  echo -e "${gl_kjlan}------------------------${gl_bai}"
	  read -e -p "请输入你的选择: " sub_choice

	  case $sub_choice in
		  1)
			  read -e -p "服务器名称: " server_name
			  read -e -p "服务器IP: " server_ip
			  read -e -p "服务器端口（22）: " server_port
			  local server_port=${server_port:-22}
			  read -e -p "服务器用户名（root）: " server_username
			  local server_username=${server_username:-root}
			  read -e -p "服务器用户密码: " server_password

			  sed -i "/servers = \[/a\    {\"name\": \"$server_name\", \"hostname\": \"$server_ip\", \"port\": $server_port, \"username\": \"$server_username\", \"password\": \"$server_password\", \"remote_path\": \"/home/\"}," ~/cluster/servers.py

			  ;;
		  2)
			  read -e -p "请输入需要删除的关键字: " rmserver
			  sed -i "/$rmserver/d" ~/cluster/servers.py
			  ;;
		  3)
			  install nano
			  nano ~/cluster/servers.py
			  ;;

		  4)
			  clear
			  echo -e "请将 ${gl_huang}/root/cluster/servers.py${gl_bai} 文件下载，完成备份！"
			  break_end
			  ;;

		  5)
			  clear
			  echo "请上传您的servers.py，按任意键开始上传！"
			  echo -e "请上传您的 ${gl_huang}servers.py${gl_bai} 文件到 ${gl_huang}/root/cluster/${gl_bai} 完成还原！"
			  break_end
			  ;;

		  12)
			  run_commands_on_servers "k update"
			  ;;
		  13)
			  run_commands_on_servers "k clean"
			  ;;
		  14)
			  run_commands_on_servers "k docker install"
			  ;;
		  15)
			  run_commands_on_servers "k bbr3"
			  ;;
		  16)
			  run_commands_on_servers "k swap 1024"
			  ;;
		  17)
			  run_commands_on_servers "k time Asia/Shanghai"
			  ;;
		  18)
			  run_commands_on_servers "k iptables_open"
			  ;;

		  51)
			  read -e -p "请输入批量执行的命令: " mingling
			  run_commands_on_servers "${mingling}"
			  ;;

		  *)
			  kejilion
			  ;;
	  esac
done

}

























kejilion_sh() {
while true; do
clear
echo -e "${gl_kjlan}"
echo "╦╔═╔═╗ ╦╦╦  ╦╔═╗╔╗╔ ╔═╗╦ ╦"
echo "╠╩╗║╣  ║║║  ║║ ║║║║ ╚═╗╠═╣"
echo "╩ ╩╚═╝╚╝╩╩═╝╩╚═╝╝╚╝o╚═╝╩ ╩"
echo -e "科技lion脚本工具箱 v$sh_v（无遥测版）"
echo -e "命令行输入${gl_huang}k${gl_kjlan}可快速启动脚本${gl_bai}"
echo -e "${gl_kjlan}------------------------${gl_bai}"
echo -e "${gl_kjlan}1.   ${gl_bai}系统信息查询"
echo -e "${gl_kjlan}2.   ${gl_bai}系统更新"
echo -e "${gl_kjlan}3.   ${gl_bai}系统清理"
echo -e "${gl_kjlan}4.   ${gl_bai}基础工具"
echo -e "${gl_kjlan}5.   ${gl_bai}BBR管理"
echo -e "${gl_kjlan}6.   ${gl_bai}Docker管理"
echo -e "${gl_kjlan}7.   ${gl_bai}WARP管理"
echo -e "${gl_kjlan}8.   ${gl_bai}测试脚本合集"
echo -e "${gl_kjlan}9.   ${gl_bai}后台工作区"
echo -e "${gl_kjlan}10.  ${gl_bai}系统工具"
echo -e "${gl_kjlan}11.  ${gl_bai}服务器集群控制"
echo -e "${gl_kjlan}------------------------${gl_bai}"
echo -e "${gl_kjlan}0.   ${gl_bai}退出脚本"
echo -e "${gl_kjlan}------------------------${gl_bai}"
read -e -p "请输入你的选择: " choice

case $choice in
  1) linux_info ;;
  2) clear ; linux_update ;;
  3) clear ; linux_clean ;;
  4) linux_tools ;;
  5) linux_bbr ;;
  6) linux_docker ;;
  7) clear ; install wget
	wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh ; bash menu.sh [option] [lisence/url/token]
	;;
  8) linux_test ;;
  9) linux_work ;;
  10) linux_Settings ;;
  11) linux_cluster ;;
  0) clear ; exit ;;
  *) echo "无效的输入!" ;;
esac
	break_end
done
}


k_info() {
echo "-------------------"
echo "视频介绍: https://www.bilibili.com/video/BV1ib421E7it?t=0.1"
echo "本脚本基于 kejilion 脚本修改"
echo "以下是k命令参考用例："
echo "启动脚本            k"
echo "安装软件包          k install nano wget | k add nano wget | k 安装 nano wget"
echo "卸载软件包          k remove nano wget | k del nano wget | k uninstall nano wget | k 卸载 nano wget"
echo "更新系统            k update | k 更新"
echo "清理系统垃圾        k clean | k 清理"
echo "重装系统面板        k dd | k 重装"
echo "bbr3控制面板        k bbr3 | k bbrv3"
echo "内核调优面板        k nhyh | k 内核优化"
echo "设置虚拟内存        k swap 2048"
echo "设置虚拟时区        k time Asia/Shanghai | k 时区 Asia/Shanghai"
echo "系统回收站          k trash | k hsz | k 回收站"
echo "系统备份功能        k backup | k bf | k 备份"
echo "ssh远程连接工具     k ssh | k 远程连接"
echo "rsync远程同步工具   k rsync | k 远程同步"
echo "硬盘管理工具        k disk | k 硬盘管理"
echo "软件启动            k start sshd | k 启动 sshd "
echo "软件停止            k stop sshd | k 停止 sshd "
echo "软件重启            k restart sshd | k 重启 sshd "
echo "软件状态查看        k status sshd | k 状态 sshd "
echo "软件开机启动        k enable docker | k autostart docke | k 开机启动 docker "
echo "docker管理平面      k docker"
echo "docker环境安装      k docker install |k docker 安装"
echo "docker容器管理      k docker ps |k docker 容器"
echo "docker镜像管理      k docker img |k docker 镜像"
echo "防火墙面板          k fhq |k 防火墙"
echo "开放端口            k dkdk 8080 |k 打开端口 8080"
echo "关闭端口            k gbdk 7800 |k 关闭端口 7800"
echo "放行IP              k fxip 127.0.0.0/8 |k 放行IP 127.0.0.0/8"
echo "阻止IP              k zzip 177.5.25.36 |k 阻止IP 177.5.25.36"
echo "命令收藏夹          k fav | k 命令收藏夹"
echo "fail2ban管理        k fail2ban | k f2b [status|enable|disable]"
echo "显示系统信息        k info"
echo "ROOT密钥管理        k sshkey"
echo "SSH公钥导入(URL)    k sshkey <url>"
echo "SSH公钥导入(GitHub) k sshkey github <user> "

}



# Versioned shared backup adapter. No downloaded helper or caller-supplied path.
kpanel_backup_center_dispatch() {
    local binary="/usr/local/libexec/kejilion-agent" metadata owner mode protocol
    [ "$(id -u)" = "0" ] || { echo "备份适配器需要 root" >&2; return 1; }
    [ -f "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ] || { echo "缺少 KPanel 备份适配器，请安装匹配版本的 Agent" >&2; return 1; }
    metadata=$(stat -c '%u %a' "$binary") || return 1
    read -r owner mode <<< "$metadata"
    [[ "$owner" = "0" && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 0022) == 0 )) || { echo "备份适配器权限无效" >&2; return 1; }
    protocol=$("$binary" backup-center protocol) || return 1
    [ "$protocol" = '{"protocol":1,"format":1}' ] || { echo "备份适配器协议不兼容" >&2; return 1; }
    "$binary" backup-center "$@"
}

if [ "$#" -eq 0 ]; then
	# 如果没有参数，运行交互式逻辑
	kejilion_sh
else
	# 如果有参数，执行相应函数
	case $1 in
		backup-center)
			shift
			kpanel_backup_center_dispatch "$@"
			;;
		install|add|安装)
			shift
			install "$@"
			;;
		remove|del|uninstall|卸载)
			shift
			remove "$@"
			;;
		update|更新)
			linux_update
			;;
		clean|清理)
			linux_clean
			;;
		dd|重装)
			dd_xitong
			;;
		bbr3|bbrv3)
			if [ "${KJ_BBRV3_NONINTERACTIVE:-}" = "1" ]; then
				shift
				bbrv3 "$@"
			else
				bbrv3
			fi
			;;
		nhyh|内核优化)
			Kernel_optimize
			;;
		trash|hsz|回收站)
			linux_trash
			;;
		backup|bf|备份)
			linux_backup
			;;
		ssh|远程连接)
			ssh_manager
			;;

		rsync|远程同步)
			rsync_manager
			;;

		rsync_run)
			shift
			run_task "$@"
			;;

		disk|硬盘管理)
			disk_manager
			;;

		swap)
			shift
			add_swap "$@"
			;;

		time|时区)
			shift
			set_timedate "$@"
			;;

		dns)
			shift
			kpanel_set_dns_noninteractive "$@"
			;;

		ssh-port)
			shift
			kpanel_ssh_port_noninteractive "$@"
			;;

		test|check|体检|测试)
			shift
			if [ "${KJ_TEST_NONINTERACTIVE:-}" = "1" ]; then
				kpanel_run_test_noninteractive "$@"
			else
				linux_test
			fi
			;;

		iptables_open)
			iptables_open
			;;

		打开端口|dkdk)
			shift
			open_port "$@"
			;;

		关闭端口|gbdk)
			shift
			close_port "$@"
			;;

		放行IP|fxip)
			shift
			allow_ip "$@"
			;;

		阻止IP|zzip)
			shift
			block_ip "$@"
			;;

		防火墙|fhq)
			iptables_panel
			;;

		命令收藏夹|fav)
			linux_fav
			;;

		status|状态)
			shift
			status "$@"
			;;
		start|启动)
			shift
			start "$@"
			;;
		stop|停止)
			shift
			stop "$@"
			;;
		restart|重启)
			shift
			restart "$@"
			;;

		enable|autostart|开机启动)
			shift
			enable "$@"
			;;

		docker)
			shift
			case $1 in
				install|安装)
					install_docker
					;;
				ps|容器)
					docker_ps
					;;
				img|镜像)
					docker_image
					;;
				*)
					linux_docker
					;;
			esac
			;;

		kpanel)
			shift
			if [ "${1:-}" = "system-resource" ]; then
				shift
				kpanel_system_resource_dispatch "$@"
			elif [ "${1:-}" = "disk-management" ]; then
				shift
				kpanel_disk_management_dispatch "$@"
			elif [ "${1:-}" = "network-operations" ]; then
				shift
				kpanel_network_operations_dispatch "$@"
			elif [ "${1:-}" = "account-management" ]; then
				shift
				kpanel_account_dispatch "$@"
			elif [ "${1:-}" = "system-tuning" ]; then
				shift
				kpanel_system_tuning_dispatch "$@"
			elif [ "${1:-}" = "virus-scan" ]; then
				shift
				kpanel_virus_scan_dispatch "$@"
			else
				echo "用法: k kpanel system-resource ... | disk-management ... | network-operations ... | account-management ... | system-tuning ... | virus-scan ..." >&2
				return 2 2>/dev/null || exit 2
			fi
			;;

		info)
			linux_info
			;;

		fail2ban|f2b)
			shift
			if [ "$#" -eq 0 ]; then
				fail2ban_panel
			else
				kpanel_f2b_dispatch "$@"
			fi
			;;

		sshkey)

			shift
			case "$1" in
				"" )
					# sshkey → 交互菜单
					sshkey_panel
					;;
				github )
					shift
					fetch_github_ssh_keys "$1"
					;;
				http://*|https://* )
					fetch_remote_ssh_keys "$1"
					;;
				ssh-rsa*|ssh-ed25519*|ssh-ecdsa* )
					import_sshkey "$1"
					;;
				* )
					echo "错误：未知参数 '$1'"
					echo "用法："
					echo "  k sshkey                  进入交互菜单"
					echo "  k sshkey \"<pubkey>\"     直接导入 SSH 公钥"
					echo "  k sshkey <url>            从 URL 导入 SSH 公钥"
					echo "  k sshkey github <user>    从 GitHub 导入 SSH 公钥"
					;;
			esac

			;;
		*)
			k_info
			;;
	esac
fi

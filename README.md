> 这是 kejilion 脚本的个人净化版，不是科技Lion原作者的官方发布。
> 相比原版，本版删除了：偷偷把使用记录和 IP 归属地上传给原作者服务器的“报信”功能、VPS 返利广告与站点引流、自带每小时更新的闭源管理面板、会整体覆盖本地文件的“检查更新”功能；下载改为直连原始站点。
> 除上述删减外，其余功能与原版一致，署名与授权以仓库许可文件为准。

<p align="center">
  <img src="https://kejilion.sh/kejilionsh_logo.webp?v=2" alt="KEJILION.SH 科技lion一键脚本工具" width="620">
</p>

<h1 align="center">KEJILION.SH · 科技lion一键脚本工具</h1>

<p align="center">
  面向 Linux 服务器的综合脚本工具箱，集成系统管理、网络测试、Docker
  与安全防护。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg?style=flat-square" alt="Apache-2.0 License"></a>
</p>

<p align="center">
  <a href="#介绍">介绍</a> ·
  <a href="#一键安装">一键安装</a> ·
  <a href="#支持系统">支持系统</a> ·
  <a href="#效果图预览">效果图预览</a> ·
  <a href="#核心功能">核心功能</a> ·
  <a href="#开源许可">开源许可</a>
</p>

## 介绍

科技Lion 的 Shell 脚本工具是一款 Linux 服务器脚本工具箱，专为系统监控、测试和运维管理而设计。
无论您是初学者还是经验丰富的用户，该工具都能提供便捷的解决方案。脚本集成 Docker
管理与各类系统工具，
让服务器维护更加简单。

KejiLion's Shell script is a toolbox designed for Linux monitoring, testing, and
server management. It brings together Docker management and system tools
in one interactive tool.

## 一键安装

使用 `root` 用户执行以下命令。

```bash
tmp=$(mktemp /tmp/kejilion.XXXXXX.sh) && curl -fsSL -o "$tmp" https://raw.githubusercontent.com/howi3c/sh/main/kejilion.sh && bash "$tmp"
```

这条命令装的是**个人净化版**（脚本从本仓库的 GitHub 直链拉取）；别改成从原作者域名 `kejilion.sh` 拉，那样装回来的是没净化的原版。

这里特意写成「先下载、再运行」：`curl … | bash` 这种管道喂法会让脚本里的选择菜单读不到你的输入（脚本从管道读完了，你的按键就没人听了）；`bash <(curl …)` 则是 bash 专有写法，换到 sh 下会直接报 `Syntax error: "(" unexpected`（精简系统默认 shell 常常是 sh）。下载失败时 curl 也会明确报错，不会静默地把空文件交给 bash。下载先落在 `mktemp` 生成的随机文件名里，避免往 `/tmp` 的固定路径写文件——那类路径可能被人预置成指向别处的符号链接。系统里没有 `curl` 就先装上它。

首次运行时会自动装好 `k` 快捷命令（屏幕有提示），之后直接输入 `k` 就能打开主菜单。

> [!IMPORTANT]
> 脚本包含软件安装、网络、防火墙、磁盘和容器等系统级操作。
> 请在执行前阅读终端提示，并提前备份重要数据、容器和配置。

## 支持系统

<p>
  <img src="https://img.shields.io/badge/Ubuntu-FFB6C1?style=for-the-badge&logo=ubuntu&logoColor=black" alt="Ubuntu">
  <img src="https://img.shields.io/badge/Debian-AFEEEE?style=for-the-badge&logo=debian&logoColor=black" alt="Debian">
  <img src="https://img.shields.io/badge/CentOS-98FB98?style=for-the-badge&logo=centos&logoColor=black" alt="CentOS">
  <img src="https://img.shields.io/badge/Alpine_Linux-ADD8E6?style=for-the-badge&logo=alpinelinux&logoColor=black" alt="Alpine Linux">
  <img src="https://img.shields.io/badge/Kali-D3D3D3?style=for-the-badge&logo=kali-linux&logoColor=black" alt="Kali Linux">
  <img src="https://img.shields.io/badge/Arch-FFFFE0?style=for-the-badge&logo=archlinux&logoColor=black" alt="Arch Linux">
  <img src="https://img.shields.io/badge/Red_Hat-FFE4E1?style=for-the-badge&logo=redhat&logoColor=black" alt="Red Hat">
  <img src="https://img.shields.io/badge/Fedora-FFD700?style=for-the-badge&logo=fedora&logoColor=black" alt="Fedora">
  <img src="https://img.shields.io/badge/AlmaLinux-FFEFD5?style=for-the-badge&logo=almalinux&logoColor=black" alt="AlmaLinux">
  <img src="https://img.shields.io/badge/Rocky_Linux-FFFACD?style=for-the-badge&logo=rocky-linux&logoColor=black" alt="Rocky Linux">
</p>

不同发行版的软件包、网络栈和服务管理方式存在差异，脚本会根据当前系统能力开放对应功能。

## 效果图预览

<p>
  <img src="https://kejilion.sh/img/screenshots/kejilionsh.webp" alt="科技lion一键脚本中文版" width="49%">
  <img src="https://kejilion.sh/img/screenshots/kejilionsh_en.webp" alt="KejiLion Shell Script English Version" width="49%">
</p>

## 核心功能

- **系统信息查询**：快速展示 CPU、内存、磁盘、带宽等运行状态。<br>
  *System status overview: CPU, memory, disk, bandwidth, and more.*
- **系统更新**：更新系统与已安装的组件到当前发行版的最新版本。
- **系统清理**：清理缓存、日志与冗余文件，回收磁盘空间。
- **基础工具**：一键安装 curl、wget、tmux、btop、vim、nano 等常用工具。
- **BBR 管理**：管理内核加速与网络拥塞控制算法。<br>
  *Network acceleration and TCP congestion control optimization.*
- **Docker 管理**：提供容器、镜像、网络、存储卷和日志管理，以及环境备份与还原。<br>
  *Docker management for containers, images, networks, volumes, and logs.*
- **WARP 管理**：管理 Cloudflare WARP 客户端，为出站流量加一层通道。
- **测试脚本合集**：集成测速、回程、延迟、丢包、IP 质量体检等工具。<br>
  *Network tools: speed tests, route tracing, latency, and packet loss tests.*
- **后台工作区**：以 tmux 会话承载常驻任务，SSH 掉线后任务继续运行。
- **系统工具**：SSH 端口、DNS、防火墙、fail2ban 防御、硬盘管理、账号管理与定时任务等本机运维项。
- **服务器集群控制**：多台机器的集中管理与批量操作。

## 项目文档

- [科技lion官方网站](https://kejilion.sh/)

## 使用与安全

- 只从本仓库获取脚本（用上面「一键安装」的命令，或把仓库整个下载到服务器），执行前可先审阅源码。
- 重要数据、Docker 数据和系统配置应定期备份。
- 生产服务器执行升级、卸载、磁盘或网络操作前，应确认终端显示的影响范围。
- 提交问题时，请隐藏密码、Token、私钥和公网 IP 等敏感信息。

## 开源许可

本项目采用 [Apache License 2.0](LICENSE) 开源。


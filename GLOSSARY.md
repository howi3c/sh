# sh（kejilion 脚本净化版）

本仓库是 kejilion 工具箱脚本的个人维护版本：目标是去掉全部“报信”行为和推销内容，同时完整保留安装、测速等正常功能。只动 kejilion.sh，其他脚本以后再说。

## Language

**报信**:
向作者或第三方发出的、内容是关于“你是谁、你的机器什么样”的网络请求——比如使用记录上报、IP 归属地上传。
_Avoid_: 远程遥测、遥测、telemetry
_注_: 面向使用者的菜单标签“无遥测版”是已接受的特例——规格用户故事 15 明文要求标题带此后缀，好让使用者一眼认出净化版。仓库内部（本文档、代码注释、提交信息、议题）仍遵守上面的 _Avoid_ 约束，一律用“报信”，不写成“遥测”。

**取内容**:
为了拿到用户要的东西而发出的网络请求——比如下载安装包、获取测速节点；请求里不夹带任何关于用户的信息。
净化版从本仓库取内容（raw.githubusercontent.com/howi3c/sh/main/…），不再从原作者域名或作者组织下的仓库取，见 ADR-0002。
_Avoid_: 下载请求、联网功能、网络调用

**净化版**:
kejilion.sh 去掉全部报信行为和推销文字之后的状态。
_Avoid_: 去广告版、无广告版、精简版

**原版**:
kejilion 项目作者发布的、未做任何清洗的脚本。
_Avoid_: 上游、官方版、正版

**兄弟文件**:
主脚本之外、与主脚本配套、经 URL 取内容下发给用户机器的文件——比如通知脚本、网络配置文件、公钥文件。
取内容只从本仓库（raw.githubusercontent.com/howi3c/sh/main/…）拿，见 ADR-0002。
_举例（规格 #15 删除后现存 5 个）_: `TG-check-notify.sh` 与 `TG-SSH-check-notify.sh`（TG 通知）、`upgrade_openssh9.8p1.sh`（OpenSSH 升级）、`archive.key`（XanMod 签名钥）、`fail2ban-ssh.conf`（SSH 防御 jail）。
_Avoid_: 配套脚本、附属文件、sibling 文件

**部署文件名**:
兄弟文件下发给用户机器时落盘用的名字，与它在仓库里的文件名可以不同。目前唯一一例：仓库里的 `fail2ban-ssh.conf` 部署到用户机时仍叫 `centos-ssh.conf`（`f2b_install_sshd()` 里的 `--output centos-ssh.conf`），这样改动不牵动用户机上的 jail 文件名与既有配置。
_Avoid_: 目标文件名、落地名

**k 快捷命令**:
安装链把正在运行的脚本本体依次落到 `~/kejilion.sh` 与 `/usr/local/bin/k`，并软链 `/usr/bin/k`；用户在任意目录输入 `k` 即打开主菜单。跑的是磁盘上的脚本文件（`./kejilion.sh`、`bash kejilion.sh`、直接跑 `k`）就以那份文件为本体；本体不在磁盘上（`bash <(curl …)` 管道安装）时，先从本仓库 raw 地址取一份落盘再接上安装链。它靠 PATH 里的命令生效，不是 shell 别名——脚本反而会删掉 `~/.bashrc` 里的 `alias k=`。
_Avoid_: 快捷方式、k 别名、别名 k


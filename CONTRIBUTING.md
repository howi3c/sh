# 贡献与同步规则

## KPanel 轻量节点运行时

- 安装器与生成的更新器共用 `KPANEL_NODE_LIFECYCLE` 模板；不可另写一份锁逻辑。
- 修改更新器、共用锁或 update service/timer 模板时，递增
  `KPANEL_NODE_RUNTIME_GENERATION`，并同步 KPanel 的嵌入模板及其来源校验。
  此数字只用于阻止旧资产回写较新的运行时，不是脚本发布版本号。
- 不删除 `/run/kejilion-node-lifecycle.lock`；卸载保留这个空锁文件，避免锁 inode
  被替换造成两个并发所有者。锁由内核释放，旧 mkdir 锁只允许核对进程后移除空目录。

# Git 常用命令

## 代理设置

```bash
# 设置全局代理
# http
git config --global https.proxy http://127.0.0.1:1080
# https
git config --global https.proxy https://127.0.0.1:1080

# 使用 socks5 代理（ss/ssr，1080 为默认端口）
git config --global http.proxy socks5://127.0.0.1:1080
git config --global https.proxy socks5://127.0.0.1:1080

# 只对 github.com 使用代理
git config --global http.https://github.com.proxy socks5://127.0.0.1:1080
git config --global https.https://github.com.proxy socks5://127.0.0.1:1080

# 取消仅对 github.com 的代理
git config --global --unset http.https://github.com.proxy
git config --global --unset https.https://github.com.proxy

# 取消所有代理
git config --global --unset http.proxy
git config --global --unset https.proxy

# 查看代理
git config --global --get http.proxy
git config --global --get https.proxy
```

## 本地修改回退

```bash
# 丢弃所有本地未提交的修改
git checkout .

# 暂存所有未提交的修改（可用 git stash pop 恢复）
git stash

# 回退到某个 commit（不保留修改）
git reset --hard HASH
# 回退到某个 commit（保留修改在暂存区）
git reset --soft HASH
# 回退到远端最新状态
git reset --hard origin/main

# 删除未跟踪的文件和目录
git clean -df

# git clean 参数说明：
#   -n  演练，展示将要删除的文件（建议先执行此命令）
#   -f  实际删除文件
#   -i  交互模式，逐个确认
#   -d  递归删除未跟踪的目录
#   -q  静默模式，仅显示错误

# 注：
# git reset 处理已跟踪的文件，将已 commit 的内容回退
# git clean 处理未跟踪的文件和目录
```

## Git LFS 常见问题

[Common Git LFS errors and tricks](https://www.yellowduck.be/posts/common-git-lfs-errors-and-tricks)

```bash
git lfs migrate import --yes --no-rewrite "container.zip"
```

# Linux设置git代理github

```
#设置全局代理
#http
git config --global https.proxy http://127.0.0.1:1080
#https
git config --global https.proxy https://127.0.0.1:1080

#使用socks5代理的 例如ss，ssr 1080是windows下ss的默认代理端口,mac下不同，或者有自定义的，根据自己的改
git config --global http.proxy socks5://127.0.0.1:1080
git config --global https.proxy socks5://127.0.0.1:1080

#只对github.com使用代理，其他仓库不走代理
git config --global http.https://github.com.proxy socks5://127.0.0.1:1080
git config --global https.https://github.com.proxy socks5://127.0.0.1:1080

#取消仅对https://github.com设置的代理
git config --global --unset http.https://github.com.proxy
git config --global --unset https.https://github.com.proxy

#取消git对所有网站的代理
git config --global --unset http.proxy
git config --global --unset https.proxy

#查看代理
git config --global --get http.proxy
git config --global --get https.proxy

```

# git丢弃本地修改

```
git checkout . #本地所有修改的。没有的提交的，都返回到原来的状态
git stash #把所有没有提交的修改暂存到stash里面。可用git stash pop回复。

git reset --hard HASH #返回到某个节点，不保留修改，已有的改动会丢失。
git reset --soft HASH #返回到某个节点, 保留修改，已有的改动会保留，在未提交中，git status或git diff可看。
git reset --hard origin/main #返回到远端状态

git clean -df #返回到某个节点，（未跟踪文件的删除）
git clean 参数
    -n 不实际删除，只是进行演练，展示将要进行的操作，有哪些文件将要被删除。（可先使用该命令参数，然后再决定是否执行）
    -f 删除文件
    -i 显示将要删除的文件
    -d 递归删除目录及文件（未跟踪的）
    -q 仅显示错误，成功删除的文件不显示


注：
git reset 删除的是已跟踪的文件，将已commit的回退。
git clean 删除的是未跟踪的文件

```

# Encountered x file(s) that should have been pointers, but weren't

[Common Git LFS errors and tricks](https://www.yellowduck.be/posts/common-git-lfs-errors-and-tricks)

```
$ git lfs migrate import --yes --no-rewrite "container.zip"
migrate: changes in your working copy will be overridden ...
migrate: checkout: ..., done.       
```

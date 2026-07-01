# Debian 上拉取与推送 GitHub 私有仓库教程日记

> 适用环境：Debian 11 / 12  
> 前置条件：拥有一个 GitHub 账号，且已有（或准备创建）私有仓库

---

## 一、安装 Git

先更新包列表并安装 Git：

```bash
sudo apt update
sudo apt install git -y
```

验证安装：

```bash
git --version
# 输出类似：git version 2.39.5
```

---

## 二、生成 SSH 密钥对

> 为什么用 SSH 而不是 HTTPS？  
> GitHub 在 2021 年 8 月后已禁用密码认证，SSH 密钥是最便捷安全的方式。私有仓库的认证等同于"你持有对应的私钥"，无需每次输入密码。

在终端中执行（将邮件替换成你 GitHub 账号的邮箱）：

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

按回车后会有以下交互：

```
Enter file in which to save the key (/home/username/.ssh/id_ed25519):
```
→ 直接回车，使用默认路径。

```
Enter passphrase (empty for no passphrase):
```
→ 输入一个密码短语（推荐设置），或直接回车留空。

```
Enter same passphrase again:
```
→ 再次确认。

完成后会在 `~/.ssh/` 下生成两个文件：
- `id_ed25519` —— 私钥（**绝对不能泄露**）
- `id_ed25519.pub` —— 公钥（可以安全分享给 GitHub）

---

## 三、将 SSH 密钥添加到 ssh-agent

启用 ssh-agent 并添加私钥：

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

如果设置了密码短语，这里会要求输入一次。之后当前会话中重复使用就不再需要输入了。

---

## 四、将公钥添加到 GitHub

### 4.1 复制公钥内容

```bash
cat ~/.ssh/id_ed25519.pub
```

输出类似：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx your-email@example.com
```

复制整行内容。

### 4.2 添加到 GitHub 账号

1. 登录 [GitHub](https://github.com)
2. 点击右上角头像 → **Settings**
3. 左侧菜单 → **SSH and GPG keys**
4. 点击绿色按钮 **New SSH key**
5. Title：填写一个辨识名，例如 `Debian-Server`
6. Key type：保持 `Authentication Key`
7. Key：粘贴刚才复制的公钥内容
8. 点击 **Add SSH key**
9. 如果 GitHub 要求确认密码，输入你的 GitHub 账户密码即可

---

## 五、测试 SSH 连接

```bash
ssh -T git@github.com
```

> 注意：用户名必须写 `git`，不要写成你自己的 GitHub 用户名。

如果弹出一条 "Are you sure you want to continue connecting" 的提示，输入 `yes`。

成功后的输出：

```
Hi your-username! You've successfully authenticated, but GitHub does not provide shell access.
```

这说明认证已经通过！

---

## 六、配置 Git 用户信息

```bash
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
```

验证：

```bash
git config --global --list
```

---

## 七、克隆私有仓库

找到 GitHub 上私有仓库的 SSH 地址，格式为：

```
git@github.com:username/repo-name.git
```

在 GitHub 仓库页面点击 **Code** 按钮，选择 **SSH** 标签即可复制。

执行克隆：

```bash
cd ~
git clone git@github.com:username/repo-name.git
cd repo-name
```

如果一切正常，私有仓库的代码已经被拉取到本地。

---

## 八、修改文件并提交

### 8.1 做一些修改

```bash
echo "# 测试提交" >> README.md
```

### 8.2 查看状态

```bash
git status
```

### 8.3 暂存并提交

```bash
git add README.md
git commit -m "docs: 添加测试提交记录"
```

---

## 九、推送到远程仓库

```bash
git push origin main
```

> 注意：有些仓库的默认分支是 `master`，请根据实际情况替换。可以用 `git branch` 查看当前分支名。

如果输出类似以下内容，说明推送成功：

```
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Writing objects: 100% (3/3), 295 bytes | 295.00 KiB/s, done.
Total 3 (delta 0), reused 0 (delta 0), pack-reused 0
To github.com:username/repo-name.git
   abc1234..def5678  main -> main
```

此时刷新 GitHub 仓库页面，就能看到最新的提交了 🎉

---

## 十、常见问题排查

### 10.1 Permission denied (publickey)

**错误信息：**
```
git@github.com: Permission denied (publickey).
```

**原因：** SSH 密钥未正确配置或未添加到 GitHub。

**解决办法：**
1. 确认 ssh-agent 已加载密钥：`ssh-add -l`
2. 确认公钥已添加到 GitHub（Settings → SSH and GPG keys）
3. 用 `ssh -Tv git@github.com` 查看详细诊断信息

### 10.2 使用多个 GitHub 账号

如果你在同一台机器上需要使用多个 GitHub 账号，可以生成不同的密钥并配置 SSH config 文件：

生成另一个密钥：

```bash
ssh-keygen -t ed25519 -C "work-email@example.com" -f ~/.ssh/id_ed25519_work
```

编辑 `~/.ssh/config` 文件（没有则创建）：

```
# 个人账号
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

# 工作账号
Host github.com-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
```

克隆工作仓库时，将 `github.com` 替换为 `github.com-work`：

```bash
git clone git@github.com-work:your-company/repo.git
```

### 10.3 克隆时报超时

**错误信息：**
```
ssh: connect to host github.com port 22: Connection timed out
```

**原因：** 部分网络环境封锁了 22 端口。

**解决办法：** 使用 HTTPS 端口 443 进行 SSH 通信。

编辑 `~/.ssh/config`：

```
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
```

保存后再次测试：

```bash
ssh -T git@github.com
```

### 10.4 推送时提示远程有更新

**错误信息：**
```
! [rejected] main -> main (fetch first)
```

**原因：** 远程仓库有本地不包含的提交。

**解决办法：** 先拉取再推送：

```bash
git pull origin main --rebase
git push origin main
```

### 10.5 每次推拉都要输入密码短语

如果你创建 SSH 密钥时设置了 passphrase，但不想每次都输入，可以让 ssh-agent 记住它。正常情况下 `ssh-add` 后当前会话不需要重复输入。如果想开机自动加载，可以将以下内容添加到 `~/.bashrc`：

```bash
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519
fi
```

---

## 附：完整操作速查

```bash
# 1. 安装 Git
sudo apt update && sudo apt install git -y

# 2. 生成密钥
ssh-keygen -t ed25519 -C "your-email@example.com"

# 3. 加载密钥
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519

# 4. 复制公钥（手动添加到 GitHub）
cat ~/.ssh/id_ed25519.pub

# 5. 测试连接
ssh -T git@github.com

# 6. 配置用户
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# 7. 克隆私有仓库
git clone git@github.com:username/repo-name.git

# 8. 修改 → 提交 → 推送
cd repo-name
# ... 做一些修改 ...
git add .
git commit -m "描述你的改动"
git push origin main
```

---

*记录日期：2026-07-01*
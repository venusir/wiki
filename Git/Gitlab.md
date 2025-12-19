## 配置

```
package['modify_kernel_parameters'] = false        # 防止在LXC容器中修改内核时报错
external_url 'https://example.com:10080'           # 代理后的域名
gitlab_rails['gitlab_shell_ssh_port'] = 10022      # 代理显示的 SSH 端口
nginx['enable'] = false                            # 禁用内置 Nginx
gitlab_workhorse['listen_network'] = "tcp"         # 仅保留 Workhorse 监听
gitlab_workhorse['listen_addr'] = "0.0.0.0:10080"  #修改监听地址 
```
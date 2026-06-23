这是一份为您专门整理的 **“基于 Cloudflare Workers + Axiom 实现免费域名访问日志收集”** 的完整流程与详细步骤指南。您可以直接将其复制到您的日记或笔记软件（如 Notion、Obsidian 或本地 Markdown 文件）中进行存档。

# 📝 技术存档：基于 CF Workers + Axiom 搭建域名访问日志系统

## 📌 项目概述

由于 Cloudflare 免费版计划不提供原始访问日志（Raw Logs）的查看与下载权限，本项目通过编写轻量级的 **Cloudflare Worker** 充当透明流量监视器，利用其 `ctx.waitUntil` 异步非阻塞特性，在**零增加网站延迟、零成本**的前提下，将精细的结构化访客日志（包含 IP、URL、状态码、User-Agent 等）实时推送到免费额度极大的 **Axiom** 日志平台进行长期存储与可视化分析。

## 🛠️ 详细部署步骤

### 第一步：准备 Axiom 日志接收端（获取配置参数）

1. **注册账号**：访问 [Axiom 官网 (axiom.co)](https://axiom.co/)，注册并登录免费版账号（每月享有 500 GB 免费写入额度）。
    
2. **创建数据集 (Dataset)**：
    
    - 进入 Axiom 控制台，点击左侧菜单栏的 **Datasets**。
        
    - 点击 **Create Dataset**，命名为一个好记的名字（例如：`cloudflare-logs`），然后点击创建。
        
    - _记录下这个 Dataset 名称，后续将其填入代码中的 `AXIOM_DATASET`_。
        
3. **创建 API Token**：
    
    - 点击左侧菜单底部的 **Settings** -> 选择 **API Tokens**。
        
    - 点击 **Create Token**，输入 Token 名称。
        
    - **关键权限**：在权限配置中，确保为该 Token 赋予 **Ingest**（写入）权限。
        
    - 点击生成后，复制保存完整的 Token 字符串（形式通常为 `xat-xxxxxx...`）。
        
    - _后续将其填入代码中的 `AXIOM_TOKEN`_。
        

### 第二步：创建并配置 Cloudflare Worker

1. **新建 Worker**：
    
    - 登录 [Cloudflare 控制台](https://dash.cloudflare.com/)。
        
    - 在左侧主菜单中导航至 **AI 与 Worker (Workers & Pages)**。
        
    - 点击 **创建 (Create)** -> **创建 Worker (Create Worker)**。
        
    - 为 Worker 命名（例如：`domain-logger`），点击底部的 **部署 (Deploy)**。
        
2. **编写与修改代码**：
    
    - 部署完成后，点击 **编辑代码 (Edit Code)** 进入在线 Web IDE 编辑器。
        
    - 清空原有全部默认代码，将下方的【完整生产代码】完整粘贴进去。
        
    - 根据第一步获取的参数，修改代码中的 `AXIOM_DATASET` 和 `AXIOM_TOKEN`（注意保留 `Bearer` 前缀）。
        
    - 点击右上角的 **部署 (Deploy)** 保存代码。
        

### 第三步：配置流量路由绑定与 DNS 代理

为了让访问域名的流量能够触发该 Worker，必须在 Cloudflare 内部配置路由规则。

1. **添加路由规则**：
    
    - 点击编辑器左上角箭头返回 Worker 管理主界面。
        
    - 切换到 **设置 (Settings)** 选项卡 -> 选择左侧的 **触发器 (Triggers)**。
        
    - 在 **路由 (Routes)** 区域点击 **添加路由 (Add Route)**。
        
    - **路由 (Route)**：输入 `example.com/*`（_将 `example.com` 替换为您自己的域名，末尾的 `/*` 代表拦截该域名下的所有子路径和资源_）。
        
    - **区域 (Zone)**：选择该域名所属的托管区域。
        
    - 点击 **保存 (Save)**。
        
2. **检查 DNS 代理状态（关键）**：
    
    - 返回 Cloudflare 首页，点击进入您的**域名配置**。
        
    - 选中左侧的 **DNS** -> **记录 (Records)**。
        
    - 检查刚刚绑定路由的域名记录（如 `A` 或 `CNAME`），确保其 **代理状态 (Proxy status)** 为 **已代理 (Proxied)**（显示为橙色小黄云 ☁️）。如果是灰色云朵（仅限 DNS），请点击编辑并开启代理，否则流量不会经过 Worker。
        

## 💻 完整生产代码

JavaScript

```
/**
 * ==============================================================================
 * 【脚本功能】
 * 本脚本是一个高级流量监控代理（Logger）。它拦截经过 Cloudflare CDN 的所有请求，
 * 异步将访问日志实时投递至第三方日志平台 Axiom。
 * * 【本次更新】
 * 1. 修正了 `host` 字段的提取逻辑：直接从 HTTP 请求头获取用户实际访问的域名（Host），
 * 而不是 Worker 自身的节点地址。
 * 2. 优化了 `url` 字段，移除了域名前缀，仅保留路径与查询参数（如 `/index.html?id=1`）。
 * 3. 继续保持对环境变量（AXIOM_DATASET, AXIOM_TOKEN）的支持和 User-Agent 的智能精简。
 * * 【使用方法】
 * 1. 将本脚本全部代码复制并替换进 Cloudflare Worker。
 * 2. 确保在 Worker 的「Settings」->「Variables」中配置了 `AXIOM_DATASET` 和 `AXIOM_TOKEN`。
 * ==============================================================================
 */

export default {
  async fetch(request, env, ctx) {
    // 1. 正常放行请求，获取源站或缓存的响应
    const response = await fetch(request);

    // 2. 提取并智能优化 User-Agent 字段
    const rawUserAgent = request.headers.get('User-Agent') || 'Unknown';
    let shortUserAgent = rawUserAgent;
    
    if (rawUserAgent.includes('Googlebot')) shortUserAgent = 'Bot: Googlebot';
    else if (rawUserAgent.includes('Bingbot')) shortUserAgent = 'Bot: Bingbot';
    else if (rawUserAgent.includes('curl')) shortUserAgent = 'Tool: curl';
    else if (rawUserAgent.includes('Go-http-client')) shortUserAgent = 'Tool: Go-client';
    else {
      // 普通浏览器日志太长，只截取前 60 个字符，兼顾识别度和存储体积
      shortUserAgent = rawUserAgent.length > 60 ? rawUserAgent.substring(0, 60) + '...' : rawUserAgent;
    }

    // 3. 解析 URL，仅保留路径和参数
    const urlObj = new URL(request.url);
    const cleanUrl = urlObj.pathname + urlObj.search;

    // 4. 【核心修正】提取用户实际访问的网站地址（Host 头）
    // 如果获取不到，则降级使用 url 中的 hostname
    const actualHost = request.headers.get('Host') || urlObj.hostname;

    // 5. 构造符合 Axiom 接收格式的结构化日志对象
    const logData = [{
      _time: new Date().toISOString(),
      host: actualHost,                    // 【已修正】用户实际访问的地址（如 www.yourdomain.com）
      url: cleanUrl,                       // 仅保留路径与参数（如 /posts/123）
      method: request.method,
      status: response.status,
      ip: request.headers.get('CF-Connecting-IP'),
      country: request.cf?.country || 'Unknown',
      colo: request.cf?.colo || 'Unknown',
      userAgent: shortUserAgent,
    }];

    // 6. 检查环境变量并异步投递日志
    if (env.AXIOM_DATASET && env.AXIOM_TOKEN) {
      const axiomEndpoint = `https://api.axiom.co/v1/datasets/${env.AXIOM_DATASET}/ingest`;

      ctx.waitUntil(
        fetch(axiomEndpoint, {
          method: 'POST',
          headers: { 
            'Content-Type': 'application/json',
            'Authorization': env.AXIOM_TOKEN
          },
          body: JSON.stringify(logData),
        }).then(res => {
          if (!res.ok) {
            console.error('Axiom 投递失败，状态码:', res.status);
          }
        }).catch(err => console.error('Axiom 网络错误:', err))
      );
    } else {
      console.warn('Worker 环境变量 AXIOM_DATASET 或 AXIOM_TOKEN 未配置，日志未投递。');
    }

    // 7. 立即为访客返回网页响应
    return response;
  },
};
```

## 🔍 验证与日常维护

1. **实时验证**：
    
    - 打开浏览器，访问您的域名（例如 `https://example.com/any-path`）。
        
    - 登录 Axiom Dashboard，进入 **Explorer** 页面。
        
    - 在上方选择对应的数据集，点击 **Run Query**，即可在下方看到精确到毫秒级的结构化请求明细。
        
2. **性能与开销说明**：
    
    - **延迟零隐患**：由于 `ctx.waitUntil` 的作用，Worker 在执行 `return response` 之后才会在后台建立与 Axiom 的网络连接，对客户端白屏时间和下载速度**完全没有任何负面影响**。
        
    - **额度消耗**：Cloudflare Worker 免费版每日提供 10 万次免费请求额度。如果网站日 PV 超过 10 万，Worker 将会报错截断或停止日志收集，如需更大规模需监控额度或升级。Axiom 端由于每月有 500 GB 额度，对于个人日志来说极其充裕。
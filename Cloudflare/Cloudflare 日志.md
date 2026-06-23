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
 * 本脚本是一个轻量级的流量监控代理（Logger）。它拦截经过 Cloudflare CDN 的所有请求，
 * 在不影响用户访问速度的前提下，异步将访问日志（含 IP、URL、状态码、User-Agent 等）
 * 实时投递至第三方高性能日志平台 Axiom 进行存储与分析。
 * * 【使用方法与获取路径详见存档指南】
 * ==============================================================================
 */

export default {
  async fetch(request, env, ctx) {
    // ================== 【用户配置区】 ==================
    // 1. 替换为你在 Axiom 创建的数据集(Dataset)名称
    const AXIOM_DATASET = 'cloudflare-logs'; 
    
    // 2. 替换为你在 Axiom 申请的具有 Ingest 权限的 API Token
    const AXIOM_TOKEN = 'Bearer xat-xxxxxx你的Token';
    // ====================================================

    // 1. 正常放行请求，获取源站或缓存的响应
    const response = await fetch(request);

    // 2. 构造符合 Axiom 接收格式的日志对象（必须放入一个数组中）
    const logData = [{
      _time: new Date().toISOString(), // Axiom 推荐使用 _time 作为主时间戳字段
      ip: request.headers.get('CF-Connecting-IP'),
      country: request.cf?.country || 'Unknown',
      colo: request.cf?.colo || 'Unknown', // 流量经过的 Cloudflare 边缘数据中心机场码（如 HKG, SFO）
      url: request.url,
      method: request.method,
      status: response.status,
      userAgent: request.headers.get('User-Agent'),
    }];

    // 3. 拼接 Axiom 官方的标准 Ingest API 地址
    const axiomEndpoint = `https://api.axiom.co/v1/datasets/${AXIOM_DATASET}/ingest`;

    // 4. 使用 ctx.waitUntil 纯异步发送到 Axiom
    // 这样能保证日志投递在后台静默执行，完全不增加用户下载网页的延迟
    ctx.waitUntil(
      fetch(axiomEndpoint, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Authorization': AXIOM_TOKEN
        },
        body: JSON.stringify(logData), // Axiom 接收数组格式的 JSON 投递
      }).then(res => {
        if (!res.ok) {
          console.error('Axiom 日志投递失败，状态码:', res.status);
        }
      }).catch(err => console.error('网络错误，日志发送失败:', err))
    );

    // 5. 立即为访客返回网页响应
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
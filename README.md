# 读书谈 · 共读资源站

在线共读社群资源网站。单文件应用，零构建，零服务器。

## 技术栈

- **前端**：单文件 HTML（内联 CSS + JS）
- **后端**：Supabase（认证、数据库、存储）
- **CDN**：Inter + Noto Serif SC 字体、Lucide Icons、marked.js、dayjs、Supabase JS SDK

## 部署步骤

### 1. 创建 Supabase 项目

1. 访问 [supabase.com](https://supabase.com) 注册/登录
2. 创建新项目，记下 **Project URL** 和 **anon public key**
3. 进入 SQL Editor，粘贴 `supabase-schema.sql` 的全部内容并执行
4. 进入 Authentication → Settings：
   - 启用 Email 登录（关闭 "Confirm email" 可跳过邮箱验证，方便测试）

### 2. 配置 Supabase 密钥

编辑 `index.html` 顶部 `<script type="module">` 中的两行：

```javascript
const SUPABASE_URL = 'YOUR_SUPABASE_URL';       // 替换为你的 Project URL
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY'; // 替换为你的 anon key
```

### 3. 部署到静态托管

将项目文件夹部署到任意静态托管服务：

- **Netlify**：拖拽文件夹到 netlify.com
- **Vercel**：`vercel` 命令部署
- **GitHub Pages**：推送到 GitHub 开启 Pages
- **Cloudflare Pages**：连接 Git 仓库自动部署

### 4. 设置管理员

1. 在网站上注册一个账号（邮箱注册）
2. 进入 Supabase → Table Editor → `profiles` 表
3. 找到你的记录，将 `role` 改为 `admin`
4. 刷新网站，即可看到"管理"入口

## 功能清单

| 功能 | 说明 |
|------|------|
| 首页 | 共读计划介绍 + 群规 + 当前共读书籍 |
| 书库 | 按类型/状态筛选，详情页汇聚全部共读信息 |
| 活动库 | 线下活动展示（海报/地点/嘉宾/价格） |
| 个人中心 | 资料编辑 + 每日阅读签到日历 |
| 管理后台 | 群规、书籍、活动 CRUD |
| 移动适配 | 375px-1440px 响应式，汉堡菜单 |

## 文件说明

| 文件 | 用途 |
|------|------|
| `index.html` | 主应用（单文件） |
| `supabase-schema.sql` | 数据库建表 + 种子数据 |
| `README.md` | 本文件 |

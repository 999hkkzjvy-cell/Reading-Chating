# 以读攻独 · 共读资源站

在线共读社群资源网站。前端零构建，后端使用 Supabase（数据库、认证、存储、Edge Functions）。

## 技术栈

- **前端**：零构建原生 ES Modules（`index.html` + `src/*.js` + `src/styles.css`）
- **后端**：Supabase（认证、数据库、存储、Edge Functions）
- **CDN**：Inter + Noto Serif SC 字体、Lucide Icons、marked.js、dayjs、Supabase JS SDK

## 部署步骤

### 1. 创建 Supabase 项目

1. 访问 [supabase.com](https://supabase.com) 注册/登录
2. 创建新项目，记下 **Project URL** 和 **anon public key**
3. 进入 SQL Editor，粘贴 `sql/supabase-schema.sql` 的全部内容并执行
4. 进入 Authentication → Settings：
   - 启用 Email 登录（关闭 "Confirm email" 可跳过邮箱验证，方便测试）

### 2. 部署 Edge Functions

项目包含 4 个 Supabase Edge Functions：

| 函数 | 用途 |
|------|------|
| `deepseek-proxy` | 管理员添加书籍时调用 AI 生成简介 |
| `scrape-douban` | 管理员同步豆瓣新书速递 |
| `fetch-douban-book` | 获取豆瓣单本书元信息并写入缓存 |
| `img-proxy` | 代理豆瓣封面图，避免外链图片失效 |

部署：

```bash
supabase functions deploy deepseek-proxy
supabase functions deploy scrape-douban
supabase functions deploy fetch-douban-book
supabase functions deploy img-proxy
```

设置密钥：

```bash
supabase secrets set DEEPSEEK_API_KEY=sk-xxx
supabase secrets set SB_SERVICE_ROLE_KEY=你的-service-role-key
```

`deepseek-proxy` 和 `scrape-douban` 只允许管理员调用；普通用户可以浏览新书和投票，但不能触发抓取或消耗 AI 额度。

### 3. 配置 Supabase 公钥

编辑 `src/config.js`：

```javascript
export const SUPABASE_URL = 'YOUR_SUPABASE_URL';
export const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

### 4. 部署到静态托管

将项目文件夹部署到任意静态托管服务：

- **Netlify**：拖拽文件夹到 netlify.com
- **Vercel**：`vercel` 命令部署
- **GitHub Pages**：推送到 GitHub 开启 Pages
- **Cloudflare Pages**：连接 Git 仓库自动部署

### 5. 设置管理员

1. 在网站上注册一个账号（邮箱注册）
2. 进入 Supabase → Table Editor → `profiles` 表
3. 找到你的记录，将 `role` 改为 `admin`
4. 刷新网站，即可看到"管理"入口

### 6. 现有数据库升级

如果你已经部署过旧版本，请按顺序执行尚未部署过的 `sql/migrate-v*.sql`。当前主要迁移包括：

- v5 增加新书速递和想共读投票
- v7 增加豆瓣书籍详情缓存，并收紧缓存写入权限
- v8 收紧用户资料读取权限，微信号等私密字段只允许本人和管理员读取
- v9-v12 增加会员等级、票券、徽章展示和周贡献排名
- v13-v18 增加书友圈、贡献值、摘抄/心情/评分和动态编辑
- v19-v24 增加点赞评论、个人主页、贡献榜、消息通知和评论防刷

更详细的部署顺序见 `sql/deploy-order.md`。

## 功能清单

| 功能 | 说明 |
|------|------|
| 首页 | 共读计划介绍 + 群规 + 当前共读书籍 |
| 书库 | 按类型/状态筛选，详情页汇聚全部共读信息 |
| 活动库 | 线下活动展示（海报/地点/嘉宾/价格） |
| 会员中心 | 等级、贡献值、徽章、票券、已解锁资源 |
| 资料与签到 | 资料编辑 + 每日阅读签到日历 |
| 书友圈 | 阅读动态、摘抄/感想、心情、评分、点赞、评论、贡献榜 |
| 管理后台 | 群规、书籍、活动 CRUD |
| 新书速递 | 豆瓣新书同步 + 想共读投票 |
| 西语文学 | 拉丁美洲文学互动地图 |
| 移动适配 | 375px-1440px 响应式，汉堡菜单 |

## 文件说明

| 文件 | 用途 |
|------|------|
| `index.html` | 应用壳、导航、CDN 脚本和样式入口 |
| `src/app.js` | 应用初始化、首页路由和全局事件 |
| `src/config.js` | Supabase 项目 URL 和 anon key |
| `src/*.js` | 前端页面、路由、数据访问和交互模块 |
| `sql/supabase-schema.sql` | 数据库建表 + 种子数据 |
| `sql/migrate-v*.sql` | 数据库升级脚本 |
| `sql/deploy-order.md` | 当前推荐 SQL 部署顺序 |
| `supabase/functions/*/index.ts` | Supabase Edge Functions |
| `README.md` | 本文件 |

## 本地检查

项目没有构建步骤。提交前建议运行：

```bash
npm run check
```

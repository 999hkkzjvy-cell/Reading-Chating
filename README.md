# 以读攻独 · 共读资源站

> 用阅读抵御孤独，遇见同频的书友。有深度、有温度的线上共读社群。

---

## 项目概览

以读攻独是一个面向西语文学与深度阅读爱好者的线上共读社群网站，支持书籍管理、共读活动、书友圈交流、会员成长、票券权限、徽章谜面与个人书库。

- **Supabase 项目**：`zugadhgezmqrnlwogomw`
- **技术栈**：原生 SPA（HTML + CSS + ES Modules）+ Supabase（Auth / DB / Storage / Edge Functions）
- **CDN 依赖**：Inter + Noto Serif SC / Lucide Icons / marked.js / DOMPurify / dayjs / Leaflet.js

---

## 功能概览

### 核心功能
- 📚 **共读书库**：书籍 CRUD 管理后台（结构化字段 + JSONB 构建器）、详情页多标签（简介/领读人/版本建议/时间计划/加入我们/活动安排/资源材料/聊天干货）
- 🗓️ **线下活动**：活动管理（CRUD）、8 种分类标签、活动状态按钮（回放/会议/敬请期待）
- 🆕 **新书速递**：豆瓣新书速递抓取前 3 页，缓存约 60 本，前台展示最新 Top 10、想共读投票与排行榜
- 🌎 **西语文学专区**：Leaflet.js + world-atlas + CARTO 底图的拉丁美洲文学交互地图
- 🧾 **聊天干货**：默认折叠、按序展示、权限保护、PDF 附件上传与查看

### 会员系统
- 🏅 **16 级会员等级**（Lv.1-Lv.16）：自动升级/降级、等级徽章发放与回收
- ⭐ **贡献值系统**：书友圈/已读/字数/精选/点赞/评论计分、贡献值流水
- 🎫 **票券系统**：资源浏览券（临时解锁 72h）、共读兑换券（永久解锁）、共读密码核销
- 🏆 **贡献排行榜**：总榜/月榜/周榜横向三列，周榜/月榜按当前自然周期实时汇总
- 🔔 **消息通知**：铃铛+红点+下拉面板+历史补录+定位跳转
- 📚 **我的书库**：已读书目、想读书目、人生之书，个人主页可公开展示

### 书友圈
- ✍️ **阅读动态**：想读/在读/已读/摘抄/感想/书评、已读评分（-10~10+emoji）
- 💬 **点赞评论**：点赞与评论贡献值、多级回复、评论防刷、通知去重
- ✏️ **动态编辑**：修改已发布内容
- 🔒 **可见性控制**：公开/仅自己可见/好友可见
- 👥 **好友系统**：关注/取关、好友动态、搜索书友圈、关注列表+粉丝列表
- 📌 **长文折叠**：摘抄、感想、书评默认显示摘要，可展开全文

### 徽章系统
- 🎖️ **17 枚徽章**：16 枚等级成长徽章 + 1 枚开创者权限徽章
- 🔄 **徽章翻面**：徽章背面图上传+预览弹窗翻转展示
- 🧩 **成就谜面答题**（v31）：每枚徽章配谜面诗、答对奖励 10 贡献值
- 🖼️ **自定义徽章展示**：用户可自选展示徽章

### 安全与权限
- 🔐 **Supabase Auth**：注册/登录、拼图验证码
- 🛡️ **RLS 安全**：行级安全策略、服务端权限验证
- 🔒 **资源权限**：受保护资源预览+临时解锁+永久解锁+开创者全开
- 🚫 **用户封禁**：管理员可封禁/解锁账号，限制书库、书友圈与西语文学板块访问/发帖
- 🧹 **安全加固**：DOMPurify/HTML 转义/CSP/CDN 锁定/href 防注入

---

## 项目结构

```
.
├── index.html              # 主入口 SPA
├── src/
│   ├── app.js              # 应用初始化
│   ├── router.js           # 路由系统
│   ├── store.js            # 全局状态管理
│   ├── config.js           # 配置常量
│   ├── constants.js        # 静态常量
│   ├── supabaseClient.js   # Supabase 客户端
│   ├── auth.js             # 认证模块
│   ├── authPages.js        # 登录/注册页面
│   ├── ui.js               # UI 工具
│   ├── utils.js            # 通用工具
│   ├── components.js       # 通用组件
│   ├── styles.css          # 全局样式
│   ├── books.js            # 书籍
│   ├── events.js           # 活动
│   ├── newBooks.js         # 新书速递
│   ├── latam.js            # 西语文学地图
│   ├── profile.js          # 个人资料
│   ├── memberCenter.js     # 会员中心
│   ├── memberSystemInfo.js # 会员系统说明页
│   ├── members.js          # 会员数据加载
│   ├── badgeRiddles.js     # 徽章谜面配置
│   ├── readingPosts.js     # 书友圈
│   ├── readingPostApi.js   # 书友圈 API
│   ├── readingPostCards.js # 书友圈卡片
│   ├── readingPostCalendar.js # 书友圈日历
│   ├── readingPostUtils.js # 书友圈工具
│   ├── access.js           # 资源权限
│   ├── tickets.js          # 票券
│   ├── uploads.js          # 文件上传
│   ├── captcha.js          # 验证码
│   ├── data.js             # 数据预取
│   └── admin.js            # 管理后台
├── supabase/
│   └── functions/          # Edge Functions：豆瓣抓取、封面代理、AI 代理等
├── sql/
│   ├── current-files/      # 当前全部单独迁移 SQL 归档
│   └── final-init/         # 新数据库从 0 初始化 SQL
│       └── 00-full-init.sql
└── ignore files/           # 本地资料区，不上传云端
    ├── AI-CONTEXT.md       # AI 开工上下文
    ├── Coding Log.md       # 本地开发日志
    ├── Deployment-Plan.md  # 本地部署规划
    ├── badges/             # 徽章终稿、谜面、提示词、开发方案
    └── books/              # 按书目归档的 seed 数据
```

---

## 数据库部署

当前数据库迁移整理到 **v46**（2026-07-12）。

- 新数据库从 0 开始：执行 [sql/final-init/00-full-init.sql](sql/final-init/00-full-init.sql)
- 现有数据库增量升级：参考 [sql/current-files/deploy-order.md](sql/current-files/deploy-order.md)
- 书籍种子数据：位于本地 `ignore files/books/`，按书目独立归档，不上传云端
- 新书速递排序字段：`migrate-v46-new-books-source-order.sql` 增加 `source_rank` / `source_page`，用于按豆瓣源页面顺序稳定展示

---

## 快速开始

1. 部署 Supabase 项目，获取 API URL 和 anon key
2. 新库执行 [00-full-init.sql](sql/final-init/00-full-init.sql)，旧库按 [deploy-order.md](sql/current-files/deploy-order.md) 增量执行
3. 在 `src/supabaseClient.js` 中配置 Supabase 连接
4. 配置 Supabase Storage bucket，用于头像、徽章、聊天干货 PDF 等文件
5. 配置 Edge Functions（豆瓣抓取、图片代理等）
   - 当前项目实际部署命令：
     ```bash
     npx supabase@latest functions deploy scrape-douban --project-ref zugadhgezmqrnlwogomw --use-api
     ```
   - `scrape-douban` 需要设置 `SB_SERVICE_ROLE_KEY` secret，用于服务端写入新书缓存
6. 部署静态文件至 GitHub Pages、Supabase Storage 或其他静态托管平台

---

## 近期更新

- **2026-07-12**：新书速递抓取逻辑升级：抓取豆瓣新书前 3 页，缓存约 60 本，前台只展示最新 Top 10；修复无评分新书被误显示为评价人数的问题；Edge Function 推荐使用 `--use-api` 部署。
- **2026-07-12**：手机端 UI 优化，调整导航、筛选、弹窗、评论、书籍详情与新书卡片的移动端布局。
- **2026-07-12**：西语文学专区拉丁美洲地图修复移动端打开问题，改进 Leaflet 动态资源加载、地图尺寸刷新与失败提示。
- **2026-07-06**：SQL 文件归档，新增新数据库最终初始化脚本；周榜/月榜改为实时按当前自然周期计算；聊天干货自动换行修复。
- **2026-07-06**：下线旧每日签到前端与 `daily_checkins` 表，阅读记录统一进入书友圈体系。
- **2026-07-06**：聊天干货支持折叠展开、PDF 附件、后台排序；补全《红楼梦》领读文档 seed。
- **2026-07-05**：书友圈长文折叠与保存位置保持。
- **2026-07-03**：我的书库、个人主页公开书库、书库展示布局优化。
- **2026-07-02**：管理员封禁/解锁、主动互动贡献值、书友搜索、关注/升级通知、首页与详情页性能优化。

---

## 开发日志

本地详见 `ignore files/Coding Log.md`。

## AI 协作上下文

本地详见 `ignore files/AI-CONTEXT.md`。后续和 AI 协作时，建议先让 AI 阅读这份文档，再按任务读取相关模块。

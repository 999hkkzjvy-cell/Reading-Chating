# 以读攻独 · 共读资源站

> 用阅读抵御孤独，遇见同频的书友。有深度、有温度的线上共读社群。

---

## 项目概览

以读攻独是一个面向西语文学爱好者的线上共读社群网站，支持书籍管理、共读活动、书友圈交流、会员成长与徽章系统。

- **网站地址**：https://zugadhgezmqrnlwogomw.supabase.co
- **技术栈**：单文件 SPA（HTML+CSS+JS）+ Supabase（Auth / DB / Storage / Edge Functions）
- **CDN 依赖**：Inter + Noto Serif SC / Lucide Icons / marked.js / DOMPurify / dayjs / Leaflet.js

---

## 功能概览

### 核心功能
- 📚 **共读书库**：书籍 CRUD 管理后台（21 字段 + JSONB 构建器）、详情页 6 标签（简介/领读人/版本建议/时间计划/活动安排/资源材料）
- 🗓️ **线下活动**：活动管理（CRUD）、8 种分类标签、活动状态按钮（回放/会议/敬请期待）
- 📖 **每日签到**：打卡日历视图
- 🆕 **新书速递**：豆瓣新书速递抓取、想共读投票、排行榜
- 🌎 **西语文学专区**：Leaflet.js + GeoJSON 拉丁美洲文学交互地图

### 会员系统
- 🏅 **16 级会员等级**（Lv.1-Lv.16）：自动升级/降级、等级徽章发放与回收
- ⭐ **贡献值系统**：书友圈/已读/字数/精选/点赞/评论计分、贡献值流水
- 🎫 **票券系统**：资源浏览券（临时解锁 72h）、共读兑换券（永久解锁）、共读密码核销
- 🏆 **贡献排行榜**：总榜/月榜/周榜横向三列
- 🔔 **消息通知**：铃铛+红点+下拉面板+历史补录+定位跳转

### 书友圈
- ✍️ **阅读动态**：想读/在读/已读/摘抄/感想/书评、已读评分（-10~10+emoji）
- 💬 **点赞评论**：点赞与评论贡献值、评论防刷通知去重
- ✏️ **动态编辑**：修改已发布内容
- 🔒 **可见性控制**：公开/仅自己可见/好友可见
- 👥 **好友系统**：关注/取关、好友动态、搜索书友圈、关注列表+粉丝列表

### 徽章系统
- 🎖️ **17 枚徽章**：16 枚等级成长徽章 + 1 枚开创者权限徽章
- 🔄 **徽章翻面**：徽章背面图上传+预览弹窗翻转展示
- 🧩 **成就谜面答题**（v31）：每枚徽章配谜面诗、答对奖励 10 贡献值
- 🖼️ **自定义徽章展示**：用户可自选展示徽章

### 安全与权限
- 🔐 **Supabase Auth**：注册/登录、拼图验证码
- 🛡️ **RLS 安全**：行级安全策略、服务端权限验证
- 🔒 **资源权限**：受保护资源预览+临时解锁+永久解锁+开创者全开
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
│   ├── checkins.js         # 每日签到
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
├── sql/
│   ├── supabase-schema.sql # 基础 Schema
│   ├── deploy-order.md     # 迁移部署顺序
│   ├── migrate-v2.sql ~ migrate-v31.sql  # 迁移脚本
│   └── seed-king-lear.sql  # 测试种子数据
└── badges/
    ├── final/              # 徽章终稿 + 谜面文档 + 提示词
    └── trials/             # 徽章设计过程稿 + 开发方案
```

---

## 数据库迁移（v2 → v31）

最新迁移：**v31 徽章谜面答题**（2026-07-01）

详见 [sql/deploy-order.md](sql/deploy-order.md) 获取完整部署顺序。

---

## 快速开始

1. 部署 Supabase 项目，获取 API URL 和 anon key
2. 按 [deploy-order.md](sql/deploy-order.md) 顺序执行 SQL 迁移
3. 在 `src/supabaseClient.js` 中配置 Supabase 连接
4. 部署静态文件至 Supabase Storage 或任意静态托管
5. 配置 Edge Functions（豆瓣抓取、图片代理）

---

## 开发日志

详见 [Coding Log.md](Coding Log.md)
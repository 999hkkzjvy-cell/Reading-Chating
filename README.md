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
- 🆕 **新书速递**：豆瓣新书速递抓取前 3 页，缓存约 60 本，前台展示最新 Top 10、想共读投票与排行榜；抓取器按豆瓣图书 subject 链接兼容页面结构变化
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
- 🎖️ **17 枚核心徽章**：16 枚等级成长徽章 + 1 枚开创者权限徽章；另支持共读纪念徽章
- 🔄 **徽章翻面**：徽章背面图上传+预览弹窗翻转展示
- 🧩 **成就谜面答题**（v31）：每枚徽章配谜面诗、答对奖励 10 贡献值
- 🖼️ **自定义徽章展示**：用户可在“我的徽章”中自选展示徽章，个人主页同步展示这组选择

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
├── badge-upload-guide.md   # 共读纪念徽章上传、挂接与缓存说明
├── index.html              # 主入口 SPA
├── sw.js                   # PWA Service Worker：网络优先导航 + 轻量离线兜底
├── offline.html            # 断网提示页
├── _headers                # Cloudflare Pages 精确缓存与安全响应头
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
│   ├── pwaMode.js          # standalone 手机模式检测
│   ├── pwaServiceWorker.js # Service Worker 注册与更新
│   ├── pwaShell.js         # PWA 底部导航
│   ├── pwa.css             # PWA 专属样式
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
    └── books-sql/          # 按书目归档的 seed 数据
```

---

## 数据库部署

当前数据库迁移文件整理到 **v50**（2026-08-01）；生产数据库升级时需执行新增的 v50 迁移。

- 新数据库从 0 开始：执行 [sql/final-init/00-full-init.sql](sql/final-init/00-full-init.sql)
- 现有数据库增量升级：参考 [sql/current-files/deploy-order.md](sql/current-files/deploy-order.md)
- 书籍种子数据：位于本地 `ignore files/books-sql/`，按书目独立归档，不上传云端
- 新书速递排序字段：`migrate-v46-new-books-source-order.sql` 增加 `source_rank` / `source_page`，用于按豆瓣源页面顺序稳定展示
- 公开主页徽章展示：`migrate-v47-public-display-badges.sql` 新增公开展示徽章 RPC，个人主页按“我的徽章”选定顺序显示，并将“读完纪念”统一为“完本纪念”。旧库执行 v47 即可，不需要重跑 v26。
- 徽章图片缓存破除：`migrate-v48-badge-cache-busting.sql` 让公开主页徽章 RPC 返回 `catalog_updated_at`，前端把 `badge_catalog.updated_at` 拼入图片 URL。覆盖同名徽章图后，更新对应 `badge_catalog.updated_at` 即可刷新缓存。
- 会员等级门槛：`migrate-v49-member-level-contribution-thresholds.sql` 调整 Lv.7–Lv.16 的贡献值区间，并重算已有会员等级；旧库按 `deploy-order.md` 补齐至 v49。
- 定时浏览券：`migrate-v50-scheduled-weekly-view-passes.sql` 启用 Supabase Cron，于每周日北京时间 20:00 自动核算并发放浏览券；同一结算周重复执行不会重复发券。
- 定时浏览券修复：已部署 v50 的数据库需继续执行 `migrate-v51-fix-scheduled-weekly-view-pass-conflict.sql`，修复首次定时运行可能出现的 `source_key` 同名错误。

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
6. 前端当前部署在 Cloudflare Pages，并绑定已购 `.com` 自定义域名；Supabase 继续承载 Auth、数据库、Storage 与 Edge Functions

## 手机 PWA

手机端采用“原网站 + 独立安装模式 PWA”并行方案：普通浏览器继续使用原网页，只有从手机主屏幕以 standalone 窗口打开时，才显示 PWA 底部导航（首页、书库、书友圈、新书、我的）。首批移动页面不包含西语文学专区；完整范围、缓存边界和验收矩阵见 [ignore files/PWA-Development-Plan.md](ignore%20files/PWA-Development-Plan.md)。

阶段三第二轮补充了 PWA 网络状态提示：断网时提示数据不会更新且不会覆盖未提交内容，恢复网络后由用户手动重新加载。

阶段一已完成：PWA manifest、安装模式识别、底部导航骨架、首页首轮移动样式和西语专区网页版提示均已加入。阶段二已完成首页、共读书库、新书快递、书籍详情与共读资源入口的 standalone 移动布局；书友圈、公开主页、个人中心及资料编辑已加入移动布局，并补齐发布动态、编辑书库、徽章预览等弹窗的手机底部抽屉样式。阶段三第一轮已加入轻量 Service Worker：只缓存离线页、manifest 和 PWA 图标，导航网络优先，Supabase/Edge Function/上传/写入请求不进入缓存；同时加入 Cloudflare Pages 精确 `_headers` 与 Service Worker kill-switch。真实账号下的写入成功/失败链路和 HTTPS Preview/设备安装升级仍需验收。

---

## 近期更新

- **2026-08-18**：启动手机 PWA 第一阶段：保留原网站显示，新增 standalone 安装模式基础、PWA manifest 与底部导航骨架；“探索”在 PWA 导航中统一为“新书”，西语文学专区暂不适配移动端。
- **2026-08-18**：PWA 阶段二首轮完成：首页、共读书库、新书快递在 standalone 手机模式下采用单列阅读布局，继续复用现有 Supabase 数据和路由；普通网页保持原样。
- **2026-08-18**：PWA 阶段二第二轮完成：书籍详情与共读资源入口加入移动阅读层级，保留分页懒加载、资源权益和解锁逻辑；书友圈、个人主页和个人中心完成移动布局骨架。
- **2026-08-18**：PWA 阶段二第三轮继续：登录态写入相关弹窗（发布/编辑书友圈、编辑我的书库、徽章预览）在 standalone 模式下改为带安全区的底部抽屉，长表单操作按钮保持可见；普通网页弹窗规则不变。
- **2026-08-18**：PWA 阶段三第一轮完成：加入网络优先的 `sw.js`、`offline.html`、Cloudflare Pages `_headers` 和版本化注册模块；仅预缓存离线壳与安装图标，不缓存 Supabase 数据、API、上传或任何写入请求，并保留 kill-switch。
- **2026-08-18**：PWA 阶段三第二轮完成：安装模式下增加断网/恢复网络提示，恢复网络后由用户手动重新加载，避免自动刷新打断未提交的发布、评论或资料编辑。
- **2026-08-01**：浏览券改为 Supabase Cron 定时发放：每周日北京时间 20:00 核算当周阅读贡献并自动发券，后台不再需要手动操作。
- **2026-08-01**：部署现状更新为 Cloudflare Pages + 已购 `.com` 自定义域名；数据库和后端服务仍在 Supabase。当前未使用 Cloudflare 或 Supabase 的付费服务，手机端尚未进行专项优化。
- **2026-07-21**：会员等级贡献值门槛调整（v49）：更新 Lv.7–Lv.16 区间，并重算已有会员等级。
- **2026-07-17**：新书速递解析兼容豆瓣页面结构变化：抓取器不再只依赖旧版 `li.media.clearfix` / `media__img` 等 class，而是按新书区域内的豆瓣图书 subject 链接识别书目，并补充封面、作者/出版社、评分/评价数的兜底解析与重复书目去重。若线上刷新仍报“未解析到任何书籍数据”，重新部署 `scrape-douban` Edge Function。
- **2026-07-13**：徽章图片缓存破除：会员中心和个人主页的徽章图片 URL 增加 `updated_at` 版本参数；新增 v48 迁移，为公开主页徽章 RPC 返回 `catalog_updated_at`；补充同名覆盖徽章后的刷新说明。
- **2026-07-12**：徽章展示升级：个人主页徽章改为同步“我的徽章”中保存的展示选择；共读完本徽章文案从“读完纪念”统一为“完本纪念”；新增 v47 迁移。
- **2026-07-12**：新书速递抓取逻辑升级：抓取豆瓣新书前 3 页，缓存约 60 本，前台只展示最新 Top 10；修复无评分新书被误显示为评价人数的问题；Edge Function 推荐使用 `--use-api` 部署。
- **2026-07-12**：西语文学专区拉丁美洲地图改进 Leaflet 动态资源加载、地图尺寸刷新与失败提示。
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

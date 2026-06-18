# Coding Log

> 以读攻独 — 开发日志

---

## 2026-06-16

**15:01** ✨ Initial: 共读资源网站 V1 — 读书谈
- 单文件 SPA，内联 CSS + JS
- 暖棕色文学风格配色
- 5 张表：profiles / site_config / books / events / daily_checkins
- RLS 全开，admin/member 角色分离
- 路由：首页 / 书库 / 书籍详情(5标签) / 活动 / 活动详情 / 个人资料 / 管理后台
- 每日阅读签到日历

**17:07** 🐛 修复 Supabase CDN 加载方式 + 配置 Supabase 密钥，修复 Schema 建表顺序

---

## 2026-06-17

**00:39** 🎨 品牌升级：读书谈 → 以读攻独，UI 全面重构
- 配色改为暖琥珀色系（#c17d4b），更简约大气
- 导航栏 NatGeo 风格：左置品牌名 + 琥珀底线
- Hero 突出"以读攻独"，群介绍衬线字体按回车分行
- 按钮阴影、卡片层次、间距留白全面打磨

**00:41** 🙈 从仓库移除 README.md，本地保留

**01:29** 🗃️ 书籍数据模型 v2：新增 11 字段，合并活动回放，版本建议 JSONB
- 新增：author_country / author_gender / translator_gender / word_count / author_bio / historical_context / host_notes
- 删除：isbn / page_count / meeting_replays
- edition_guide：TEXT → JSONB（版本名称/译者/出版方/优缺点/购买/豆瓣链接）
- 管理后台表单 21 字段重构 + 封面图上传 Supabase Storage
- 可视化构建器：版本建议 + 统一活动安排
- 书籍详情页 5→6 标签
- 新增 migrate-v2.sql 迁移脚本

**12:54** 🎉 + 🙈 云端同步：以读攻独 V1 + gitignore 保护本地更新日志

**14:10** 🧩 封装书籍卡片组件 + 信息行规范化（国别/译者/出版方）

**14:24** 🔧 首页卡片状态标签移至封面右上角

**14:26** 🔧 首页状态标签移至卡片右上角，不挡封面

**14:34** 🐛 修复封面溢出：cover-slot 恢复 position:relative

**15:26** ✨ 书籍详情页重构：简介分区分割线、领读人 host 字段、版本建议 edition_notes、卡片样式优化

**15:32** ✨ reading_schedule 改为 JSONB：计划简述 + PDF 上传（新增 files Storage bucket）

**15:46** ✨ 新增聊天干货分页 + chatsubstance JSONB 字段

**15:55** ✨ 新增灵沁碎碎念独立分页（有内容显示，无内容隐藏）

**16:24** 🐛 修复中文文件名上传 Storage 失败（封面+PDF）

**16:46** 🐛 修复时间计划分页内容被 md-content 限制宽度导致过早换行

**18:07** 🐛 修复编辑弹窗：禁止点击外部关闭、禁止 Enter 意外提交

---

## 2026-06-18

**00:29** 🔒 安全修复 Top 5
- 封面 URL oninput XSS → 安全 DOM createElement
- 13 处 marked.parse() → 引入 DOMPurify + safeMarked()
- DeepSeek API Key → Supabase Edge Function 代理
- 管理权限纯客户端 → Router guard 数据库查询
- err.message XSS → HTML 实体转义

**00:53** 🐛 修复 safeMarked 作用域错误（移出 if 块 + 修正递归调用）

**01:07** 📐 书库卡片缩小为 4 列，按开始时间降序排列

**01:19** 📐 书库卡片 6 列布局 + 作者格式 [国别] 作者 著

**01:44** 🔒 剩余安全修复
- 新增 h() HTML 转义函数，22 处模板注入点全覆盖
- 新增 safeUrl() 防 javascript: 协议注入，7 处外部链接
- lucide CDN @latest → @0.344.0
- 添加 Content-Security-Policy meta 标签

**01:57** 🙈 gitignore：本地计划文档和开发日志不上传

**01:57** 📁 整理项目结构：SQL 文件移入 sql/ 目录

**01:59** 📁 sql/ 补入 v3、v4 迁移文件

**15:30** ✨ 新书速递功能完整开发
- 数据库迁移 v5：douban_new_books（缓存）+ reading_wishlist（投票），含 RLS
- Edge Function scrape-douban：Cheerio 解析豆瓣 /latest，新结构 ul.chart-dashed-list > li.media.clearfix
- Edge Function img-proxy：绕过豆瓣图片防盗链 HTTP 418，--no-verify-jwt 公开访问
- 前端路由 /new-books：导航栏入口 + 横向卡片（左封面右信息，每行 2 张）+ 想共读排行榜（右侧）
- 缓存机制：24h 自动刷新 + 手动刷新按钮，每日清理 0 票旧书
- 用户交互：登录后可点击想共读/取消，实时更新排行榜

**16:10** 🐛 修复 Edge Function 调用缺少 apikey 认证头（CORS 预检失败）
**16:25** 🐛 适配豆瓣页面结构变化（ul.cover-col-4 → ul.chart-dashed-list）
**16:50** 🐛 修复豆瓣封面防盗链：自建 img-proxy 替代失效的 weserv.nl
**17:15** 💄 排行榜移至新书速递页面右侧（desktop 侧栏 / mobile 回落下方）
**17:30** 💄 新书卡片重构：竖向→横向布局，每行 2 张，字段分行显示
**17:45** 🐛 隐藏空译者行：豆瓣列表页无译者数据

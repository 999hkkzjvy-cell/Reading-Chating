# 最终初始化 SQL

更新时间：2026-07-21

本目录用于全新的 Supabase 数据库从 0 初始化。

## 推荐执行顺序

1. 执行 `00-full-init.sql`
2. 按需要执行书籍 seed 数据：
   - `../books/king-lear/seed-king-lear.sql`
   - `../books/red-mansion/seed-red-mansion-from-shimo.sql`
   - `../books/red-mansion/seed-red-mansion-leading-docs-01-10.sql`
   - `../books/red-mansion/seed-red-mansion-leading-docs-11-40.sql`
   - `../books/red-mansion/seed-red-mansion-leading-docs-41-50.sql`
   - `../books/red-mansion/seed-red-mansion-leading-docs-51-80.sql`

## 说明

- `00-full-init.sql` 已合并当前基础 schema 与截至 v49 的有效迁移，适合空库初始化。
- 旧每日签到表 `daily_checkins` 已下线；新库初始化不会保留旧签到数据结构。
- 现有正式库不要重复执行 `00-full-init.sql`，应按 `../current-files/deploy-order.md` 做增量升级。
- Supabase Storage 中的实际图片、PDF、徽章文件仍需要单独上传。
- Edge Functions 和环境变量仍需要在 Supabase 后台单独部署与配置。

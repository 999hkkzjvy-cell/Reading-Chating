# SQL 部署顺序

本文档记录当前项目推荐的 Supabase SQL 执行顺序，避免重复执行早期迁移导致 policy 或对象重名。

## 新项目初始化

新建 Supabase 项目时，推荐按以下顺序执行：

1. `sql/supabase-schema.sql`
2. `sql/migrate-v9-member-foundation.sql`
3. `sql/migrate-v10-badge-display-preferences.sql`
4. `sql/migrate-v11-recalculate-member-level-backfill.sql`
5. `sql/migrate-v12-weekly-contribution-rank.sql`
6. `sql/migrate-v13-reading-posts-contributions.sql`
7. `sql/migrate-v14-reading-post-douban-required.sql`
8. `sql/migrate-v15-revoke-level-badges-on-downgrade.sql`
9. `sql/migrate-v16-reading-post-excerpt-mood.sql`
10. `sql/migrate-v17-reading-post-rating.sql`
11. `sql/migrate-v18-reading-post-edit.sql`
12. `sql/migrate-v19-likes-comments.sql`
13. `sql/migrate-v20-post-author-level.sql`
14. `sql/migrate-v21-user-profile.sql`
15. `sql/migrate-v22-contribution-leaderboard.sql`
16. `sql/migrate-v23-notifications.sql`
17. `sql/migrate-v24-comment-anti-spam-notification-dedupe.sql`

`supabase-schema.sql` 已包含早期基础结构，例如用户资料、站点配置、书库、活动、新书速递、豆瓣缓存、每日签到、`covers`/`files` Storage policy 等。新项目初始化后不要再重复执行 `migrate-v2.sql` 到 `migrate-v8-profile-privacy.sql`，除非你明确知道当前库缺少对应对象。

## 旧项目升级

旧库升级时，只执行尚未执行过的迁移，并严格按照版本号从小到大执行：

```text
migrate-v2.sql
migrate-v3-checkin-enhance.sql
migrate-v4-host-edition.sql
migrate-v5-new-books.sql
migrate-v6-event-category.sql
migrate-v7.sql
migrate-v8-profile-privacy.sql
migrate-v9-member-foundation.sql
migrate-v10-badge-display-preferences.sql
migrate-v11-recalculate-member-level-backfill.sql
migrate-v12-weekly-contribution-rank.sql
migrate-v13-reading-posts-contributions.sql
migrate-v14-reading-post-douban-required.sql
migrate-v15-revoke-level-badges-on-downgrade.sql
migrate-v16-reading-post-excerpt-mood.sql
migrate-v17-reading-post-rating.sql
migrate-v18-reading-post-edit.sql
migrate-v19-likes-comments.sql
migrate-v20-post-author-level.sql
migrate-v21-user-profile.sql
migrate-v22-contribution-leaderboard.sql
migrate-v23-notifications.sql
migrate-v24-comment-anti-spam-notification-dedupe.sql
```

如果不确定某个迁移是否已执行，先检查目标表、函数或字段是否存在。不要在同一个库里重复执行没有 `DROP POLICY IF EXISTS` 或 `CREATE POLICY` 防重处理的早期迁移。

## Storage 与 Edge Functions

会员徽章图片使用 Supabase Storage 的 `badges` bucket，图片路径由 `badge_catalog.image_bucket` 和 `badge_catalog.image_path` 决定。

当前 Edge Functions：

- `deepseek-proxy`
- `scrape-douban`
- `fetch-douban-book`
- `img-proxy`

部署后需要设置：

```bash
supabase secrets set DEEPSEEK_API_KEY=sk-xxx
supabase secrets set SB_SERVICE_ROLE_KEY=你的-service-role-key
```

`SB_SERVICE_ROLE_KEY` 也可使用 `SUPABASE_SERVICE_ROLE_KEY`，但项目文档统一推荐 `SB_SERVICE_ROLE_KEY`。

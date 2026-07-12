# SQL 部署顺序

本文档记录当前项目推荐的 Supabase SQL 执行顺序，避免重复执行早期迁移导致 policy 或对象重名。

## 新项目初始化

新建 Supabase 项目时，推荐直接执行最终初始化套件：

1. `../final-init/00-full-init.sql`

如果需要拆分执行或定位问题，也可以按以下顺序执行：

1. `supabase-schema.sql`
2. `migrate-v9-member-foundation.sql`
3. `migrate-v10-badge-display-preferences.sql`
4. `migrate-v11-recalculate-member-level-backfill.sql`
5. `migrate-v12-weekly-contribution-rank.sql`
6. `migrate-v13-reading-posts-contributions.sql`
7. `migrate-v14-reading-post-douban-required.sql`
8. `migrate-v15-revoke-level-badges-on-downgrade.sql`
9. `migrate-v16-reading-post-excerpt-mood.sql`
10. `migrate-v17-reading-post-rating.sql`
11. `migrate-v18-reading-post-edit.sql`
12. `migrate-v19-likes-comments.sql`
13. `migrate-v20-post-author-level.sql`
14. `migrate-v21-user-profile.sql`
15. `migrate-v22-contribution-leaderboard.sql`
16. `migrate-v23-notifications.sql`
17. `migrate-v24-comment-anti-spam-notification-dedupe.sql`
18. `migrate-v25-resource-access.sql`
19. `migrate-v26-co-reading-claims.sql`
20. `migrate-v27-readable-co-reading-passwords.sql`
21. `migrate-v28-avatar-upload-profile.sql`
22. `migrate-v28-badge-back-images.sql`
23. `migrate-v29-friends-search.sql`
24. `migrate-v30-friend-lists.sql`
25. `migrate-v31-badge-riddle-answers.sql`
26. `migrate-v32-month-week-contribution.sql`
27. `migrate-v32-admin-member-list.sql`
28. `migrate-v33-reading-circle-auth-required.sql`
29. `migrate-v34-given-interaction-contributions.sql`
30. `migrate-v35-member-search.sql`
31. `migrate-v36-follow-level-notifications.sql`
32. `migrate-v37-member-ban.sql`
33. `migrate-v37-fix-visibility-friends.sql`
34. `migrate-v38-host-notes-fields.sql`
35. `migrate-v38-member-library.sql`
36. `migrate-v39-nested-comments.sql`
37. `migrate-v39-public-member-library.sql`
38. `migrate-v40-comment-reply-notification-dedupe.sql`
39. `migrate-v41-weekly-view-pass-source-key-fix.sql`
40. `migrate-v42-live-weekly-contribution-rank.sql`
41. `migrate-v43-live-monthly-contribution-rank.sql`
42. `migrate-v44-drop-legacy-checkins.sql`
43. `migrate-v45-add-xuxu-notes.sql`
44. `migrate-v46-new-books-source-order.sql`
45. `migrate-v47-public-display-badges.sql`

`supabase-schema.sql` 已包含早期基础结构，例如用户资料、站点配置、书库、活动、新书速递、豆瓣缓存、`covers`/`files` Storage policy 等。旧每日签到表已在 v44 下线，新项目初始化后不要再重复执行 `migrate-v2.sql` 到 `migrate-v8-profile-privacy.sql`，除非你明确知道当前库缺少对应对象。

## 专题种子数据

以下 SQL 不是结构迁移，而是补充特定书目的内容数据。只在目标书目已经存在、且需要补入资料时执行：

- `../books/king-lear/seed-king-lear.sql`：补入《李尔王》共读资料。
- `../books/red-mansion/seed-red-mansion-from-shimo.sql`：根据石墨文档补入《红楼梦》共读资料。
- `../books/red-mansion/seed-red-mansion-leading-docs-01-10.sql`：根据石墨文档补入《红楼梦》前 10 回领读文档到聊天干货。建议在 `seed-red-mansion-from-shimo.sql` 之后执行。
- `../books/red-mansion/seed-red-mansion-leading-docs-11-40.sql`：根据石墨文档补入《红楼梦》第 11-40 回领读文档到聊天干货。建议在 `seed-red-mansion-leading-docs-01-10.sql` 之后执行。
- `../books/red-mansion/seed-red-mansion-leading-docs-41-50.sql`：根据石墨文档补入《红楼梦》第 41-50 回领读文档到聊天干货，不纳入群友补充。建议在 `seed-red-mansion-leading-docs-11-40.sql` 之后执行。
- `../books/red-mansion/seed-red-mansion-leading-docs-51-80.sql`：根据石墨文档补入《红楼梦》第 51-80 回领读文档到聊天干货，不纳入群友补充。建议在 `seed-red-mansion-leading-docs-41-50.sql` 之后执行。

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
migrate-v25-resource-access.sql
migrate-v26-co-reading-claims.sql
migrate-v27-readable-co-reading-passwords.sql
migrate-v28-avatar-upload-profile.sql
migrate-v28-badge-back-images.sql
migrate-v29-friends-search.sql
migrate-v30-friend-lists.sql
migrate-v31-badge-riddle-answers.sql
migrate-v32-month-week-contribution.sql
migrate-v32-admin-member-list.sql
migrate-v33-reading-circle-auth-required.sql
migrate-v34-given-interaction-contributions.sql
migrate-v35-member-search.sql
migrate-v36-follow-level-notifications.sql
migrate-v37-member-ban.sql
migrate-v37-fix-visibility-friends.sql
migrate-v38-host-notes-fields.sql
migrate-v38-member-library.sql
migrate-v39-nested-comments.sql
migrate-v39-public-member-library.sql
migrate-v40-comment-reply-notification-dedupe.sql
migrate-v41-weekly-view-pass-source-key-fix.sql
migrate-v42-live-weekly-contribution-rank.sql
migrate-v43-live-monthly-contribution-rank.sql
migrate-v44-drop-legacy-checkins.sql
migrate-v45-add-xuxu-notes.sql
migrate-v46-new-books-source-order.sql
migrate-v47-public-display-badges.sql
```

如果不确定某个迁移是否已执行，先检查目标表、函数或字段是否存在。不要在同一个库里重复执行没有 `DROP POLICY IF EXISTS` 或 `CREATE POLICY` 防重处理的早期迁移。

注意：`migrate-v44-drop-legacy-checkins.sql` 会删除旧 `daily_checkins` 表及其中历史签到数据；如果需要留档，请先导出该表。

## Storage 与 Edge Functions

会员徽章图片使用 Supabase Storage 的 `badges` bucket，图片路径由 `badge_catalog.image_bucket` 和 `badge_catalog.image_path` 决定。

当前 Edge Functions：

- `deepseek-proxy`
- `scrape-douban`
- `fetch-douban-book`
- `img-proxy`

`scrape-douban` 推荐使用 Supabase API 端打包部署，避免本地 eszip 偶发生成失败：

```bash
npx supabase@latest functions deploy scrape-douban --project-ref zugadhgezmqrnlwogomw --use-api
```

部署后需要设置：

```bash
supabase secrets set DEEPSEEK_API_KEY=sk-xxx
supabase secrets set SB_SERVICE_ROLE_KEY=你的-service-role-key
```

`SB_SERVICE_ROLE_KEY` 也可使用 `SUPABASE_SERVICE_ROLE_KEY`，但项目文档统一推荐 `SB_SERVICE_ROLE_KEY`。

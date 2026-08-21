# 当前 SQL 文件归档

更新时间：2026-08-21

本目录保存当前项目仍在使用的单独 SQL 文件，包括基础 schema、历史迁移和部署顺序文档。

## 用途

- 现有 Supabase 数据库继续增量部署时，参考 `deploy-order.md`。
- 排查线上数据库结构问题时，可在这里查找对应迁移。
- 保留历史迁移文件，方便回看每个版本引入了哪些表、字段、函数、策略和 RPC。
- `migrate-v50-scheduled-weekly-view-passes.sql` 会启用 Supabase Cron，并在每周日北京时间 20:00 自动核算和发放资源浏览券。
- `migrate-v51-fix-scheduled-weekly-view-pass-conflict.sql` 修复 v50 定时任务的 `source_key` 同名歧义；已执行 v50 的数据库需要继续执行该迁移。
- `migrate-v52-reading-post-tags.sql` 增加按用户隔离的书友圈标签、发布/编辑标签和按标签/发表用户搜索；当前 Supabase 项目已执行该迁移，其他已执行 v51 的数据库需要继续执行。

## 注意

- 不建议把本目录所有 SQL 一次性重复跑到已有正式库。
- 如果是全新数据库，从 0 开始部署，请优先使用 `../final-init/00-full-init.sql`。
- 书籍 seed 数据仅保存在本地忽略目录 `ignore files/books-sql/`，不随仓库同步。

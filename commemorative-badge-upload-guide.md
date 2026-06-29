# 共读纪念徽章上传与挂接说明

共读密码创建后，系统会自动为对应书籍生成两条纪念徽章记录：

- 占位版徽章：`commemorative_book_书籍ID_claimed`
- 已读版徽章：`commemorative_book_书籍ID_finished`

其中 `书籍ID` 是 `books.id`。

## 1. 查询书籍 ID

在 Supabase SQL Editor 执行：

```sql
SELECT id, title
FROM public.books
ORDER BY id;
```

记下要挂接徽章的书籍 ID。

## 2. 上传徽章图片

进入 Supabase Storage，打开 `badges` bucket。

建议路径格式：

```text
final/commemorative/book-书籍ID-claimed.png
final/commemorative/book-书籍ID-finished.png
```

例如书籍 ID 为 `12`：

```text
final/commemorative/book-12-claimed.png
final/commemorative/book-12-finished.png
```

注意：路径中不要重复写 `badges/`，因为 `badges` 是 bucket 名。

## 3. 挂接到 badge_catalog

假设书籍 ID 为 `12`，在 Supabase SQL Editor 执行：

```sql
UPDATE public.badge_catalog
SET image_bucket = 'badges',
    image_path = 'final/commemorative/book-12-claimed.png',
    updated_at = now()
WHERE badge_key = 'commemorative_book_12_claimed';

UPDATE public.badge_catalog
SET image_bucket = 'badges',
    image_path = 'final/commemorative/book-12-finished.png',
    updated_at = now()
WHERE badge_key = 'commemorative_book_12_finished';
```

把 `12` 和图片路径替换为实际书籍 ID 与实际上传路径。

## 4. 验证

执行：

```sql
SELECT badge_key, title, image_bucket, image_path
FROM public.badge_catalog
WHERE badge_key IN (
  'commemorative_book_12_claimed',
  'commemorative_book_12_finished'
);
```

确认 `image_bucket` 为 `badges`，`image_path` 为刚上传的路径。

然后刷新网站，在用户获得该纪念徽章后查看会员中心徽章墙。

## 5. 缓存说明

如果你用同名文件覆盖图片，浏览器或 Supabase CDN 可能仍显示旧图。

更稳妥的做法是上传新文件名，例如：

```text
final/commemorative/book-12-claimed-v2.png
```

然后重新更新 `badge_catalog.image_path`。

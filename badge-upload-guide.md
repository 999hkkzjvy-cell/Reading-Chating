# 共读纪念徽章上传与挂接说明

共读密码创建后，系统会自动为对应书籍生成两条纪念徽章记录：

- 占位版徽章：`commemorative_book_书籍ID_claimed`
- 已读版徽章：`commemorative_book_书籍ID_finished`

每条徽章记录支持正面图和背面图，所以每期共读需要准备 4 张图片：

- 占位版正面
- 占位版背面
- 已读版正面
- 已读版背面

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
final/commemorative/book-书籍ID-claimed-front.png
final/commemorative/book-书籍ID-claimed-back.png
final/commemorative/book-书籍ID-finished-front.png
final/commemorative/book-书籍ID-finished-back.png
```

例如书籍 ID 为 `12`：

```text
final/commemorative/book-12-claimed-front.png
final/commemorative/book-12-claimed-back.png
final/commemorative/book-12-finished-front.png
final/commemorative/book-12-finished-back.png
```

注意：路径中不要重复写 `badges/`，因为 `badges` 是 bucket 名。

## 3. 挂接到 badge_catalog

假设书籍 ID 为 `12`，在 Supabase SQL Editor 执行：

```sql
UPDATE public.badge_catalog
SET image_bucket = 'badges',
    image_path = 'final/commemorative/book-12-claimed-front.png',
    back_image_bucket = 'badges',
    back_image_path = 'final/commemorative/book-12-claimed-back.png',
    updated_at = now()
WHERE badge_key = 'commemorative_book_12_claimed';

UPDATE public.badge_catalog
SET image_bucket = 'badges',
    image_path = 'final/commemorative/book-12-finished-front.png',
    back_image_bucket = 'badges',
    back_image_path = 'final/commemorative/book-12-finished-back.png',
    updated_at = now()
WHERE badge_key = 'commemorative_book_12_finished';
```

把 `12` 和图片路径替换为实际书籍 ID 与实际上传路径。

## 4. 验证

执行：

```sql
SELECT badge_key, title, image_bucket, image_path, back_image_bucket, back_image_path
FROM public.badge_catalog
WHERE badge_key IN (
  'commemorative_book_12_claimed',
  'commemorative_book_12_finished'
);
```

确认 `image_bucket` / `back_image_bucket` 为 `badges`，`image_path` / `back_image_path` 为刚上传的路径。

然后刷新网站，在用户获得该纪念徽章后查看会员中心徽章墙或个人主页徽章墙。点击徽章放大，再点击放大的徽章即可翻转查看背面。

## 5. 缓存说明

如果你用同名文件覆盖图片，浏览器或 Supabase CDN 可能仍显示旧图。

更稳妥的做法是上传新文件名，例如：

```text
final/commemorative/book-12-claimed-v2.png
```

然后重新更新 `badge_catalog.image_path` 或 `badge_catalog.back_image_path`。

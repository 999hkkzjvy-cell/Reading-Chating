-- ============================================================
-- 以读攻独 · 最终版数据库初始化 SQL
--
-- 用途：新 Supabase 数据库从 0 初始化。
-- 重要：只建议在空库执行，不要在已有线上库重复执行本文件。
-- 生成来源：sql/current-files/supabase-schema.sql + 当前有效迁移 v9-v44。
-- 生成时间：2026-07-06T14:49:02.592Z
-- ============================================================



-- ============================================================
-- BEGIN supabase-schema.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · 共读资源网站 — 数据库 Schema v2
-- 在 Supabase SQL Editor 中执行此文件
-- 注意：按依赖顺序排列，不可随意调整
-- ============================================================

-- ============================================================
-- 1. profiles — 用户资料（最优先，其他表和策略依赖它）
-- ============================================================
CREATE TABLE profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL,
  avatar_url      TEXT,
  bio             TEXT,
  wechat_id       TEXT,
  city            TEXT,
  role            TEXT DEFAULT 'member'
                  CHECK (role IN ('admin','host','member')),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE POLICY "profiles_read_self_or_admin" ON profiles FOR SELECT
  USING (auth.uid() = id OR is_admin());
CREATE POLICY "profiles_update_self" ON profiles FOR UPDATE
  USING (auth.uid() = id OR is_admin())
  WITH CHECK (auth.uid() = id OR is_admin());
CREATE POLICY "profiles_insert_self" ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Trigger: 新用户注册时自动创建 profile
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- 2. site_config — 站点配置
-- ============================================================
CREATE TABLE site_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

ALTER TABLE site_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "site_config_read_all" ON site_config FOR SELECT USING (true);
CREATE POLICY "site_config_admin_write" ON site_config FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- 3. books — 书籍及共读信息 (v2)
-- ============================================================
CREATE TABLE books (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- 基本信息
  title             TEXT NOT NULL,
  author            TEXT NOT NULL,
  author_country    TEXT,
  author_gender     TEXT,
  translator        TEXT,
  translator_gender TEXT,
  publisher         TEXT,
  word_count        INTEGER,
  cover_url         TEXT,
  genre             TEXT DEFAULT '文学',
  description       TEXT,
  author_bio        TEXT,
  historical_context TEXT,
  status            TEXT DEFAULT 'upcoming'
                    CHECK (status IN ('upcoming','active','completed')),
  -- 共读详情
  edition_guide     JSONB DEFAULT '[]',
  edition_notes     TEXT,
  reading_schedule  JSONB DEFAULT '{"summary":"","pdf_url":""}',
  host              TEXT,
  host_intro        TEXT,
  host_notes        TEXT,
  xuxu_notes        TEXT,
  activities        JSONB DEFAULT '[]',
  chatsubstance     JSONB DEFAULT '[]',
  resources         JSONB DEFAULT '{"extended_reading":[],"text_materials":[],"film_resources":[],"other":[]}',
  -- 时间
  start_date        DATE,
  end_date          DATE,
  -- 元数据
  created_at        TIMESTAMPTZ DEFAULT now(),
  created_by        UUID REFERENCES auth.users(id),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_books_status ON books(status);
CREATE INDEX idx_books_genre ON books(genre);

ALTER TABLE books ENABLE ROW LEVEL SECURITY;
CREATE POLICY "books_read_all" ON books FOR SELECT USING (true);
CREATE POLICY "books_admin_write" ON books FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- 4. events — 线下活动
-- ============================================================
CREATE TABLE events (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title           TEXT NOT NULL,
  category        TEXT DEFAULT '其他',
  link            TEXT,
  poster_url      TEXT,
  location        TEXT,
  event_date      TIMESTAMPTZ NOT NULL,
  guests          TEXT,
  price           TEXT,
  description     TEXT,
  status          TEXT DEFAULT 'upcoming'
                  CHECK (status IN ('upcoming','ongoing','ended','cancelled')),
  created_at      TIMESTAMPTZ DEFAULT now(),
  created_by      UUID REFERENCES auth.users(id),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_events_status ON events(status);
CREATE INDEX idx_events_date ON events(event_date);

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events_read_all" ON events FOR SELECT USING (true);
CREATE POLICY "events_admin_write" ON events FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- 5. douban_new_books — 新书速递缓存
-- ============================================================
CREATE TABLE douban_new_books (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title           TEXT NOT NULL,
  cover_url       TEXT,
  author          TEXT,
  translator      TEXT,
  publisher       TEXT,
  description     TEXT,
  douban_url      TEXT NOT NULL UNIQUE,
  rating          TEXT,
  review_count    INTEGER DEFAULT 0,
  fiction_type    TEXT CHECK (fiction_type IN ('fiction','non-fiction')),
  source_rank     INTEGER,
  source_page     INTEGER,
  scraped_at      TIMESTAMPTZ DEFAULT now(),
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_dnb_scraped ON douban_new_books(scraped_at);
CREATE INDEX idx_dnb_reviews ON douban_new_books(review_count DESC);
CREATE INDEX idx_dnb_latest_source_order ON douban_new_books(scraped_at DESC, source_rank ASC);

ALTER TABLE douban_new_books ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dnb_read_all" ON douban_new_books FOR SELECT USING (true);
CREATE POLICY "dnb_admin_write" ON douban_new_books FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- 6. reading_wishlist — 想共读投票
-- ============================================================
CREATE TABLE reading_wishlist (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES douban_new_books(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, book_id)
);

CREATE INDEX idx_wishlist_book ON reading_wishlist(book_id);
CREATE INDEX idx_wishlist_user ON reading_wishlist(user_id);

ALTER TABLE reading_wishlist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wishlist_read_all" ON reading_wishlist FOR SELECT USING (true);
CREATE POLICY "wishlist_insert_auth" ON reading_wishlist FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "wishlist_delete_own" ON reading_wishlist FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 7. douban_book_cache — 豆瓣详情缓存
-- ============================================================
CREATE TABLE douban_book_cache (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  douban_url    TEXT UNIQUE NOT NULL,
  title         TEXT,
  cover_url     TEXT,
  author        TEXT,
  translator    TEXT,
  publisher     TEXT,
  rating        TEXT,
  review_count  INTEGER DEFAULT 0,
  description   TEXT,
  pages         TEXT,
  fetched_at    TIMESTAMPTZ DEFAULT now(),
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_dbc_url ON douban_book_cache(douban_url);

ALTER TABLE douban_book_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dbc_read_all" ON douban_book_cache FOR SELECT USING (true);
CREATE POLICY "dbc_admin_write" ON douban_book_cache FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- 8. Storage — 封面图 bucket
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('covers', 'covers', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "covers_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');
CREATE POLICY "covers_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
CREATE POLICY "covers_admin_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
CREATE POLICY "covers_admin_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

-- 文件 bucket（PDF 等）
INSERT INTO storage.buckets (id, name, public)
VALUES ('files', 'files', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "files_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'files');
CREATE POLICY "files_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'files' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

-- ============================================================
-- 种子数据
-- ============================================================

-- 群规和介绍
INSERT INTO site_config (key, value) VALUES
('group_rules', '**以读攻独 · 共读群规**

1. **友好交流，求同存异**。尊重他人观点，避免人身攻击。
2. **尊重版权和隐私**。未经允许，请勿随意转发、引用、截屏群内的聊天记录及群内资源。
3. **聚焦共读主题**。讨论请围绕共读书籍和相关主题，适度控制灌水，给每位群友舒适的交流空间。
4. **涉及历史或政治话题时注意尺度**，将其作为理解作品的背景知识，不要过度延展。
5. **不涉及译本优劣比较**，尤其避免译者之间的拉踩。
6. **积极表达赞赏和认可**，也欢迎用打赏的形式支持分享者。')
ON CONFLICT (key) DO NOTHING;

INSERT INTO site_config (key, value) VALUES
('reading_plan_intro', '我们是一群热爱阅读的朋友，定期组织线上共读活动。
每期围绕一本（或一套）书展开，由领读人带领精读讨论，辅以线上讲座、文艺放映、嘉宾对谈等形式，打造有深度又有温度的阅读体验。

欢迎加入我们，以读攻独，一起读书、一起聊书。')
ON CONFLICT (key) DO NOTHING;

-- 示例书籍：《丰饶之海》
INSERT INTO books (
  title, author, author_country, author_gender,
  translator, translator_gender, publisher,
  genre, description, author_bio, historical_context, status,
  edition_guide, reading_schedule, host_intro, host_notes,
  activities, resources,
  start_date, end_date
) VALUES (
  '丰饶之海',
  '三岛由纪夫',
  '日本',
  '男',
  '陈德文 等',
  '男',
  '一页文库 / 北京燕山出版社 / 重庆出版社 等',
  '文学',
  '《丰饶之海》是三岛由纪夫的绝笔之作，由《春雪》《奔马》《晓寺》《天人五衰》四部曲组成。小说以转世轮回为主题，跨越从大正初年到昭和四十年的日本近现代史，是一部宏大深邃的文学巨著。',
  '三岛由纪夫（1925-1970），日本小说家、剧作家。本名平冈公威，东京出生。毕业于东京大学法学部，曾任职于大藏省，后辞职专事写作。代表作有《假面的告白》《金阁寺》《潮骚》《丰饶之海》等。1970年11月25日，在完成《丰饶之海》最终卷后，于东京市谷自卫队驻地剖腹自杀，震惊日本社会。',
  '《丰饶之海》创作于1965-1970年，正值日本战后经济高速增长期。三岛对战后日本的物质主义、传统价值观的丧失深感忧虑，这种焦虑贯穿作品始终。小说以轮回转世为框架，融入了佛教唯识宗思想、日本传统美学和近代历史批判，是三岛文学与思想的集大成之作。',
  'active',
  '[
    {
      "name": "一页2021文库版",
      "translator": "陈德文",
      "publisher": "一页文库",
      "pros": "一人担纲四本，翻译连贯统一性好；便携小开本",
      "cons": "纸质偏黄；部分注释较少",
      "buy_link": "",
      "douban_link": ""
    },
    {
      "name": "北京燕山出版社版",
      "translator": "郑民钦/许金龙/竺家荣/林少华",
      "publisher": "北京燕山出版社",
      "pros": "四位译者各有所长；初版具有收藏价值",
      "cons": "混合译本风格不完全统一；老版不易购买",
      "buy_link": "",
      "douban_link": ""
    },
    {
      "name": "重庆出版社2014修订版",
      "translator": "文洁若/李芒",
      "publisher": "重庆出版社",
      "pros": "文洁若译本在《春雪》获得较多认可；修订版校对较仔细",
      "cons": "全套购买不便；部分绝版",
      "buy_link": "",
      "douban_link": ""
    }
  ]',
  '共读期：**2月1日 — 3月31日**（部分收尾活动延续至4月底）

春节期间放假一周，可补进度也可抢跑。

每周阅读篇幅略有不同，建议尽量不要落后于周计划进度，避免影响线上活动体验。具体阅读计划表见群内共享文档。',
  '本次共读由**韩钊老师**领读。

早稻田大学博士毕业，译有《春琴抄》《小丑之花》《潮骚》《吞鲸者》《短歌是我，悲伤的玩具》等，杭州"普通读者"书店主理人。幽默风趣又热爱日本文学，将带我们从文本出发，深入三岛由纪夫的文学世界。',
  '韩老师建议：共读前可以先看一遍市川昆导演的《炎上》（改编自《金阁寺》），对三岛的视觉美学有个直观感受。另外推荐阅读三岛的短篇《忧国》，作为理解其政治美学的人门。',
  '[
    {"type":"导读预热","title":"通往丰饶之海——三岛的文学迷狂与时代暗涌","time":"2月1日 19:30","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":"韩老师开讲历史背景、三岛周边知识，提供延伸阅读参考"},
    {"type":"精读分析","title":"精读课：春雪（上半本）","time":"2月8日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":"每周精读本周阅读范围内的文本"},
    {"type":"精读分析","title":"精读课：春雪（下半本）","time":"2月15日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"精读分析","title":"精读课：奔马（上半本）","time":"2月22日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"精读分析","title":"精读课：奔马（下半本）","time":"3月1日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"精读分析","title":"精读课：晓寺（上半本）","time":"3月8日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"精读分析","title":"精读课：晓寺（下半本）","time":"3月15日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"精读分析","title":"精读课：天人五衰","time":"3月22日","status":"已完结","meeting_link":"","replay_link":"","guests":"韩钊","description":""},
    {"type":"文艺放映","title":"文艺放映室","time":"2月3日","status":"已完结","meeting_link":"","replay_link":"","guests":"","description":"春节期间线上放映会，一起边看三岛衍生影视作品边讨论"},
    {"type":"嘉宾分享","title":"神秘嘉宾分享对谈","time":"待定","status":"计划中","meeting_link":"","replay_link":"","guests":"特邀嘉宾（待公布）","description":"隐藏嘉宾主题分享对谈，具体时间和主题待公布"},
    {"type":"圆桌讨论","title":"收官圆桌讨论会","time":"待定","status":"计划中","meeting_link":"","replay_link":"","guests":"","description":"聊聊读丰饶之海的感受，票选分享突出群友，抽奖赠书"}
  ]',
  '{
    "extended_reading": [
      {"title": "常见简中三岛传记", "url": "", "description": "中文世界主要的三岛由纪夫传记作品概览"},
      {"title": "推荐日语三岛相关传记分析", "url": "", "description": "日文原版三岛研究著作推荐"},
      {"title": "推荐相关三岛读物", "url": "", "description": "三岛其他作品及相关研究导读"}
    ],
    "text_materials": [
      {"title": "三岛由纪夫作品篇目一览", "url": "", "description": "完整作品年表"},
      {"title": "井上隆史：《丰饶之海》的世界观", "url": "", "description": "学术论文"},
      {"title": "三岛由纪夫：评谷崎润一郎", "url": "", "description": ""},
      {"title": "三岛由纪夫：我写不出广阔的河流般的作品", "url": "", "description": "三岛生前最后一次访谈"},
      {"title": "寺山修司 x 三岛由纪夫：情色、戏剧与时间", "url": "", "description": "对谈记录"},
      {"title": "三岛由纪夫 × 大岛渚对谈", "url": "", "description": ""},
      {"title": "维基百科：三岛事件", "url": "", "description": ""},
      {"title": "莫言：三岛由纪夫猜想", "url": "", "description": ""}
    ],
    "film_resources": [
      {"title": "纪录片《三岛：最后的辩论》", "url": "", "description": ""},
      {"title": "电影《三岛由纪夫传》", "url": "", "description": ""},
      {"title": "宝冢音乐剧《春雪》", "url": "", "description": ""},
      {"title": "电影《潮骚》", "url": "", "description": ""},
      {"title": "电影《人斩》", "url": "", "description": "三岛本人出演"},
      {"title": "短片《忧国》+幕后花絮及采访", "url": "", "description": ""},
      {"title": "电影《金阁寺》", "url": "", "description": ""},
      {"title": "话剧《萨德侯爵夫人》", "url": "", "description": ""}
    ]
  }',
  '2026-02-01',
  '2026-03-31'
);

-- 示例线下活动
INSERT INTO events (title, poster_url, location, event_date, guests, price, description, status) VALUES
(
  '杭州普通读者书店线下共读会',
  '',
  '杭州·普通读者书店',
  '2026-04-15 14:00:00',
  '韩钊（译者、书店主理人）',
  '免费',
  '长三角的朋友们约起来！和领读人韩老师线下面基，聊聊《丰饶之海》的阅读感受。不管是开放聊聊的圆桌会，还是熟悉的文本细读模式，能和聊得来的朋友见面总是开心的事。',
  'upcoming'
);

-- ============================================================
-- END supabase-schema.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v9-member-foundation.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v9 迁移：会员系统第一阶段
-- 数据库基础、等级配置、徽章 catalog、注册初始化与首次资源浏览券
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- ------------------------------------------------------------
-- 0. 通用管理员判断函数
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ------------------------------------------------------------
-- 1. 会员等级配置
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_levels (
  level                       INTEGER PRIMARY KEY,
  title                       TEXT,
  tier                        TEXT NOT NULL,
  min_contribution            INTEGER NOT NULL,
  max_contribution            INTEGER,
  weekly_view_passes          INTEGER NOT NULL DEFAULT 0,
  badge_key                   TEXT,
  reward_redemption_tickets   INTEGER NOT NULL DEFAULT 0,
  is_active                   BOOLEAN NOT NULL DEFAULT true,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT member_levels_level_nonnegative CHECK (level >= 0),
  CONSTRAINT member_levels_min_nonnegative CHECK (min_contribution >= 0),
  CONSTRAINT member_levels_max_valid CHECK (max_contribution IS NULL OR max_contribution >= min_contribution),
  CONSTRAINT member_levels_weekly_passes_nonnegative CHECK (weekly_view_passes >= 0),
  CONSTRAINT member_levels_reward_tickets_nonnegative CHECK (reward_redemption_tickets >= 0)
);

ALTER TABLE public.member_levels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "member_levels_read_all" ON public.member_levels;
CREATE POLICY "member_levels_read_all" ON public.member_levels FOR SELECT USING (true);
DROP POLICY IF EXISTS "member_levels_admin_write" ON public.member_levels;
CREATE POLICY "member_levels_admin_write" ON public.member_levels FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

INSERT INTO public.member_levels
  (level, title, tier, min_contribution, max_contribution, weekly_view_passes, badge_key, reward_redemption_tickets)
VALUES
  (0,  NULL,       '基础会员', 0,    5,    0, NULL,                  0),
  (1,  '漫游者',   '青铜会员', 6,    30,   1, 'level_01_wanderer',    1),
  (2,  '冒险者',   '青铜会员', 31,   100,  1, 'level_02_adventurer',  1),
  (3,  '纪事者',   '青铜会员', 101,  200,  1, 'level_03_chronicler',  1),
  (4,  '追寻者',   '青铜会员', 201,  320,  1, 'level_04_seeker',      1),
  (5,  '隧行者',   '青铜会员', 321,  500,  1, 'level_05_tunnel',      1),
  (6,  '迷宫客',   '青铜会员', 501,  700,  1, 'level_06_labyrinth',   1),
  (7,  '破壁者',   '白银会员', 701,  1100,  2, 'level_07_wallbreaker', 1),
  (8,  '游戏者',   '白银会员', 1101, 1500,  2, 'level_08_player',      1),
  (9,  '驭词者',   '白银会员', 1501, 2000,  2, 'level_09_wordtamer',   1),
  (10, '观星者',   '白银会员', 2001, 2500,  2, 'level_10_stargazer',   1),
  (11, '建筑师',   '白银会员', 2501, 3000,  2, 'level_11_architect',   1),
  (12, '冥语者',   '黄金会员', 3001, 4000,  3, 'level_12_nether',      1),
  (13, '荒港客',   '黄金会员', 4001, 5000,  3, 'level_13_wasteport',   1),
  (14, '炼金士',   '黄金会员', 5001, 7000,  3, 'level_14_alchemist',   1),
  (15, '面具人',   '黄金会员', 7001, 10000, 3, 'level_15_maskman',     1),
  (16, '弑神者',   '黄金会员', 10001, NULL, 3, 'level_16_godslayer',   1)
ON CONFLICT (level) DO UPDATE SET
  title = EXCLUDED.title,
  tier = EXCLUDED.tier,
  min_contribution = EXCLUDED.min_contribution,
  max_contribution = EXCLUDED.max_contribution,
  weekly_view_passes = EXCLUDED.weekly_view_passes,
  badge_key = EXCLUDED.badge_key,
  reward_redemption_tickets = EXCLUDED.reward_redemption_tickets,
  is_active = true,
  updated_at = now();

-- ------------------------------------------------------------
-- 2. 徽章 catalog 与 Supabase Storage bucket
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('badges', 'badges', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "badges_read_all" ON storage.objects;
CREATE POLICY "badges_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'badges');

DROP POLICY IF EXISTS "badges_admin_insert" ON storage.objects;
CREATE POLICY "badges_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'badges' AND public.is_admin());

DROP POLICY IF EXISTS "badges_admin_update" ON storage.objects;
CREATE POLICY "badges_admin_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'badges' AND public.is_admin())
  WITH CHECK (bucket_id = 'badges' AND public.is_admin());

DROP POLICY IF EXISTS "badges_admin_delete" ON storage.objects;
CREATE POLICY "badges_admin_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'badges' AND public.is_admin());

CREATE TABLE IF NOT EXISTS public.badge_catalog (
  badge_key     TEXT PRIMARY KEY,
  badge_type    TEXT NOT NULL CHECK (badge_type IN ('level', 'founder', 'commemorative', 'behavior')),
  title         TEXT NOT NULL,
  level         INTEGER,
  image_bucket  TEXT NOT NULL DEFAULT 'badges',
  image_path    TEXT,
  back_image_bucket TEXT NOT NULL DEFAULT 'badges',
  back_image_path TEXT,
  riddle_key    TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT badge_catalog_level_for_level_badges CHECK (
    (badge_type = 'level' AND level IS NOT NULL) OR
    (badge_type <> 'level')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_badge_catalog_level_unique
  ON public.badge_catalog(level)
  WHERE badge_type = 'level' AND level IS NOT NULL;

ALTER TABLE public.badge_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "badge_catalog_read_all" ON public.badge_catalog;
CREATE POLICY "badge_catalog_read_all" ON public.badge_catalog FOR SELECT USING (true);
DROP POLICY IF EXISTS "badge_catalog_admin_write" ON public.badge_catalog;
CREATE POLICY "badge_catalog_admin_write" ON public.badge_catalog FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

INSERT INTO public.badge_catalog
  (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
VALUES
  ('level_01_wanderer',    'level',   '漫游者', 1,  'badges', 'final/lv01-wanderer.png',         'level_01_wanderer'),
  ('level_02_adventurer',  'level',   '冒险者', 2,  'badges', 'final/lv02-adventurer.png',       'level_02_adventurer'),
  ('level_03_chronicler',  'level',   '纪事者', 3,  'badges', 'final/lv03-chronicler.png',       'level_03_chronicler'),
  ('level_04_seeker',      'level',   '追寻者', 4,  'badges', 'final/lv04-seeker.png',           'level_04_seeker'),
  ('level_05_tunnel',      'level',   '隧行者', 5,  'badges', 'final/lv05-tunnel-walker.png',    'level_05_tunnel'),
  ('level_06_labyrinth',   'level',   '迷宫客', 6,  'badges', 'final/lv06-labyrinth-guest.png',  'level_06_labyrinth'),
  ('level_07_wallbreaker', 'level',   '破壁者', 7,  'badges', 'final/lv07-wallbreaker.png',      'level_07_wallbreaker'),
  ('level_08_player',      'level',   '游戏者', 8,  'badges', 'final/lv08-player.png',           'level_08_player'),
  ('level_09_wordtamer',   'level',   '驭词者', 9,  'badges', 'final/lv09-wordtamer.png',        'level_09_wordtamer'),
  ('level_10_stargazer',   'level',   '观星者', 10, 'badges', 'final/lv10-stargazer.png',        'level_10_stargazer'),
  ('level_11_architect',   'level',   '建筑师', 11, 'badges', 'final/lv11-architect.png',        'level_11_architect'),
  ('level_12_nether',      'level',   '冥语者', 12, 'badges', 'final/lv12-nether-speaker.png',   'level_12_nether'),
  ('level_13_wasteport',   'level',   '荒港客', 13, 'badges', 'final/lv13-wasteport-guest.png',  'level_13_wasteport'),
  ('level_14_alchemist',   'level',   '炼金士', 14, 'badges', 'final/lv14-alchemist.png',        'level_14_alchemist'),
  ('level_15_maskman',     'level',   '面具人', 15, 'badges', 'final/lv15-maskman.png',          'level_15_maskman'),
  ('level_16_godslayer',   'level',   '弑神者', 16, 'badges', 'final/lv16-godslayer.png',        'level_16_godslayer'),
  ('founder',              'founder', '开创者', NULL, 'badges', 'final/founder-v21.png',         'founder')
ON CONFLICT (badge_key) DO UPDATE SET
  badge_type = EXCLUDED.badge_type,
  title = EXCLUDED.title,
  level = EXCLUDED.level,
  image_bucket = EXCLUDED.image_bucket,
  image_path = EXCLUDED.image_path,
  riddle_key = EXCLUDED.riddle_key,
  is_active = true,
  updated_at = now();

-- ------------------------------------------------------------
-- 3. 用户会员汇总、徽章、资源浏览券、共读兑换券
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_stats (
  user_id                 UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  level                   INTEGER NOT NULL DEFAULT 0 REFERENCES public.member_levels(level),
  tier                    TEXT NOT NULL DEFAULT '基础会员',
  contribution_total      INTEGER NOT NULL DEFAULT 0,
  contribution_month      INTEGER NOT NULL DEFAULT 0,
  contribution_week       INTEGER NOT NULL DEFAULT 0,
  current_badge_key       TEXT REFERENCES public.badge_catalog(badge_key),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT member_stats_contribution_nonnegative CHECK (
    contribution_total >= 0 AND contribution_month >= 0 AND contribution_week >= 0
  )
);

CREATE INDEX IF NOT EXISTS idx_member_stats_level ON public.member_stats(level);
CREATE INDEX IF NOT EXISTS idx_member_stats_total ON public.member_stats(contribution_total DESC);
CREATE INDEX IF NOT EXISTS idx_member_stats_week ON public.member_stats(contribution_week DESC);

ALTER TABLE public.member_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "member_stats_read_self_or_admin" ON public.member_stats;
CREATE POLICY "member_stats_read_self_or_admin" ON public.member_stats FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "member_stats_admin_write" ON public.member_stats;
CREATE POLICY "member_stats_admin_write" ON public.member_stats FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.user_badges (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key         TEXT NOT NULL REFERENCES public.badge_catalog(badge_key),
  badge_type        TEXT NOT NULL CHECK (badge_type IN ('level', 'founder', 'commemorative', 'behavior')),
  awarded_reason    TEXT,
  awarded_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at        TIMESTAMPTZ,
  UNIQUE(user_id, badge_key)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON public.user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_badge ON public.user_badges(badge_key);

ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_badges_read_self_or_admin" ON public.user_badges;
CREATE POLICY "user_badges_read_self_or_admin" ON public.user_badges FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "user_badges_admin_write" ON public.user_badges;
CREATE POLICY "user_badges_admin_write" ON public.user_badges FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.view_passes (
  id                           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id                      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status                       TEXT NOT NULL DEFAULT 'available'
                               CHECK (status IN ('available', 'used', 'expired', 'revoked')),
  issued_reason                TEXT NOT NULL
                               CHECK (issued_reason IN ('signup', 'weekly', 'active_bonus', 'admin')),
  source_key                   TEXT,
  issued_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at                   TIMESTAMPTZ NOT NULL,
  used_at                      TIMESTAMPTZ,
  used_resource_key            TEXT,
  temporary_access_expires_at  TIMESTAMPTZ,
  revoked_at                   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_view_passes_user_status ON public.view_passes(user_id, status);
CREATE INDEX IF NOT EXISTS idx_view_passes_expires ON public.view_passes(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_view_passes_user_source_key
  ON public.view_passes(user_id, source_key)
  WHERE source_key IS NOT NULL;

ALTER TABLE public.view_passes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "view_passes_read_self_or_admin" ON public.view_passes;
CREATE POLICY "view_passes_read_self_or_admin" ON public.view_passes FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "view_passes_admin_write" ON public.view_passes;
CREATE POLICY "view_passes_admin_write" ON public.view_passes FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.resource_redemption_tickets (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available', 'used', 'revoked')),
  issued_level    INTEGER REFERENCES public.member_levels(level),
  issued_reason   TEXT NOT NULL CHECK (issued_reason IN ('level_up', 'admin')),
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at         TIMESTAMPTZ,
  used_book_id    BIGINT REFERENCES public.books(id),
  revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_redemption_tickets_user_status
  ON public.resource_redemption_tickets(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_redemption_level_reward_once
  ON public.resource_redemption_tickets(user_id, issued_level)
  WHERE issued_reason = 'level_up';

ALTER TABLE public.resource_redemption_tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "redemption_tickets_read_self_or_admin" ON public.resource_redemption_tickets;
CREATE POLICY "redemption_tickets_read_self_or_admin" ON public.resource_redemption_tickets FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "redemption_tickets_admin_write" ON public.resource_redemption_tickets;
CREATE POLICY "redemption_tickets_admin_write" ON public.resource_redemption_tickets FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- 4. 初始化、等级重算与注册触发
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.initialize_member_for_user(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.member_stats (
    user_id,
    level,
    tier,
    contribution_total,
    contribution_month,
    contribution_week,
    current_badge_key
  )
  VALUES (
    p_user_id,
    0,
    '基础会员',
    0,
    0,
    0,
    NULL
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.view_passes (
    user_id,
    status,
    issued_reason,
    source_key,
    issued_at,
    expires_at
  )
  VALUES (
    p_user_id,
    'available',
    'signup',
    'signup_initial_view_pass',
    now(),
    now() + interval '7 days'
  )
  ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key
    INTO v_new_level, v_new_tier, v_new_badge_key
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  IF v_new_level > COALESCE(v_old_level, 0) THEN
    INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
    SELECT p_user_id, ml.badge_key, 'level', 'level_up'
    FROM public.member_levels ml
    WHERE ml.level > COALESCE(v_old_level, 0)
      AND ml.level <= v_new_level
      AND ml.badge_key IS NOT NULL
    ON CONFLICT (user_id, badge_key) DO UPDATE SET
      revoked_at = NULL,
      awarded_reason = EXCLUDED.awarded_reason;

    INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
    SELECT p_user_id, 'available', ml.level, 'level_up'
    FROM public.member_levels ml
    WHERE ml.level > COALESCE(v_old_level, 0)
      AND ml.level <= v_new_level
      AND ml.reward_redemption_tickets > 0
    ON CONFLICT DO NOTHING;
  ELSIF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 新用户注册时：创建 profile + 初始化会员状态 + 发首次资源浏览券
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email))
  ON CONFLICT (id) DO NOTHING;

  PERFORM public.initialize_member_for_user(NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 为历史用户补齐会员状态和首次资源浏览券
SELECT public.initialize_member_for_user(id)
FROM public.profiles;

-- ------------------------------------------------------------
-- 5. 权限说明
-- ------------------------------------------------------------
COMMENT ON TABLE public.member_levels IS '会员等级配置：Lv.0-Lv.16、段位、贡献值区间和每周资源浏览券数量';
COMMENT ON TABLE public.member_stats IS '用户会员汇总：等级、段位、贡献值和当前等级徽章';
COMMENT ON TABLE public.badge_catalog IS '徽章配置：等级成长徽章、开创者徽章和后续纪念 / 行为徽章';
COMMENT ON TABLE public.user_badges IS '用户已获得徽章记录';
COMMENT ON TABLE public.view_passes IS '资源浏览券：首次注册、每周发放、活跃奖励或管理员发放';
COMMENT ON TABLE public.resource_redemption_tickets IS '共读兑换券：升级或管理员发放，用于后续永久解锁历史共读资源';

-- ============================================================
-- END migrate-v9-member-foundation.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v10-badge-display-preferences.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v10 迁移：用户个人中心徽章展示偏好
-- 支持用户在“更多徽章”页选择最多 6 枚徽章展示在个人中心
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_badge_display_preferences (
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key   TEXT NOT NULL REFERENCES public.badge_catalog(badge_key) ON DELETE CASCADE,
  sort_order  INTEGER NOT NULL CHECK (sort_order BETWEEN 1 AND 6),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_key),
  UNIQUE (user_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_member_badge_display_user_order
  ON public.member_badge_display_preferences(user_id, sort_order);

CREATE OR REPLACE FUNCTION public.check_member_badge_display_preference()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_badges ub
    WHERE ub.user_id = NEW.user_id
      AND ub.badge_key = NEW.badge_key
      AND ub.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot display a badge that the user has not earned';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.member_badge_display_preferences p
    WHERE p.user_id = NEW.user_id
      AND p.badge_key <> NEW.badge_key
  ) >= 6 THEN
    RAISE EXCEPTION 'A user can display at most 6 badges';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_member_badge_display_preference_check
  ON public.member_badge_display_preferences;
CREATE TRIGGER trg_member_badge_display_preference_check
  BEFORE INSERT OR UPDATE ON public.member_badge_display_preferences
  FOR EACH ROW EXECUTE FUNCTION public.check_member_badge_display_preference();

ALTER TABLE public.member_badge_display_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badge_display_read_self_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_read_self_or_admin"
  ON public.member_badge_display_preferences
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "badge_display_insert_self_earned_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_insert_self_earned_or_admin"
  ON public.member_badge_display_preferences
  FOR INSERT
  WITH CHECK (
    public.is_admin()
    OR (
      auth.uid() = user_id
      AND EXISTS (
        SELECT 1
        FROM public.user_badges ub
        WHERE ub.user_id = member_badge_display_preferences.user_id
          AND ub.badge_key = member_badge_display_preferences.badge_key
          AND ub.revoked_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "badge_display_update_self_earned_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_update_self_earned_or_admin"
  ON public.member_badge_display_preferences
  FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (
    public.is_admin()
    OR (
      auth.uid() = user_id
      AND EXISTS (
        SELECT 1
        FROM public.user_badges ub
        WHERE ub.user_id = member_badge_display_preferences.user_id
          AND ub.badge_key = member_badge_display_preferences.badge_key
          AND ub.revoked_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "badge_display_delete_self_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_delete_self_or_admin"
  ON public.member_badge_display_preferences
  FOR DELETE
  USING (auth.uid() = user_id OR public.is_admin());

COMMENT ON TABLE public.member_badge_display_preferences IS
  '用户个人中心徽章展示偏好：每人最多选择 6 枚已获得徽章';

-- ============================================================
-- END migrate-v10-badge-display-preferences.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v11-recalculate-member-level-backfill.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v11 迁移：修正会员等级重算补发逻辑
-- 让 recalculate_member_level 在重算时补齐当前等级应有徽章
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key
    INTO v_new_level, v_new_tier, v_new_badge_key
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 等级徽章是历史成就：重算时补齐当前等级及以下所有应有徽章。
  -- 这样即使管理员手动改过 level，或之前发放中断，再重算也能修复缺失徽章。
  INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
  SELECT p_user_id, ml.badge_key, 'level', 'level_recalculate'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.badge_key IS NOT NULL
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  -- 共读兑换券仍按等级奖励每级最多一张。这里补齐缺失记录，
  -- 已使用或已回收的同等级券不会重复创建。
  INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
  SELECT p_user_id, 'available', ml.level, 'level_up'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.reward_redemption_tickets > 0
  ON CONFLICT DO NOTHING;

  IF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.recalculate_member_level(UUID) IS
  '根据贡献值重算会员等级，补齐当前等级应有徽章和缺失的等级奖励券';

-- ============================================================
-- END migrate-v11-recalculate-member-level-backfill.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v12-weekly-contribution-rank.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v12 迁移：当前用户本周贡献排名
-- 为会员中心“本周贡献值”卡片提供当前周排名
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_my_weekly_contribution_rank()
RETURNS TABLE (
  rank_position INTEGER,
  total_members INTEGER,
  contribution_week INTEGER
) AS $$
  WITH ranked AS (
    SELECT
      ms.user_id,
      ms.contribution_week,
      RANK() OVER (ORDER BY ms.contribution_week DESC) AS rank_position,
      COUNT(*) OVER () AS total_members
    FROM public.member_stats ms
  )
  SELECT
    ranked.rank_position::INTEGER,
    ranked.total_members::INTEGER,
    ranked.contribution_week::INTEGER
  FROM ranked
  WHERE ranked.user_id = auth.uid();
$$ LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() TO authenticated;

COMMENT ON FUNCTION public.get_my_weekly_contribution_rank() IS
  '返回当前登录用户在 member_stats.contribution_week 中的本周贡献排名';

-- ============================================================
-- END migrate-v12-weekly-contribution-rank.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v13-reading-posts-contributions.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v13 迁移：书友圈与阅读动态贡献值
-- 公开 / 私密阅读动态、贡献值流水、发布计分和删除 / 改私密回收
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.contribution_logs (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id             UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  source_type         TEXT NOT NULL,
  source_id           BIGINT,
  points              INTEGER NOT NULL,
  reason              TEXT NOT NULL,
  contribution_scope  TEXT NOT NULL DEFAULT 'reading_activity'
                      CHECK (contribution_scope IN ('reading_activity', 'system_reward', 'admin_adjustment')),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  revoked_at          TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contribution_logs_user_active
  ON public.contribution_logs(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_contribution_logs_source
  ON public.contribution_logs(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_contribution_logs_scope_active
  ON public.contribution_logs(contribution_scope, is_active);

ALTER TABLE public.contribution_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contribution_logs_read_self_or_admin" ON public.contribution_logs;
CREATE POLICY "contribution_logs_read_self_or_admin"
  ON public.contribution_logs
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "contribution_logs_admin_write" ON public.contribution_logs;
CREATE POLICY "contribution_logs_admin_write"
  ON public.contribution_logs
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.reading_posts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_type       TEXT NOT NULL CHECK (post_type IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review')),
  book_title      TEXT NOT NULL,
  author          TEXT,
  douban_url      TEXT,
  cover_url       TEXT,
  linked_book_id  BIGINT REFERENCES public.books(id) ON DELETE SET NULL,
  content         TEXT,
  visibility      TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  like_count      INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
  comment_count   INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  is_featured     BOOLEAN NOT NULL DEFAULT false,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reading_posts_public
  ON public.reading_posts(created_at DESC)
  WHERE visibility = 'public' AND is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_reading_posts_user
  ON public.reading_posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reading_posts_type
  ON public.reading_posts(post_type);

ALTER TABLE public.reading_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reading_posts_read_public_self_or_admin" ON public.reading_posts;
CREATE POLICY "reading_posts_read_public_self_or_admin"
  ON public.reading_posts
  FOR SELECT
  USING (
    (visibility = 'public' AND is_deleted = false)
    OR auth.uid() = user_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "reading_posts_admin_write" ON public.reading_posts;
CREATE POLICY "reading_posts_admin_write"
  ON public.reading_posts
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.apply_member_contribution_delta(
  p_user_id UUID,
  p_delta INTEGER
)
RETURNS VOID AS $$
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  UPDATE public.member_stats
  SET contribution_total = GREATEST(contribution_total + p_delta, 0),
      contribution_month = GREATEST(contribution_month + p_delta, 0),
      contribution_week = GREATEST(contribution_week + p_delta, 0),
      updated_at = now()
  WHERE user_id = p_user_id;

  PERFORM public.recalculate_member_level(p_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.award_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_today_count INTEGER;
  v_delta INTEGER := 0;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF NOT FOUND OR v_post.is_deleted OR v_post.visibility <> 'public' THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND is_active = true
  ) THEN
    RETURN;
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_count
  FROM public.contribution_logs
  WHERE user_id = v_post.user_id
    AND source_type = 'reading_post'
    AND reason = 'post_publish'
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_count >= 3 THEN
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_post.user_id, 'reading_post', p_post_id, 1, 'post_publish', 'reading_activity');
  v_delta := v_delta + 1;

  IF char_length(COALESCE(v_post.content, '')) >= 50 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 2, 'post_long_content', 'reading_activity');
    v_delta := v_delta + 2;
  END IF;

  IF v_post.post_type = 'finished' THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 5, 'post_finished_book', 'reading_activity');
    v_delta := v_delta + 5;
  END IF;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.revoke_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_delta INTEGER;
BEGIN
  SELECT user_id
    INTO v_user_id
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(points), 0)
    INTO v_delta
  FROM public.contribution_logs
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  UPDATE public.contribution_logs
  SET is_active = false,
      revoked_at = now()
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_user_id, -v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    content,
    visibility,
    linked_book_id
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    NULLIF(trim(COALESCE(p_douban_url, '')), ''),
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    p_visibility,
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.update_reading_post_visibility(
  p_post_id BIGINT,
  p_visibility TEXT
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND user_id = auth.uid()
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF v_post.visibility = p_visibility THEN
    RETURN;
  END IF;

  UPDATE public.reading_posts
  SET visibility = p_visibility,
      updated_at = now()
  WHERE id = p_post_id;

  IF p_visibility = 'private' THEN
    PERFORM public.revoke_reading_post_contributions(p_post_id);
  ELSE
    PERFORM public.award_reading_post_contributions(p_post_id);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.delete_reading_post(p_post_id BIGINT)
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.reading_posts
    WHERE id = p_post_id
      AND user_id = auth.uid()
      AND is_deleted = false
  ) THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  UPDATE public.reading_posts
  SET is_deleted = true,
      updated_at = now()
  WHERE id = p_post_id;

  PERFORM public.revoke_reading_post_contributions(p_post_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.set_reading_post_featured(
  p_post_id BIGINT,
  p_featured BOOLEAN
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_existing_featured_points INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF p_featured AND v_post.visibility <> 'public' THEN
    RAISE EXCEPTION 'Only public posts can be featured';
  END IF;

  UPDATE public.reading_posts
  SET is_featured = p_featured,
      updated_at = now()
  WHERE id = p_post_id;

  SELECT COALESCE(SUM(points), 0)
    INTO v_existing_featured_points
  FROM public.contribution_logs
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND reason = 'post_featured'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF p_featured AND v_existing_featured_points = 0 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 10, 'post_featured', 'reading_activity');

    PERFORM public.apply_member_contribution_delta(v_post.user_id, 10);
  ELSIF NOT p_featured AND v_existing_featured_points <> 0 THEN
    UPDATE public.contribution_logs
    SET is_active = false,
        revoked_at = now()
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND reason = 'post_featured'
      AND contribution_scope = 'reading_activity'
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -v_existing_featured_points);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  content TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.content,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_reading_post_visibility(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_reading_post(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_reading_post_featured(BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

COMMENT ON TABLE public.contribution_logs IS '贡献值流水：记录阅读动态、系统奖励和管理员调整产生的贡献值';
COMMENT ON TABLE public.reading_posts IS '书友圈阅读动态：想读、在读、已读、摘抄、感想和书评';

-- ============================================================
-- END migrate-v13-reading-posts-contributions.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v14-reading-post-douban-required.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v14 迁移：书友圈发布要求豆瓣链接与书名
-- 后端约束动态类型、可见范围、书名、豆瓣链接必填
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.reading_posts
  ALTER COLUMN douban_url SET NOT NULL;

ALTER TABLE public.reading_posts
  ALTER COLUMN book_title SET NOT NULL;

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = ''
    OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?'
  THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    content,
    visibility,
    linked_book_id
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    p_visibility,
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- END migrate-v14-reading-post-douban-required.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v15-revoke-level-badges-on-downgrade.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v15 迁移：降级时回收高等级成长徽章
-- 防止通过低质量互动短期刷取高等级徽章后永久保留
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key
    INTO v_new_level, v_new_tier, v_new_badge_key
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 补齐当前等级及以下应有等级徽章。
  INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
  SELECT p_user_id, ml.badge_key, 'level', 'level_recalculate'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.badge_key IS NOT NULL
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  -- 降级或贡献值回收后，回收高于当前等级的成长徽章。
  -- 开创者、纪念徽章、行为徽章不受等级回退影响。
  UPDATE public.user_badges ub
  SET revoked_at = now()
  FROM public.badge_catalog bc
  WHERE ub.user_id = p_user_id
    AND ub.badge_key = bc.badge_key
    AND ub.badge_type = 'level'
    AND bc.badge_type = 'level'
    AND bc.level > v_new_level
    AND ub.revoked_at IS NULL;

  -- 共读兑换券仍按等级奖励每级最多一张。这里补齐缺失记录，
  -- 已使用或已回收的同等级券不会重复创建。
  INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
  SELECT p_user_id, 'available', ml.level, 'level_up'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.reward_redemption_tickets > 0
  ON CONFLICT DO NOTHING;

  IF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.recalculate_member_level(UUID) IS
  '根据贡献值重算会员等级，补齐当前等级应有徽章，并回收高于当前等级的成长徽章和未使用升级券';

-- ============================================================
-- END migrate-v15-revoke-level-badges-on-downgrade.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v16-reading-post-excerpt-mood.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v16 迁移：书友圈摘抄独立字段与阅读心情
-- 摘抄 excerpt 与感想/书评 content 分离；mood_color 控制卡片边框色
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS excerpt TEXT;

ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS mood_color TEXT;

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_mood_color_valid;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_mood_color_valid
  CHECK (mood_color IS NULL OR mood_color ~ '^#[0-9A-Fa-f]{6}$');

CREATE OR REPLACE FUNCTION public.award_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_today_count INTEGER;
  v_delta INTEGER := 0;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_text_length INTEGER;
BEGIN
  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF NOT FOUND OR v_post.is_deleted OR v_post.visibility <> 'public' THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND is_active = true
  ) THEN
    RETURN;
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_count
  FROM public.contribution_logs
  WHERE user_id = v_post.user_id
    AND source_type = 'reading_post'
    AND reason = 'post_publish'
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_count >= 3 THEN
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_post.user_id, 'reading_post', p_post_id, 1, 'post_publish', 'reading_activity');
  v_delta := v_delta + 1;

  v_text_length := char_length(COALESCE(v_post.content, ''));
  IF v_text_length >= 50 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 2, 'post_long_content', 'reading_activity');
    v_delta := v_delta + 2;
  END IF;

  IF v_post.post_type = 'finished' THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 5, 'post_finished_book', 'reading_activity');
    v_delta := v_delta + 5;
  END IF;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
  v_mood_color TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = ''
    OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?'
  THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;

  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    excerpt,
    content,
    mood_color,
    visibility,
    linked_book_id
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_excerpt, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    v_mood_color,
    p_visibility,
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

-- ============================================================
-- END migrate-v16-reading-post-excerpt-mood.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v17-reading-post-rating.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v17 迁移：书友圈动态类型精简 + 已读评分
-- 动态类型限制为 想读/在读/已读 三种；已读时可填写 -10~10 评分
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 添加评分列（-10 ~ 10，最多2位小数）
ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS rating NUMERIC(4,2);

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_rating_range;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_rating_range
  CHECK (rating IS NULL OR (rating >= -10 AND rating <= 10));

-- 2. 更新 post_type 约束为三种
-- 注意：如果表中已存在旧类型（excerpt/reflection/review）的记录，需要先处理
-- 可选：将旧类型记录迁移到兼容类型，或删除旧记录
-- UPDATE public.reading_posts SET post_type = 'finished' WHERE post_type IN ('excerpt', 'reflection', 'review');

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_post_type_check;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_post_type_check
  CHECK (post_type IN ('want', 'reading', 'finished'));

-- 3. 更新 create_reading_post 函数：新增 p_rating 参数，精简 post_type 校验
DROP FUNCTION IF EXISTS public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
  v_mood_color TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = ''
    OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?'
  THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;

  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
  END IF;

  -- 评分仅已读类型可填，校验范围 -10~10，最多2位小数
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    excerpt,
    content,
    mood_color,
    visibility,
    linked_book_id,
    rating
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_excerpt, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    v_mood_color,
    p_visibility,
    p_linked_book_id,
    p_rating
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. 更新 list_reading_posts 函数：返回 rating 字段
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 授权
GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

COMMENT ON TABLE public.reading_posts IS '书友圈阅读动态：想读、在读、已读（附评分）';

-- ============================================================
-- END migrate-v17-reading-post-rating.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v18-reading-post-edit.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v18 迁移：书友圈编辑功能
-- 允许作者编辑已发布动态的内容字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_reading_post(
  p_post_id BIGINT,
  p_post_type TEXT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_old_visibility TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND user_id = auth.uid()
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found or access denied';
  END IF;

  IF p_post_type IS NOT NULL THEN
    IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
      RAISE EXCEPTION 'Invalid post type';
    END IF;
    UPDATE public.reading_posts SET post_type = p_post_type WHERE id = p_post_id;
  END IF;

  IF p_excerpt IS NOT NULL THEN
    UPDATE public.reading_posts SET excerpt = NULLIF(trim(p_excerpt), '') WHERE id = p_post_id;
  END IF;

  IF p_content IS NOT NULL THEN
    UPDATE public.reading_posts SET content = NULLIF(trim(p_content), '') WHERE id = p_post_id;
  END IF;

  IF p_mood_color IS NOT NULL THEN
    IF p_mood_color != '' AND p_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
      RAISE EXCEPTION 'Invalid mood color';
    END IF;
    UPDATE public.reading_posts
      SET mood_color = NULLIF(trim(p_mood_color), '')
      WHERE id = p_post_id;
  END IF;

  IF p_visibility IS NOT NULL THEN
    IF p_visibility NOT IN ('public', 'private') THEN
      RAISE EXCEPTION 'Invalid visibility';
    END IF;
    v_old_visibility := v_post.visibility;
    UPDATE public.reading_posts SET visibility = p_visibility WHERE id = p_post_id;
    IF v_old_visibility != p_visibility THEN
      IF p_visibility = 'private' THEN
        PERFORM public.revoke_reading_post_contributions(p_post_id);
      ELSE
        PERFORM public.award_reading_post_contributions(p_post_id);
      END IF;
    END IF;
  END IF;

  -- 评分：传 null 清空，传数值校验后更新
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;
  UPDATE public.reading_posts SET rating = p_rating WHERE id = p_post_id;

  UPDATE public.reading_posts SET updated_at = now() WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;

-- ============================================================
-- END migrate-v18-reading-post-edit.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v19-likes-comments.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v19 迁移：点赞、评论与升级奖励完善
-- Phase 4: post_likes + post_comments 表 + RPC 函数
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- ============================================================
-- 1. post_likes 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.post_likes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_post ON public.post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user ON public.post_likes(user_id, created_at DESC);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_likes_read_all" ON public.post_likes;
CREATE POLICY "post_likes_read_all"
  ON public.post_likes FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "post_likes_insert_own" ON public.post_likes;
CREATE POLICY "post_likes_insert_own"
  ON public.post_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "post_likes_delete_own" ON public.post_likes;
CREATE POLICY "post_likes_delete_own"
  ON public.post_likes FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 2. post_comments 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.post_comments (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content     TEXT NOT NULL CHECK (char_length(trim(content)) > 0),
  is_deleted  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post ON public.post_comments(post_id, created_at ASC)
  WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_post_comments_user ON public.post_comments(user_id, created_at DESC);

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_comments_read_all" ON public.post_comments;
CREATE POLICY "post_comments_read_all"
  ON public.post_comments FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "post_comments_insert_own" ON public.post_comments;
CREATE POLICY "post_comments_insert_own"
  ON public.post_comments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "post_comments_update_own" ON public.post_comments;
CREATE POLICY "post_comments_update_own"
  ON public.post_comments FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================================
-- 3. toggle_post_like — 点赞/取消点赞
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id BIGINT)
RETURNS TEXT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_existing_like BIGINT;
  v_today_like_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_action TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  -- 不能给自己点赞
  IF v_post.user_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot like your own post';
  END IF;

  SELECT id INTO v_existing_like
  FROM public.post_likes
  WHERE post_id = p_post_id AND user_id = v_user_id;

  IF FOUND THEN
    -- 取消点赞
    DELETE FROM public.post_likes WHERE id = v_existing_like;
    UPDATE public.reading_posts
      SET like_count = GREATEST(like_count - 1, 0), updated_at = now()
      WHERE id = p_post_id;

    -- 回收点赞贡献值
    UPDATE public.contribution_logs
    SET is_active = false, revoked_at = now()
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND source_id = v_existing_like
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -1);
    v_action := 'unliked';
  ELSE
    -- 点赞
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (p_post_id, v_user_id)
    RETURNING id INTO v_existing_like;

    UPDATE public.reading_posts
      SET like_count = like_count + 1, updated_at = now()
      WHERE id = p_post_id;

    -- 检查作者今日点赞贡献值上限（每日 10）
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_like_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND reason = 'received_like'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_like_count < 10 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_like', v_existing_like, 1, 'received_like', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 1);
    END IF;

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 4. create_comment — 发表评论
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_content, '')) = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  -- 每天最多 50 条评论（防刷）
  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content)
  VALUES (p_post_id, v_user_id, trim(p_content))
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  -- 给动态作者发放评论贡献值（每日上限 20，不对自己评论加分）
  IF v_post.user_id <> v_user_id THEN
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 5. delete_comment — 删除评论（软删除）
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_comment(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_comment public.post_comments%ROWTYPE;
  v_post public.reading_posts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_comment
  FROM public.post_comments
  WHERE id = p_comment_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comment not found';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = v_comment.post_id AND is_deleted = false;

  -- 仅评论作者或动态作者可删除
  IF v_comment.user_id <> auth.uid() AND v_post.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.post_comments
  SET is_deleted = true, updated_at = now()
  WHERE id = p_comment_id;

  UPDATE public.reading_posts
    SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now()
    WHERE id = v_comment.post_id;

  -- 回收评论贡献值
  UPDATE public.contribution_logs
  SET is_active = false, revoked_at = now()
  WHERE user_id = v_post.user_id
    AND source_type = 'post_comment'
    AND source_id = p_comment_id
    AND is_active = true;

  IF FOUND THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, -2);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 6. list_comments — 获取某条动态的评论列表
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_comments(p_post_id BIGINT)
RETURNS TABLE (
  id BIGINT,
  post_id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  content TEXT,
  is_deleted BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.post_id,
    pc.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    pc.content,
    pc.is_deleted,
    pc.created_at,
    pc.updated_at
  FROM public.post_comments pc
  LEFT JOIN public.profiles p ON p.id = pc.user_id
  WHERE pc.post_id = p_post_id
    AND pc.is_deleted = false
  ORDER BY pc.created_at ASC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 7. 更新 list_reading_posts：追加 has_liked 字段
-- ============================================================
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC,
  has_liked BOOLEAN
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ) AS has_liked
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 8. 授权
-- ============================================================
GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_comment(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_comments(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

-- ============================================================
-- END migrate-v19-likes-comments.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v20-post-author-level.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v20 迁移：书友圈动态卡片展示用户等级
-- list_reading_posts 追加 member_level 和 member_title 字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC,
  has_liked BOOLEAN,
  member_level INTEGER,
  member_title TEXT
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ) AS has_liked,
    COALESCE(ms.level, 0) AS member_level,
    COALESCE(ml.title, '') AS member_title
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = ms.level
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

-- ============================================================
-- END migrate-v20-post-author-level.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v21-user-profile.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v21 迁移：用户个人主页
-- get_public_member_profile：公开的会员信息
-- list_user_public_posts：某用户的公开书友圈
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 公开会员信息
CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    COALESCE(ms.level, 0),
    COALESCE(ms.tier, '基础会员'),
    COALESCE(ml.title, ''),
    COALESCE(ms.contribution_total, 0),
    COALESCE(ms.contribution_month, 0),
    COALESCE(ms.contribution_week, 0),
    ms.current_badge_key
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 2. 某用户的公开书友圈
CREATE OR REPLACE FUNCTION public.list_user_public_posts(p_user_id UUID)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC,
  has_liked BOOLEAN,
  member_level INTEGER,
  member_title TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ),
    COALESCE(ms.level, 0),
    COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.user_id = p_user_id
    AND rp.is_deleted = false
    AND rp.visibility = 'public'
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_public_posts(UUID) TO anon, authenticated;

-- ============================================================
-- END migrate-v21-user-profile.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v22-contribution-leaderboard.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v22 迁移：贡献榜单
-- 总榜 / 月榜 / 周榜，各取前10名，同分按注册时间先后排序
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_contribution_leaderboard(p_type TEXT DEFAULT 'total')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  contribution INTEGER
) AS $$
BEGIN
  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY
        CASE p_type
          WHEN 'total' THEN ms.contribution_total
          WHEN 'month' THEN ms.contribution_month
          WHEN 'week'  THEN ms.contribution_week
        END DESC,
        p.created_at ASC
    )::BIGINT AS rank,
    ms.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    COALESCE(ms.level, 0) AS level,
    COALESCE(ml.title, '') AS title,
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END AS contribution
  FROM public.member_stats ms
  JOIN public.profiles p ON p.id = ms.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END > 0
  ORDER BY
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END DESC,
    p.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO anon, authenticated;

-- ============================================================
-- END migrate-v22-contribution-leaderboard.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v23-notifications.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v23 迁移：消息通知系统
-- 点赞/评论时通知动态作者，铃铛图标+红点+下拉面板
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 通知表
CREATE TABLE IF NOT EXISTS public.notifications (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN ('like', 'comment')),
  actor_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  is_read     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications(user_id, created_at DESC)
  WHERE is_read = false;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_read_own" ON public.notifications;
CREATE POLICY "notifications_read_own"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
CREATE POLICY "notifications_update_own"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- 2. 更新 toggle_post_like：点赞时写入通知
CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id BIGINT)
RETURNS TEXT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_existing_like BIGINT;
  v_today_like_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_action TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF v_post.user_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot like your own post';
  END IF;

  SELECT id INTO v_existing_like
  FROM public.post_likes
  WHERE post_id = p_post_id AND user_id = v_user_id;

  IF FOUND THEN
    DELETE FROM public.post_likes WHERE id = v_existing_like;
    UPDATE public.reading_posts
      SET like_count = GREATEST(like_count - 1, 0), updated_at = now()
      WHERE id = p_post_id;

    UPDATE public.contribution_logs
    SET is_active = false, revoked_at = now()
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND source_id = v_existing_like
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -1);
    v_action := 'unliked';
  ELSE
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (p_post_id, v_user_id)
    RETURNING id INTO v_existing_like;

    UPDATE public.reading_posts
      SET like_count = like_count + 1, updated_at = now()
      WHERE id = p_post_id;

    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_like_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND reason = 'received_like'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_like_count < 10 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_like', v_existing_like, 1, 'received_like', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 1);
    END IF;

    -- 写入通知
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'like', v_user_id, p_post_id);

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 create_comment：评论时写入通知（不自评）
CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_content, '')) = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content)
  VALUES (p_post_id, v_user_id, trim(p_content))
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  IF v_post.user_id <> v_user_id THEN
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;

    -- 写入通知
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id);
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. 获取通知列表
CREATE OR REPLACE FUNCTION public.get_notifications(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  id BIGINT,
  type TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMPTZ,
  actor_id UUID,
  actor_name TEXT,
  actor_avatar TEXT,
  post_id BIGINT,
  book_title TEXT
) AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.type,
    n.is_read,
    n.created_at,
    n.actor_id,
    COALESCE(ap.display_name, '书友') AS actor_name,
    ap.avatar_url AS actor_avatar,
    n.post_id,
    rp.book_title
  FROM public.notifications n
  JOIN public.profiles ap ON ap.id = n.actor_id
  JOIN public.reading_posts rp ON rp.id = n.post_id
  WHERE n.user_id = auth.uid()
  ORDER BY n.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 未读数量
CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
RETURNS BIGINT AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.notifications
  WHERE user_id = auth.uid() AND is_read = false;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 6. 标记已读
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids BIGINT[])
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE user_id = auth.uid()
    AND id = ANY(p_ids);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 7. 全部已读
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE user_id = auth.uid()
    AND is_read = false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 8. 授权
GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(BIGINT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

-- ============================================================
-- 9. 历史数据补录（部署后执行一次即可）
-- ============================================================

-- 历史点赞 → 通知（跳过给自己的点赞）
INSERT INTO public.notifications (user_id, type, actor_id, post_id, created_at, is_read)
SELECT
  rp.user_id,
  'like',
  pl.user_id,
  pl.post_id,
  pl.created_at,
  true  -- 历史消息默认已读
FROM public.post_likes pl
JOIN public.reading_posts rp ON rp.id = pl.post_id
WHERE rp.user_id <> pl.user_id
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.type = 'like'
      AND n.actor_id = pl.user_id
      AND n.post_id = pl.post_id
      AND n.created_at = pl.created_at
  );

-- 历史评论 → 通知（跳过给自己的评论）
INSERT INTO public.notifications (user_id, type, actor_id, post_id, created_at, is_read)
SELECT
  rp.user_id,
  'comment',
  pc.user_id,
  pc.post_id,
  pc.created_at,
  true  -- 历史消息默认已读
FROM public.post_comments pc
JOIN public.reading_posts rp ON rp.id = pc.post_id
WHERE rp.user_id <> pc.user_id
  AND pc.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.type = 'comment'
      AND n.actor_id = pc.user_id
      AND n.post_id = pc.post_id
      AND n.created_at = pc.created_at
  );

-- ============================================================
-- END migrate-v23-notifications.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v24-comment-anti-spam-notification-dedupe.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v24 迁移：评论防刷、通知去重
-- 评论 800 字上限；同一用户同一动态 10 分钟内禁止重复评论；
-- 点赞/评论通知按未读维度去重，避免通知列表被刷屏。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 通知去重索引：同一接收者、同一类型、同一触发者、同一动态，只保留一条未读通知
-- 如果已存在重复未读通知，先把较旧的重复项标为已读，保留最新的一条未读。
WITH ranked_unread AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY user_id, type, actor_id, post_id
      ORDER BY created_at DESC, id DESC
    ) AS rn
  FROM public.notifications
  WHERE is_read = false
)
UPDATE public.notifications n
SET is_read = true
FROM ranked_unread r
WHERE n.id = r.id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unread_dedupe
  ON public.notifications(user_id, type, actor_id, post_id)
  WHERE is_read = false;

-- 2. 更新 toggle_post_like：点赞通知未读去重
CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id BIGINT)
RETURNS TEXT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_existing_like BIGINT;
  v_today_like_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_action TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF v_post.user_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot like your own post';
  END IF;

  SELECT id INTO v_existing_like
  FROM public.post_likes
  WHERE post_id = p_post_id AND user_id = v_user_id;

  IF FOUND THEN
    DELETE FROM public.post_likes WHERE id = v_existing_like;
    UPDATE public.reading_posts
      SET like_count = GREATEST(like_count - 1, 0), updated_at = now()
      WHERE id = p_post_id;

    UPDATE public.contribution_logs
    SET is_active = false, revoked_at = now()
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND source_id = v_existing_like
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -1);
    v_action := 'unliked';
  ELSE
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (p_post_id, v_user_id)
    RETURNING id INTO v_existing_like;

    UPDATE public.reading_posts
      SET like_count = like_count + 1, updated_at = now()
      WHERE id = p_post_id;

    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_like_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND reason = 'received_like'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_like_count < 10 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_like', v_existing_like, 1, 'received_like', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 1);
    END IF;

    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'like', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 create_comment：800 字上限、重复评论防刷、评论通知未读去重
CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  v_content := trim(COALESCE(p_content, ''));
  IF v_content = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  IF char_length(v_content) > 800 THEN
    RAISE EXCEPTION 'Comment content exceeds 800 characters';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.post_comments
    WHERE post_id = p_post_id
      AND user_id = v_user_id
      AND is_deleted = false
      AND content = v_content
      AND created_at >= now() - interval '10 minutes'
  ) THEN
    RAISE EXCEPTION 'Duplicate comment too soon';
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content)
  VALUES (p_post_id, v_user_id, v_content)
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  IF v_post.user_id <> v_user_id THEN
    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;

    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;

-- ============================================================
-- END migrate-v24-comment-anti-spam-notification-dedupe.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v25-resource-access.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v25 迁移：资源权限与票券解锁
-- 永久权限按 book_id 授予；临时权限按 resource_key 授予 72 小时
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.resource_access_grants (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  resource_scope  TEXT NOT NULL DEFAULT 'book' CHECK (resource_scope IN ('book', 'resource')),
  resource_key    TEXT,
  grant_type      TEXT NOT NULL CHECK (grant_type IN ('commemorative', 'redeemed', 'founder', 'admin')),
  source_id       BIGINT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_resource_access_user_book
  ON public.resource_access_grants(user_id, book_id)
  WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_access_unique_active_book
  ON public.resource_access_grants(user_id, book_id, resource_scope)
  WHERE revoked_at IS NULL AND resource_scope = 'book';

ALTER TABLE public.resource_access_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "resource_access_read_self_or_admin" ON public.resource_access_grants;
CREATE POLICY "resource_access_read_self_or_admin"
  ON public.resource_access_grants FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "resource_access_admin_write" ON public.resource_access_grants;
CREATE POLICY "resource_access_admin_write"
  ON public.resource_access_grants FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.expire_view_passes_for_user(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.view_passes
  SET status = 'expired',
      revoked_at = COALESCE(revoked_at, now())
  WHERE user_id = p_user_id
    AND status = 'available'
    AND expires_at <= now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_resource_access_summary(p_book_id BIGINT)
RETURNS TABLE (
  has_permanent_access BOOLEAN,
  available_view_passes INTEGER,
  available_redemption_tickets INTEGER,
  temporary_resource_keys TEXT[]
) AS $$
DECLARE
  v_user_id UUID;
  v_is_admin BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, 0, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT public.is_admin() INTO v_is_admin;

  RETURN QUERY
  SELECT
    (
      COALESCE(v_is_admin, false)
      OR EXISTS (
        SELECT 1
        FROM public.resource_access_grants rag
        WHERE rag.user_id = v_user_id
          AND rag.book_id = p_book_id
          AND rag.resource_scope = 'book'
          AND rag.revoked_at IS NULL
      )
    ) AS has_permanent_access,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'available'
        AND vp.expires_at > now()
    ) AS available_view_passes,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.resource_redemption_tickets rt
      WHERE rt.user_id = v_user_id
        AND rt.status = 'available'
    ) AS available_redemption_tickets,
    COALESCE((
      SELECT array_agg(vp.used_resource_key)
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'used'
        AND vp.used_resource_key IS NOT NULL
        AND vp.temporary_access_expires_at > now()
        AND vp.used_resource_key LIKE ('book:' || p_book_id || ':%')
    ), ARRAY[]::TEXT[]) AS temporary_resource_keys;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.consume_view_pass(
  p_book_id BIGINT,
  p_resource_key TEXT
)
RETURNS TIMESTAMPTZ AS $$
DECLARE
  v_user_id UUID;
  v_pass_id BIGINT;
  v_existing_expires TIMESTAMPTZ;
  v_new_expires TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_resource_key IS NULL OR p_resource_key !~ ('^book:' || p_book_id || ':') THEN
    RAISE EXCEPTION 'Invalid resource key';
  END IF;

  IF public.is_admin() OR EXISTS (
    SELECT 1
    FROM public.resource_access_grants rag
    WHERE rag.user_id = v_user_id
      AND rag.book_id = p_book_id
      AND rag.resource_scope = 'book'
      AND rag.revoked_at IS NULL
  ) THEN
    RETURN now() + interval '100 years';
  END IF;

  SELECT vp.temporary_access_expires_at
    INTO v_existing_expires
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'used'
    AND vp.used_resource_key = p_resource_key
    AND vp.temporary_access_expires_at > now()
  ORDER BY vp.temporary_access_expires_at DESC
  LIMIT 1;

  IF v_existing_expires IS NOT NULL THEN
    RETURN v_existing_expires;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT vp.id
    INTO v_pass_id
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'available'
    AND vp.expires_at > now()
  ORDER BY vp.expires_at ASC, vp.issued_at ASC
  LIMIT 1
  FOR UPDATE;

  IF v_pass_id IS NULL THEN
    RAISE EXCEPTION 'No available view pass';
  END IF;

  v_new_expires := now() + interval '72 hours';

  UPDATE public.view_passes
  SET status = 'used',
      used_at = now(),
      used_resource_key = p_resource_key,
      temporary_access_expires_at = v_new_expires
  WHERE id = v_pass_id;

  RETURN v_new_expires;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.redeem_book_access(p_book_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_ticket_id BIGINT;
  v_grant_id BIGINT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT rag.id
    INTO v_grant_id
  FROM public.resource_access_grants rag
  WHERE rag.user_id = v_user_id
    AND rag.book_id = p_book_id
    AND rag.resource_scope = 'book'
    AND rag.revoked_at IS NULL
  LIMIT 1;

  IF v_grant_id IS NOT NULL THEN
    RETURN v_grant_id;
  END IF;

  SELECT rt.id
    INTO v_ticket_id
  FROM public.resource_redemption_tickets rt
  WHERE rt.user_id = v_user_id
    AND rt.status = 'available'
  ORDER BY rt.issued_at ASC
  LIMIT 1
  FOR UPDATE;

  IF v_ticket_id IS NULL THEN
    RAISE EXCEPTION 'No available redemption ticket';
  END IF;

  UPDATE public.resource_redemption_tickets
  SET status = 'used',
      used_at = now(),
      used_book_id = p_book_id
  WHERE id = v_ticket_id;

  INSERT INTO public.resource_access_grants
    (user_id, book_id, resource_scope, grant_type, source_id)
  VALUES
    (v_user_id, p_book_id, 'book', 'redeemed', v_ticket_id)
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_resource_access_summary(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_view_pass(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_book_access(BIGINT) TO authenticated;

COMMENT ON TABLE public.resource_access_grants IS
  '受保护资源永久权限：第一版按 book_id 授权整本书 / 整期共读资源';

-- ============================================================
-- END migrate-v25-resource-access.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v26-co-reading-claims.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v26 迁移：共读密码、纪念券、纪念徽章与周券发放
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- 1. 书籍加入页配置
-- ------------------------------------------------------------
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_intro TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_qr_url TEXT;

-- ------------------------------------------------------------
-- 2. 共读密码与领取记录
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.co_reading_passwords (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  book_id       BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  label         TEXT NOT NULL DEFAULT '共读密码',
  password_hash TEXT NOT NULL,
  password_plain TEXT,
  starts_at     TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_co_reading_passwords_book
  ON public.co_reading_passwords(book_id, is_active);

ALTER TABLE public.co_reading_passwords ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "co_reading_passwords_admin_read" ON public.co_reading_passwords;
CREATE POLICY "co_reading_passwords_admin_read"
  ON public.co_reading_passwords FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "co_reading_passwords_admin_write" ON public.co_reading_passwords;
CREATE POLICY "co_reading_passwords_admin_write"
  ON public.co_reading_passwords FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.co_reading_claims (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  password_id     BIGINT REFERENCES public.co_reading_passwords(id) ON DELETE SET NULL,
  group_member_id TEXT NOT NULL,
  claimed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_co_reading_claims_book
  ON public.co_reading_claims(book_id, claimed_at DESC);

ALTER TABLE public.co_reading_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "co_reading_claims_read_self_or_admin" ON public.co_reading_claims;
CREATE POLICY "co_reading_claims_read_self_or_admin"
  ON public.co_reading_claims FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "co_reading_claims_admin_write" ON public.co_reading_claims;
CREATE POLICY "co_reading_claims_admin_write"
  ON public.co_reading_claims FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.commemorative_tickets (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  claim_id        BIGINT REFERENCES public.co_reading_claims(id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  group_member_id TEXT,
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at      TIMESTAMPTZ,
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_commemorative_tickets_user
  ON public.commemorative_tickets(user_id, status);

ALTER TABLE public.commemorative_tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "commemorative_tickets_read_self_or_admin" ON public.commemorative_tickets;
CREATE POLICY "commemorative_tickets_read_self_or_admin"
  ON public.commemorative_tickets FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "commemorative_tickets_admin_write" ON public.commemorative_tickets;
CREATE POLICY "commemorative_tickets_admin_write"
  ON public.commemorative_tickets FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- 3. 开创者徽章即权限
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_founder_badge(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.user_badges ub
    JOIN public.badge_catalog bc ON bc.badge_key = ub.badge_key
    WHERE ub.user_id = p_user_id
      AND ub.revoked_at IS NULL
      AND (ub.badge_key = 'founder' OR ub.badge_type = 'founder' OR bc.badge_type = 'founder')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.get_resource_access_summary(p_book_id BIGINT)
RETURNS TABLE (
  has_permanent_access BOOLEAN,
  available_view_passes INTEGER,
  available_redemption_tickets INTEGER,
  temporary_resource_keys TEXT[]
) AS $$
DECLARE
  v_user_id UUID;
  v_is_admin BOOLEAN;
  v_is_founder BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, 0, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT public.is_admin() INTO v_is_admin;
  SELECT public.has_founder_badge(v_user_id) INTO v_is_founder;

  RETURN QUERY
  SELECT
    (
      COALESCE(v_is_admin, false)
      OR COALESCE(v_is_founder, false)
      OR EXISTS (
        SELECT 1
        FROM public.resource_access_grants rag
        WHERE rag.user_id = v_user_id
          AND rag.book_id = p_book_id
          AND rag.resource_scope = 'book'
          AND rag.revoked_at IS NULL
      )
    ) AS has_permanent_access,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'available'
        AND vp.expires_at > now()
    ) AS available_view_passes,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.resource_redemption_tickets rt
      WHERE rt.user_id = v_user_id
        AND rt.status = 'available'
    ) AS available_redemption_tickets,
    COALESCE((
      SELECT array_agg(vp.used_resource_key)
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'used'
        AND vp.used_resource_key IS NOT NULL
        AND vp.temporary_access_expires_at > now()
        AND vp.used_resource_key LIKE ('book:' || p_book_id || ':%')
    ), ARRAY[]::TEXT[]) AS temporary_resource_keys;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.consume_view_pass(
  p_book_id BIGINT,
  p_resource_key TEXT
)
RETURNS TIMESTAMPTZ AS $$
DECLARE
  v_user_id UUID;
  v_pass_id BIGINT;
  v_existing_expires TIMESTAMPTZ;
  v_new_expires TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_resource_key IS NULL OR p_resource_key !~ ('^book:' || p_book_id || ':') THEN
    RAISE EXCEPTION 'Invalid resource key';
  END IF;

  IF public.is_admin()
    OR public.has_founder_badge(v_user_id)
    OR EXISTS (
      SELECT 1
      FROM public.resource_access_grants rag
      WHERE rag.user_id = v_user_id
        AND rag.book_id = p_book_id
        AND rag.resource_scope = 'book'
        AND rag.revoked_at IS NULL
    )
  THEN
    RETURN now() + interval '100 years';
  END IF;

  SELECT vp.temporary_access_expires_at
    INTO v_existing_expires
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'used'
    AND vp.used_resource_key = p_resource_key
    AND vp.temporary_access_expires_at > now()
  ORDER BY vp.temporary_access_expires_at DESC
  LIMIT 1;

  IF v_existing_expires IS NOT NULL THEN
    RETURN v_existing_expires;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT vp.id
    INTO v_pass_id
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'available'
    AND vp.expires_at > now()
  ORDER BY vp.expires_at ASC, vp.issued_at ASC
  LIMIT 1
  FOR UPDATE;

  IF v_pass_id IS NULL THEN
    RAISE EXCEPTION 'No available view pass';
  END IF;

  v_new_expires := now() + interval '72 hours';

  UPDATE public.view_passes
  SET status = 'used',
      used_at = now(),
      used_resource_key = p_resource_key,
      temporary_access_expires_at = v_new_expires
  WHERE id = v_pass_id;

  RETURN v_new_expires;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

-- ------------------------------------------------------------
-- 4. 共读纪念徽章与密码核销
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_commemorative_badges(p_book_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_title TEXT;
BEGIN
  SELECT title INTO v_title
  FROM public.books
  WHERE id = p_book_id;

  IF v_title IS NULL THEN
    RAISE EXCEPTION 'Book not found';
  END IF;

  INSERT INTO public.badge_catalog
    (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
  VALUES
    ('commemorative_book_' || p_book_id || '_claimed', 'commemorative', '《' || v_title || '》共读纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_claimed'),
    ('commemorative_book_' || p_book_id || '_finished', 'commemorative', '《' || v_title || '》完本纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_finished')
  ON CONFLICT (badge_key) DO UPDATE SET
    title = EXCLUDED.title,
    badge_type = EXCLUDED.badge_type,
    is_active = true,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_create_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_label TEXT DEFAULT '共读密码',
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  IF trim(COALESCE(p_password, '')) = '' THEN
    RAISE EXCEPTION 'Password is required';
  END IF;

  INSERT INTO public.co_reading_passwords
    (book_id, label, password_hash, password_plain, starts_at, expires_at, created_by)
  VALUES
    (p_book_id, COALESCE(NULLIF(trim(COALESCE(p_label, '')), ''), '共读密码'), crypt(trim(p_password), gen_salt('bf')), trim(p_password), p_starts_at, p_expires_at, auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.ensure_commemorative_badges(p_book_id);
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_set_co_reading_password_active(
  p_password_id BIGINT,
  p_is_active BOOLEAN
)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  UPDATE public.co_reading_passwords
  SET is_active = p_is_active,
      updated_at = now()
  WHERE id = p_password_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.claim_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_group_member_id TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_password_id BIGINT;
  v_claim_id BIGINT;
  v_ticket_id BIGINT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_group_member_id, '')) = '' THEN
    RAISE EXCEPTION 'Group member id is required';
  END IF;

  SELECT id INTO v_claim_id
  FROM public.co_reading_claims
  WHERE user_id = v_user_id
    AND book_id = p_book_id
  LIMIT 1;

  IF v_claim_id IS NOT NULL THEN
    RETURN v_claim_id;
  END IF;

  SELECT id INTO v_password_id
  FROM public.co_reading_passwords
  WHERE book_id = p_book_id
    AND is_active = true
    AND (starts_at IS NULL OR starts_at <= now())
    AND (expires_at IS NULL OR expires_at >= now())
    AND password_hash = crypt(trim(COALESCE(p_password, '')), password_hash)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_password_id IS NULL THEN
    RAISE EXCEPTION 'Invalid co-reading password';
  END IF;

  PERFORM public.ensure_commemorative_badges(p_book_id);

  INSERT INTO public.co_reading_claims
    (user_id, book_id, password_id, group_member_id)
  VALUES
    (v_user_id, p_book_id, v_password_id, trim(p_group_member_id))
  RETURNING id INTO v_claim_id;

  INSERT INTO public.commemorative_tickets
    (user_id, book_id, claim_id, group_member_id)
  VALUES
    (v_user_id, p_book_id, v_claim_id, trim(p_group_member_id))
  ON CONFLICT (user_id, book_id) DO UPDATE SET
    status = 'active',
    revoked_at = NULL
  RETURNING id INTO v_ticket_id;

  INSERT INTO public.resource_access_grants
    (user_id, book_id, resource_scope, grant_type, source_id)
  VALUES
    (v_user_id, p_book_id, 'book', 'commemorative', v_claim_id)
  ON CONFLICT (user_id, book_id, resource_scope)
    WHERE revoked_at IS NULL AND resource_scope = 'book'
  DO NOTHING;

  INSERT INTO public.user_badges
    (user_id, badge_key, badge_type, awarded_reason)
  VALUES
    (v_user_id, 'commemorative_book_' || p_book_id || '_claimed', 'commemorative', 'co_reading_password_claim')
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  RETURN v_claim_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.award_finished_commemorative_badge()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.post_type = 'finished'
    AND NEW.linked_book_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.commemorative_tickets ct
      WHERE ct.user_id = NEW.user_id
        AND ct.book_id = NEW.linked_book_id
        AND ct.status = 'active'
    )
  THEN
    PERFORM public.ensure_commemorative_badges(NEW.linked_book_id);

    INSERT INTO public.user_badges
      (user_id, badge_key, badge_type, awarded_reason)
    VALUES
      (NEW.user_id, 'commemorative_book_' || NEW.linked_book_id || '_finished', 'commemorative', 'finished_reading_post')
    ON CONFLICT (user_id, badge_key) DO UPDATE SET
      revoked_at = NULL,
      awarded_reason = EXCLUDED.awarded_reason;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_award_finished_commemorative_badge ON public.reading_posts;
CREATE TRIGGER trg_award_finished_commemorative_badge
AFTER INSERT OR UPDATE OF post_type, linked_book_id ON public.reading_posts
FOR EACH ROW
EXECUTE FUNCTION public.award_finished_commemorative_badge();

-- ------------------------------------------------------------
-- 5. 管理员一键发放本周资源浏览券
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_source_key TEXT;
  v_inserted INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  v_source_key := 'weekly_' || to_char(date_trunc('week', now()), 'IYYY_IW');

  WITH weekly_activity AS (
    SELECT
      cl.user_id,
      SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= date_trunc('week', now())
      AND cl.created_at < date_trunc('week', now()) + interval '7 days'
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      ml.weekly_view_passes,
      COALESCE(wa.points, 0) AS weekly_activity_points,
      row_number() OVER (ORDER BY COALESCE(wa.points, 0) DESC, ms.contribution_total DESC, ms.user_id) AS rank_position
    FROM public.member_stats ms
    JOIN public.member_levels ml ON ml.level = ms.level
    LEFT JOIN weekly_activity wa ON wa.user_id = ms.user_id
    WHERE ml.weekly_view_passes > 0
  ),
  expanded AS (
    SELECT
      r.user_id,
      generate_series(1, r.weekly_view_passes * CASE WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2 ELSE 1 END) AS pass_no
    FROM ranked r
  ),
  inserted AS (
    INSERT INTO public.view_passes
      (user_id, status, issued_reason, source_key, issued_at, expires_at)
    SELECT
      e.user_id,
      'available',
      'weekly',
      v_source_key || '_' || e.user_id || '_' || e.pass_no,
      now(),
      now() + interval '7 days'
    FROM expanded e
    ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING
    RETURNING user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT user_id)::INTEGER
    INTO v_inserted, issued_users
  FROM inserted;

  issued_passes := COALESCE(v_inserted, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.has_founder_badge(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_resource_access_summary(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_view_pass(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_co_reading_password(BIGINT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_co_reading_password_active(BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_co_reading_password(BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;

COMMENT ON TABLE public.co_reading_passwords IS '按书籍 / 共读期配置的共读密码，hash 用于核销，password_plain 仅管理员后台展示';
COMMENT ON TABLE public.co_reading_claims IS '用户核销共读密码记录，包含群内 ID';
COMMENT ON TABLE public.commemorative_tickets IS '共读纪念券，激活对应书籍 / 共读期永久资源权限';

-- ============================================================
-- END migrate-v26-co-reading-claims.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v27-readable-co-reading-passwords.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v27 迁移：共读密码自动生成与管理员明文展示
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.co_reading_passwords
  ADD COLUMN IF NOT EXISTS password_plain TEXT;

CREATE OR REPLACE FUNCTION public.admin_create_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_label TEXT DEFAULT '共读密码',
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_id BIGINT;
  v_password TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  v_password := trim(COALESCE(p_password, ''));
  IF char_length(v_password) < 15 THEN
    RAISE EXCEPTION 'Password must be at least 15 characters';
  END IF;

  IF v_password !~ '^[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Password must contain only letters and numbers';
  END IF;

  INSERT INTO public.co_reading_passwords
    (book_id, label, password_hash, password_plain, starts_at, expires_at, created_by)
  VALUES
    (
      p_book_id,
      COALESCE(NULLIF(trim(COALESCE(p_label, '')), ''), '共读密码'),
      crypt(v_password, gen_salt('bf')),
      v_password,
      p_starts_at,
      p_expires_at,
      auth.uid()
    )
  RETURNING id INTO v_id;

  PERFORM public.ensure_commemorative_badges(p_book_id);
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

COMMENT ON COLUMN public.co_reading_passwords.password_plain IS
  '管理员后台展示用共读密码明文；RLS 限制为管理员可读';

COMMENT ON TABLE public.co_reading_passwords IS
  '按书籍 / 共读期配置的共读密码，hash 用于核销，password_plain 仅管理员后台展示';

-- ============================================================
-- END migrate-v27-readable-co-reading-passwords.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v28-avatar-upload-profile.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v28 迁移：头像上传存储桶 + 公开资料扩展字段
-- avatars 存储桶 + get_public_member_profile 返回 bio/city/wechat_id
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 创建 avatars 存储桶
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
  ON CONFLICT (id) DO NOTHING;

-- 2. avatars 存储桶 RLS 策略
DROP POLICY IF EXISTS "avatars_read_all" ON storage.objects;
CREATE POLICY "avatars_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_insert_own" ON storage.objects;
CREATE POLICY "avatars_insert_own"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
CREATE POLICY "avatars_update_own"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND auth.role() = 'authenticated');

-- 3. 更新 get_public_member_profile：追加 bio / city / wechat_id
DROP FUNCTION IF EXISTS public.get_public_member_profile(UUID);

CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  city TEXT,
  wechat_id TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    p.bio,
    p.city,
    p.wechat_id,
    COALESCE(ms.level, 0),
    COALESCE(ms.tier, '基础会员'),
    COALESCE(ml.title, ''),
    COALESCE(ms.contribution_total, 0),
    COALESCE(ms.contribution_month, 0),
    COALESCE(ms.contribution_week, 0),
    ms.current_badge_key
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO anon, authenticated;

-- ============================================================
-- END migrate-v28-avatar-upload-profile.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v28-badge-back-images.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v28 迁移：徽章背面图
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.badge_catalog
  ADD COLUMN IF NOT EXISTS back_image_bucket TEXT NOT NULL DEFAULT 'badges';

ALTER TABLE public.badge_catalog
  ADD COLUMN IF NOT EXISTS back_image_path TEXT;

COMMENT ON COLUMN public.badge_catalog.back_image_bucket IS
  '徽章背面图片所在 Supabase Storage bucket';

COMMENT ON COLUMN public.badge_catalog.back_image_path IS
  '徽章背面图片在 bucket 内的路径；为空时预览不启用翻面';

-- ============================================================
-- END migrate-v28-badge-back-images.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v29-friends-search.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v29 迁移：好友系统 + 搜索 + 好友可见
-- user_follows 表 + 关注/取关 + 好友可见 + 搜索书友圈
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. user_follows 表
CREATE TABLE IF NOT EXISTS public.user_follows (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  follower_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON public.user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_following ON public.user_follows(following_id);

ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_follows_read_all" ON public.user_follows;
CREATE POLICY "user_follows_read_all"
  ON public.user_follows FOR SELECT USING (true);

DROP POLICY IF EXISTS "user_follows_insert_own" ON public.user_follows;
CREATE POLICY "user_follows_insert_own"
  ON public.user_follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS "user_follows_delete_own" ON public.user_follows;
CREATE POLICY "user_follows_delete_own"
  ON public.user_follows FOR DELETE
  USING (auth.uid() = follower_id);

-- 2. toggle_follow — 关注/取关
CREATE OR REPLACE FUNCTION public.toggle_follow(p_following_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_follower_id UUID;
  v_exists BIGINT;
BEGIN
  v_follower_id := auth.uid();
  IF v_follower_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF v_follower_id = p_following_id THEN
    RAISE EXCEPTION 'Cannot follow yourself';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_following_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  SELECT id INTO v_exists FROM public.user_follows
  WHERE follower_id = v_follower_id AND following_id = p_following_id;

  IF FOUND THEN
    DELETE FROM public.user_follows WHERE id = v_exists;
    RETURN 'unfollowed';
  ELSE
    INSERT INTO public.user_follows (follower_id, following_id)
    VALUES (v_follower_id, p_following_id);
    RETURN 'followed';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 关注/粉丝计数
CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user_id UUID)
RETURNS TABLE (following_count BIGINT, follower_count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM public.user_follows WHERE follower_id = p_user_id),
    (SELECT COUNT(*) FROM public.user_follows WHERE following_id = p_user_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 4. 检查是否已关注
CREATE OR REPLACE FUNCTION public.is_following(p_following_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.user_follows
    WHERE follower_id = auth.uid() AND following_id = p_following_id
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 更新 reading_posts visibility CHECK 支持 friends
ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_visibility_check;
ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_visibility_check
  CHECK (visibility IN ('public', 'friends', 'private'));

-- 6. 更新 create_reading_post 接受 friends
DROP FUNCTION IF EXISTS public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
  v_mood_color TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;
  IF p_visibility NOT IN ('public', 'friends', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;
  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;
  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = '' OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?' THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;
  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
  END IF;
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;

  INSERT INTO public.reading_posts (
    user_id, post_type, book_title, author, douban_url, cover_url,
    excerpt, content, mood_color, visibility, linked_book_id, rating
  ) VALUES (
    auth.uid(), p_post_type, trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url, NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_excerpt, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    v_mood_color, p_visibility, p_linked_book_id, p_rating
  ) RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);
  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 7. 更新 update_reading_post 接受 friends
CREATE OR REPLACE FUNCTION public.update_reading_post(
  p_post_id BIGINT,
  p_post_type TEXT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_old_visibility TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  SELECT * INTO v_post FROM public.reading_posts
  WHERE id = p_post_id AND user_id = auth.uid() AND is_deleted = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found or access denied';
  END IF;
  IF p_post_type IS NOT NULL THEN
    IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
      RAISE EXCEPTION 'Invalid post type';
    END IF;
    UPDATE public.reading_posts SET post_type = p_post_type WHERE id = p_post_id;
  END IF;
  IF p_excerpt IS NOT NULL THEN
    UPDATE public.reading_posts SET excerpt = NULLIF(trim(p_excerpt), '') WHERE id = p_post_id;
  END IF;
  IF p_content IS NOT NULL THEN
    UPDATE public.reading_posts SET content = NULLIF(trim(p_content), '') WHERE id = p_post_id;
  END IF;
  IF p_mood_color IS NOT NULL THEN
    IF p_mood_color != '' AND p_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
      RAISE EXCEPTION 'Invalid mood color';
    END IF;
    UPDATE public.reading_posts SET mood_color = NULLIF(trim(p_mood_color), '') WHERE id = p_post_id;
  END IF;
  IF p_visibility IS NOT NULL THEN
    IF p_visibility NOT IN ('public', 'friends', 'private') THEN
      RAISE EXCEPTION 'Invalid visibility';
    END IF;
    v_old_visibility := v_post.visibility;
    UPDATE public.reading_posts SET visibility = p_visibility WHERE id = p_post_id;
    IF v_old_visibility != p_visibility THEN
      IF p_visibility = 'private' THEN
        PERFORM public.revoke_reading_post_contributions(p_post_id);
      ELSE
        PERFORM public.award_reading_post_contributions(p_post_id);
      END IF;
    END IF;
  END IF;
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;
  UPDATE public.reading_posts SET rating = p_rating WHERE id = p_post_id;
  UPDATE public.reading_posts SET updated_at = now() WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 8. 更新 list_reading_posts 支持 friends 范围
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  IF p_scope IN ('mine', 'friends') AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope = 'friends' AND (
        (rp.visibility = 'public' OR rp.visibility = 'friends')
        AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = rp.user_id)
      ))
      OR (p_scope = 'public' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 9. 搜索书友圈
CREATE OR REPLACE FUNCTION public.search_reading_posts(p_query TEXT)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND rp.visibility = 'public'
    AND (
      rp.book_title ILIKE '%' || p_query || '%'
      OR rp.author ILIKE '%' || p_query || '%'
    )
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 10. 授权
GRANT EXECUTE ON FUNCTION public.toggle_follow(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_follow_counts(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_following(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_reading_posts(TEXT) TO anon, authenticated;

-- ============================================================
-- END migrate-v29-friends-search.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v30-friend-lists.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v30 迁移：好友列表
-- list_following / list_followers 返回关注/粉丝清单
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 我关注的
CREATE OR REPLACE FUNCTION public.list_following(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  city TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    COALESCE(ms.level, 0),
    COALESCE(ml.title, ''),
    p.city,
    uf.created_at
  FROM public.user_follows uf
  JOIN public.profiles p ON p.id = uf.following_id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE uf.follower_id = p_user_id
  ORDER BY uf.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 2. 关注我的
CREATE OR REPLACE FUNCTION public.list_followers(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  city TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    COALESCE(ms.level, 0),
    COALESCE(ml.title, ''),
    p.city,
    uf.created_at
  FROM public.user_follows uf
  JOIN public.profiles p ON p.id = uf.follower_id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE uf.following_id = p_user_id
  ORDER BY uf.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_following(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_followers(UUID) TO anon, authenticated;

-- ============================================================
-- END migrate-v30-friend-lists.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v31-badge-riddle-answers.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v31 迁移：徽章成就谜面答题
-- 每枚徽章答对一次后记录状态，并奖励 10 贡献值
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.badge_riddle_answers (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key       TEXT NOT NULL REFERENCES public.badge_catalog(badge_key) ON DELETE CASCADE,
  answer_text     TEXT NOT NULL,
  awarded_points  INTEGER NOT NULL DEFAULT 10,
  solved_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, badge_key)
);

CREATE INDEX IF NOT EXISTS idx_badge_riddle_answers_user
  ON public.badge_riddle_answers(user_id, solved_at DESC);

ALTER TABLE public.badge_riddle_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badge_riddle_answers_read_self_or_admin" ON public.badge_riddle_answers;
CREATE POLICY "badge_riddle_answers_read_self_or_admin"
  ON public.badge_riddle_answers
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "badge_riddle_answers_admin_write" ON public.badge_riddle_answers;
CREATE POLICY "badge_riddle_answers_admin_write"
  ON public.badge_riddle_answers
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.badge_riddle_answer_tokens(p_badge_key TEXT)
RETURNS TEXT[] AS $$
BEGIN
  RETURN CASE p_badge_key
    WHEN 'founder' THEN ARRAY['文学爆炸', '四主将', '爆炸']
    WHEN 'level_01_wanderer' THEN ARRAY['聂鲁达', '巴勃罗', '元素颂歌', '漫歌', '黑岛']
    WHEN 'level_02_adventurer' THEN ARRAY['塞万提斯', '堂吉诃德']
    WHEN 'level_03_chronicler' THEN ARRAY['加西拉索', '印卡王室述评', '印卡王室评述']
    WHEN 'level_04_seeker' THEN ARRAY['波拉尼奥', '荒野侦探', '2666']
    WHEN 'level_05_tunnel' THEN ARRAY['萨瓦托', '亚巴顿']
    WHEN 'level_06_labyrinth' THEN ARRAY['博尔赫斯', '阿莱夫', '虚构集', '小径分岔']
    WHEN 'level_07_wallbreaker' THEN ARRAY['胡安娜', '克鲁兹', '索尔胡安娜']
    WHEN 'level_08_player' THEN ARRAY['科塔萨尔', '跳房子']
    WHEN 'level_09_wordtamer' THEN ARRAY['因凡特', '三只忧伤的老虎', '忧伤的老虎']
    WHEN 'level_10_stargazer' THEN ARRAY['李斯佩克朵', '李斯佩克多', '星辰时刻']
    WHEN 'level_11_architect' THEN ARRAY['卡彭铁尔', '人间王国', '千柱之城']
    WHEN 'level_12_nether' THEN ARRAY['鲁尔福', '佩德罗巴拉莫', '燃烧的原野']
    WHEN 'level_13_wasteport' THEN ARRAY['奥内蒂', '造船厂', '收尸人']
    WHEN 'level_14_alchemist' THEN ARRAY['马尔克斯', '百年孤独']
    WHEN 'level_15_maskman' THEN ARRAY['富恩特斯', '奥拉', '阿尔特米奥', '最明净的地区']
    WHEN 'level_16_godslayer' THEN ARRAY['略萨', '巴尔加斯', '城市与狗', '酒吧长谈', '公羊的节日']
    ELSE ARRAY[]::TEXT[]
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.normalize_badge_riddle_answer(p_answer TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN lower(
    regexp_replace(
      COALESCE(p_answer, ''),
      '[[:space:][:punct:]，。、《》「」『』（）【】·—-]+',
      '',
      'g'
    )
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.submit_badge_riddle_answer(
  p_badge_key TEXT,
  p_answer TEXT
)
RETURNS TABLE (
  correct BOOLEAN,
  already_solved BOOLEAN,
  awarded_points INTEGER,
  message TEXT
) AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_answer TEXT := public.normalize_badge_riddle_answer(p_answer);
  v_tokens TEXT[];
  v_correct BOOLEAN := false;
  v_answer_id BIGINT;
  v_points INTEGER := 10;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF COALESCE(trim(p_badge_key), '') = '' THEN
    RAISE EXCEPTION 'badge_key_required';
  END IF;

  IF COALESCE(v_answer, '') = '' THEN
    RETURN QUERY SELECT false, false, 0, '请先输入答案。';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_badges
    WHERE user_id = v_user_id
      AND badge_key = p_badge_key
      AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'badge_not_owned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.badge_riddle_answers
    WHERE user_id = v_user_id
      AND badge_key = p_badge_key
  ) THEN
    RETURN QUERY SELECT true, true, 0, '这枚徽章已经答对过了。';
    RETURN;
  END IF;

  v_tokens := public.badge_riddle_answer_tokens(p_badge_key);

  IF COALESCE(array_length(v_tokens, 1), 0) = 0 THEN
    RAISE EXCEPTION 'badge_riddle_not_configured';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM unnest(v_tokens) AS token
    WHERE position(public.normalize_badge_riddle_answer(token) IN v_answer) > 0
  ) INTO v_correct;

  IF NOT v_correct THEN
    RETURN QUERY SELECT false, false, 0, '答案还不对，可以再试一次。';
    RETURN;
  END IF;

  INSERT INTO public.badge_riddle_answers
    (user_id, badge_key, answer_text, awarded_points)
  VALUES
    (v_user_id, p_badge_key, left(p_answer, 200), v_points)
  ON CONFLICT (user_id, badge_key) DO NOTHING
  RETURNING id INTO v_answer_id;

  IF v_answer_id IS NULL THEN
    RETURN QUERY SELECT true, true, 0, '这枚徽章已经答对过了。';
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_user_id, 'badge_riddle', v_answer_id, v_points, 'badge_riddle_solved', 'system_reward');

  PERFORM public.apply_member_contribution_delta(v_user_id, v_points);

  RETURN QUERY SELECT true, false, v_points, '答对了，已增加 10 贡献值。';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.submit_badge_riddle_answer(TEXT, TEXT) TO authenticated;

COMMENT ON TABLE public.badge_riddle_answers IS '徽章成就谜面答题记录：每个用户每枚徽章只可领取一次贡献值奖励';
COMMENT ON FUNCTION public.submit_badge_riddle_answer(TEXT, TEXT) IS '提交徽章谜面答案；答对一次奖励 10 贡献值，答错不扣分';

-- ============================================================
-- END migrate-v31-badge-riddle-answers.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v32-month-week-contribution.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v32 迁移：月贡献/周贡献跨周期自动重置
-- apply_member_contribution_delta 增加周期检测逻辑
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 从 contribution_logs 精确重算当月/当周贡献值
UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('month', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  contribution_week = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('week', timezone('Asia/Shanghai', now()))
    ), 0
  );

-- 2. 更新 apply_member_contribution_delta 增加周期重置
CREATE OR REPLACE FUNCTION public.apply_member_contribution_delta(
  p_user_id UUID,
  p_delta INTEGER
)
RETURNS VOID AS $$
DECLARE
  v_stats public.member_stats%ROWTYPE;
  v_this_month TIMESTAMPTZ;
  v_this_week TIMESTAMPTZ;
  v_last_month TIMESTAMPTZ;
  v_last_week TIMESTAMPTZ;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT * INTO v_stats FROM public.member_stats WHERE user_id = p_user_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_this_month := date_trunc('month', timezone('Asia/Shanghai', now()));
  v_this_week  := date_trunc('week', timezone('Asia/Shanghai', now()));
  v_last_month := date_trunc('month', v_stats.updated_at);
  v_last_week  := date_trunc('week', v_stats.updated_at);

  UPDATE public.member_stats
  SET
    contribution_total = GREATEST(contribution_total + p_delta, 0),
    contribution_month = GREATEST(
      CASE WHEN v_last_month < v_this_month THEN 0 ELSE contribution_month END + p_delta,
      0
    ),
    contribution_week = GREATEST(
      CASE WHEN v_last_week < v_this_week THEN 0 ELSE contribution_week END + p_delta,
      0
    ),
    updated_at = now()
  WHERE user_id = p_user_id;

  PERFORM public.recalculate_member_level(p_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- END migrate-v32-month-week-contribution.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v32-admin-member-list.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v32 迁移：管理后台会员清单与备注
-- 管理员可查看会员 UID / 昵称 / email / 注册时间 / 等级，并维护备注
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_admin_notes (
  user_id     UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  note        TEXT NOT NULL DEFAULT '',
  created_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.member_admin_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_admin_notes_admin_read" ON public.member_admin_notes;
CREATE POLICY "member_admin_notes_admin_read"
  ON public.member_admin_notes
  FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "member_admin_notes_admin_write" ON public.member_admin_notes;
CREATE POLICY "member_admin_notes_admin_write"
  ON public.member_admin_notes
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  registered_at TIMESTAMPTZ,
  level INTEGER,
  title TEXT,
  tier TEXT,
  note TEXT
) AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.display_name,
    au.email::TEXT AS email,
    COALESCE(au.created_at, p.created_at) AS registered_at,
    COALESCE(ms.level, 0) AS level,
    ml.title,
    COALESCE(ms.tier, ml.tier, '基础会员') AS tier,
    COALESCE(man.note, '') AS note
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  LEFT JOIN public.member_admin_notes man ON man.user_id = p.id
  ORDER BY COALESCE(au.created_at, p.created_at) DESC, p.display_name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_update_member_note(
  p_user_id UUID,
  p_note TEXT
)
RETURNS public.member_admin_notes AS $$
DECLARE
  v_row public.member_admin_notes%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  INSERT INTO public.member_admin_notes
    (user_id, note, created_by, updated_by, created_at, updated_at)
  VALUES
    (p_user_id, COALESCE(p_note, ''), auth.uid(), auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET
    note = EXCLUDED.note,
    updated_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.admin_list_members() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_member_note(UUID, TEXT) TO authenticated;

COMMENT ON TABLE public.member_admin_notes IS '管理员维护的会员后台备注，仅管理员可见';
COMMENT ON FUNCTION public.admin_list_members() IS '管理员后台会员清单，包含 auth.users.email 与会员等级';
COMMENT ON FUNCTION public.admin_update_member_note(UUID, TEXT) IS '管理员更新单个会员备注';

-- ============================================================
-- END migrate-v32-admin-member-list.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v33-reading-circle-auth-required.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v33 迁移：书友圈仅登录会员可浏览
-- 游客不可浏览书友圈广场、贡献榜、个人主页中的书友圈动态
-- 在 Supabase SQL Editor 中执行
-- ============================================================

DROP POLICY IF EXISTS "reading_posts_read_public_self_or_admin" ON public.reading_posts;
CREATE POLICY "reading_posts_read_public_self_or_admin"
  ON public.reading_posts
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      (visibility = 'public' AND is_deleted = false)
      OR auth.uid() = user_id
      OR public.is_admin()
    )
  );

CREATE OR REPLACE FUNCTION public.require_authenticated_member()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login_required';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope = 'friends' AND (
        (rp.visibility = 'public' OR rp.visibility = 'friends')
        AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = rp.user_id)
      ))
      OR (p_scope = 'public' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.search_reading_posts(p_query TEXT)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND rp.visibility = 'public'
    AND (
      rp.book_title ILIKE '%' || p_query || '%'
      OR rp.author ILIKE '%' || p_query || '%'
    )
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_user_public_posts(p_user_id UUID)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC,
  has_liked BOOLEAN,
  member_level INTEGER,
  member_title TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ),
    COALESCE(ms.level, 0),
    COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.user_id = p_user_id
    AND rp.is_deleted = false
    AND rp.visibility = 'public'
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  city TEXT,
  wechat_id TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    p.bio,
    p.city,
    p.wechat_id,
    COALESCE(ms.level, 0),
    COALESCE(ms.tier, '基础会员'),
    COALESCE(ml.title, ''),
    COALESCE(ms.contribution_total, 0),
    COALESCE(ms.contribution_month, 0),
    COALESCE(ms.contribution_week, 0),
    ms.current_badge_key
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_contribution_leaderboard(p_type TEXT DEFAULT 'total')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  contribution INTEGER
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY
        CASE p_type
          WHEN 'total' THEN ms.contribution_total
          WHEN 'month' THEN ms.contribution_month
          WHEN 'week'  THEN ms.contribution_week
        END DESC,
        p.created_at ASC
    )::BIGINT AS rank,
    ms.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    COALESCE(ms.level, 0) AS level,
    COALESCE(ml.title, '') AS title,
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END AS contribution
  FROM public.member_stats ms
  JOIN public.profiles p ON p.id = ms.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END > 0
  ORDER BY
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END DESC,
    p.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.list_reading_posts(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.search_reading_posts(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_user_public_posts(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_public_member_profile(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) FROM anon;

GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_reading_posts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_public_posts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO authenticated;

COMMENT ON FUNCTION public.require_authenticated_member() IS '要求当前请求来自已登录用户，用于限制书友圈浏览';

-- ============================================================
-- END migrate-v33-reading-circle-auth-required.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v34-given-interaction-contributions.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v34 迁移：主动互动贡献值
-- 为他人书友圈点赞满 5 次 +1；评论他人书友圈每次 +1。
-- 主动点赞/评论贡献值合计每日最多 10 分。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 统计某个自然日内，主动点赞/评论已经获得的有效贡献值。
-- 日期按 Asia/Shanghai 计算，便于和站内每日规则保持一致。
CREATE OR REPLACE FUNCTION public.given_interaction_points_on_day(
  p_user_id UUID,
  p_created_at TIMESTAMPTZ
)
RETURNS INTEGER AS $$
DECLARE
  v_day_start TIMESTAMPTZ;
  v_day_end TIMESTAMPTZ;
  v_points INTEGER := 0;
BEGIN
  IF p_user_id IS NULL OR p_created_at IS NULL THEN
    RETURN 0;
  END IF;

  v_day_start := (timezone('Asia/Shanghai', p_created_at)::date AT TIME ZONE 'Asia/Shanghai');
  v_day_end := v_day_start + interval '1 day';

  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_points
  FROM public.contribution_logs
  WHERE user_id = p_user_id
    AND source_type IN ('post_like_given_batch', 'post_comment_given')
    AND reason IN ('given_5_likes', 'given_comment')
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_day_start
    AND created_at < v_day_end;

  RETURN COALESCE(v_points, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 尝试写入 1 分主动互动贡献值；若当日已达 10 分或该来源已计分，则不写入。
CREATE OR REPLACE FUNCTION public.try_insert_given_interaction_contribution(
  p_user_id UUID,
  p_source_type TEXT,
  p_source_id BIGINT,
  p_reason TEXT,
  p_created_at TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_user_id IS NULL OR p_source_type IS NULL OR p_source_id IS NULL OR p_reason IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE user_id = p_user_id
      AND source_type = p_source_type
      AND source_id = p_source_id
      AND reason = p_reason
      AND contribution_scope = 'reading_activity'
      AND is_active = true
  ) THEN
    RETURN false;
  END IF;

  IF public.given_interaction_points_on_day(p_user_id, p_created_at) >= 10 THEN
    RETURN false;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope, created_at)
  VALUES
    (p_user_id, p_source_type, p_source_id, 1, p_reason, 'reading_activity', p_created_at);

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 为他人点赞：按当前有效点赞数每满 5 次发放 1 分。
-- 取消点赞后若不再满足对应档位，会回收失效档位的贡献值。
CREATE OR REPLACE FUNCTION public.refresh_given_like_contributions(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_revoked_points INTEGER := 0;
  v_inserted_points INTEGER := 0;
  v_batch RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- 失效的点赞档位：当前有效点赞序列中不再处于第 5/10/15... 个位置的流水。
  WITH valid_batches AS (
    SELECT id
    FROM (
      SELECT
        pl.id,
        row_number() OVER (ORDER BY pl.created_at ASC, pl.id ASC) AS rn
      FROM public.post_likes pl
      JOIN public.reading_posts rp ON rp.id = pl.post_id
      WHERE pl.user_id = p_user_id
        AND rp.user_id <> p_user_id
        AND rp.is_deleted = false
    ) ranked
    WHERE ranked.rn % 5 = 0
  ),
  to_revoke AS (
    SELECT cl.id, cl.points
    FROM public.contribution_logs cl
    WHERE cl.user_id = p_user_id
      AND cl.source_type = 'post_like_given_batch'
      AND cl.reason = 'given_5_likes'
      AND cl.contribution_scope = 'reading_activity'
      AND cl.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM valid_batches vb
        WHERE vb.id = cl.source_id
      )
  ),
  revoked AS (
    UPDATE public.contribution_logs cl
    SET is_active = false,
        revoked_at = now()
    FROM to_revoke tr
    WHERE cl.id = tr.id
    RETURNING tr.points
  )
  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_revoked_points
  FROM revoked;

  IF v_revoked_points > 0 THEN
    PERFORM public.apply_member_contribution_delta(p_user_id, -v_revoked_points);
  END IF;

  FOR v_batch IN
    SELECT id, created_at
    FROM (
      SELECT
        pl.id,
        pl.created_at,
        row_number() OVER (ORDER BY pl.created_at ASC, pl.id ASC) AS rn
      FROM public.post_likes pl
      JOIN public.reading_posts rp ON rp.id = pl.post_id
      WHERE pl.user_id = p_user_id
        AND rp.user_id <> p_user_id
        AND rp.is_deleted = false
    ) ranked
    WHERE ranked.rn % 5 = 0
    ORDER BY created_at ASC, id ASC
  LOOP
    IF public.try_insert_given_interaction_contribution(
      p_user_id,
      'post_like_given_batch',
      v_batch.id,
      'given_5_likes',
      v_batch.created_at
    ) THEN
      v_inserted_points := v_inserted_points + 1;
    END IF;
  END LOOP;

  IF v_inserted_points > 0 THEN
    PERFORM public.apply_member_contribution_delta(p_user_id, v_inserted_points);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.sync_given_like_contributions()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.refresh_given_like_contributions(NEW.user_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_given_like_contributions(OLD.user_id);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_given_like_contributions ON public.post_likes;
CREATE TRIGGER trg_sync_given_like_contributions
  AFTER INSERT OR DELETE ON public.post_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_given_like_contributions();

-- 评论他人书友圈：每条有效评论 +1。
-- 删除评论后回收该条评论带来的主动评论贡献值。
CREATE OR REPLACE FUNCTION public.award_given_comment_contribution(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_commenter_id UUID;
  v_post_owner_id UUID;
  v_comment_created_at TIMESTAMPTZ;
BEGIN
  SELECT pc.user_id, rp.user_id, pc.created_at
    INTO v_commenter_id, v_post_owner_id, v_comment_created_at
  FROM public.post_comments pc
  JOIN public.reading_posts rp ON rp.id = pc.post_id
  WHERE pc.id = p_comment_id
    AND pc.is_deleted = false
    AND rp.is_deleted = false;

  IF v_commenter_id IS NULL OR v_post_owner_id IS NULL OR v_commenter_id = v_post_owner_id THEN
    RETURN;
  END IF;

  IF public.try_insert_given_interaction_contribution(
    v_commenter_id,
    'post_comment_given',
    p_comment_id,
    'given_comment',
    v_comment_created_at
  ) THEN
    PERFORM public.apply_member_contribution_delta(v_commenter_id, 1);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.revoke_given_comment_contribution(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_commenter_id UUID;
  v_points INTEGER := 0;
BEGIN
  SELECT user_id
    INTO v_commenter_id
  FROM public.post_comments
  WHERE id = p_comment_id;

  IF v_commenter_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_points
  FROM public.contribution_logs
  WHERE user_id = v_commenter_id
    AND source_type = 'post_comment_given'
    AND source_id = p_comment_id
    AND reason = 'given_comment'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF v_points <= 0 THEN
    RETURN;
  END IF;

  UPDATE public.contribution_logs
  SET is_active = false,
      revoked_at = now()
  WHERE user_id = v_commenter_id
    AND source_type = 'post_comment_given'
    AND source_id = p_comment_id
    AND reason = 'given_comment'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  PERFORM public.apply_member_contribution_delta(v_commenter_id, -v_points);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.sync_given_comment_contributions()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_deleted = false THEN
      PERFORM public.award_given_comment_contribution(NEW.id);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF COALESCE(OLD.is_deleted, false) IS DISTINCT FROM COALESCE(NEW.is_deleted, false) THEN
      IF NEW.is_deleted = true THEN
        PERFORM public.revoke_given_comment_contribution(NEW.id);
      ELSE
        PERFORM public.award_given_comment_contribution(NEW.id);
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_given_comment_contributions ON public.post_comments;
CREATE TRIGGER trg_sync_given_comment_contributions
  AFTER INSERT OR UPDATE OF is_deleted ON public.post_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_given_comment_contributions();

-- 回算既有数据：
-- 1. 对所有未删除、且评论对象不是自己的评论，按评论发生日期补记主动评论贡献值。
-- 2. 对所有未删除动态下的有效点赞，按每个用户第 5/10/15... 个点赞的发生日期补记主动点赞贡献值。
-- 3. 每日主动互动贡献值上限 10 分，回算时同样生效。
DO $$
DECLARE
  v_event RECORD;
  v_inserted BOOLEAN;
BEGIN
  FOR v_event IN
    WITH valid_like_batches AS (
      SELECT user_id, id AS source_id, created_at
      FROM (
        SELECT
          pl.user_id,
          pl.id,
          pl.created_at,
          row_number() OVER (
            PARTITION BY pl.user_id
            ORDER BY pl.created_at ASC, pl.id ASC
          ) AS rn
        FROM public.post_likes pl
        JOIN public.reading_posts rp ON rp.id = pl.post_id
        WHERE rp.user_id <> pl.user_id
          AND rp.is_deleted = false
      ) ranked
      WHERE ranked.rn % 5 = 0
    ),
    valid_comments AS (
      SELECT pc.user_id, pc.id AS source_id, pc.created_at
      FROM public.post_comments pc
      JOIN public.reading_posts rp ON rp.id = pc.post_id
      WHERE pc.is_deleted = false
        AND rp.is_deleted = false
        AND rp.user_id <> pc.user_id
    )
    SELECT user_id, 'post_like_given_batch'::TEXT AS source_type, source_id, 'given_5_likes'::TEXT AS reason, created_at
    FROM valid_like_batches
    UNION ALL
    SELECT user_id, 'post_comment_given'::TEXT AS source_type, source_id, 'given_comment'::TEXT AS reason, created_at
    FROM valid_comments
    ORDER BY user_id, created_at ASC, source_type, source_id
  LOOP
    v_inserted := public.try_insert_given_interaction_contribution(
      v_event.user_id,
      v_event.source_type,
      v_event.source_id,
      v_event.reason,
      v_event.created_at
    );

    IF v_inserted THEN
      PERFORM public.apply_member_contribution_delta(v_event.user_id, 1);
    END IF;
  END LOOP;
END $$;

-- 回算会按历史日期写 contribution_logs。这里重新校准当前月/周贡献，避免历史分数污染本周活跃榜。
UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('month', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  contribution_week = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('week', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  updated_at = now();

REVOKE EXECUTE ON FUNCTION public.given_interaction_points_on_day(UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.try_insert_given_interaction_contribution(UUID, TEXT, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refresh_given_like_contributions(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_given_like_contributions() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_given_comment_contribution(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_given_comment_contribution(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_given_comment_contributions() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- END migrate-v34-given-interaction-contributions.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v35-member-search.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v35 迁移：书友搜索
-- 在「我的好友」页面按显示名字搜索书友，并进入公开个人主页。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.search_members_by_display_name(p_query TEXT)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  city TEXT,
  level INTEGER,
  title TEXT
) AS $$
DECLARE
  v_query TEXT;
BEGIN
  PERFORM public.require_authenticated_member();

  v_query := trim(COALESCE(p_query, ''));
  IF char_length(v_query) < 1 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    COALESCE(NULLIF(trim(p.display_name), ''), '书友') AS display_name,
    p.avatar_url,
    p.city,
    COALESCE(ms.level, 0) AS level,
    COALESCE(ml.title, '') AS title
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id <> auth.uid()
    AND COALESCE(p.display_name, '') ILIKE '%' || v_query || '%'
  ORDER BY
    CASE
      WHEN COALESCE(p.display_name, '') ILIKE v_query || '%' THEN 0
      ELSE 1
    END,
    COALESCE(ms.level, 0) DESC,
    COALESCE(p.display_name, '') ASC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.search_members_by_display_name(TEXT) TO authenticated;

COMMENT ON FUNCTION public.search_members_by_display_name(TEXT) IS
  '按显示名字搜索书友，用于个人中心-我的好友页面。';

-- ============================================================
-- END migrate-v35-member-search.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v36-follow-level-notifications.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v36 迁移：关注与升级通知
-- 1. 关注时通知被关注者：「XXX关注了你」
-- 2. 升级获得新等级徽章时通知本人：「恭喜你升级到 Lv.02 冒险者...」
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 扩展通知表：允许非书友圈动态通知。
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('like', 'comment', 'follow', 'level_badge'));

ALTER TABLE public.notifications
  ALTER COLUMN post_id DROP NOT NULL;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS message TEXT,
  ADD COLUMN IF NOT EXISTS link_path TEXT;

UPDATE public.notifications
SET link_path = '/reading-circle?post=' || post_id::TEXT
WHERE link_path IS NULL
  AND post_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unread_follow_dedupe
  ON public.notifications(user_id, type, actor_id)
  WHERE is_read = false AND type = 'follow';

-- 重新定义通知列表，兼容 follow / level_badge 这类没有 post_id 的通知。
DROP FUNCTION IF EXISTS public.get_notifications(INTEGER);

CREATE OR REPLACE FUNCTION public.get_notifications(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  id BIGINT,
  type TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMPTZ,
  actor_id UUID,
  actor_name TEXT,
  actor_avatar TEXT,
  post_id BIGINT,
  book_title TEXT,
  message TEXT,
  link_path TEXT
) AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.type,
    n.is_read,
    n.created_at,
    n.actor_id,
    COALESCE(ap.display_name, '书友') AS actor_name,
    ap.avatar_url AS actor_avatar,
    n.post_id,
    rp.book_title,
    n.message,
    COALESCE(
      n.link_path,
      CASE WHEN n.post_id IS NOT NULL THEN '/reading-circle?post=' || n.post_id::TEXT ELSE NULL END
    ) AS link_path
  FROM public.notifications n
  LEFT JOIN public.profiles ap ON ap.id = n.actor_id
  LEFT JOIN public.reading_posts rp ON rp.id = n.post_id
  WHERE n.user_id = auth.uid()
  ORDER BY n.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 关注/取关：关注时写入通知，取消关注不删除历史通知。
CREATE OR REPLACE FUNCTION public.toggle_follow(p_following_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_follower_id UUID;
  v_exists BIGINT;
  v_follower_name TEXT;
BEGIN
  v_follower_id := auth.uid();
  IF v_follower_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF v_follower_id = p_following_id THEN
    RAISE EXCEPTION 'Cannot follow yourself';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_following_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  SELECT id INTO v_exists
  FROM public.user_follows
  WHERE follower_id = v_follower_id AND following_id = p_following_id;

  IF FOUND THEN
    DELETE FROM public.user_follows WHERE id = v_exists;
    RETURN 'unfollowed';
  ELSE
    INSERT INTO public.user_follows (follower_id, following_id)
    VALUES (v_follower_id, p_following_id);

    SELECT COALESCE(NULLIF(trim(display_name), ''), '书友')
      INTO v_follower_name
    FROM public.profiles
    WHERE id = v_follower_id;

    INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path)
    VALUES (
      p_following_id,
      'follow',
      v_follower_id,
      NULL,
      COALESCE(v_follower_name, '书友') || '关注了你',
      '/user/' || v_follower_id::TEXT
    )
    ON CONFLICT (user_id, type, actor_id) WHERE is_read = false AND type = 'follow'
    DO UPDATE SET
      created_at = now(),
      message = EXCLUDED.message,
      link_path = EXCLUDED.link_path;

    RETURN 'followed';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 升级时写入等级徽章通知。
CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
  v_new_title TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key, title
    INTO v_new_level, v_new_tier, v_new_badge_key, v_new_title
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
    v_new_title := '';
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 补齐当前等级及以下应有等级徽章。
  INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
  SELECT p_user_id, ml.badge_key, 'level', 'level_recalculate'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.badge_key IS NOT NULL
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  -- 只有真正升级时通知；降级、同级重算、Lv.0 不通知。
  IF v_new_level > COALESCE(v_old_level, 0) AND v_new_level > 0 THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path)
    VALUES (
      p_user_id,
      'level_badge',
      p_user_id,
      NULL,
      '恭喜你升级到 Lv.' || lpad(v_new_level::TEXT, 2, '0') || ' ' || COALESCE(v_new_title, '') || '，快去个人中心看看你的徽章并点击答题吧！',
      '/member'
    );
  END IF;

  -- 降级或贡献值回收后，回收高于当前等级的成长徽章。
  -- 开创者、纪念徽章、行为徽章不受等级回退影响。
  UPDATE public.user_badges ub
  SET revoked_at = now()
  FROM public.badge_catalog bc
  WHERE ub.user_id = p_user_id
    AND ub.badge_key = bc.badge_key
    AND ub.badge_type = 'level'
    AND bc.badge_type = 'level'
    AND bc.level > v_new_level
    AND ub.revoked_at IS NULL;

  -- 共读兑换券仍按等级奖励每级最多一张。这里补齐缺失记录，
  -- 已使用或已回收的同等级券不会重复创建。
  INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
  SELECT p_user_id, 'available', ml.level, 'level_up'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.reward_redemption_tickets > 0
  ON CONFLICT DO NOTHING;

  IF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_follow(UUID) TO authenticated;

-- 补推送一遍既有关注关系，便于上线后核验关注通知。
-- 已存在同一关注者的未读关注通知时只刷新时间和文案。
INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path, is_read, created_at)
SELECT
  uf.following_id,
  'follow',
  uf.follower_id,
  NULL,
  COALESCE(NULLIF(trim(p.display_name), ''), '书友') || '关注了你',
  '/user/' || uf.follower_id::TEXT,
  false,
  now()
FROM public.user_follows uf
LEFT JOIN public.profiles p ON p.id = uf.follower_id
ON CONFLICT (user_id, type, actor_id) WHERE is_read = false AND type = 'follow'
DO UPDATE SET
  created_at = now(),
  message = EXCLUDED.message,
  link_path = EXCLUDED.link_path;

-- 补推送一遍当前等级徽章通知，便于上线后核验升级徽章通知样式。
-- 仅补 Lv.1 以上；已有同文案未读通知时不重复插入。
INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path, is_read, created_at)
SELECT
  ms.user_id,
  'level_badge',
  ms.user_id,
  NULL,
  '恭喜你升级到 Lv.' || lpad(ms.level::TEXT, 2, '0') || ' ' || COALESCE(ml.title, '') || '，快去个人中心看看你的徽章并点击答题吧！',
  '/member',
  false,
  now()
FROM public.member_stats ms
JOIN public.member_levels ml ON ml.level = ms.level
WHERE ms.level > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = ms.user_id
      AND n.type = 'level_badge'
      AND n.is_read = false
      AND n.message = '恭喜你升级到 Lv.' || lpad(ms.level::TEXT, 2, '0') || ' ' || COALESCE(ml.title, '') || '，快去个人中心看看你的徽章并点击答题吧！'
  );

COMMENT ON FUNCTION public.recalculate_member_level(UUID) IS
  '根据贡献值重算会员等级，补齐当前等级应有徽章，升级时发送徽章通知，并回收高于当前等级的成长徽章和未使用升级券';

-- ============================================================
-- END migrate-v36-follow-level-notifications.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v37-member-ban.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v37 迁移：会员封禁
-- 管理员可在会员清单中封禁/解锁用户。
-- 封禁后，该账号不能浏览共读书库、书友圈、西语文学板块，也不能在书友圈发帖互动。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_bans (
  user_id     UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL DEFAULT '',
  banned_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  banned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  lifted_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  lifted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_member_bans_active
  ON public.member_bans(user_id)
  WHERE lifted_at IS NULL;

ALTER TABLE public.member_bans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_bans_admin_read" ON public.member_bans;
CREATE POLICY "member_bans_admin_read"
  ON public.member_bans
  FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "member_bans_admin_write" ON public.member_bans;
CREATE POLICY "member_bans_admin_write"
  ON public.member_bans
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.is_user_banned(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.member_bans mb
    WHERE mb.user_id = p_user_id
      AND mb.lifted_at IS NULL
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_current_user_banned()
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() THEN
    RETURN false;
  END IF;

  RETURN public.is_user_banned(auth.uid());
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.require_not_banned()
RETURNS VOID AS $$
BEGIN
  IF public.is_current_user_banned() THEN
    RAISE EXCEPTION 'account_banned';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.require_authenticated_member()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login_required';
  END IF;

  PERFORM public.require_not_banned();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_set_member_ban(
  p_user_id UUID,
  p_is_banned BOOLEAN,
  p_reason TEXT DEFAULT ''
)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  IF p_user_id = auth.uid() AND p_is_banned THEN
    RAISE EXCEPTION 'cannot_ban_self';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  IF p_is_banned THEN
    INSERT INTO public.member_bans
      (user_id, reason, banned_by, banned_at, lifted_by, lifted_at)
    VALUES
      (p_user_id, COALESCE(p_reason, ''), auth.uid(), now(), NULL, NULL)
    ON CONFLICT (user_id) DO UPDATE SET
      reason = EXCLUDED.reason,
      banned_by = auth.uid(),
      banned_at = now(),
      lifted_by = NULL,
      lifted_at = NULL;
  ELSE
    UPDATE public.member_bans
    SET lifted_by = auth.uid(),
        lifted_at = now()
    WHERE user_id = p_user_id
      AND lifted_at IS NULL;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 被封禁用户不可读取共读书库；游客仍可浏览公开书库。
DROP POLICY IF EXISTS "books_read_all" ON public.books;
DROP POLICY IF EXISTS "books_read_public_not_banned" ON public.books;
CREATE POLICY "books_read_public_not_banned"
  ON public.books
  FOR SELECT
  USING (
    auth.uid() IS NULL
    OR public.is_admin()
    OR NOT public.is_user_banned(auth.uid())
  );

-- 书友圈写入兜底：阻断被封禁用户绕过前端直接调用 RPC。
CREATE OR REPLACE FUNCTION public.block_banned_reading_circle_write()
RETURNS TRIGGER AS $$
BEGIN
  IF public.is_current_user_banned() THEN
    RAISE EXCEPTION 'account_banned';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_block_banned_reading_posts_write ON public.reading_posts;
CREATE TRIGGER trg_block_banned_reading_posts_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.reading_posts
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

DROP TRIGGER IF EXISTS trg_block_banned_post_comments_write ON public.post_comments;
CREATE TRIGGER trg_block_banned_post_comments_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.post_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

DROP TRIGGER IF EXISTS trg_block_banned_post_likes_write ON public.post_likes;
CREATE TRIGGER trg_block_banned_post_likes_write
  BEFORE INSERT OR DELETE ON public.post_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

-- 会员清单增加封禁状态；改返回类型需要先删除旧函数。
DROP FUNCTION IF EXISTS public.admin_list_members();

CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  registered_at TIMESTAMPTZ,
  level INTEGER,
  title TEXT,
  tier TEXT,
  note TEXT,
  is_banned BOOLEAN,
  ban_reason TEXT,
  banned_at TIMESTAMPTZ
) AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.display_name,
    au.email::TEXT AS email,
    COALESCE(au.created_at, p.created_at) AS registered_at,
    COALESCE(ms.level, 0) AS level,
    ml.title,
    COALESCE(ms.tier, ml.tier, '基础会员') AS tier,
    COALESCE(man.note, '') AS note,
    (mb.user_id IS NOT NULL) AS is_banned,
    COALESCE(mb.reason, '') AS ban_reason,
    mb.banned_at
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  LEFT JOIN public.member_admin_notes man ON man.user_id = p.id
  LEFT JOIN public.member_bans mb ON mb.user_id = p.id AND mb.lifted_at IS NULL
  ORDER BY COALESCE(au.created_at, p.created_at) DESC, p.display_name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_current_user_banned() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_member_ban(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_members() TO authenticated;

COMMENT ON TABLE public.member_bans IS '会员封禁记录；lifted_at 为空代表当前封禁中';
COMMENT ON FUNCTION public.admin_set_member_ban(UUID, BOOLEAN, TEXT) IS '管理员封禁或解锁会员';

-- ============================================================
-- END migrate-v37-member-ban.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v37-fix-visibility-friends.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v37 迁移：修复好友可见切换报错
-- update_reading_post_visibility 支持 friends
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_reading_post_visibility(
  p_post_id BIGINT,
  p_visibility TEXT
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_visibility NOT IN ('public', 'friends', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND user_id = auth.uid()
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF v_post.visibility = p_visibility THEN
    RETURN;
  END IF;

  UPDATE public.reading_posts
  SET visibility = p_visibility,
      updated_at = now()
  WHERE id = p_post_id;

  IF p_visibility = 'private' THEN
    PERFORM public.revoke_reading_post_contributions(p_post_id);
  ELSE
    PERFORM public.award_reading_post_contributions(p_post_id);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.update_reading_post_visibility(BIGINT, TEXT) TO authenticated;

-- ============================================================
-- END migrate-v37-fix-visibility-friends.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v38-host-notes-fields.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v38 迁移：共读导言增加标题/副标题/作者字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_title TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_subtitle TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_author TEXT;

-- ============================================================
-- END migrate-v38-host-notes-fields.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v38-member-library.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v38 迁移：我的书库
-- 已读书目来自已读书友圈；想读书目最多 5 本；人生之书最多 3 本。
-- 管理员可导出当前所有会员想读 / 人生之书数据。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_library_items (
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  list_type   TEXT NOT NULL CHECK (list_type IN ('want', 'life')),
  sort_order  INTEGER NOT NULL,
  book_title  TEXT NOT NULL,
  author      TEXT,
  douban_url  TEXT NOT NULL,
  cover_url   TEXT,
  reason      TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, list_type, sort_order),
  CONSTRAINT member_library_items_sort_limit CHECK (
    (list_type = 'want' AND sort_order BETWEEN 1 AND 5)
    OR (list_type = 'life' AND sort_order BETWEEN 1 AND 3)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_member_library_unique_book
  ON public.member_library_items(user_id, list_type, douban_url);

CREATE INDEX IF NOT EXISTS idx_member_library_user_type
  ON public.member_library_items(user_id, list_type, sort_order);

ALTER TABLE public.member_library_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_library_read_self_or_admin" ON public.member_library_items;
CREATE POLICY "member_library_read_self_or_admin"
  ON public.member_library_items
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "member_library_write_self" ON public.member_library_items;
CREATE POLICY "member_library_write_self"
  ON public.member_library_items
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.list_my_finished_books()
RETURNS TABLE (
  post_id BIGINT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  content TEXT,
  visibility TEXT,
  finished_at TIMESTAMPTZ,
  post_count BIGINT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH finished AS (
    SELECT
      rp.*,
      COALESCE(NULLIF(trim(rp.douban_url), ''), 'title:' || lower(trim(rp.book_title))) AS book_key
    FROM public.reading_posts rp
    WHERE rp.user_id = auth.uid()
      AND rp.post_type = 'finished'
      AND rp.is_deleted = false
  ),
  ranked AS (
    SELECT
      f.*,
      row_number() OVER (PARTITION BY f.book_key ORDER BY f.created_at DESC, f.id DESC) AS rn,
      count(*) OVER (PARTITION BY f.book_key) AS post_count
    FROM finished f
  )
  SELECT
    r.id,
    r.book_title,
    r.author,
    r.douban_url,
    r.cover_url,
    r.content,
    r.visibility,
    r.created_at,
    r.post_count
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.created_at DESC, r.id DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_my_member_library_items()
RETURNS TABLE (
  list_type TEXT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  reason TEXT,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    mli.list_type,
    mli.sort_order,
    mli.book_title,
    mli.author,
    mli.douban_url,
    mli.cover_url,
    mli.reason,
    mli.updated_at
  FROM public.member_library_items mli
  WHERE mli.user_id = auth.uid()
  ORDER BY mli.list_type, mli.sort_order;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.upsert_my_member_library_item(
  p_list_type TEXT,
  p_sort_order INTEGER,
  p_book_title TEXT,
  p_author TEXT,
  p_douban_url TEXT,
  p_cover_url TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT ''
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_douban_url TEXT;
BEGIN
  PERFORM public.require_authenticated_member();
  v_user_id := auth.uid();

  IF p_list_type NOT IN ('want', 'life') THEN
    RAISE EXCEPTION 'invalid_list_type';
  END IF;

  IF (p_list_type = 'want' AND (p_sort_order < 1 OR p_sort_order > 5))
    OR (p_list_type = 'life' AND (p_sort_order < 1 OR p_sort_order > 3)) THEN
    RAISE EXCEPTION 'invalid_sort_order';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'book_title_required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = '' OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?' THEN
    RAISE EXCEPTION 'valid_douban_url_required';
  END IF;

  DELETE FROM public.member_library_items
  WHERE user_id = v_user_id
    AND list_type = p_list_type
    AND douban_url = v_douban_url
    AND sort_order <> p_sort_order;

  INSERT INTO public.member_library_items (
    user_id, list_type, sort_order, book_title, author, douban_url, cover_url, reason, created_at, updated_at
  ) VALUES (
    v_user_id,
    p_list_type,
    p_sort_order,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    COALESCE(p_reason, ''),
    now(),
    now()
  )
  ON CONFLICT (user_id, list_type, sort_order) DO UPDATE SET
    book_title = EXCLUDED.book_title,
    author = EXCLUDED.author,
    douban_url = EXCLUDED.douban_url,
    cover_url = EXCLUDED.cover_url,
    reason = EXCLUDED.reason,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.delete_my_member_library_item(
  p_list_type TEXT,
  p_sort_order INTEGER
)
RETURNS VOID AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  DELETE FROM public.member_library_items
  WHERE user_id = auth.uid()
    AND list_type = p_list_type
    AND sort_order = p_sort_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_export_member_library()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  list_type TEXT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  reason TEXT,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  RETURN QUERY
  SELECT
    mli.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    au.email::TEXT AS email,
    mli.list_type,
    mli.sort_order,
    mli.book_title,
    mli.author,
    mli.douban_url,
    mli.reason,
    mli.updated_at
  FROM public.member_library_items mli
  LEFT JOIN public.profiles p ON p.id = mli.user_id
  LEFT JOIN auth.users au ON au.id = mli.user_id
  ORDER BY mli.list_type, mli.sort_order, mli.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_my_finished_books() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_member_library_items() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_my_member_library_item(TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_member_library_item(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_export_member_library() TO authenticated;

COMMENT ON TABLE public.member_library_items IS '会员个人书库：想读书目与人生之书当前列表';
COMMENT ON FUNCTION public.list_my_finished_books() IS '从当前用户已读书友圈中聚合已读书目';
COMMENT ON FUNCTION public.admin_export_member_library() IS '管理员导出会员想读书目与人生之书';

-- ============================================================
-- END migrate-v38-member-library.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v39-nested-comments.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v39 迁移：评论嵌套 + 回复通知
-- post_comments 增加 parent_id，支持回复他人评论
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 0. 更新 notifications 类型约束，加入 comment_reply
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('like', 'comment', 'follow', 'level_badge', 'comment_reply'));

-- 1. 添加 parent_id 列
ALTER TABLE public.post_comments
  ADD COLUMN IF NOT EXISTS parent_id BIGINT
  REFERENCES public.post_comments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_post_comments_parent
  ON public.post_comments(parent_id) WHERE parent_id IS NOT NULL;

-- 2. 更新 create_comment 支持 parent_id + 回复通知
DROP FUNCTION IF EXISTS public.create_comment(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT,
  p_parent_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_parent public.post_comments%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_content, '')) = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  -- 验证 parent_id 存在且属于同一帖子
  IF p_parent_id IS NOT NULL THEN
    SELECT * INTO v_parent
    FROM public.post_comments
    WHERE id = p_parent_id AND post_id = p_post_id AND is_deleted = false;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parent comment not found';
    END IF;
  END IF;

  -- 每天最多 50 条评论（防刷）
  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content, parent_id)
  VALUES (p_post_id, v_user_id, trim(p_content), p_parent_id)
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  -- 给动态作者发放评论贡献值（每日上限 20，不对自己评论加分）
  IF v_post.user_id <> v_user_id THEN
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;

    -- 通知动态作者
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id);
  END IF;

  -- 回复通知：告知被回复的人（不是自己、不是动态作者）
  IF p_parent_id IS NOT NULL AND v_parent.user_id <> v_user_id AND v_parent.user_id <> v_post.user_id THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_parent.user_id, 'comment_reply', v_user_id, p_post_id);
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 list_comments 返回 parent_id 和回复的父评论作者名
DROP FUNCTION IF EXISTS public.list_comments(BIGINT);

CREATE OR REPLACE FUNCTION public.list_comments(p_post_id BIGINT)
RETURNS TABLE (
  id BIGINT,
  post_id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  content TEXT,
  is_deleted BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  parent_id BIGINT,
  parent_author_name TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.post_id,
    pc.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    pc.content,
    pc.is_deleted,
    pc.created_at,
    pc.updated_at,
    pc.parent_id,
    pa.display_name AS parent_author_name
  FROM public.post_comments pc
  LEFT JOIN public.profiles p ON p.id = pc.user_id
  LEFT JOIN public.post_comments pp ON pp.id = pc.parent_id
  LEFT JOIN public.profiles pa ON pa.id = pp.user_id
  WHERE pc.post_id = p_post_id
    AND pc.is_deleted = false
  ORDER BY COALESCE(pc.parent_id, pc.id), pc.created_at ASC
  LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 4. 授权
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_comments(BIGINT) TO anon, authenticated;

-- ============================================================
-- END migrate-v39-nested-comments.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v39-public-member-library.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v39 迁移：个人主页公开书库
-- 将会员的已读书目、想读书目、人生之书提供给个人主页展示。
-- 在 Supabase SQL Editor 中执行，需先执行 v38。
-- ============================================================

CREATE OR REPLACE FUNCTION public.list_public_member_library(p_user_id UUID)
RETURNS TABLE (
  list_type TEXT,
  post_id BIGINT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  note TEXT,
  item_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH finished AS (
    SELECT
      rp.*,
      COALESCE(NULLIF(trim(rp.douban_url), ''), 'title:' || lower(trim(rp.book_title))) AS book_key
    FROM public.reading_posts rp
    WHERE rp.user_id = p_user_id
      AND rp.post_type = 'finished'
      AND rp.visibility = 'public'
      AND rp.is_deleted = false
  ),
  ranked_finished AS (
    SELECT
      f.*,
      row_number() OVER (PARTITION BY f.book_key ORDER BY f.created_at DESC, f.id DESC) AS rn
    FROM finished f
  )
  SELECT *
  FROM (
    SELECT
      'finished'::TEXT AS list_type,
      rf.id AS post_id,
      NULL::INTEGER AS sort_order,
      rf.book_title,
      rf.author,
      rf.douban_url,
      rf.cover_url,
      rf.content AS note,
      rf.created_at AS item_at
    FROM ranked_finished rf
    WHERE rf.rn = 1

    UNION ALL

    SELECT
      mli.list_type,
      NULL::BIGINT AS post_id,
      mli.sort_order,
      mli.book_title,
      mli.author,
      mli.douban_url,
      mli.cover_url,
      mli.reason AS note,
      mli.updated_at AS item_at
    FROM public.member_library_items mli
    WHERE mli.user_id = p_user_id
      AND mli.list_type IN ('want', 'life')
  ) library
  ORDER BY
    CASE library.list_type
      WHEN 'life' THEN 1
      WHEN 'want' THEN 2
      ELSE 3
    END,
    library.sort_order NULLS LAST,
    library.item_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_public_member_library(UUID) TO authenticated;

COMMENT ON FUNCTION public.list_public_member_library(UUID) IS
  '个人主页展示公开书库：公开已读书目、想读书目、人生之书';

-- ============================================================
-- END migrate-v39-public-member-library.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v40-comment-reply-notification-dedupe.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v40 迁移：修复楼中楼回复通知去重冲突
-- v39 重写 create_comment 时遗漏了 v24 的通知 ON CONFLICT 去重，
-- 导致同一用户对同一动态/评论连续回复时撞
-- idx_notifications_unread_dedupe 唯一索引。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT,
  p_parent_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_parent public.post_comments%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  v_content := trim(COALESCE(p_content, ''));
  IF v_content = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  IF char_length(v_content) > 800 THEN
    RAISE EXCEPTION 'Comment content exceeds 800 characters';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF p_parent_id IS NOT NULL THEN
    SELECT * INTO v_parent
    FROM public.post_comments
    WHERE id = p_parent_id
      AND post_id = p_post_id
      AND is_deleted = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parent comment not found';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.post_comments
    WHERE post_id = p_post_id
      AND user_id = v_user_id
      AND is_deleted = false
      AND COALESCE(parent_id, 0) = COALESCE(p_parent_id, 0)
      AND content = v_content
      AND created_at >= now() - interval '10 minutes'
  ) THEN
    RAISE EXCEPTION 'Duplicate comment too soon';
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content, parent_id)
  VALUES (p_post_id, v_user_id, v_content, p_parent_id)
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  IF v_post.user_id <> v_user_id THEN
    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;

    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();
  END IF;

  IF p_parent_id IS NOT NULL
     AND v_parent.user_id <> v_user_id
     AND v_parent.user_id <> v_post.user_id THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_parent.user_id, 'comment_reply', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT, BIGINT) TO authenticated;

-- ============================================================
-- END migrate-v40-comment-reply-notification-dedupe.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v41-weekly-view-pass-source-key-fix.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v41 迁移：修复每周资源浏览券发放 source_key 歧义
-- admin_issue_weekly_view_passes 的 RETURNS TABLE 含 source_key 输出列，
-- 与 view_passes.source_key 字段同名，导致 ON CONFLICT 谓词中
-- column reference "source_key" is ambiguous。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
#variable_conflict use_column
DECLARE
  v_source_key TEXT;
  v_inserted_passes INTEGER;
  v_inserted_users INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  v_source_key := 'weekly_' || to_char(date_trunc('week', now()), 'IYYY_IW');

  WITH weekly_activity AS (
    SELECT
      cl.user_id,
      SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= date_trunc('week', now())
      AND cl.created_at < date_trunc('week', now()) + interval '7 days'
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      ml.weekly_view_passes,
      COALESCE(wa.points, 0) AS weekly_activity_points,
      row_number() OVER (
        ORDER BY COALESCE(wa.points, 0) DESC, ms.contribution_total DESC, ms.user_id
      ) AS rank_position
    FROM public.member_stats ms
    JOIN public.member_levels ml ON ml.level = ms.level
    LEFT JOIN weekly_activity wa ON wa.user_id = ms.user_id
    WHERE ml.weekly_view_passes > 0
  ),
  expanded AS (
    SELECT
      r.user_id,
      generate_series(
        1,
        r.weekly_view_passes * CASE
          WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2
          ELSE 1
        END
      ) AS pass_no
    FROM ranked r
  ),
  passes_to_insert AS (
    SELECT
      e.user_id,
      (v_source_key || '_' || e.user_id || '_' || e.pass_no) AS pass_source_key
    FROM expanded e
  ),
  inserted AS (
    INSERT INTO public.view_passes
      (user_id, status, issued_reason, source_key, issued_at, expires_at)
    SELECT
      pti.user_id,
      'available',
      'weekly',
      pti.pass_source_key,
      now(),
      now() + interval '7 days'
    FROM passes_to_insert pti
    ON CONFLICT (user_id, source_key) WHERE (source_key IS NOT NULL)
    DO NOTHING
    RETURNING public.view_passes.user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT inserted.user_id)::INTEGER
    INTO v_inserted_passes, v_inserted_users
  FROM inserted;

  issued_passes := COALESCE(v_inserted_passes, 0);
  issued_users := COALESCE(v_inserted_users, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;

-- ============================================================
-- END migrate-v41-weekly-view-pass-source-key-fix.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v42-live-weekly-contribution-rank.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v42 迁移：周贡献榜实时按当前自然周计算
--
-- 背景：
-- member_stats.contribution_week 是缓存字段。旧逻辑只在用户产生新贡献时重置，
-- 所以上周有分、本周没有动作的用户可能继续残留在本周榜。
--
-- 本迁移：
-- 1. 将 get_contribution_leaderboard('week') 改为实时汇总当前上海自然周的 reading_activity 日志。
-- 2. 将 get_my_weekly_contribution_rank() 改为实时汇总当前上海自然周的 reading_activity 日志。
-- 3. 顺手校准 member_stats.contribution_week，清掉当前缓存里的旧周残留。
-- ============================================================

UPDATE public.member_stats ms
SET
  contribution_week = COALESCE(
    (
      SELECT SUM(cl.points)
      FROM public.contribution_logs cl
      WHERE cl.user_id = ms.user_id
        AND cl.is_active = true
        AND cl.contribution_scope = 'reading_activity'
        AND cl.created_at >= (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai')
        AND cl.created_at <  (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days'
    ),
    0
  ),
  updated_at = now();

CREATE OR REPLACE FUNCTION public.get_contribution_leaderboard(p_type TEXT DEFAULT 'total')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  contribution INTEGER
) AS $$
DECLARE
  v_week_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end   TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  WITH live_week AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_week_start
      AND cl.created_at < v_week_end
    GROUP BY cl.user_id
  ),
  scored AS (
    SELECT
      ms.user_id,
      COALESCE(p.display_name, '书友') AS display_name,
      p.avatar_url,
      COALESCE(ms.level, 0) AS level,
      COALESCE(ml.title, '') AS title,
      p.created_at,
      CASE p_type
        WHEN 'total' THEN ms.contribution_total
        WHEN 'month' THEN ms.contribution_month
        WHEN 'week'  THEN COALESCE(lw.contribution, 0)
      END::INTEGER AS contribution
    FROM public.member_stats ms
    JOIN public.profiles p ON p.id = ms.user_id
    LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
    LEFT JOIN live_week lw ON lw.user_id = ms.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY scored.contribution DESC, scored.created_at ASC)::BIGINT AS rank,
    scored.user_id,
    scored.display_name,
    scored.avatar_url,
    scored.level,
    scored.title,
    scored.contribution
  FROM scored
  WHERE scored.contribution > 0
  ORDER BY scored.contribution DESC, scored.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_weekly_contribution_rank()
RETURNS TABLE (
  rank_position INTEGER,
  total_members INTEGER,
  contribution_week INTEGER
) AS $$
DECLARE
  v_week_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end   TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  RETURN QUERY
  WITH live_week AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution_week
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_week_start
      AND cl.created_at < v_week_end
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      COALESCE(lw.contribution_week, 0)::INTEGER AS contribution_week,
      RANK() OVER (ORDER BY COALESCE(lw.contribution_week, 0) DESC) AS rank_position,
      COUNT(*) OVER () AS total_members
    FROM public.member_stats ms
    LEFT JOIN live_week lw ON lw.user_id = ms.user_id
  )
  SELECT
    ranked.rank_position::INTEGER,
    ranked.total_members::INTEGER,
    ranked.contribution_week::INTEGER
  FROM ranked
  WHERE ranked.user_id = auth.uid();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() TO authenticated;

COMMENT ON FUNCTION public.get_contribution_leaderboard(TEXT) IS
  '贡献榜单。week 类型实时汇总当前上海自然周 reading_activity 贡献，避免 member_stats 周缓存残留旧数据。';

COMMENT ON FUNCTION public.get_my_weekly_contribution_rank() IS
  '返回当前登录用户在当前上海自然周 reading_activity 贡献中的实时排名。';

-- ============================================================
-- END migrate-v42-live-weekly-contribution-rank.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v43-live-monthly-contribution-rank.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v43 迁移：月贡献榜实时按当前自然月计算
--
-- 背景：
-- member_stats.contribution_month 也是缓存字段。旧逻辑只在用户产生新贡献时重置，
-- 所以上月有分、本月没有动作的用户可能继续残留在月贡献榜。
--
-- 本迁移：
-- 1. 将 get_contribution_leaderboard('month') 改为实时汇总当前上海自然月的 reading_activity 日志。
-- 2. 保留 v42 中 get_contribution_leaderboard('week') 的实时当前上海自然周口径。
-- 3. 顺手校准 member_stats.contribution_month，清掉当前缓存里的旧月残留。
-- ============================================================

UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (
      SELECT SUM(cl.points)
      FROM public.contribution_logs cl
      WHERE cl.user_id = ms.user_id
        AND cl.is_active = true
        AND cl.contribution_scope = 'reading_activity'
        AND cl.created_at >= (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai')
        AND cl.created_at <  (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '1 month'
    ),
    0
  ),
  updated_at = now();

CREATE OR REPLACE FUNCTION public.get_contribution_leaderboard(p_type TEXT DEFAULT 'total')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  contribution INTEGER
) AS $$
DECLARE
  v_month_start TIMESTAMPTZ := date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_month_end   TIMESTAMPTZ := (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '1 month';
  v_week_start  TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end    TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  WITH live_month AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_month_start
      AND cl.created_at < v_month_end
    GROUP BY cl.user_id
  ),
  live_week AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_week_start
      AND cl.created_at < v_week_end
    GROUP BY cl.user_id
  ),
  scored AS (
    SELECT
      ms.user_id,
      COALESCE(p.display_name, '书友') AS display_name,
      p.avatar_url,
      COALESCE(ms.level, 0) AS level,
      COALESCE(ml.title, '') AS title,
      p.created_at,
      CASE p_type
        WHEN 'total' THEN ms.contribution_total
        WHEN 'month' THEN COALESCE(lm.contribution, 0)
        WHEN 'week'  THEN COALESCE(lw.contribution, 0)
      END::INTEGER AS contribution
    FROM public.member_stats ms
    JOIN public.profiles p ON p.id = ms.user_id
    LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
    LEFT JOIN live_month lm ON lm.user_id = ms.user_id
    LEFT JOIN live_week lw ON lw.user_id = ms.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY scored.contribution DESC, scored.created_at ASC)::BIGINT AS rank,
    scored.user_id,
    scored.display_name,
    scored.avatar_url,
    scored.level,
    scored.title,
    scored.contribution
  FROM scored
  WHERE scored.contribution > 0
  ORDER BY scored.contribution DESC, scored.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO authenticated;

COMMENT ON FUNCTION public.get_contribution_leaderboard(TEXT) IS
  '贡献榜单。month/week 类型实时汇总当前上海自然月/自然周 reading_activity 贡献，避免 member_stats 月周缓存残留旧数据。';

-- ============================================================
-- END migrate-v43-live-monthly-contribution-rank.sql
-- ============================================================



-- ============================================================
-- BEGIN migrate-v44-drop-legacy-checkins.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v44 迁移：下线旧每日签到数据表
--
-- 背景：
-- 旧的每日签到前端功能已经废弃，阅读记录统一迁移到书友圈体系。
--
-- 影响：
-- 执行后会删除 daily_checkins 表及其索引、RLS policy 和表内历史签到数据。
-- 如果需要保留历史数据，请先在 Supabase 中导出 daily_checkins。
-- ============================================================

DROP TABLE IF EXISTS daily_checkins CASCADE;

-- ============================================================
-- END migrate-v44-drop-legacy-checkins.sql
-- ============================================================



-- ============================================================
-- BEGIN migrate-v47-public-display-badges.sql
-- ============================================================

-- ============================================================
-- 以读攻独 · v47 迁移：公开个人主页展示徽章与完本文案
-- 在 Supabase SQL Editor 中执行
-- ============================================================

UPDATE public.badge_catalog
SET
  title = replace(title, '读完纪念', '完本纪念'),
  updated_at = now()
WHERE title LIKE '%读完纪念%';

CREATE OR REPLACE FUNCTION public.ensure_commemorative_badges(p_book_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_title TEXT;
BEGIN
  SELECT title INTO v_title
  FROM public.books
  WHERE id = p_book_id;

  IF v_title IS NULL THEN
    RAISE EXCEPTION 'Book not found';
  END IF;

  INSERT INTO public.badge_catalog
    (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
  VALUES
    ('commemorative_book_' || p_book_id || '_claimed', 'commemorative', '《' || v_title || '》共读纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_claimed'),
    ('commemorative_book_' || p_book_id || '_finished', 'commemorative', '《' || v_title || '》完本纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_finished')
  ON CONFLICT (badge_key) DO UPDATE SET
    title = EXCLUDED.title,
    badge_type = EXCLUDED.badge_type,
    is_active = true,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_public_member_display_badges(p_user_id UUID)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  badge_key TEXT,
  badge_type TEXT,
  awarded_reason TEXT,
  awarded_at TIMESTAMPTZ,
  catalog_badge_type TEXT,
  title TEXT,
  level INTEGER,
  image_bucket TEXT,
  image_path TEXT,
  back_image_bucket TEXT,
  back_image_path TEXT,
  catalog_updated_at TIMESTAMPTZ,
  sort_order INTEGER
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH active_badges AS (
    SELECT
      ub.id,
      ub.user_id,
      ub.badge_key,
      ub.badge_type,
      ub.awarded_reason,
      ub.awarded_at,
      bc.badge_type AS catalog_badge_type,
      replace(COALESCE(bc.title, ub.badge_key), '读完纪念', '完本纪念') AS title,
      bc.level,
      bc.image_bucket,
      bc.image_path,
      bc.back_image_bucket,
      bc.back_image_path,
      bc.updated_at AS catalog_updated_at,
      (
        ub.badge_key = 'founder'
        OR ub.badge_type = 'founder'
        OR bc.badge_type = 'founder'
      ) AS is_founder
    FROM public.user_badges ub
    JOIN public.badge_catalog bc ON bc.badge_key = ub.badge_key
    WHERE ub.user_id = p_user_id
      AND ub.revoked_at IS NULL
  ),
  prefs AS (
    SELECT p.badge_key, p.sort_order
    FROM public.member_badge_display_preferences p
    JOIN active_badges ab ON ab.badge_key = p.badge_key
    WHERE p.user_id = p_user_id
  ),
  has_prefs AS (
    SELECT EXISTS (SELECT 1 FROM prefs) AS value
  ),
  selected_keys AS (
    SELECT prefs.badge_key FROM prefs
    UNION
    SELECT ab.badge_key
    FROM active_badges ab
    WHERE ab.is_founder
      AND NOT EXISTS (
        SELECT 1
        FROM prefs p
        WHERE p.badge_key = ab.badge_key
      )
  ),
  preferred AS (
    SELECT ab.*, p.sort_order
    FROM active_badges ab
    JOIN prefs p ON p.badge_key = ab.badge_key
  ),
  founder AS (
    SELECT ab.*, 0 AS sort_order
    FROM active_badges ab
    CROSS JOIN has_prefs hp
    WHERE hp.value
      AND ab.is_founder
      AND NOT EXISTS (
        SELECT 1
        FROM prefs p
        WHERE p.badge_key = ab.badge_key
      )
  ),
  filler AS (
    SELECT
      ranked.id,
      ranked.user_id,
      ranked.badge_key,
      ranked.badge_type,
      ranked.awarded_reason,
      ranked.awarded_at,
      ranked.catalog_badge_type,
      ranked.title,
      ranked.level,
      ranked.image_bucket,
      ranked.image_path,
      ranked.back_image_bucket,
      ranked.back_image_path,
      ranked.catalog_updated_at,
      ranked.is_founder,
      (100 + ranked.fill_order)::INTEGER AS sort_order
    FROM (
      SELECT
        ab.*,
        (ROW_NUMBER() OVER (ORDER BY ab.is_founder DESC, ab.awarded_at DESC, ab.id DESC))::INTEGER AS fill_order
      FROM active_badges ab
      CROSS JOIN has_prefs hp
      WHERE hp.value
        AND NOT EXISTS (
          SELECT 1
          FROM selected_keys sk
          WHERE sk.badge_key = ab.badge_key
        )
    ) ranked
  ),
  fallback AS (
    SELECT
      ranked.id,
      ranked.user_id,
      ranked.badge_key,
      ranked.badge_type,
      ranked.awarded_reason,
      ranked.awarded_at,
      ranked.catalog_badge_type,
      ranked.title,
      ranked.level,
      ranked.image_bucket,
      ranked.image_path,
      ranked.back_image_bucket,
      ranked.back_image_path,
      ranked.catalog_updated_at,
      ranked.is_founder,
      ranked.fallback_order AS sort_order
    FROM (
      SELECT
        ab.*,
        (ROW_NUMBER() OVER (ORDER BY ab.is_founder DESC, ab.awarded_at DESC, ab.id DESC))::INTEGER AS fallback_order
      FROM active_badges ab
      CROSS JOIN has_prefs hp
      WHERE NOT hp.value
    ) ranked
  ),
  display_rows AS (
    SELECT * FROM preferred
    UNION ALL
    SELECT * FROM founder
    UNION ALL
    SELECT * FROM filler
    UNION ALL
    SELECT * FROM fallback
  )
  SELECT
    dr.id,
    dr.user_id,
    dr.badge_key,
    dr.badge_type,
    dr.awarded_reason,
    dr.awarded_at,
    dr.catalog_badge_type,
    dr.title,
    dr.level,
    dr.image_bucket,
    dr.image_path,
    dr.back_image_bucket,
    dr.back_image_path,
    dr.catalog_updated_at,
    dr.sort_order
  FROM display_rows dr
  ORDER BY dr.sort_order ASC, dr.awarded_at DESC, dr.id DESC
  LIMIT 6;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) TO authenticated;

COMMENT ON FUNCTION public.list_public_member_display_badges(UUID) IS
  '公开个人主页展示徽章：优先使用用户在个人中心保存的徽章展示偏好；未保存时按旧规则返回最多 6 枚；返回 catalog_updated_at 供图片缓存破除。';

-- ============================================================
-- END migrate-v47-public-display-badges.sql + migrate-v48-badge-cache-busting.sql
-- ============================================================


-- ============================================================
-- BEGIN migrate-v50-scheduled-weekly-view-passes.sql
-- 每周日 20:00（Asia/Shanghai / UTC+8）自动核算并发放浏览券。
-- Supabase 数据库默认使用 UTC，因此 Cron 为周日 12:00 UTC。
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;

CREATE OR REPLACE FUNCTION private.issue_weekly_view_passes(
  p_period_start TIMESTAMPTZ,
  p_issued_at TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_period_start TIMESTAMPTZ := p_period_start;
  v_period_end TIMESTAMPTZ := p_period_start + interval '7 days';
  v_source_key TEXT;
  v_inserted_passes INTEGER;
  v_inserted_users INTEGER;
BEGIN
  IF v_period_start <> (date_trunc('week', timezone('Asia/Shanghai', v_period_start)) AT TIME ZONE 'Asia/Shanghai') THEN
    RAISE EXCEPTION 'p_period_start must be the beginning of an Asia/Shanghai week';
  END IF;

  v_source_key := 'weekly_' || to_char(v_period_start AT TIME ZONE 'Asia/Shanghai', 'IYYY_IW');

  WITH weekly_activity AS (
    SELECT cl.user_id, SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_period_start
      AND cl.created_at < v_period_end
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      ml.weekly_view_passes,
      COALESCE(wa.points, 0) AS weekly_activity_points,
      ROW_NUMBER() OVER (
        ORDER BY COALESCE(wa.points, 0) DESC, ms.contribution_total DESC, ms.user_id
      ) AS rank_position
    FROM public.member_stats ms
    JOIN public.member_levels ml ON ml.level = ms.level
    LEFT JOIN weekly_activity wa ON wa.user_id = ms.user_id
    WHERE ml.weekly_view_passes > 0
  ),
  expanded AS (
    SELECT
      r.user_id,
      GENERATE_SERIES(
        1,
        r.weekly_view_passes * CASE
          WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2
          ELSE 1
        END
      ) AS pass_no
    FROM ranked r
  ),
  inserted AS (
    INSERT INTO public.view_passes (
      user_id, status, issued_reason, source_key, issued_at, expires_at
    )
    SELECT
      e.user_id,
      'available',
      'weekly',
      v_source_key || '_' || e.user_id || '_' || e.pass_no,
      p_issued_at,
      p_issued_at + interval '7 days'
    FROM expanded e
    ON CONFLICT (user_id, source_key) WHERE (source_key IS NOT NULL)
    DO NOTHING
    RETURNING user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT user_id)::INTEGER
    INTO v_inserted_passes, v_inserted_users
  FROM inserted;

  issued_users := COALESCE(v_inserted_users, 0);
  issued_passes := COALESCE(v_inserted_passes, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION private.issue_weekly_view_passes(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_scheduled_weekly_view_passes()
RETURNS VOID AS $$
DECLARE
  v_period_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
BEGIN
  PERFORM private.issue_weekly_view_passes(v_period_start, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION private.run_scheduled_weekly_view_passes() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_period_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  RETURN QUERY
  SELECT * FROM private.issue_weekly_view_passes(v_period_start, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job
    WHERE jobname = 'weekly-view-passes-sunday-2000-shanghai'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'weekly-view-passes-sunday-2000-shanghai',
    '0 12 * * 0',
    'SELECT private.run_scheduled_weekly_view_passes();'
  );
END;
$schedule$;

COMMENT ON FUNCTION private.issue_weekly_view_passes(TIMESTAMPTZ, TIMESTAMPTZ) IS
  '按指定上海自然周核算阅读贡献并发放浏览券；source_key 保证同一周重复执行不重复发券。';

COMMENT ON FUNCTION private.run_scheduled_weekly_view_passes() IS
  '由 pg_cron 于每周日 12:00 UTC（北京时间 20:00）调用。';

-- ============================================================
-- END migrate-v50-scheduled-weekly-view-passes.sql
-- ============================================================

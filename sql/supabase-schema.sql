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
CREATE POLICY "profiles_read_all" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update_self" ON profiles FOR UPDATE
  USING (auth.uid() = id OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
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
  activities        JSONB DEFAULT '[]',
  chatsubstance     JSONB DEFAULT '[]',
  resources         JSONB DEFAULT '{"extended_reading":[],"text_materials":[],"film_resources":[]}',
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
-- 5. daily_checkins — 每日阅读签到（依赖 profiles）
-- ============================================================
CREATE TABLE daily_checkins (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  checkin_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  book_title      TEXT,
  excerpt         TEXT,
  reflection      TEXT,
  mood_color      TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, checkin_date)
);

CREATE INDEX idx_checkins_user ON daily_checkins(user_id);
CREATE INDEX idx_checkins_date ON daily_checkins(checkin_date);

ALTER TABLE daily_checkins ENABLE ROW LEVEL SECURITY;
CREATE POLICY "checkins_read_self" ON daily_checkins FOR SELECT
  USING (auth.uid() = user_id OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
CREATE POLICY "checkins_insert_self" ON daily_checkins FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "checkins_update_self" ON daily_checkins FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- 6. Storage — 封面图 bucket
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

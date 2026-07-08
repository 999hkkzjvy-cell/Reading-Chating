-- 以读攻独 · 种子数据：《源氏物语》共读
-- 来源：石墨文档《2025小群共读3：《源氏物语》共读文档》
-- 链接：https://shimo.im/docs/m8AZMGp8Wnun8Vkb/
--
-- 用法：在 Supabase SQL Editor 中执行本文件，向 books 表新增一条《源氏物语》共读记录。

INSERT INTO books (
  title, author, author_country, author_gender,
  publisher, genre, description, author_bio, historical_context,
  status, edition_guide, edition_notes, reading_schedule,
  host, host_intro, host_notes,
  activities, resources, start_date, end_date, word_count
) VALUES (
  '源氏物语',
  '紫式部',
  '日本',
  '女',
  '人民文学出版社 / 译林出版社',
  '文学',

  $desc$《源氏物语》是日本平安时代女作家紫式部创作的长篇小说，成书于约1001年至1008年之间。全书共五十四帖，以光源氏的一生为主线，穿插其与众多女性的情感纠葛，描绘了平安时代宫廷贵族的生活风貌、审美情趣与命运沉浮。作品被誉为世界上第一部长篇小说，也是日本古典文学的高峰。$desc$,

  $bio$紫式部（约973年—约1014年），日本平安时代著名女性文学家，本名不详，因其兄曾任越前守，故又称“藤原香子”。她曾任一条天皇中宫藤原彰子的侍女，并因博学被召入宫中讲授汉籍。其代表作《源氏物语》是日本古典文学乃至世界文学史上的瑰宝，另有《紫式部日记》等作品传世。$bio$,

  $ctx$平安时代（794年—1185年）是日本古典文学的黄金时期，宫廷文化繁荣，和歌、物语文学兴盛。在这一背景下，《源氏物语》以贵族社会的恋爱、政治与日常生活为题材，展现了当时独特的审美意识、礼仪制度与情感表达方式。$ctx$,

  'completed',

  $guide$[
    {
      "name": "丰子恺译本",
      "translator": "丰子恺",
      "publisher": "人民文学出版社",
      "pros": "篇幅短，官职后和台词前常加人名，人物关系相对明晰，文笔流畅简练，有中式古典韵味，尤其适合初读。",
      "cons": "略有模式化之嫌，细节也稍有丢失。",
      "buy_link": "",
      "douban_link": ""
    },
    {
      "name": "林文月译本",
      "translator": "林文月",
      "publisher": "译林出版社",
      "pros": "日语母语水平，翻译处理更为还原，较长篇幅注意了更多细节，对作者的敏感暧昧把握更佳，更有日本文学的风致。",
      "cons": "可能稍嫌唠叨；通勤读书强烈建议四卷平装版，但篇尾注较多。",
      "buy_link": "",
      "douban_link": ""
    }
  ]$guide$::jsonb,

  $edition_notes$本次共读由自由放飞的 Claudia（C姐）领读，不设置译本限制，读日文版、英文版均可。

根据读过的大佬们的综合感受：丰子恺译本篇幅短、人物关系明晰、文笔流畅简练、有中式古典韵味，适合初读；林文月译本更为还原、细节丰富、更能把握日本文学风致，但稍嫌唠叨。

特别提醒：微信读书的《源氏物语》排版非常影响阅读体验，建议有条件的还是上纸质版。如果日常通勤读书较多，强烈建议考虑译林的林译本四卷平装版。$edition_notes$,

  $schedule${
    "summary": "4月15日-6月14日为共读期，部分收尾活动可能延续至6月底。\\n\\n因为各种版本页码差别较大，本次阅读不做页数进度表，基本按照一天一帖的节奏推进，每十帖歇一天，超长篇幅的若菜篇也多给一天。\\n\\n《源氏物语》丰译本约95万字，林译本过百万字，因此把共读时长放宽到了2个月，大家日常尽量跟好进度，争取都完本。",
    "pdf_url": "https://uploader.shimo.im/f/nLwrgLBN4tZH0P1q.xlsx"
  }$schedule$::jsonb,

  'Claudia（C姐）',

  $host_intro$本次共读由自由放飞的 Claudia（C姐）领读。

C姐以自由奔放的阅读风格和丰富的日本文学积累，带领群友深入《源氏物语》的世界。从文本细节到衍生作品，从平安风物到人物情感，相信这次共读会碰撞出许多精彩火花。$host_intro$,

  $host_notes$刚准备做线下活动文本细读的时候，完全没有想到萧瑟会放弃马尔克斯、契诃夫的名篇流量，把第一篇文本细读的荣誉交给宫本辉《浮月》。（要知道他对日本文学的拒绝程度远超过我！）

但读完《浮月》以后确实折服，那些细碎但绝不冗杂的细节也像月光泠泠，在你认真看进去时，寒光一闪，晃了你的眼睛和心。至于后来读《泥河》《锦绣》时流过的泪、读到忘记午休的一本又一本宫本辉、发现未读所剩无几而吝惜地放慢阅读脚步，这都是共读老朋友熟悉甚至有相同经历的故事了。

那么好的日本文学有的是，为什么偏偏选中《源氏物语》这样的大部头呢？我当然可以说因为经典，甚至去DS上生成一篇对《源氏物语》的夸夸来作为陈述理由。

但其实原因远没有那么堂皇：只是因为在第一次升级版文学高速之后，看着C姐和四工老师聊源氏物语聊得火热，虽然中译本英译本的人名甚至都对得艰难，但聊得兴起抚掌慨叹时，他们眼睛里的光真的太过诱惑。

可怕的是这样的场景在清明小聚时又上演了一次……他们以“为共读做准备”为名聊得理所应当，全然不顾我们这些没读过的听众的死活，连拒绝读文学的冰冷社科机器阿隆都表示了垂直入坑的共读意愿，我当时到底有多么心痒痒自然不必说，和呵呵默契对视的眼神里都只有四个字：“想马上看！”

盼望着，盼望着！《源氏物语》共读终于迎来了开营时刻，那么就引用一下柳公子的梗吧：源神！启动！

希望大家读到什么多聊，问傻问题也别怕，混脸熟了你以后会更容易赢得随机福利掉落和未来的小共读席位。感谢每一个愿意主动提出问题、帮助回答问题、讲出自己见解的小伙伴！共读需要你们的参与才有意义～$host_notes$,

  $activities$[
    {
      "type": "导读预热",
      "title": "C姐导读《用想象力置景：在故事开始之前》",
      "time": "2025-04-18",
      "status": "已完结",
      "meeting_link": "",
      "replay_link": "",
      "guests": "Claudia（C姐）",
      "description": "领读人开营导读，用想象力为《源氏物语》置景。"
    },
    {
      "type": "文艺放映",
      "title": "文艺放映室《源氏物语 千年之恋》（天海佑希版）",
      "time": "2025-06-04",
      "status": "已完结",
      "meeting_link": "",
      "replay_link": "",
      "guests": "",
      "description": "源氏物语衍生作品放映，一起边看边讨论。"
    },
    {
      "type": "嘉宾分享",
      "title": "线下文学高速共读会：尤瑟纳尔《源氏公子最后的爱情》",
      "time": "2025-06-07",
      "status": "已完结",
      "meeting_link": "",
      "replay_link": "",
      "guests": "",
      "description": "线下文学高速共读交流活动。"
    },
    {
      "type": "圆桌讨论",
      "title": "收官圆桌、分享及抽奖福利",
      "time": "2025年6月中下旬",
      "status": "已完结",
      "meeting_link": "",
      "replay_link": "",
      "guests": "",
      "description": "共读完结后的圆桌讨论会，票选表现突出的群友并送出小礼物，群里也会开展抽奖活动。"
    }
  ]$activities$::jsonb,

  $resources${
    "extended_reading": [
      {"title": "讲谈社·日本的历史", "url": "", "description": ""},
      {"title": "平安时代（岩波日本史 第三卷）", "url": "", "description": ""},
      {"title": "《源氏物语》的美学世界", "url": "", "description": ""},
      {"title": "平安朝的生活与文学", "url": "", "description": ""},
      {"title": "源氏物语：平安时代风俗文化图鉴（台版为《源氏物语解剖图鉴》）", "url": "", "description": ""},
      {"title": "歌舞伎100剧目：戏剧与文化的艺术盛宴", "url": "", "description": ""},
      {"title": "江户衣装：谱写江户时代的民俗风情", "url": "", "description": ""},
      {"title": "平安朝宫廷才女的散文体文学书写", "url": "", "description": ""},
      {"title": "枕草子", "url": "", "description": ""},
      {"title": "日本古典女性日记（紫式部日记、蜻蛉日记、和泉式部日记、更级日记）", "url": "", "description": ""},
      {"title": "浮世绘女儿", "url": "", "description": ""},
      {"title": "浮世绘里的一百零一月", "url": "", "description": ""}
    ],
    "text_materials": [
      {"title": "《源氏物语》共读 领读人开营说两句 By Claudia", "url": "https://uploader.shimo.im/f/oc1brxHrNzWvGCG8.pdf", "description": "领读人开营寄语 PDF"},
      {"title": "用想象力置景：在故事开始之前", "url": "https://uploader.shimo.im/f/4F0QCpLSrXn0ruot.pptx", "description": "C姐导读会 PPT"}
    ],
    "film_resources": [
      {"title": "《源氏物语》幻想交响绘卷", "url": "", "description": ""},
      {"title": "日本宫廷雅乐复原", "url": "", "description": ""},
      {"title": "讲座：林文月谈《源氏物语》", "url": "", "description": ""},
      {"title": "讲座：朱嘉雯谈《源氏物语》（35集共计65讲）", "url": "", "description": ""},
      {"title": "纪录片《100分的名著：源氏物语》", "url": "", "description": ""},
      {"title": "纪录片《午后书房》", "url": "", "description": ""},
      {"title": "纪录片《源氏物语诞生的秘密》", "url": "", "description": ""},
      {"title": "纪录片《尺八 · 一声一世》", "url": "", "description": ""},
      {"title": "纪录片《日本藏品奇谈：两幅源氏物语绘卷》", "url": "", "description": ""},
      {"title": "纪录片《美之壶》系列", "url": "", "description": ""},
      {"title": "纪录片《日本匠人》系列", "url": "", "description": ""},
      {"title": "电影《源氏物语 千年之恋》（天海佑希版）", "url": "", "description": ""},
      {"title": "电影《源氏物语》（东山纪之版）", "url": "", "description": "完整版没有字幕，中字版分P需自己点着看"},
      {"title": "动画电影《源氏物语》（1987年版）", "url": "", "description": ""},
      {"title": "动画番剧《源氏物语千年纪》（2009年版）", "url": "", "description": ""},
      {"title": "歌舞伎《源氏物语》（市川海老藏版）", "url": "", "description": ""},
      {"title": "歌舞伎《源氏物语：浮舟篇》（坂东玉三郎版）", "url": "", "description": ""},
      {"title": "歌舞伎《源氏物语：末摘花篇》（坂东玉三郎版）", "url": "", "description": ""},
      {"title": "冰舞《源氏物语》", "url": "", "description": ""},
      {"title": "宝冢音乐剧《源氏物语》（花组2000年版）", "url": "", "description": ""}
    ],
    "other": [
      {"title": "其他歌舞伎推荐材料", "url": "", "description": "非常推荐前两个歌舞伎解说视频，有非常多的补充知识！"}
    ]
  }$resources$::jsonb,

  '2025-04-15',
  '2025-06-14',
  1000000
);

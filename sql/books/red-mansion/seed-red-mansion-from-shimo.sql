-- ============================================================
-- 以读攻独 · 种子数据：《红楼梦》共读资料
-- 来源：石墨文档《2025小群共读4：《红楼梦》共读文档》
-- 链接：https://shimo.im/docs/heJkShJjdk5oVJ7H/
--
-- 用法：
-- 1. 确认线上 books 表中已存在 title 为「红楼梦」或「《红楼梦》」的记录。
-- 2. 在 Supabase SQL Editor 中执行本文件。
-- 3. 本脚本只更新对应书籍，不新增书籍，不删除任何现有数据。
-- ============================================================

DO $$
DECLARE
  v_book_id BIGINT;
BEGIN
  SELECT id
  INTO v_book_id
  FROM public.books
  WHERE trim(both '《》' FROM title) = '红楼梦'
  ORDER BY id DESC
  LIMIT 1;

  IF v_book_id IS NULL THEN
    RAISE EXCEPTION '未找到 title 为「红楼梦」或「《红楼梦》」的书籍记录，请先在管理后台创建该书。';
  END IF;

  UPDATE public.books
  SET
    title = '红楼梦',
    author = '曹雪芹',
    author_country = '中国',
    author_gender = '男',
    genre = '文学',
    status = 'completed',
    start_date = DATE '2025-09-01',
    end_date = DATE '2025-11-30',
    word_count = 1000000,
    edition_notes = $edition$
本次共读以前80回为主，后40回不做要求，但也可一并讨论。

不设置版本限制，手头有啥读啥（连环画、缩略本除外），多种不同版本也可以在共读中互相比较、补充信息。

如果是第一次读，建议选择人民文学出版社大红本平装，价格友好，版本权威可靠，全网容易买到，微信读书也有电子版。

如果是第二次、第三次读，并且已经对程高本、脂评等有一点了解，可以选择自己感兴趣的新版本。

另附一份《红楼梦》版本介绍，供大家了解选择：
https://shimo.im/docs/8Nk6eKyK1RuR5pqL/
$edition$,
    edition_guide = $edition_guide$[
      {
        "name": "人民文学出版社大红本平装",
        "translator": "",
        "publisher": "人民文学出版社",
        "pros": "适合第一次阅读，价格友好，版本权威可靠，全网容易买到，微信读书也有电子版。",
        "cons": "已经读过多次或希望深入比较版本的读者，可以再按个人兴趣选择程高本、脂评本等其他版本。",
        "buy_link": "",
        "douban_link": ""
      },
      {
        "name": "自选版本",
        "translator": "",
        "publisher": "",
        "pros": "适合已经读过《红楼梦》、对版本系统有基本判断的读者，可围绕程高本、脂评等方向延伸阅读。",
        "cons": "初读者可能会被版本差异和批注系统分散注意力。",
        "buy_link": "",
        "douban_link": "https://shimo.im/docs/8Nk6eKyK1RuR5pqL/"
      }
    ]$edition_guide$::jsonb,
    reading_schedule = $schedule${
      "summary": "9月1日-11月30日为共读期，也为初次读《红楼梦》的朋友留出了一个月读剩下的40回，部分收尾活动延续至12月底。\\n\\n《红楼梦》全书过百万字，如果算上各种批注只会更多。考虑到下半年大家逐渐忙起来，本次进度计划做得相对轻松，大家日常尽量跟好进度，群里讨论也会比较集中。\\n\\n因为各种版本页码差别较大，本次阅读不做页数进度表，基本按照一天一回的节奏推进，每十回歇一天，等等赶进度的同志们。\\n\\n阅读计划图：\\n- https://uploader.shimo.im/f/Ru1IX2tjwppg6vdG.png\\n- https://uploader.shimo.im/f/uYX7P8nejqWrzYCI.png\\n- https://uploader.shimo.im/f/KixOb92pVMFF6Aes.png",
      "pdf_url": "https://uploader.shimo.im/f/cUL69a4mDvCw1BvI.xlsx"
    }$schedule$::jsonb,
    host = 'song果皮皮',
    host_intro = $host_intro$
本次共读由 song果皮皮，我们的皮神领读。

从《城市与狗》到《源氏物语》，皮皮关于人物和隐藏剧情的脑洞分析总是让我们惊艳；民俗学背景也贴合这个包罗万象的大观园世界。更重要的是，有热情的读者，总会更亲切、更懂我们普通读者，相信这次共读一定又能碰撞出很多新火花。
$host_intro$,
    host_notes_title = '灵沁的一点碎碎念',
    host_notes_subtitle = '关于《红楼梦》与这次共读',
    host_notes_author = '灵沁',
    host_notes = $host_notes$
皮皮已经写了非常完备的开营寄语了，我就不再补充这些了，讲讲我读《红楼梦》的小故事吧。

我倒算是早熟，三四岁的时候妈妈就给我讲故事，只是娘亲太文艺了，小时候给我讲的故事是什么《洋文观止》之类的。反正也很难说小时候我到底听没听懂，更不知道到底是因为太好听我想去自己看，还是因为太难听我想自己挑书，总之很小就认了不少字，已经可以自己看各种书了。

小学二年级我被寄养在大姨家里，陌生的环境没什么小伙伴，我就开始窝在家里啃书来看。看《射雕英雄传》《倚天屠龙记》，也无知者无畏地看《金瓶梅》，家里的一套岳麓书社四大名著自然也逃不脱我的魔爪。其他三本都不爱看，就《红楼梦》对我的胃口。

小学时读《红楼梦》的时光模模糊糊，当时爱看什么，现在一点儿也想不起来。只知道我从小拍艺术照不喜欢当小姐，偏喜欢做丫鬟，“丫鬟可以出去玩！”大概是 E 人的种子初初开花的声音，也是喜欢晴雯、鸳鸯、小红这些活泼泼的丫鬟们的开始。那时候《红楼梦》的背景音，总是87版里那些姐姐妹妹们银铃般的笑声。

初中开始慢慢懂点儿事，眼睛里有了林黛玉，有了史湘云，有了贾探春，开始红着脸读“贾宝玉初试云雨情”“贾天祥正照风月鉴”，也开始跟着87版《红楼梦》的配乐背下那些判词诗句。

从这以后《红楼梦》就没怎么放下过，每年总有几天会随手翻开，读上几页。记下湘云卧芍的花团锦簇，也记下宝黛钗和妙玉吃茶的乐趣，记得被黛玉团成个团儿掷与宝玉解困的《杏帘在望》，也记得凹晶馆里冷冷清清的“寒塘渡鹤影，冷月葬花魂”。慢慢熟悉了那些因为长得不好看被我长期忽视的婆子小厮乳母管家，也开始探寻匆匆出场又匆匆消失的人物的踪迹，更开始猜测拼凑后40回的可能面目。

再到后来，开始看各种各样的剧，当然有过很多很多次失望。但看到民族舞剧《红楼梦》的时候，我知道它远远不能表达《红楼梦》之万一，依然冲到了首演现场，躲在口罩后面哭得发抖。那些纷繁的细节在短短两个多小时里向我涌来，在一次次挽起的幕帘中，我仿若分花拂柳，一一找寻辨认书中的影子，为剧中人、书中人，甚至那么多个阅读时间切片上的我自己落泪。

现在开始的《红楼梦》共读，已经不知道是我第几次翻开这本书，但我想，我还会持续地读下去。

希望大家读到什么多聊，问傻问题也别怕，混脸熟了你以后会更容易赢得随机福利掉落和未来的小共读席位。感谢每一个愿意主动提出问题、帮助回答问题、讲出自己见解的小伙伴！共读需要你们的参与才有意义。
$host_notes$,
    activities = $activities$[
      {
        "type": "导读预热",
        "title": "皮皮导读《同做红楼梦里人》",
        "time": "2025-08-31",
        "status": "已完结",
        "meeting_link": "",
        "replay_link": "https://meeting.tencent.com/crm/KzBx5Bzr9d",
        "guests": "song果皮皮",
        "description": "皮神为了这次共读准备的领读人导读会，带大家一起“入梦”。"
      },
      {
        "type": "文艺放映",
        "title": "文艺放映室：越剧版《红楼梦》",
        "time": "待定",
        "status": "计划中",
        "meeting_link": "",
        "replay_link": "",
        "guests": "",
        "description": "《红楼梦》作为第一大 IP，衍生作品众多，放映会也照常开张。计划线上放映越剧《红楼梦》，大家一起边看边讨论。"
      },
      {
        "type": "嘉宾分享",
        "title": "柳公子主题分享会：红绡化烬 白露为霜",
        "time": "共读期内",
        "status": "已完结",
        "meeting_link": "",
        "replay_link": "https://meeting.tencent.com/crm/lJPZygEE35",
        "guests": "柳公子",
        "description": "《红楼梦》共读期间的嘉宾主题分享。"
      },
      {
        "type": "嘉宾分享",
        "title": "阿隆主题分享会：清代政治与社会文化漫谈",
        "time": "共读期内",
        "status": "已完结",
        "meeting_link": "",
        "replay_link": "https://meeting.tencent.com/crm/2kjz5y8ofc",
        "guests": "阿隆",
        "description": "围绕清代政治与社会文化展开的主题分享。"
      },
      {
        "type": "线下活动",
        "title": "现实里的红楼三城",
        "time": "共读期及收尾期",
        "status": "计划中",
        "meeting_link": "",
        "replay_link": "",
        "guests": "",
        "description": "曹雪芹与南京、苏州、北京等城市关联深厚，有机会可组织线下活动，一起走走现实里的红楼三城。"
      },
      {
        "type": "圆桌讨论",
        "title": "收官圆桌、分享及抽奖福利",
        "time": "共读收尾期",
        "status": "计划中",
        "meeting_link": "",
        "replay_link": "",
        "guests": "全体群友",
        "description": "共读完照例组织收官圆桌讨论会，欢迎大家聊聊读完的感受。圆桌会结束后票选分享表现突出的群友，送出小礼物，并开展抽奖活动。"
      }
    ]$activities$::jsonb,
    chatsubstance = $chats$[
      {
        "topic": "领读文稿 & 群聊干货存档",
        "speaker": "共读群共建",
        "content": "领读文档为避免剧透，延后一天放出（如9月1日按进度读第一回，领读文档就在9月2日放出相关内容）。日常也希望大家积极参与群聊，交流碰撞火花，有空的也可以帮忙整理群聊干货，共建我们的《红楼梦》共读文档。\\n\\n存档链接：https://shimo.im/docs/WlArdapbPaH45xq2/"
      },
      {
        "topic": "关于剧透",
        "speaker": "灵沁",
        "content": "虽然宝黛的爱情故事每个中国人都熟悉，但《红楼梦》的故事远不止宝黛爱情。考虑到群里有第一次读《红楼梦》的小伙伴，希望老朋友们尽量按照共读计划进度讨论，克制剧透欲，更大程度保留初读乐趣，也让讨论主题更聚焦。"
      }
    ]$chats$::jsonb,
    resources = $resources${
      "extended_reading": [
        {
          "title": "《命若朝露：红楼梦里的法律、社会与女性》",
          "url": "https://book.douban.com/subject/37134066/",
          "description": "从法律社会史角度解读《红楼梦》，聚焦清代女性的法律困境，以及性别、家庭、法律、政治之间的互动。"
        },
        {
          "title": "《红楼小人物》",
          "url": "https://book.douban.com/subject/36955216/",
          "description": "以“小”人物视角洞察红楼大世界。"
        },
        {
          "title": "《红楼十二层：周汝昌妙解红楼》",
          "url": "https://book.douban.com/subject/1024842/",
          "description": "周汝昌红学解读著作。"
        },
        {
          "title": "《红楼夺目红》",
          "url": "https://book.douban.com/subject/1054784/",
          "description": "周汝昌先生红学随笔集，以短文讲“大旨”。"
        },
        {
          "title": "《荣国府的经济账》",
          "url": "https://weread.qq.com/book-detail?type=1&senderVid=80455645&v=cde3230071c79027cdef4dd",
          "description": "从经济和家族运行角度进入《红楼梦》的辅助读物。"
        },
        {
          "title": "《红楼梦魇》",
          "url": "https://book.douban.com/subject/2008406/",
          "description": "张爱玲研究《红楼梦》的重要著作，也是一部带有作家眼光的文本考据。"
        }
      ],
      "text_materials": [
        {
          "title": "领读人开营寄语",
          "url": "https://uploader.shimo.im/f/HL1CkdHdwalWLGeE.pdf",
          "description": "领读人 song果皮皮 为本期共读撰写的开营寄语。"
        },
        {
          "title": "《红楼梦》版本介绍",
          "url": "https://shimo.im/docs/8Nk6eKyK1RuR5pqL/",
          "description": "关于《红楼梦》版本选择的补充资料。"
        },
        {
          "title": "《红楼梦》共读进度计划表",
          "url": "https://uploader.shimo.im/f/cUL69a4mDvCw1BvI.xlsx",
          "description": "本期共读阅读进度表。"
        },
        {
          "title": "阅读计划图（一）",
          "url": "https://uploader.shimo.im/f/Ru1IX2tjwppg6vdG.png",
          "description": "共读阅读计划图片。"
        },
        {
          "title": "阅读计划图（二）",
          "url": "https://uploader.shimo.im/f/uYX7P8nejqWrzYCI.png",
          "description": "共读阅读计划图片。"
        },
        {
          "title": "阅读计划图（三）",
          "url": "https://uploader.shimo.im/f/KixOb92pVMFF6Aes.png",
          "description": "共读阅读计划图片。"
        },
        {
          "title": "各类红楼人物表",
          "url": "https://weibo.com/5155715530/OwoHb3fjU",
          "description": "人物关系与人物表资料入口。"
        },
        {
          "title": "红楼人物表图片（一）",
          "url": "https://uploader.shimo.im/f/e9yFrKPijt7sE7Jl.jpg",
          "description": "红楼人物表图片资料。"
        },
        {
          "title": "红楼人物表图片（二）",
          "url": "https://uploader.shimo.im/f/Pdo0WV7N6myCiT2H.png",
          "description": "红楼人物表图片资料。"
        },
        {
          "title": "荣宁二府及大观园地图（一）",
          "url": "https://uploader.shimo.im/f/ZpJduTIgKQgqrVmI.jfif",
          "description": "荣宁二府及大观园地图资料。"
        },
        {
          "title": "荣宁二府及大观园地图（二）",
          "url": "https://uploader.shimo.im/f/OUw6qU9nErweS76t.jpg",
          "description": "荣宁二府及大观园地图资料。"
        },
        {
          "title": "现实里的红楼之影：南京原址资料",
          "url": "https://jres2023.xhby.net/js/wh/201907/t20190701_6245711.shtml",
          "description": "南京与《红楼梦》相关地点资料。"
        },
        {
          "title": "现实里的红楼之影：金陵家园资料",
          "url": "https://www.jntimes.cn/jnwm/202405/t20240504_8262076.shtml",
          "description": "从江宁织造府到随园等南京相关资料。"
        },
        {
          "title": "现实里的红楼之影：南京走读资料",
          "url": "https://baijiahao.baidu.com/s?id=1699244009142487116&wfr=spider&for=pc",
          "description": "南京街头走读《红楼梦》相关资料。"
        },
        {
          "title": "现实里的红楼之影：苏州园林",
          "url": "http://www.ourjiangsu.com/a/20191123/157449828617.shtml",
          "description": "苏州园林与《红楼梦》相关资料。"
        },
        {
          "title": "现实里的红楼之影：北京",
          "url": "https://mp.weixin.qq.com/s?__biz=MjM5ODI0NzM4Mw==&mid=2648238997&idx=1&sn=a18c625da4da4735a3cdc60c7be52088&chksm=bf9ba4c52421d8f080705e7c9391d0567ce6906e714017246f2b31884e1c483edde0671fc48d&mpshare=1&scene=1&srcid=0827L0jZZIMeECyDJAUn2x15&sharer_shareinfo=1279f293167156fbb440f0f6268480ac&sharer_shareinfo_first=1279f293167156fbb440f0f6268480ac#rd",
          "description": "北京与《红楼梦》相关资料。"
        }
      ],
      "film_resources": [
        {
          "title": "87版电视剧《红楼梦》",
          "url": "https://www.bilibili.com/bangumi/play/ss33624?spm_id_from=333.337.0.0",
          "description": "87版电视剧《红楼梦》。"
        },
        {
          "title": "木鱼解说87版电视剧《红楼梦》",
          "url": "https://www.bilibili.com/video/BV1CC4y1a7ee/?spm_id_from=333.337.search-card.all.click",
          "description": "木鱼微剧场《红楼梦》全系列解说。"
        },
        {
          "title": "欧丽娟讲《红楼梦》",
          "url": "https://www.bilibili.com/video/BV1hp4y1t7zq/?spm_id_from=333.337.search-card.all.click",
          "description": "欧丽娟老师《红楼梦》讲说系列。"
        },
        {
          "title": "王德峰讲《红楼梦》",
          "url": "https://www.bilibili.com/video/BV1P5411Z7aJ/?spm_id_from=333.788.recommend_more_video.0",
          "description": "王德峰讲《红楼梦》系列。"
        },
        {
          "title": "87版《红楼梦》取景地介绍",
          "url": "https://www.bilibili.com/video/BV16D28YVEeD/?buvid=Z44355481EC2836C48D8A43F313B0D8E223D&from_spmid=search.search-result.0.0&is_story_h5=false&mid=k4Bnl1HqN0k3e69DCQtPHQ%3D%3D&plat_id=116&share_from=ugc&share_medium=iphone&share_plat=ios&share_session_id=7BA8C9C3-4F48-4824-8090-731EC7239DDB&share_source=WEIXIN&share_tag=s_i&spmid=united.player-video-detail.0.0&timestamp=1757235424&unique_k=FQLqftM&up_id=524843245",
          "description": "87版《红楼梦》取景地介绍。"
        },
        {
          "title": "87版《红楼梦》苏州园林取景资料",
          "url": "https://www.bilibili.com/video/BV1do4y1t7Ek/?share_source=copy_web",
          "description": "87版《红楼梦》在苏州园林取景的相关介绍。"
        }
      ],
      "other": [
        {
          "title": "原始共读文档",
          "url": "https://shimo.im/docs/heJkShJjdk5oVJ7H/",
          "description": "石墨文档《2025小群共读4：《红楼梦》共读文档》。"
        }
      ]
    }$resources$::jsonb,
    updated_at = now()
  WHERE id = v_book_id;

  RAISE NOTICE '已更新《红楼梦》共读资料，book_id=%', v_book_id;
END $$;

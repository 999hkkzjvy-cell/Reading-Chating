export const GENRES = ['全部', '文学', '历史', '哲学', '科幻', '社科', '心理', '传记', '商业', '科普', '其他'];

export const STATUS_MAP = {
  upcoming: '即将开读',
  active: '正在共读',
  completed: '已读完',
  ongoing: '进行中',
  ended: '已结束',
  cancelled: '已取消'
};

export const STATUS_CLASS = {
  upcoming: 'tag-upcoming',
  active: 'tag-active',
  completed: 'tag-completed',
  ongoing: 'tag-active',
  ended: 'tag-completed',
  cancelled: 'tag-completed'
};

export const MOODS = [
  { label: '无', value: '', cls: 'none' },
  { label: '朱砂', value: '#c4665a' },
  { label: '暖橙', value: '#d4a843' },
  { label: '秋叶', value: '#c17d4b' },
  { label: '青绿', value: '#6b9070' },
  { label: '黛蓝', value: '#5a7a8a' },
  { label: '烟紫', value: '#8b7b8b' },
  { label: '月白', value: '#c5d0d8' }
];

export const ACT_TYPES = ['导读预热', '精读分析', '文艺放映', '嘉宾分享', '圆桌讨论', '线下活动', '签售征订', '其他'];
export const ACT_STATUSES = ['计划中', '进行中', '已完结'];

import { h, safeColor } from './utils.js';
import { CALENDAR_DAY_NAMES } from './readingPostUtils.js';

function buildDailyActivity(posts) {
  const map = new Map();
  posts.forEach(post => {
    const dateKey = dayjs(post.created_at).format('YYYY-MM-DD');
    const current = map.get(dateKey) || { count: 0, latestAt: 0, moodColor: '' };
    const createdAt = new Date(post.created_at).getTime();
    current.count += 1;
    if (!current.latestAt || createdAt >= current.latestAt) {
      current.latestAt = createdAt;
      current.moodColor = safeColor(post.mood_color, '');
    }
    map.set(dateKey, current);
  });
  return map;
}

export function renderReadingActivityCalendar(posts, scope) {
  const now = dayjs();
  const todayStr = now.format('YYYY-MM-DD');
  const firstDay = now.startOf('month');
  const daysInMonth = firstDay.daysInMonth();
  const startDayOfWeek = firstDay.day();
  const prevMonthDays = firstDay.subtract(1, 'day').daysInMonth();
  const activity = buildDailyActivity(posts);
  const monthPrefix = now.format('YYYY-MM');
  const monthTotal = Array.from(activity.entries())
    .filter(([dateKey]) => dateKey.startsWith(monthPrefix))
    .reduce((sum, [, item]) => sum + item.count, 0);
  const todayCount = activity.get(todayStr)?.count || 0;

  let cells = CALENDAR_DAY_NAMES.map(d => `<div class="day-name">${d}</div>`).join('');
  for (let i = startDayOfWeek - 1; i >= 0; i--) {
    cells += `<div class="day other-month"><span>${prevMonthDays - i}</span></div>`;
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const dateKey = firstDay.date(d).format('YYYY-MM-DD');
    const dayActivity = activity.get(dateKey);
    let cls = 'day';
    if (dayActivity) {
      cls += ' checked';
    } else if (dateKey === todayStr) {
      cls += ' today';
    } else if (dayjs(dateKey).isAfter(now, 'day')) {
      cls += ' future';
    }
    const moodColor = safeColor(dayActivity?.moodColor, '#c17d4b');
    const style = dayActivity ? `style="--mood-dot:${moodColor}"` : '';
    const title = dayActivity ? `title="${dateKey} · ${dayActivity.count} 条动态"` : '';
    cells += `<div class="${cls}" ${style} ${title}><span>${d}</span></div>`;
  }

  const totalCells = startDayOfWeek + daysInMonth;
  const remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  for (let d = 1; d <= remaining; d++) {
    cells += `<div class="day other-month"><span>${d}</span></div>`;
  }

  return `
    <section class="card reading-circle-calendar-card">
      <div class="card-body">
        <div class="member-panel-head">
          <div>
            <h3>本月书友圈</h3>
            <span>${scope === 'mine' ? '我的编写情况' : '广场编写情况'}</span>
          </div>
        </div>
        <div class="reading-circle-calendar-stats">
          <div>
            <span>今日</span>
            <strong>${h(todayCount)} 条</strong>
          </div>
          <div>
            <span>${now.format('M月')}</span>
            <strong>${h(monthTotal)} 条</strong>
          </div>
        </div>
        <div class="calendar reading-circle-calendar">
          <div class="calendar-header">
            <h4>${now.format('YYYY年M月')}</h4>
          </div>
          <div class="calendar-grid">${cells}</div>
        </div>
      </div>
    </section>
  `;
}

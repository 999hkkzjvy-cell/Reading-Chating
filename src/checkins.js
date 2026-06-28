import { MOODS } from './constants.js';
import { getMonthCheckinsFull } from './data.js';
import { showModal } from './ui.js';
import { esc, formatDate, h, safeColor } from './utils.js';

let calYear = null;
let calMonth = null;
let calCheckinsData = [];

function ensureCalState() {
  if (calYear === null) {
    calYear = dayjs().year();
    calMonth = dayjs().month() + 1;
  }
}

export async function resetCalendarToCurrentMonth() {
  const now = dayjs();
  calYear = now.year();
  calMonth = now.month() + 1;
  calCheckinsData = await getMonthCheckinsFull(calYear, calMonth);
}

export function getCalendarState() {
  ensureCalState();
  return {
    year: calYear,
    month: calMonth,
    checkins: calCheckinsData
  };
}

export function getCalendarCheckins() {
  return calCheckinsData;
}

export function findTodayCheckin() {
  const todayStr = dayjs().format('YYYY-MM-DD');
  return calCheckinsData.find(c => c.checkin_date === todayStr);
}

export function renderCalendarGrid() {
  ensureCalState();
  const now = dayjs();
  const todayStr = now.format('YYYY-MM-DD');
  const map = new Map(calCheckinsData.map(c => [c.checkin_date, c]));
  const firstDay = dayjs(`${calYear}-${String(calMonth).padStart(2, '0')}-01`);
  const daysInMonth = firstDay.daysInMonth();
  const startDayOfWeek = firstDay.day();
  const prevMonthDays = firstDay.subtract(1, 'day').daysInMonth();

  let cells = '';
  ['日', '一', '二', '三', '四', '五', '六'].forEach(d => {
    cells += `<div class="day-name">${d}</div>`;
  });
  for (let i = startDayOfWeek - 1; i >= 0; i--) {
    cells += `<div class="day other-month"><span>${prevMonthDays - i}</span></div>`;
  }
  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = firstDay.date(d).format('YYYY-MM-DD');
    const checkin = map.get(dateStr);
    let cls = 'day';
    if (checkin) {
      cls += ' checked';
    } else if (dateStr === todayStr) {
      cls += ' today';
    } else if (dayjs(dateStr).isAfter(now, 'day')) {
      cls += ' future';
    }
    const style = (checkin && checkin.mood_color)
      ? `style="--mood-dot:${safeColor(checkin.mood_color, '#c17d4b')}"` : '';
    const dataDate = checkin ? `data-date="${esc(dateStr)}"` : '';
    cells += `<div class="${cls}" ${style} ${dataDate}><span>${d}</span></div>`;
  }
  const totalCells = startDayOfWeek + daysInMonth;
  const remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  for (let d = 1; d <= remaining; d++) {
    cells += `<div class="day other-month"><span>${d}</span></div>`;
  }
  return cells;
}

export async function refreshCalendar() {
  ensureCalState();
  calCheckinsData = await getMonthCheckinsFull(calYear, calMonth);

  const gridEl = document.getElementById('cal-grid');
  if (!gridEl) return;
  gridEl.innerHTML = renderCalendarGrid();

  const label = document.getElementById('cal-month-label');
  if (label) label.textContent = `${calYear}年${calMonth}月`;

  const btn = document.getElementById('checkin-btn');
  if (btn) {
    const todayCheckin = findTodayCheckin();
    btn.textContent = todayCheckin ? '编辑今日签到' : '📖 今日签到';
    btn.classList.toggle('btn-ghost', !!todayCheckin);
  }
}

export async function moveCalendarMonth(delta) {
  ensureCalState();
  calMonth += delta;
  if (calMonth < 1) {
    calMonth = 12;
    calYear--;
  }
  if (calMonth > 12) {
    calMonth = 1;
    calYear++;
  }
  await refreshCalendar();
}

export function showCheckinForm(existing = null) {
  const isEdit = !!existing;
  const dateStr = existing ? existing.checkin_date : dayjs().format('YYYY-MM-DD');
  const currentMood = existing?.mood_color || '';

  const html = `
    <form id="checkin-form">
      <div class="form-group">
        <label>签到日期</label>
        <input type="date" value="${esc(dateStr)}" readonly disabled style="opacity:0.7;cursor:not-allowed;">
        <input type="hidden" name="checkin_date" value="${esc(dateStr)}">
      </div>
      <div class="form-group">
        <label>正在读的书 *</label>
        <input type="text" name="book_title" value="${esc(existing?.book_title || '')}" placeholder="例如：《红楼梦》" required>
      </div>
      <div class="form-group">
        <label>摘抄</label>
        <textarea name="excerpt" placeholder="今天读到的触动你的句子...">${h(existing?.excerpt || '')}</textarea>
      </div>
      <div class="form-group">
        <label>感想</label>
        <textarea name="reflection" placeholder="今天的阅读感悟...">${h(existing?.reflection || '')}</textarea>
      </div>
      <div class="form-group">
        <label>心情颜色</label>
        <div class="mood-swatches">
          ${MOODS.map(m => {
            const isSelected = m.value === currentMood || (!m.value && !currentMood);
            const selectedClass = isSelected ? ' selected' : '';
            const style = m.value ? `background:${m.value};` : '';
            return `<div class="mood-swatch ${m.cls || ''}${selectedClass}"
              data-color="${m.value}" style="${style}"
              title="${m.label}"></div>`;
          }).join('')}
        </div>
        <input type="hidden" name="mood_color" value="${esc(currentMood)}" id="mood-color-input">
      </div>
      <button type="submit" class="btn btn-primary" style="width:100%">
        ${isEdit ? '保存修改' : '签到'}
      </button>
      ${isEdit ? '<input type="hidden" name="is_edit" value="1">' : ''}
    </form>`;

  const modal = showModal(isEdit ? '编辑签到' : '每日阅读签到', html);
  modal.querySelectorAll('.mood-swatch').forEach(swatch => {
    swatch.addEventListener('click', () => {
      modal.querySelectorAll('.mood-swatch').forEach(s => s.classList.remove('selected'));
      swatch.classList.add('selected');
      modal.querySelector('#mood-color-input').value = swatch.dataset.color;
    });
  });
  return modal;
}

export function showCheckinDetail(checkin) {
  const moodColor = safeColor(checkin.mood_color);
  const bookTitle = checkin.book_title || '未记录';
  const html = `
    <div class="checkin-detail-head">
      <span class="mood-dot" style="background:${moodColor};${!checkin.mood_color ? 'border-style:dashed;' : ''}"></span>
      <strong style="font-size:1.1rem;">${formatDate(checkin.checkin_date)}</strong>
    </div>
    <div class="checkin-detail-book">
      <span style="color:var(--color-text-3);">在读：</span>
      <strong>${h(bookTitle)}</strong>
    </div>
    ${checkin.excerpt ? `
      <div style="margin-bottom:var(--space-2);">
        <div style="color:var(--color-text-3);font-size:0.82rem;font-weight:600;margin-bottom:6px;">摘抄</div>
        <div class="checkin-excerpt"><blockquote>${checkin.excerpt.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</blockquote></div>
      </div>
    ` : ''}
    ${checkin.reflection ? `
      <div style="margin-bottom:var(--space-2);">
        <div style="color:var(--color-text-3);font-size:0.82rem;font-weight:600;margin-bottom:6px;">感想</div>
        <div class="checkin-reflection"><p>${checkin.reflection.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</p></div>
      </div>
    ` : ''}
    <div style="text-align:right;margin-top:var(--space-3);">
      <button class="btn btn-outline btn-sm" id="edit-checkin-btn" data-date="${esc(checkin.checkin_date)}">编辑</button>
    </div>
  `;
  showModal('签到详情', html);
}

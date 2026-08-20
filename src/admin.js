import { statusTag } from './components.js';
import { ACT_STATUSES, ACT_TYPES } from './constants.js';
import { aiFillBookInfo, loadBooks, loadConfig, loadEvents } from './data.js';
import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { createCoReadingPassword, setCoReadingPasswordActive } from './tickets.js';
import { showModal, toast } from './ui.js';
import {
  esc,
  formatDateCompact,
  formatDateTime,
  formatDateTimeFilename,
  formatDateTimeLocal,
  h,
  safeUrl,
  toBeijingISOString
} from './utils.js';

function generateReadablePassword(length = 18) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, byte => alphabet[byte % alphabet.length]).join('');
}

function memberLevelText(member) {
  const level = Number(member.level || 0);
  if (level <= 0) return member.tier || '基础会员';
  return `Lv.${level} ${member.title || ''}`.trim();
}

function libraryTypeLabel(type) {
  return type === 'life' ? '人生之书' : '想读书目';
}

function csvCell(value) {
  const text = String(value ?? '');
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function downloadTextFile(filename, content, mimeType = 'text/plain;charset=utf-8') {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function memberLibraryRowsToCsv(rows) {
  const header = ['用户UID', '显示名字', 'Email', '类型', '排序', '书名', '作者', '豆瓣链接', '理由', '更新时间'];
  const lines = rows.map(row => [
    row.user_id,
    row.display_name,
    row.email,
    libraryTypeLabel(row.list_type),
    row.sort_order,
    row.book_title,
    row.author,
    row.douban_url,
    row.reason,
    formatDateTime(row.updated_at)
  ].map(csvCell).join(','));
  return '\ufeff' + [header.map(csvCell).join(','), ...lines].join('\n');
}

function topCounts(rows, keyFn, limit = 10) {
  const counts = new Map();
  rows.forEach(row => {
    const key = keyFn(row);
    if (!key) return;
    counts.set(key, (counts.get(key) || 0) + 1);
  });
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-Hans-CN'))
    .slice(0, limit);
}

function buildMemberLibraryReport(rows) {
  const wantRows = rows.filter(row => row.list_type === 'want');
  const lifeRows = rows.filter(row => row.list_type === 'life');
  const users = new Set(rows.map(row => row.user_id).filter(Boolean));
  const bookKey = row => row.book_title ? `${row.book_title}${row.author ? ` - ${row.author}` : ''}` : '';

  const renderTop = list => list.length
    ? list.map(([name, count], index) => `${index + 1}. ${name}：${count} 次`).join('\n')
    : '暂无数据';

  return `# 会员书库分析报告

生成时间：${formatDateTime(new Date().toISOString())}

## 数据概览

- 参与会员数：${users.size}
- 想读书目：${wantRows.length}
- 人生之书：${lifeRows.length}
- 总记录数：${rows.length}

## 想读书目高频书

${renderTop(topCounts(wantRows, bookKey))}

## 人生之书高频书

${renderTop(topCounts(lifeRows, bookKey))}

## 高频作者

${renderTop(topCounts(rows, row => row.author || ''))}

## 可作为共读候选的书目

${renderTop(topCounts(wantRows, bookKey, 15))}
`;
}

async function loadAdminMemberLibraryRows() {
  const { data, error } = await sb.rpc('admin_export_member_library');
  if (error) throw error;
  return data || [];
}

const ADMIN_TABS = ['rules', 'books', 'events', 'member-list', 'members'];

function currentAdminTab() {
  const active = document.querySelector('#admin-tabs .tab.active')?.dataset.tab;
  if (ADMIN_TABS.includes(active)) return active;
  const queryTab = router.currentQuery().tab;
  return ADMIN_TABS.includes(queryTab) ? queryTab : 'rules';
}

function syncAdminTabToHash(tab) {
  const value = ADMIN_TABS.includes(tab) ? tab : 'rules';
  history.replaceState(null, '', `#/admin?tab=${encodeURIComponent(value)}`);
}

async function refreshAdminPreservingPosition() {
  const tab = currentAdminTab();
  const scrollY = window.scrollY;
  syncAdminTabToHash(tab);
  await router.render();
  requestAnimationFrame(() => window.scrollTo(0, scrollY));
}

function renderAdminMemberList(members, error) {
  if (error) {
    return `
      <div class="admin-inline-warning">
        <i data-lucide="database"></i>
        <span>会员清单暂不可用：请先部署 v32 会员清单 SQL。</span>
      </div>
    `;
  }

  if (!members?.length) {
    return '<p class="admin-muted">暂无会员数据。</p>';
  }

  return `
    <div class="admin-member-toolbar">
      <div class="admin-member-search">
        <i data-lucide="search"></i>
        <input type="search" id="admin-member-search-input" placeholder="搜索用户 ID 或显示名字">
      </div>
      <span class="admin-muted">可在这里封禁或解锁会员账号。</span>
    </div>
    <div class="admin-member-table-wrap">
      <table class="admin-member-table">
        <thead>
          <tr>
            <th>会员信息</th>
            <th>注册与等级</th>
            <th>账号状态</th>
            <th>备注</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          ${members.map(member => `
            <tr data-admin-member-row data-member-search="${esc(`${member.user_id || ''} ${member.display_name || ''}`.toLowerCase())}">
              <td>
                <div class="admin-member-identity">
                  <strong>${h(member.display_name || '未命名')}</strong>
                  <span>${h(member.email || '未记录邮箱')}</span>
                  <code>${h(member.user_id)}</code>
                </div>
              </td>
              <td>
                <div class="admin-member-meta">
                  <span>${h(memberLevelText(member))}</span>
                  <small>注册：${h(formatDateTime(member.registered_at))}</small>
                </div>
              </td>
              <td>
                ${member.is_banned
                  ? `<span class="admin-member-status banned">已封禁</span>${member.banned_at ? `<small>${h(formatDateTime(member.banned_at))}</small>` : ''}${member.ban_reason ? `<small>${h(member.ban_reason)}</small>` : ''}`
                  : '<span class="admin-member-status normal">正常</span>'}
              </td>
              <td>
                <textarea
                  class="admin-member-note-input"
                  data-member-note="${esc(member.user_id)}"
                  maxlength="1000"
                  placeholder="添加后台备注，仅管理员可见"
                >${h(member.note || '')}</textarea>
              </td>
              <td>
                <div class="admin-member-actions">
                  <button type="button" class="btn btn-outline btn-sm" data-action="admin-save-member-note" data-user-id="${esc(member.user_id)}">保存备注</button>
                  <button
                    type="button"
                    class="btn btn-sm ${member.is_banned ? 'btn-outline' : 'btn-danger'}"
                    data-action="admin-toggle-member-ban"
                    data-user-id="${esc(member.user_id)}"
                    data-is-banned="${member.is_banned ? 'true' : 'false'}"
                    data-display-name="${esc(member.display_name || '未命名')}"
                  >${member.is_banned ? '解锁用户' : '封禁用户'}</button>
                </div>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

// ===========================================
// ROUTE: ADMIN
// ===========================================
route('/admin', async () => {
  const config = await loadConfig();
  const books = await loadBooks();
  const events = await loadEvents();
  const activeTab = currentAdminTab();
  const { data: adminMembers, error: adminMembersError } = await sb.rpc('admin_list_members');
  const { data: coReadingPasswords } = await sb
    .from('co_reading_passwords')
    .select('*, books(title)')
    .order('created_at', { ascending: false })
    .limit(30);

  return `
    <div class="container section">
      <div class="page-header"><h1>管理后台</h1></div>
      <div class="tabs" id="admin-tabs">
        <button class="tab ${activeTab === 'rules' ? 'active' : ''}" data-tab="rules">群规编辑</button>
        <button class="tab ${activeTab === 'books' ? 'active' : ''}" data-tab="books">书籍管理</button>
        <button class="tab ${activeTab === 'events' ? 'active' : ''}" data-tab="events">活动管理</button>
        <button class="tab ${activeTab === 'member-list' ? 'active' : ''}" data-tab="member-list">会员清单</button>
        <button class="tab ${activeTab === 'members' ? 'active' : ''}" data-tab="members">会员运营</button>
      </div>
      <div id="admin-tab-rules" style="${activeTab === 'rules' ? '' : 'display:none;'}">
        <h3 style="margin-bottom:var(--space-2);">群规</h3>
        <form id="rules-form">
          <div class="form-group"><label>共读群公约（Markdown）</label><textarea name="group_rules" style="min-height:200px;">${h(config.group_rules || '')}</textarea></div>
          <div class="form-group"><label>共读计划介绍（Markdown）</label><textarea name="reading_plan_intro" style="min-height:120px;">${h(config.reading_plan_intro || '')}</textarea></div>
          <button type="submit" class="btn btn-primary">保存设置</button>
        </form>
        <hr style="margin:var(--space-4) 0;border-color:var(--color-border);">
        <h3 style="margin-bottom:var(--space-2);">添加新书</h3>
        <button class="btn btn-outline" id="btn-add-book">+ 添加书籍</button>
        <div style="margin-top:var(--space-3);">
          <h4 style="margin-bottom:var(--space-1);">现有书籍</h4>
          ${books.map(b => `
            <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
              <span>${h(b.title)}${b.start_date && b.end_date ? '（' + formatDateCompact(b.start_date) + '-' + formatDateCompact(b.end_date) + '）' : ''} ${statusTag(b.status)}</span>
              <div>
                <button class="btn btn-ghost btn-sm btn-edit-book" data-id="${b.id}">编辑</button>
                <button class="btn btn-danger btn-sm btn-del-book" data-id="${b.id}">删除</button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
      <div id="admin-tab-events" style="${activeTab === 'events' ? '' : 'display:none;'}">
        <h3 style="margin-bottom:var(--space-2);">添加线下活动</h3>
        <button class="btn btn-outline" id="btn-add-event">+ 添加活动</button>
        <div style="margin-top:var(--space-3);">
          <h4 style="margin-bottom:var(--space-1);">现有活动</h4>
          ${events.map(ev => `
            <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
              <span>${h(ev.title)}（${formatDateTime(ev.event_date)}${ev.location ? ' · ' + h(ev.location) : ''}） ${statusTag(ev.status)}</span>
              <div>
                <button class="btn btn-ghost btn-sm btn-edit-event" data-id="${ev.id}">编辑</button>
                <button class="btn btn-danger btn-sm btn-del-event" data-id="${ev.id}">删除</button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
      <div id="admin-tab-books" style="${activeTab === 'books' ? '' : 'display:none;'}">
        <h3 style="margin-bottom:var(--space-2);">添加新书</h3>
        <button class="btn btn-outline" id="btn-add-book2">+ 添加书籍</button>
        <div style="margin-top:var(--space-3);">
          ${books.map(b => `
            <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
              <span>${h(b.title)}${b.start_date && b.end_date ? '（' + formatDateCompact(b.start_date) + '-' + formatDateCompact(b.end_date) + '）' : ''} ${statusTag(b.status)}</span>
              <div>
                <button class="btn btn-ghost btn-sm btn-edit-book" data-id="${b.id}">编辑</button>
                <button class="btn btn-danger btn-sm btn-del-book" data-id="${b.id}">删除</button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
      <div id="admin-tab-member-list" style="${activeTab === 'member-list' ? '' : 'display:none;'}">
        <div class="card" style="margin-bottom:var(--space-3);">
          <div class="card-body">
            <div class="admin-section-head">
              <div>
                <h3>会员清单</h3>
                <p>查看所有会员基础信息，维护后台备注，并封禁或解锁会员账号。</p>
              </div>
              <span>${h(adminMembers?.length || 0)} 位会员</span>
            </div>
            ${renderAdminMemberList(adminMembers || [], adminMembersError)}
          </div>
        </div>
      </div>

      <div id="admin-tab-members" style="${activeTab === 'members' ? '' : 'display:none;'}">
        <div class="card" style="margin-bottom:var(--space-3);">
          <div class="card-body">
            <h3 style="margin-bottom:var(--space-1);">本周资源浏览券</h3>
            <p style="color:var(--color-text-2);font-size:0.9rem;margin:0;">系统会在每周日北京时间 20:00 自动核算截至该时刻的当周阅读贡献，并按会员等级发放浏览券；前 5 名活跃会员数量翻倍。无需手动操作。</p>
          </div>
        </div>

        <div class="card" style="margin-bottom:var(--space-3);">
          <div class="card-body">
            <h3 style="margin-bottom:var(--space-1);">会员书库数据</h3>
            <p style="color:var(--color-text-2);font-size:0.9rem;margin-bottom:var(--space-2);">抽取当前所有会员的想读书目与人生之书，下载 CSV 数据表格或 Markdown 分析报告。</p>
            <div style="display:flex;gap:var(--space-2);flex-wrap:wrap;">
              <button type="button" class="btn btn-outline" data-action="admin-download-member-library-csv"><i data-lucide="table"></i> 下载数据表格</button>
              <button type="button" class="btn btn-outline" data-action="admin-download-member-library-report"><i data-lucide="file-text"></i> 下载分析报告</button>
            </div>
          </div>
        </div>

        <div class="card" style="margin-bottom:var(--space-3);">
          <div class="card-body">
            <h3 style="margin-bottom:var(--space-2);">创建共读密码</h3>
            <form id="admin-co-reading-password-form">
              <div class="grid-2">
                <div class="form-group">
                  <label>共读书目</label>
                  <select name="book_id" required>
                    <option value="">请选择</option>
                    ${books.map(book => `<option value="${h(book.id)}">${h(book.title)}</option>`).join('')}
                  </select>
                </div>
                <div class="form-group">
                  <label>名称</label>
                  <input type="text" name="label" value="共读密码">
                </div>
                <div class="form-group">
                  <label>开始时间（北京时间）</label>
                  <input type="datetime-local" name="starts_at">
                </div>
                <div class="form-group">
                  <label>过期时间（北京时间）</label>
                  <input type="datetime-local" name="expires_at">
                </div>
              </div>
              <button type="submit" class="btn btn-primary">自动生成并创建密码</button>
            </form>
          </div>
        </div>

        <div class="card">
          <div class="card-body">
            <h3 style="margin-bottom:var(--space-2);">现有共读密码</h3>
            ${(coReadingPasswords || []).length ? `
              <div style="display:flex;flex-direction:column;gap:8px;">
                ${(coReadingPasswords || []).map(row => `
                  <div style="display:flex;justify-content:space-between;gap:var(--space-2);align-items:center;border-bottom:1px solid var(--color-border);padding:8px 0;">
                    <div>
                      <strong>${h(row.books?.title || `书目 #${row.book_id}`)}</strong>
                      <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:4px;">
                        <code style="padding:3px 7px;border-radius:var(--radius-sm);background:var(--color-bg-alt);border:1px solid var(--color-border);font-size:0.85rem;">${h(row.password_plain || '历史密码不可显示')}</code>
                      </div>
                      <div style="font-size:0.82rem;color:var(--color-text-3);">${h(row.label || '共读密码')} · ${row.is_active ? '启用中' : '已停用'}${row.expires_at ? ' · 过期：' + h(formatDateTime(row.expires_at)) : ''}</div>
                    </div>
                    <button type="button" class="btn btn-outline btn-sm" data-action="admin-toggle-co-reading-password" data-id="${h(row.id)}" data-active="${row.is_active ? 'false' : 'true'}">${row.is_active ? '停用' : '启用'}</button>
                  </div>
                `).join('')}
              </div>
            ` : '<p style="color:var(--color-text-3);">暂无共读密码。部署 v26 后可在这里创建。</p>'}
          </div>
        </div>
      </div>
    </div>
  `;
});

// Admin tab switching
document.addEventListener('click', (e) => {
  const tab = e.target.closest('#admin-tabs .tab');
  if (!tab) return;
  document.querySelectorAll('#admin-tabs .tab').forEach(t => t.classList.remove('active'));
  tab.classList.add('active');
  ['rules','books','events','member-list','members'].forEach(t => {
    const el = document.getElementById('admin-tab-' + t);
    if (el) el.style.display = tab.dataset.tab === t ? '' : 'none';
  });
  syncAdminTabToHash(tab.dataset.tab);
});

// Admin: save rules
document.addEventListener('submit', async (e) => {
  if (e.target.id === 'rules-form') {
    e.preventDefault();
    const fd = new FormData(e.target);
    for (const [key, value] of fd.entries()) {
      await sb.from('site_config').upsert({ key, value }, { onConflict: 'key' });
    }
    await loadConfig(); // refresh cached config
    toast('设置已保存');
  }

  if (e.target.id === 'admin-co-reading-password-form') {
    e.preventDefault();
    const fd = new FormData(e.target);
    const submitBtn = e.target.querySelector('button[type="submit"]');
    if (submitBtn) submitBtn.disabled = true;
    const { error } = await createCoReadingPassword({
      bookId: fd.get('book_id'),
      password: generateReadablePassword(),
      label: fd.get('label')?.trim() || '共读密码',
      startsAt: toBeijingISOString(fd.get('starts_at')),
      expiresAt: toBeijingISOString(fd.get('expires_at'))
    });
    if (error) {
      toast('创建失败：' + error.message, 'error');
      if (submitBtn) submitBtn.disabled = false;
      return;
    }
    toast('共读密码已创建');
    await refreshAdminPreservingPosition();
  }
});

// ===========================================
// VISUAL FORM BUILDERS — v2 unified
// ===========================================
function actItem(a) { a=a||{}; return `
  <div class="builder-item">
    <div class="b-row">
      <select name="act_type" style="max-width:110px">${ACT_TYPES.map(t=>`<option value="${t}" ${a.type===t?'selected':''}>${t}</option>`).join('')}</select>
      <select name="act_status" style="max-width:100px">${ACT_STATUSES.map(s=>`<option value="${s}" ${a.status===s?'selected':''}>${s}</option>`).join('')}</select>
      <input name="act_title" value="${esc(a.title)}" placeholder="活动标题 *" style="flex:2" required>
      <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
    </div>
    <div class="b-row">
      <input name="act_time" value="${esc(a.time)}" placeholder="时间（北京时间）如 19:30 或 2月1日" style="flex:1">
      <input name="act_meeting_link" value="${esc(a.meeting_link)}" placeholder="会议链接" style="flex:1">
      <input name="act_replay_link" value="${esc(a.replay_link)}" placeholder="回放链接" style="flex:1">
    </div>
    <div class="b-row">
      <input name="act_guests" value="${esc(a.guests)}" placeholder="嘉宾（可选）">
    </div>
    <div class="b-row">
      <input name="act_desc" value="${esc(a.description)}" placeholder="描述（可选）">
    </div>
  </div>`;
}
function ednItem(e) { e=e||{}; return `
  <div class="builder-item">
    <div class="b-row">
      <input name="edn_name" value="${esc(e.name)}" placeholder="版本名称 *" style="flex:2" required>
      <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
    </div>
    <div class="b-row">
      <input name="edn_translator" value="${esc(e.translator)}" placeholder="译者">
      <input name="edn_publisher" value="${esc(e.publisher)}" placeholder="出版方">
    </div>
    <div class="b-row">
      <input name="edn_pros" value="${esc(e.pros)}" placeholder="优点">
      <input name="edn_cons" value="${esc(e.cons)}" placeholder="缺点">
    </div>
    <div class="b-row">
      <input name="edn_buy_link" value="${esc(e.buy_link)}" placeholder="购买链接">
      <input name="edn_douban_link" value="${esc(e.douban_link)}" placeholder="豆瓣链接">
    </div>
  </div>`;
}
function chatItem(c) { c=c||{}; return `
  <div class="builder-item">
    <div class="b-row">
      <input type="number" name="chat_sort_order" value="${esc(c.sort_order != null ? c.sort_order : '')}" placeholder="序号" style="width:64px;min-width:64px;" min="1">
      <input name="chat_topic" value="${esc(c.topic)}" placeholder="干货主题 *" style="flex:2" required>
      <div class="builder-sort-actions" aria-label="聊天干货排序">
        <button type="button" class="btn-sort-row" data-action="move-chat-up" title="上移">↑</button>
        <button type="button" class="btn-sort-row" data-action="move-chat-down" title="下移">↓</button>
      </div>
      <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
    </div>
    <div class="b-row">
      <input name="chat_speaker" value="${esc(c.speaker)}" placeholder="主发言人">
    </div>
    <div class="b-row">
      <textarea name="chat_content" placeholder="详细内容（Markdown）" style="min-height:60px;width:100%;">${esc(c.content)}</textarea>
    </div>
    <div class="b-row" style="align-items:center;">
      <input type="file" class="chat-image-input" accept="image/*" style="flex:1;font-size:0.85rem;">
      <span style="font-size:0.78rem;color:var(--color-text-3);white-space:nowrap;">上传图片 → 正文光标处插入 Markdown</span>
    </div>
    <div class="b-row">
      <input name="chat_pdf_url" value="${esc(c.pdf_url || c.pdfUrl || c.file_url || '')}" placeholder="PDF 链接（可选）" style="flex:2">
      <input type="file" class="chat-pdf-input" accept=".pdf,application/pdf" style="flex:1;font-size:0.85rem;">
    </div>
    <div class="chat-pdf-name" style="font-size:0.82rem;color:var(--color-text-2);margin-top:4px;">${(c.pdf_url || c.pdfUrl || c.file_url) ? '已上传：' + h(String(c.pdf_url || c.pdfUrl || c.file_url).split('/').pop()) : ''}</div>
  </div>`;
}
function resItem(r) { r=r||{}; return `
  <div class="builder-item">
    <div class="b-row">
      <input name="res_title" value="${esc(r.title)}" placeholder="标题" style="flex:2">
      <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
    </div>
    <div class="b-row">
      <input name="res_url" value="${esc(r.url)}" placeholder="链接（可选）">
      <input name="res_desc" value="${esc(r.description)}" placeholder="描述（可选）">
    </div>
  </div>`;
}

// Admin: add/edit book form
function showBookForm(bookData = null) {
  const isEdit = !!bookData;
  const book = bookData || { title:'', author:'', author_country:'', author_gender:'', translator:'', translator_gender:'', publisher:'', word_count:'', cover_url:'', genre:'文学', description:'', author_bio:'', historical_context:'', status:'upcoming', edition_guide:'[]', edition_notes:'', reading_schedule:'{"summary":"","pdf_url":""}', host:'', host_intro:'', host_notes:'', host_notes_title:'', host_notes_subtitle:'', host_notes_author:'', xuxu_notes:'', activities:'[]', chatsubstance:'[]', resources:'{"extended_reading":[],"text_materials":[],"film_resources":[],"other":[]}', start_date:'', end_date:'', join_enabled:false, join_intro:'', join_qr_url:'' };
  const genres = ['文学','历史','哲学','科幻','社科','心理','传记','商业','科普','其他'];
  // Parse JSONB data for visual builders
  let acts=[], edns=[], chats=[], extR=[], txtM=[], filmR=[], otherR=[];
  try { acts = typeof book.activities==='string' ? JSON.parse(book.activities||'[]') : (book.activities||[]); } catch(e){}
  try { edns = typeof book.edition_guide==='string' ? JSON.parse(book.edition_guide||'[]') : (book.edition_guide||[]); } catch(e){}
  try { chats = typeof book.chatsubstance==='string' ? JSON.parse(book.chatsubstance||'[]') : (book.chatsubstance||[]); } catch(e){}
  try {
    const res = typeof book.resources==='string' ? JSON.parse(book.resources||'{}') : (book.resources||{});
    extR = res.extended_reading||[]; txtM = res.text_materials||[]; filmR = res.film_resources||[]; otherR = res.other||[];
  } catch(e){}
  let scheduleForForm = { summary: '', pdf_url: '' };
  try {
    scheduleForForm = typeof book.reading_schedule === 'string'
      ? JSON.parse(book.reading_schedule || '{}')
      : (book.reading_schedule || {});
  } catch(e) {
    scheduleForForm = { summary: String(book.reading_schedule || ''), pdf_url: '' };
  }

  const formHtml = `
    <form id="book-edit-form" style="max-height:70vh;overflow-y:auto;">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--space-2);">
        <div class="form-group"><label>书名 *</label><input type="text" name="title" value="${esc(book.title)}" required></div>
        <div class="form-group"><label>作者 *</label><input type="text" name="author" value="${esc(book.author)}" required></div>
        <div class="form-group"><label>作者国别</label><input type="text" name="author_country" value="${esc(book.author_country || '')}"></div>
        <div class="form-group"><label>作者性别</label><input type="text" name="author_gender" value="${esc(book.author_gender || '')}"></div>
        <div class="form-group"><label>译者</label><input type="text" name="translator" value="${esc(book.translator || '')}"></div>
        <div class="form-group"><label>译者性别</label><input type="text" name="translator_gender" value="${esc(book.translator_gender || '')}"></div>
        <div class="form-group"><label>出版方</label><input type="text" name="publisher" value="${esc(book.publisher || '')}"></div>
        <div class="form-group"><label>字数</label><input type="number" name="word_count" value="${esc(book.word_count || '')}"></div>
        <div class="form-group"><label>类型 *</label><select name="genre" required>${genres.map(g => `<option value="${g}" ${book.genre === g ? 'selected' : ''}>${g}</option>`).join('')}</select></div>
        <div class="form-group"><label>共读状态 *</label><select name="status">
          <option value="upcoming" ${book.status === 'upcoming' ? 'selected' : ''}>即将开读</option>
          <option value="active" ${book.status === 'active' ? 'selected' : ''}>正在共读</option>
          <option value="completed" ${book.status === 'completed' ? 'selected' : ''}>已读完</option>
        </select></div>
        <div class="form-group"><label>开始日期 *</label><input type="date" name="start_date" value="${esc(book.start_date || '')}" required></div>
        <div class="form-group"><label>结束日期 *</label><input type="date" name="end_date" value="${esc(book.end_date || '')}" required></div>
      </div>

      <div class="builder-section">
        <label>加入我们分页</label>
        <label style="display:flex;align-items:center;gap:8px;font-size:0.9rem;margin-bottom:var(--space-2);">
          <input type="checkbox" name="join_enabled" ${book.join_enabled ? 'checked' : ''}>
          开启书籍详情页“加入我们”分页
        </label>
        <p style="font-size:0.84rem;color:var(--color-text-3);margin-bottom:var(--space-2);">页面说明文字已固定，只需要上传入群二维码并在会员运营中创建本期共读密码。</p>
        <div class="form-group">
          <label>入群二维码</label>
          <div class="cover-upload">
            <div class="cover-preview" id="join-qr-preview">
              ${book.join_qr_url ? `<img src="${safeUrl(book.join_qr_url)}" alt="">` : '<i data-lucide="qr-code" style="width:28px;height:28px;color:var(--color-text-3);"></i>'}
            </div>
            <div class="cover-inputs">
              <input type="url" name="join_qr_url" value="${esc(book.join_qr_url || '')}" placeholder="粘贴二维码图片 URL" id="join-qr-url-input">
              <div class="divider-text">或</div>
              <input type="file" accept="image/*" id="join-qr-file-input" style="font-size:0.85rem;">
            </div>
          </div>
        </div>
      </div>

      <!-- Cover image: URL + upload -->
      <div class="form-group">
        <label>封面图 *</label>
        <div class="cover-upload">
          <div class="cover-preview" id="cover-preview">
            ${book.cover_url ? `<img src="${safeUrl(book.cover_url)}" alt="">` : '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>'}
          </div>
          <div class="cover-inputs">
            <input type="url" name="cover_url" value="${esc(book.cover_url || '')}" placeholder="粘贴图片 URL" id="cover-url-input" required>
            <div class="divider-text">或</div>
            <input type="file" accept="image/*" id="cover-file-input" style="font-size:0.85rem;">
          </div>
        </div>
      </div>

      <div style="display:flex;align-items:center;gap:8px;margin-bottom:var(--space-1);">
        <button type="button" class="btn btn-outline btn-sm" id="btn-ai-fill">🤖 AI 自动填充简介</button>
        <span style="font-size:0.78rem;color:var(--color-text-3);">AI 自动编写书籍简介、作者简介、时代背景（不剧透）</span>
      </div>
      <div class="form-group"><label>书籍简介（Markdown）</label><textarea name="description" style="min-height:60px;">${h(book.description || '')}</textarea></div>
      <div class="form-group"><label>作者简介（Markdown）</label><textarea name="author_bio" style="min-height:60px;">${h(book.author_bio || '')}</textarea></div>
      <div class="form-group"><label>创作时代背景（Markdown）</label><textarea name="historical_context" style="min-height:60px;">${h(book.historical_context || '')}</textarea></div>
      <div class="form-group"><label>版本建议简述（Markdown）</label><textarea name="edition_notes" style="min-height:60px;" placeholder="版本选择的总体建议...">${h(book.edition_notes || '')}</textarea></div>

      <!-- Visual Builder: Edition Guide -->
      <div class="builder-section">
        <label>📖 版本建议</label>
        <div class="builder-items" id="builder-editions">${edns.length ? edns.map(ednItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无版本</div>'}</div>
        <button type="button" class="btn-add-row" data-action="add-edition">+ 添加版本</button>
      </div>

      <div class="form-group"><label>共读时间计划简述（Markdown）</label><textarea name="schedule_summary" style="min-height:80px;">${h(scheduleForForm.summary || '')}</textarea></div>
      <div class="form-group">
        <label>时间计划 PDF</label>
        <div style="display:flex;gap:var(--space-2);align-items:center;">
          <input type="file" id="schedule-pdf-input" accept=".pdf" style="flex:1;">
          <input type="hidden" name="schedule_pdf_url" id="schedule-pdf-url" value="${esc(scheduleForForm.pdf_url || '')}">
        </div>
        <div id="schedule-pdf-name" style="font-size:0.82rem;color:var(--color-text-2);margin-top:4px;">${scheduleForForm.pdf_url ? '已上传：' + h(String(scheduleForForm.pdf_url).split('/').pop()) : ''}</div>
      </div>
      <div class="form-group"><label>领读人</label><input type="text" name="host" value="${esc(book.host || '')}" placeholder="领读人姓名"></div>
      <div class="form-group"><label>领读人简介（Markdown）</label><textarea name="host_intro" style="min-height:80px;">${h(book.host_intro || '')}</textarea></div>
      <div class="form-group"><label>导言标题</label><input type="text" name="host_notes_title" value="${esc(book.host_notes_title || '')}" placeholder="可选"></div>
      <div class="form-group"><label>导言副标题</label><input type="text" name="host_notes_subtitle" value="${esc(book.host_notes_subtitle || '')}" placeholder="可选"></div>
      <div class="form-group"><label>导言作者</label><input type="text" name="host_notes_author" value="${esc(book.host_notes_author || '')}" placeholder="必填" required></div>
      <div class="form-group"><label>领读导言正文（Markdown）</label><textarea name="host_notes" style="min-height:80px;">${h(book.host_notes || '')}</textarea></div>
      <div class="form-group"><label>灵沁碎碎念（Markdown）</label><textarea name="xuxu_notes" style="min-height:80px;">${h(book.xuxu_notes || '')}</textarea></div>

      <!-- Visual Builder: Activities (unified) -->
      <div class="builder-section">
        <label>📅 活动安排</label>
        <div class="builder-items" id="builder-acts">${acts.length ? acts.map(actItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无活动</div>'}</div>
        <button type="button" class="btn-add-row" data-action="add-activity">+ 添加活动</button>
      </div>

      <!-- Visual Builder: Chat Substance -->
      <div class="builder-section">
        <label>💬 聊天干货</label>
        <div class="builder-items" id="builder-chats">${chats.length ? chats.map(chatItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无干货</div>'}</div>
        <button type="button" class="btn-add-row" data-action="add-chat">+ 添加聊天干货</button>
      </div>

      <!-- Visual Builder: Resources -->
      <div class="builder-section">
        <label>📚 资源材料</label>
        <div class="res-section">
          <h5>延伸读物</h5>
          <div class="builder-items" id="builder-ext">${extR.length ? extR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
          <button type="button" class="btn-add-row" data-action="add-ext">+ 添加延伸读物</button>
        </div>
        <div class="res-section">
          <h5>文字材料</h5>
          <div class="builder-items" id="builder-txt">${txtM.length ? txtM.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
          <button type="button" class="btn-add-row" data-action="add-txt">+ 添加文字材料</button>
        </div>
        <div class="res-section">
          <h5>影视资源</h5>
          <div class="builder-items" id="builder-film">${filmR.length ? filmR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
          <button type="button" class="btn-add-row" data-action="add-film">+ 添加影视资源</button>
        </div>
        <div class="res-section">
          <h5>其他</h5>
          <div class="builder-items" id="builder-other">${otherR.length ? otherR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
          <button type="button" class="btn-add-row" data-action="add-other">+ 添加其他</button>
        </div>
      </div>

      <button type="submit" class="btn btn-primary">${isEdit ? '保存修改' : '添加书籍'}</button>
      <input type="hidden" name="book_id" value="${esc(book.id || '')}">
    </form>`;
  const modal = showModal(isEdit ? '编辑书籍' : '添加书籍', formHtml, () => {
    document.removeEventListener('submit', bookFormHandler);
  });
  modal.querySelector('.modal').classList.add('modal-wide');
  document.addEventListener('submit', bookFormHandler);
  function bookFormHandler(e) {
    if (e.target.id !== 'book-edit-form') return;
    e.preventDefault();
    const fd = new FormData(e.target);
    const data = Object.fromEntries(fd.entries());
    data.join_enabled = fd.get('join_enabled') === 'on';

    // Collect from visual builders
    function collectItems(containerId, fields) {
      const items = document.querySelectorAll(`#${containerId} .builder-item`);
      return Array.from(items).map(item => {
        const obj = {};
        fields.forEach(f => { const el = item.querySelector(`[name="${f}"]`); if (el) obj[f] = el.value; });
        return obj;
      }).filter(obj => Object.values(obj).some(v => v.trim()));
    }

    // Edition guide
    const edns = collectItems('builder-editions', ['edn_name','edn_translator','edn_publisher','edn_pros','edn_cons','edn_buy_link','edn_douban_link']).map(o => ({
      name: o.edn_name||'', translator: o.edn_translator||'', publisher: o.edn_publisher||'',
      pros: o.edn_pros||'', cons: o.edn_cons||'', buy_link: o.edn_buy_link||'', douban_link: o.edn_douban_link||''
    }));
    data.edition_guide = JSON.stringify(edns);

    // Activities (unified)
    data.activities = collectItems('builder-acts', ['act_type','act_title','act_time','act_status','act_meeting_link','act_replay_link','act_guests','act_desc']).map(o => ({
      type: o.act_type||'导读预热', title: o.act_title||'', time: o.act_time||'',
      status: o.act_status||'计划中', meeting_link: o.act_meeting_link||'',
      replay_link: o.act_replay_link||'', guests: o.act_guests||'', description: o.act_desc||''
    }));

    // Resources
    const extR = collectItems('builder-ext', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
    const txtM = collectItems('builder-txt', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
    const filmR = collectItems('builder-film', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
    const otherR = collectItems('builder-other', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
    data.resources = { extended_reading: extR, text_materials: txtM, film_resources: filmR, other: otherR };

    // Chatsubstance
    data.chatsubstance = JSON.stringify(collectItems('builder-chats', ['chat_topic','chat_speaker','chat_content','chat_pdf_url','chat_sort_order']).map(o => ({
      topic: o.chat_topic||'', speaker: o.chat_speaker||'', content: o.chat_content||'', pdf_url: o.chat_pdf_url||'', sort_order: o.chat_sort_order ? parseInt(o.chat_sort_order) : null
    })));

    // Serialize reading_schedule from form fields
    data.reading_schedule = JSON.stringify({
      summary: data.schedule_summary || '',
      pdf_url: data.schedule_pdf_url || ''
    });
    delete data.schedule_summary; delete data.schedule_pdf_url;

    // Clean up — remove builder field names not in books table
    delete data.online_activities; delete data.meeting_replays; delete data.isbn; delete data.page_count;
    ['edn_name','edn_translator','edn_publisher','edn_pros','edn_cons','edn_buy_link','edn_douban_link',
     'act_type','act_title','act_time','act_status','act_meeting_link','act_replay_link','act_guests','act_desc',
     'chat_topic','chat_speaker','chat_content','chat_pdf_url','chat_sort_order',
     'res_title','res_url','res_desc'].forEach(f => delete data[f]);
    data.word_count = data.word_count ? parseInt(data.word_count) : null;
    saveBook(data, data.book_id);
    modal.remove();
    document.removeEventListener('submit', bookFormHandler);
  }
}

async function saveBook(data, id) {
  const payload = { ...data };
  delete payload.book_id;
  payload.updated_at = new Date().toISOString();
  if (!id) payload.created_by = store.get('user').id;

  let error;
  if (id) {
    ({ error } = await sb.from('books').update(payload).eq('id', id));
  } else {
    ({ error } = await sb.from('books').insert(payload));
  }
  if (error) { toast('保存失败：' + error.message, 'error'); return; }
  toast(id ? '书籍已更新' : '书籍已添加');
  await refreshAdminPreservingPosition();
}

async function deleteBook(id) {
  if (!confirm('确定要删除这本书吗？')) return;
  const { error } = await sb.from('books').delete().eq('id', id);
  if (error) { toast('删除失败：' + error.message, 'error'); return; }
  toast('书籍已删除');
  await refreshAdminPreservingPosition();
}

// Admin: add/edit event form
function showEventForm(eventData = null) {
  const isEdit = !!eventData;
  const ev = eventData || { title:'', category:'', link:'', poster_url:'', location:'', event_date:'', guests:'', price:'', description:'', status:'upcoming' };
  const formHtml = `
    <form id="event-edit-form">
      <div class="form-group"><label>活动名称 *</label><input type="text" name="title" value="${esc(ev.title)}" required></div>
      <div class="form-group"><label>活动分类 *</label><select name="category" required>
        <option value="">请选择</option>
        <option value="文学高速" ${ev.category === '文学高速' ? 'selected' : ''}>文学高速</option>
        <option value="其他" ${ev.category === '其他' ? 'selected' : ''}>其他</option>
      </select></div>
      <div class="form-group"><label>活动链接</label><input type="url" name="link" value="${esc(ev.link || '')}" placeholder="https://...（可选）"></div>
      <div class="form-group">
        <label>海报图</label>
        <div class="cover-upload">
          <div class="cover-preview" id="poster-preview">
            ${ev.poster_url ? `<img src="${safeUrl(ev.poster_url)}" alt="">` : '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>'}
          </div>
          <div class="cover-inputs">
            <input type="url" name="poster_url" value="${esc(ev.poster_url || '')}" placeholder="粘贴图片 URL" id="poster-url-input" required>
            <div class="divider-text">或</div>
            <input type="file" accept="image/*" id="poster-file-input" style="font-size:0.85rem;">
          </div>
        </div>
      </div>
      <div class="form-group"><label>地点</label><input type="text" name="location" value="${esc(ev.location || '')}"></div>
      <div class="form-group"><label>时间（北京时间）</label><input type="datetime-local" name="event_date" value="${esc(formatDateTimeLocal(ev.event_date))}"></div>
      <div class="form-group"><label>嘉宾</label><input type="text" name="guests" value="${esc(ev.guests || '')}"></div>
      <div class="form-group"><label>价格</label><input type="text" name="price" value="${esc(ev.price || '')}" placeholder="免费 / ¥68"></div>
      <div class="form-group"><label>状态</label><select name="status">
        <option value="upcoming" ${ev.status === 'upcoming' ? 'selected' : ''}>即将开始</option>
        <option value="ongoing" ${ev.status === 'ongoing' ? 'selected' : ''}>进行中</option>
        <option value="ended" ${ev.status === 'ended' ? 'selected' : ''}>已结束</option>
        <option value="cancelled" ${ev.status === 'cancelled' ? 'selected' : ''}>已取消</option>
      </select></div>
      <div class="form-group"><label>活动简介（Markdown）</label><textarea name="description" style="min-height:100px;">${h(ev.description || '')}</textarea></div>
      <button type="submit" class="btn btn-primary">${isEdit ? '保存修改' : '添加活动'}</button>
      <input type="hidden" name="event_id" value="${esc(ev.id || '')}">
    </form>`;
  const modal = showModal(isEdit ? '编辑活动' : '添加活动', formHtml, () => {
    document.removeEventListener('submit', eventFormHandler);
  });
  modal.querySelector('.modal').classList.add('modal-wide');
  document.addEventListener('submit', eventFormHandler);
  function eventFormHandler(e) {
    if (e.target.id !== 'event-edit-form') return;
    e.preventDefault();
    const fd = new FormData(e.target);
    const data = Object.fromEntries(fd.entries());
    saveEvent(data, data.event_id);
    modal.remove();
    document.removeEventListener('submit', eventFormHandler);
  }
}

async function saveEvent(data, id) {
  const payload = { ...data };
  delete payload.event_id;
  if (payload.event_date) {
    const eventDate = toBeijingISOString(payload.event_date);
    if (!eventDate) {
      toast('保存失败：活动时间格式无效', 'error');
      return;
    }
    payload.event_date = eventDate;
  }
  payload.updated_at = new Date().toISOString();
  if (!id) payload.created_by = store.get('user').id;

  let error;
  if (id) {
    ({ error } = await sb.from('events').update(payload).eq('id', id));
  } else {
    ({ error } = await sb.from('events').insert(payload));
  }
  if (error) { toast('保存失败：' + error.message, 'error'); return; }
  toast(id ? '活动已更新' : '活动已添加');
  await refreshAdminPreservingPosition();
}

async function deleteEvent(id) {
  if (!confirm('确定要删除这个活动吗？')) return;
  const { error } = await sb.from('events').delete().eq('id', id);
  if (error) { toast('删除失败：' + error.message, 'error'); return; }
  toast('活动已删除');
  await refreshAdminPreservingPosition();
}

// Admin button handlers
document.addEventListener('click', async (e) => {
  // This handler is async because of AI fill button
  const libraryCsvBtn = e.target.closest('[data-action="admin-download-member-library-csv"]');
  if (libraryCsvBtn) {
    libraryCsvBtn.disabled = true;
    try {
      const rows = await loadAdminMemberLibraryRows();
      downloadTextFile(`member-library-${formatDateTimeFilename()}.csv`, memberLibraryRowsToCsv(rows), 'text/csv;charset=utf-8');
      toast(`已导出 ${rows.length} 条书库数据`);
    } catch (err) {
      toast('导出失败：' + (err.message || '未知错误'), 'error');
    } finally {
      libraryCsvBtn.disabled = false;
    }
    return;
  }

  const libraryReportBtn = e.target.closest('[data-action="admin-download-member-library-report"]');
  if (libraryReportBtn) {
    libraryReportBtn.disabled = true;
    try {
      const rows = await loadAdminMemberLibraryRows();
      downloadTextFile(`member-library-report-${formatDateTimeFilename()}.md`, buildMemberLibraryReport(rows));
      toast('分析报告已生成');
    } catch (err) {
      toast('报告生成失败：' + (err.message || '未知错误'), 'error');
    } finally {
      libraryReportBtn.disabled = false;
    }
    return;
  }

  const togglePasswordBtn = e.target.closest('[data-action="admin-toggle-co-reading-password"]');
  if (togglePasswordBtn) {
    togglePasswordBtn.disabled = true;
    const { error } = await setCoReadingPasswordActive(togglePasswordBtn.dataset.id, togglePasswordBtn.dataset.active === 'true');
    if (error) {
      toast('操作失败：' + error.message, 'error');
      togglePasswordBtn.disabled = false;
      return;
    }
    toast(togglePasswordBtn.dataset.active === 'true' ? '密码已启用' : '密码已停用');
    await refreshAdminPreservingPosition();
    return;
  }

  const saveMemberNoteBtn = e.target.closest('[data-action="admin-save-member-note"]');
  if (saveMemberNoteBtn) {
    const userId = saveMemberNoteBtn.dataset.userId;
    const noteInput = [...document.querySelectorAll('[data-member-note]')]
      .find(input => input.dataset.memberNote === userId);
    saveMemberNoteBtn.disabled = true;
    const { error } = await sb.rpc('admin_update_member_note', {
      p_user_id: userId,
      p_note: noteInput?.value || ''
    });
    if (error) {
      toast('备注保存失败：' + error.message, 'error');
      saveMemberNoteBtn.disabled = false;
      return;
    }
    toast('会员备注已保存');
    saveMemberNoteBtn.disabled = false;
    return;
  }

  const toggleMemberBanBtn = e.target.closest('[data-action="admin-toggle-member-ban"]');
  if (toggleMemberBanBtn) {
    const userId = toggleMemberBanBtn.dataset.userId;
    const displayName = toggleMemberBanBtn.dataset.displayName || userId;
    const isBanned = toggleMemberBanBtn.dataset.isBanned === 'true';
    let reason = '';

    if (isBanned) {
      if (!confirm(`确定解锁「${displayName}」吗？解锁后该账号将恢复共读书库、书友圈和西语文学板块访问权限。`)) return;
    } else {
      const promptedReason = prompt(`确定封禁「${displayName}」吗？\n封禁后该账号将不能浏览共读书库、书友圈、西语文学板块，也不能在书友圈发帖互动。\n\n可填写封禁原因：`, '');
      if (promptedReason === null) return;
      reason = promptedReason;
      if (!confirm(`请再次确认：封禁「${displayName}」？`)) return;
    }

    toggleMemberBanBtn.disabled = true;
    const { error } = await sb.rpc('admin_set_member_ban', {
      p_user_id: userId,
      p_is_banned: !isBanned,
      p_reason: reason
    });
    if (error) {
      toast((isBanned ? '解锁失败：' : '封禁失败：') + error.message, 'error');
      toggleMemberBanBtn.disabled = false;
      return;
    }
    toast(isBanned ? '用户已解锁' : '用户已封禁');
    await refreshAdminPreservingPosition();
    return;
  }

  const addBookBtn = e.target.closest('#btn-add-book, #btn-add-book2');
  if (addBookBtn) { showBookForm(); return; }
  const addEventBtn = e.target.closest('#btn-add-event');
  if (addEventBtn) { showEventForm(); return; }
  const editBookBtn = e.target.closest('.btn-edit-book');
  if (editBookBtn) {
    const id = editBookBtn.dataset.id;
    const book = store.get('books').find(b => String(b.id) === id);
    if (book) showBookForm(book);
    return;
  }
  const delBookBtn = e.target.closest('.btn-del-book');
  if (delBookBtn) { deleteBook(delBookBtn.dataset.id); return; }
  const editEventBtn = e.target.closest('.btn-edit-event');
  if (editEventBtn) {
    const id = editEventBtn.dataset.id;
    const event = store.get('events').find(ev => String(ev.id) === id);
    if (event) showEventForm(event);
    return;
  }
  const delEventBtn = e.target.closest('.btn-del-event');
  if (delEventBtn) { deleteEvent(delEventBtn.dataset.id); return; }

  const moveChatBtn = e.target.closest('[data-action="move-chat-up"], [data-action="move-chat-down"]');
  if (moveChatBtn) {
    const item = moveChatBtn.closest('#builder-chats .builder-item');
    const container = item?.parentElement;
    if (!item || !container) return;
    if (moveChatBtn.dataset.action === 'move-chat-up') {
      const prev = item.previousElementSibling;
      if (prev) container.insertBefore(item, prev);
    } else {
      const next = item.nextElementSibling;
      if (next) container.insertBefore(next, item);
    }
    return;
  }

  // Visual builder: add buttons
  const addBtn = e.target.closest('.btn-add-row');
  if (addBtn) {
    const action = addBtn.dataset.action;
    const map = {
      'add-edition':  { container: 'builder-editions', html: ednItem() },
      'add-activity': { container: 'builder-acts', html: actItem() },
      'add-ext':      { container: 'builder-ext', html: resItem() },
      'add-txt':      { container: 'builder-txt', html: resItem() },
      'add-film':     { container: 'builder-film', html: resItem() },
      'add-other':    { container: 'builder-other', html: resItem() },
      'add-chat':     { container: 'builder-chats', html: chatItem() }
    };
    const cfg = map[action];
    if (cfg) {
      const container = document.getElementById(cfg.container);
      if (container) {
        // Remove empty placeholder
        const placeholder = container.querySelector('.builder-item[style]');
        if (placeholder) placeholder.remove();
        container.insertAdjacentHTML('beforeend', cfg.html);
      }
    }
    return;
  }

  // AI fill button in book form
  const aiBtn = e.target.closest('#btn-ai-fill');
  if (aiBtn) {
    aiBtn.disabled = true;
    aiBtn.textContent = '⏳ AI 正在搜索编写...';
    const modal = aiBtn.closest('.modal');
    const titleEl = modal?.querySelector('[name="title"]');
    const authorEl = modal?.querySelector('[name="author"]');
    const descEl = modal?.querySelector('[name="description"]');
    const bioEl = modal?.querySelector('[name="author_bio"]');
    const ctxEl = modal?.querySelector('[name="historical_context"]');
    const result = await aiFillBookInfo(titleEl?.value || '', authorEl?.value || '');
    if (result) {
      if (descEl) descEl.value = result.description || '';
      if (bioEl) bioEl.value = result.author_bio || '';
      if (ctxEl) ctxEl.value = result.historical_context || '';
      toast('AI 内容已填充，请检查修改 ✨');
    }
    aiBtn.disabled = false;
    aiBtn.textContent = '🤖 AI 自动填充简介';
    return;
  }
});

document.addEventListener('input', (e) => {
  const searchInput = e.target.closest('#admin-member-search-input');
  if (!searchInput) return;

  const query = searchInput.value.trim().toLowerCase();
  document.querySelectorAll('[data-admin-member-row]').forEach(row => {
    const haystack = row.dataset.memberSearch || '';
    row.style.display = !query || haystack.includes(query) ? '' : 'none';
  });
});

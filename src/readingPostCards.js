import { store } from './store.js';
import { esc, formatDateTime, h, proxyImg, safeColor, safeUrl } from './utils.js';
import { contentLabel, formatBookTitle, POST_TYPE_LABELS, ratingEmoji, VISIBILITY_LABELS } from './readingPostUtils.js';

const postCache = new Map();

export function getCachedPost(id) {
  return postCache.get(Number(id));
}

export function clearCachedPost(id) {
  postCache.delete(Number(id));
}

function renderAuthorAvatar(post) {
  if (post.avatar_url) {
    return `<img src="${safeUrl(post.avatar_url)}" alt="">`;
  }
  return h((post.display_name || '书')[0].toUpperCase());
}

function renderTextBlock(label, text, cls = '') {
  if (!text) return '';
  return `
    <div class="reading-post-content-block ${cls}">
      <span>${h(label)}</span>
      <p class="reading-post-content">${h(text)}</p>
    </div>
  `;
}

export function renderPostCard(post, scope) {
  const isMine = store.get('user')?.id === post.user_id;
  const excerpt = renderTextBlock('摘抄', post.excerpt, 'quote');
  const content = renderTextBlock(contentLabel(post.post_type), post.content);
  const rating = post.post_type === 'finished' && post.rating != null
    ? `<div class="reading-post-rating"><span>评分</span><strong>${ratingEmoji(post.rating)} ${h(post.rating)}</strong></div>`
    : '';
  const moodColor = safeColor(post.mood_color, '');
  const moodStyle = moodColor ? `style="--reading-mood-border:${moodColor};"` : '';
  const cover = post.cover_url ? `
    <div class="reading-post-cover">
      <img src="${safeUrl(proxyImg(post.cover_url))}" alt="${esc(post.book_title)}">
    </div>
  ` : '';
  const titleLink = post.douban_url
    ? `<a href="${safeUrl(post.douban_url)}" target="_blank" rel="noopener">${h(formatBookTitle(post.book_title))}</a>`
    : h(formatBookTitle(post.book_title));
  const bookLine = post.author
    ? `${titleLink}<span class="reading-post-title-author"> - ${h(post.author)}</span>`
    : titleLink;

  postCache.set(Number(post.id), post);

  return `
    <article class="card reading-post-card" id="post-${h(post.id)}" ${moodStyle}>
      <div class="card-body">
        <div class="reading-post-head">
          <div class="reading-post-user">
            <div class="reading-post-avatar">${renderAuthorAvatar(post)}</div>
            <div>
              <a href="#/user/${h(post.user_id)}" class="reading-post-username">${h(post.display_name || '书友')}</a>
              ${post.member_level > 0 ? `<span class="member-level-badge">Lv.${h(post.member_level)} ${h(post.member_title)}</span>` : ''}
              <span class="reading-post-time">${h(formatDateTime(post.created_at))}</span>
            </div>
          </div>
          <div class="reading-post-tags">
            <span class="tag tag-genre">${h(POST_TYPE_LABELS[post.post_type] || post.post_type)}</span>
            ${scope === 'mine' ? `<span class="tag tag-completed">${h(VISIBILITY_LABELS[post.visibility] || post.visibility)}</span>` : ''}
          </div>
        </div>
        <div class="reading-post-main">
          ${cover}
          <div class="reading-post-body">
            <div class="reading-post-title-row">
              <h3>${bookLine}</h3>
              ${rating}
            </div>
            ${excerpt}
            ${content}
          </div>
        </div>
        <div class="reading-post-foot">
          <button type="button" class="btn-like ${post.has_liked ? 'liked' : ''}" data-action="toggle-post-like" data-id="${h(post.id)}" title="${post.has_liked ? '取消点赞' : '点赞'}">
            <i data-lucide="heart"></i><span>${h(post.like_count || 0)}</span>
          </button>
          <button type="button" class="btn-comment-toggle" data-action="toggle-post-comments" data-id="${h(post.id)}" title="查看评论">
            <i data-lucide="message-circle"></i><span>${h(post.comment_count || 0)}</span>
          </button>
          ${isMine ? `
            <div class="reading-post-actions">
              <button type="button" class="btn btn-ghost btn-sm" data-action="edit-reading-post" data-id="${h(post.id)}">编辑</button>
              <button type="button" class="btn btn-ghost btn-sm" data-action="toggle-post-visibility" data-id="${h(post.id)}" data-next="${post.visibility === 'public' ? 'private' : 'public'}">
                ${post.visibility === 'public' ? '设为私密' : '设为公开'}
              </button>
              <button type="button" class="btn btn-danger btn-sm" data-action="delete-reading-post" data-id="${h(post.id)}">删除</button>
            </div>
          ` : ''}
        </div>
        <div class="reading-post-comments" data-post-comments="${h(post.id)}" style="display:none;">
          <div class="comments-list" data-comments-list="${h(post.id)}"></div>
          <form class="comment-form" data-comment-form="${h(post.id)}" novalidate>
            <textarea name="content" placeholder="写下你的评论，最多 800 字..." maxlength="800" required rows="2"></textarea>
            <button type="submit" class="btn btn-sm btn-primary">发送</button>
          </form>
        </div>
      </div>
    </article>
  `;
}

export function renderPosts(posts, scope) {
  if (!posts.length) {
    return `
      <div class="empty-state">
        <i data-lucide="messages-square"></i>
        <p>${scope === 'mine' ? '你还没有发布书友圈动态。' : '还没有公开书友圈动态。'}</p>
      </div>
    `;
  }

  return `<div class="reading-post-list">${posts.map(post => renderPostCard(post, scope)).join('')}</div>`;
}

import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';
import { sb } from './supabaseClient.js';

export async function loadReadingPosts(scope = 'public') {
  const { data, error } = await sb.rpc('list_reading_posts', { p_scope: scope });
  if (error) {
    console.warn('Reading posts unavailable:', error.message);
    return { posts: [], error };
  }
  return { posts: data || [], error: null };
}

export async function fetchDoubanBook(url) {
  const resp = await fetch(`${SUPABASE_URL}/functions/v1/fetch-douban-book`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
    },
    body: JSON.stringify({ url })
  });
  const result = await resp.json().catch(() => ({}));
  if (!resp.ok || !result?.success || !result?.data?.title) {
    throw new Error(result?.error || result?.detail || '未抓取到书籍信息');
  }
  return result.data;
}

export function createReadingPost(payload) {
  return sb.rpc('create_reading_post', payload);
}

export function updateReadingPost(payload) {
  return sb.rpc('update_reading_post', payload);
}

export function updateReadingPostVisibility(postId, visibility) {
  return sb.rpc('update_reading_post_visibility', {
    p_post_id: Number(postId),
    p_visibility: visibility
  });
}

export function deleteReadingPost(postId) {
  return sb.rpc('delete_reading_post', {
    p_post_id: Number(postId)
  });
}

export function togglePostLike(postId) {
  return sb.rpc('toggle_post_like', { p_post_id: Number(postId) });
}

export function listComments(postId) {
  return sb.rpc('list_comments', { p_post_id: Number(postId) });
}

export function createComment(postId, content) {
  return sb.rpc('create_comment', {
    p_post_id: Number(postId),
    p_content: content
  });
}

export function deleteCommentById(commentId) {
  return sb.rpc('delete_comment', { p_comment_id: Number(commentId) });
}

export function getPublicMemberProfile(userId) {
  return sb.rpc('get_public_member_profile', { p_user_id: userId });
}

export function listUserPublicPosts(userId) {
  return sb.rpc('list_user_public_posts', { p_user_id: userId });
}

export function getContributionLeaderboard(type) {
  return sb.rpc('get_contribution_leaderboard', { p_type: type });
}

export function searchReadingPosts(query) {
  return sb.rpc('search_reading_posts', { p_query: query });
}

export function toggleFollow(userId) {
  return sb.rpc('toggle_follow', { p_following_id: userId });
}

export function isFollowing(userId) {
  return sb.rpc('is_following', { p_following_id: userId });
}

export function getFollowCounts(userId) {
  return sb.rpc('get_follow_counts', { p_user_id: userId });
}

export function listFollowing(userId) {
  return sb.rpc('list_following', { p_user_id: userId });
}

export function listFollowers(userId) {
  return sb.rpc('list_followers', { p_user_id: userId });
}

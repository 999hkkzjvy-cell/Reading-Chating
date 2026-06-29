import { sb } from './supabaseClient.js';

export async function loadBookAccessSummary(bookId) {
  const { data, error } = await sb.rpc('get_resource_access_summary', { p_book_id: Number(bookId) });
  if (error) {
    console.warn('Resource access unavailable:', error.message);
    return {
      hasPermanentAccess: false,
      availableViewPasses: 0,
      availableRedemptionTickets: 0,
      temporaryResourceKeys: [],
      error
    };
  }

  const row = Array.isArray(data) ? (data[0] || {}) : (data || {});
  return {
    hasPermanentAccess: !!row.has_permanent_access,
    availableViewPasses: row.available_view_passes || 0,
    availableRedemptionTickets: row.available_redemption_tickets || 0,
    temporaryResourceKeys: row.temporary_resource_keys || [],
    error: null
  };
}

export function consumeViewPass(bookId, resourceKey) {
  return sb.rpc('consume_view_pass', {
    p_book_id: Number(bookId),
    p_resource_key: resourceKey
  });
}

export function redeemBookAccess(bookId) {
  return sb.rpc('redeem_book_access', {
    p_book_id: Number(bookId)
  });
}

export function claimCoReadingPassword(bookId, password, groupMemberId) {
  return sb.rpc('claim_co_reading_password', {
    p_book_id: Number(bookId),
    p_password: password,
    p_group_member_id: groupMemberId
  });
}

export function createCoReadingPassword({ bookId, password, label, startsAt, expiresAt }) {
  return sb.rpc('admin_create_co_reading_password', {
    p_book_id: Number(bookId),
    p_password: password,
    p_label: label || '共读密码',
    p_starts_at: startsAt || null,
    p_expires_at: expiresAt || null
  });
}

export function setCoReadingPasswordActive(passwordId, isActive) {
  return sb.rpc('admin_set_co_reading_password_active', {
    p_password_id: Number(passwordId),
    p_is_active: !!isActive
  });
}

export function issueWeeklyViewPasses() {
  return sb.rpc('admin_issue_weekly_view_passes');
}

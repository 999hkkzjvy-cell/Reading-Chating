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

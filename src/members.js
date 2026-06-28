import { sb } from './supabaseClient.js';
import { store } from './store.js';

export async function loadMemberSummary(userId = store.get('user')?.id) {
  if (!userId) {
    store.set('member', null);
    return null;
  }

  try {
    const { data: stats, error: statsError } = await sb
      .from('member_stats')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();

    if (statsError) {
      console.warn('Member stats unavailable:', statsError.message);
      store.set('member', null);
      return null;
    }

    const nowIso = new Date().toISOString();
    const [
      { data: viewPasses },
      { data: redemptionTickets },
      { data: badges },
      { data: currentLevel },
      { data: nextLevel },
      { data: badgeDisplayPreferences },
      { data: weeklyRank }
    ] = await Promise.all([
      sb
        .from('view_passes')
        .select('*')
        .eq('user_id', userId)
        .order('issued_at', { ascending: false }),
      sb
        .from('resource_redemption_tickets')
        .select('*')
        .eq('user_id', userId)
        .order('issued_at', { ascending: false }),
      sb
        .from('user_badges')
        .select('*, badge_catalog(*)')
        .eq('user_id', userId)
        .is('revoked_at', null)
        .order('awarded_at', { ascending: false }),
      stats
        ? sb.from('member_levels').select('*').eq('level', stats.level).maybeSingle()
        : Promise.resolve({ data: null }),
      stats && stats.level < 16
        ? sb.from('member_levels').select('*').eq('level', stats.level + 1).maybeSingle()
        : Promise.resolve({ data: null }),
      sb
        .from('member_badge_display_preferences')
        .select('badge_key, sort_order')
        .eq('user_id', userId)
        .order('sort_order', { ascending: true }),
      sb.rpc('get_my_weekly_contribution_rank')
    ]);

    const safeViewPasses = viewPasses || [];
    const safeRedemptionTickets = redemptionTickets || [];

    const summary = {
      stats,
      currentLevel: currentLevel || null,
      nextLevel: nextLevel || null,
      availableViewPasses: safeViewPasses.filter(pass => (
        pass.status === 'available' && (!pass.expires_at || pass.expires_at > nowIso)
      )).length,
      availableRedemptionTickets: safeRedemptionTickets.filter(ticket => ticket.status === 'available').length,
      viewPasses: safeViewPasses,
      redemptionTickets: safeRedemptionTickets,
      badges: badges || [],
      badgeDisplayPreferences: badgeDisplayPreferences || [],
      weeklyRank: Array.isArray(weeklyRank) ? (weeklyRank[0] || null) : (weeklyRank || null)
    };

    store.set('member', summary);
    return summary;
  } catch (err) {
    console.warn('Member summary load failed:', err);
    store.set('member', null);
    return null;
  }
}

// Supabase Edge Function: Douban New Books Scraper
// Deploy: supabase functions deploy scrape-douban
// Set secret: supabase secrets set SB_SERVICE_ROLE_KEY=sb_xxx

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as cheerio from "npm:cheerio@1.0.0";

const DOUBAN_LATEST_URL = "https://book.douban.com/latest";
const SB_URL = Deno.env.get("SUPABASE_URL") || "https://zugadhgezmqrnlwogomw.supabase.co";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function requireAdmin(req: Request, serviceRoleKey: string) {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace(/^Bearer\s+/i, "");
  if (!token) return { ok: false, status: 401, error: "Unauthorized", client: null };

  const sb = createClient(SB_URL, serviceRoleKey);
  const { data: userData, error: userError } = await sb.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return { ok: false, status: 401, error: "Invalid session", client: null };

  const { data: profile, error: profileError } = await sb
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || profile?.role !== "admin") return { ok: false, status: 403, error: "Admin only", client: null };
  return { ok: true, status: 200, error: "", client: sb };
}

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: CORS_HEADERS,
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const force = body.force === true;

    const serviceRoleKey = Deno.env.get("SB_SERVICE_ROLE_KEY")!;

    if (!serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Server config missing: SB_SERVICE_ROLE_KEY" }),
        { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    const adminCheck = await requireAdmin(req, serviceRoleKey);
    if (!adminCheck.ok || !adminCheck.client) {
      return new Response(
        JSON.stringify({ error: adminCheck.error }),
        { status: adminCheck.status, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }
    const sb = adminCheck.client;

    // Check last scrape time — skip if within 24h and not forced
    if (!force) {
      const { data: last } = await sb
        .from("douban_new_books")
        .select("scraped_at")
        .order("scraped_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (last?.scraped_at) {
        const hoursSince = (Date.now() - new Date(last.scraped_at).getTime()) / (1000 * 60 * 60);
        if (hoursSince < 24) {
          return new Response(
            JSON.stringify({ cached: true, scraped_at: last.scraped_at, message: "数据在 24 小时内已更新，跳过抓取" }),
            { headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
          );
        }
      }
    }

    // Fetch Douban latest page
    const res = await fetch(DOUBAN_LATEST_URL, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      },
      signal: AbortSignal.timeout(15000),
    });

    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: `豆瓣请求失败: HTTP ${res.status}` }),
        { status: 502, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    const html = await res.text();
    const $ = cheerio.load(html);

    const books: Array<{
      title: string;
      cover_url: string;
      author: string;
      translator: string;
      publisher: string;
      description: string;
      douban_url: string;
      rating: string;
      review_count: number;
      fiction_type: string;
      scraped_at: string;
    }> = [];

    // Parse the single book list: ul.chart-dashed-list > li.media.clearfix
    $("ul.chart-dashed-list li.media.clearfix").each((_, el) => {
        const $el = $(el);

        const coverLink = $el.find("div.media__img a");
        const coverImg = coverLink.find("img.subject-cover");
        const cover_url = coverImg.attr("src") || "";
        const douban_url = coverLink.attr("href") || "";

        const titleEl = $el.find("div.media__body h2 a.fleft");
        const title = titleEl.text().trim();

        if (!title) return;

        // Info line: "作者 / 出版日期 / 出版社 / 价格 / 装帧"
        const infoRaw = $el.find("p.subject-abstract.color-gray").text().trim();
        const infoParts = infoRaw.split("/").map((s) => s.trim()).filter(Boolean);

        const author = infoParts[0] || "";

        // Publisher: part containing 出版/社/书局/书店
        let publisher = "";
        for (const p of infoParts) {
          if (p.includes("出版") || p.includes("社") || p.includes("书局") || p.includes("书店")) {
            publisher = p;
            break;
          }
        }

        // Rating area
        const ratingRaw = $el.find("p.subject-rating").text().trim();
        let rating = "";
        let review_count = 0;

        // Extract rating score (e.g. "8.5")
        const scoreMatch = ratingRaw.match(/([\d.]+)/);
        if (scoreMatch) rating = scoreMatch[1];

        // Extract review count (e.g. "(380人评价)")
        const reviewMatch = ratingRaw.match(/\((\d+)人评价\)/);
        if (reviewMatch) review_count = parseInt(reviewMatch[1], 10) || 0;

        // Tags / genre (from div.subject-tags span)
        const tagText = $el.find("div.subject-tags span").text().trim();
        const fiction_type = tagText.includes("虚构") || tagText.includes("小说") || tagText.includes("文学")
          ? "fiction" : "non-fiction";

        books.push({
          title,
          cover_url: cover_url || "",
          author: author || "",
          translator: "",
          publisher,
          description: "",
          douban_url,
          rating,
          review_count,
          fiction_type,
          scraped_at: new Date().toISOString(),
        });
      });

    if (books.length === 0) {
      return new Response(
        JSON.stringify({ error: "未解析到任何书籍数据，豆瓣页面结构可能已变化" }),
        { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    // Sort by review_count descending, keep top 20 (we show top 10 in UI, but cache more)
    books.sort((a, b) => b.review_count - a.review_count);
    const topBooks = books.slice(0, 20);

    // Upsert into douban_new_books
    const { error: upsertError } = await sb
      .from("douban_new_books")
      .upsert(topBooks, { onConflict: "douban_url", ignoreDuplicates: false });

    if (upsertError) {
      return new Response(
        JSON.stringify({ error: "写入数据库失败", detail: upsertError.message }),
        { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    // Cleanup: delete old books with 0 votes (not from today's scrape)
    // Books that have >= 1 vote (in reading_wishlist) are kept forever
    // 1. Get all book IDs that have votes
    const { data: votedIds } = await sb
      .from("reading_wishlist")
      .select("book_id");

    const votedIdSet = new Set((votedIds || []).map((v) => v.book_id));

    // 2. Get old books (before today) without votes
    const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const { data: oldBooks } = await sb
      .from("douban_new_books")
      .select("id, scraped_at")
      .lt("scraped_at", today);

    const idsToDelete = (oldBooks || [])
      .filter((b) => !votedIdSet.has(b.id))
      .map((b) => b.id);

    if (idsToDelete.length > 0) {
      // Delete in batches of 100
      for (let i = 0; i < idsToDelete.length; i += 100) {
        const batch = idsToDelete.slice(i, i + 100);
        await sb.from("douban_new_books").delete().in("id", batch);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        count: topBooks.length,
        total_parsed: books.length,
        cleaned: idsToDelete.length,
        books: topBooks,
      }),
      { headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: "抓取失败", detail: message }),
      { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
    );
  }
});

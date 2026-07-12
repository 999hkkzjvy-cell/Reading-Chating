// Supabase Edge Function: Douban New Books Scraper
// Deploy: supabase functions deploy scrape-douban
// Set secret: supabase secrets set SB_SERVICE_ROLE_KEY=sb_xxx

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const DOUBAN_LATEST_URL = "https://book.douban.com/latest";
const DOUBAN_LATEST_PAGES = 3;
const DISPLAY_BOOKS_LIMIT = 10;
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

    const scrapeStartedAt = new Date().toISOString();

    async function fetchLatestPage(page: number) {
      const url = new URL(DOUBAN_LATEST_URL);
      if (page > 1) {
        url.searchParams.set("p", String(page));
        url.searchParams.set("subcat", "全部");
        url.searchParams.set("updated_at", "");
      }

      const res = await fetch(url.toString(), {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        },
        signal: AbortSignal.timeout(15000),
      });

      if (!res.ok) {
        throw new Error(`豆瓣请求失败: HTTP ${res.status}`);
      }

      return await res.text();
    }

    const pageWarnings: string[] = [];

    function decodeHtml(value: string) {
      return value
        .replace(/&nbsp;/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">");
    }

    function stripTags(value: string) {
      return decodeHtml(value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim());
    }

    function matchText(source: string, pattern: RegExp) {
      const match = source.match(pattern);
      return match ? stripTags(match[1]) : "";
    }

    function matchAttr(source: string, pattern: RegExp) {
      const match = source.match(pattern);
      return match ? decodeHtml(match[1].trim()) : "";
    }

    function parseBookItems(html: string) {
      const items: string[] = [];
      const itemRe = /<li\b[^>]*class=["'][^"']*\bmedia\b[^"']*\bclearfix\b[^"']*["'][^>]*>[\s\S]*?<\/li>/gi;
      let itemMatch: RegExpExecArray | null;
      while ((itemMatch = itemRe.exec(html)) !== null) {
        items.push(itemMatch[0]);
      }
      return items;
    }

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
      source_rank: number;
      source_page: number;
      scraped_at: string;
    }> = [];

    for (let page = 1; page <= DOUBAN_LATEST_PAGES; page += 1) {
      let html = "";
      try {
        html = await fetchLatestPage(page);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        pageWarnings.push(`第 ${page} 页抓取失败：${message}`);
        continue;
      }

      // Parse the book list: ul.chart-dashed-list > li.media.clearfix
      parseBookItems(html).forEach((el) => {
        const cover_url = matchAttr(el, /<img\b[^>]*class=["'][^"']*\bsubject-cover\b[^"']*["'][^>]*src=["']([^"']+)["']/i);
        const douban_url = matchAttr(el, /<div\b[^>]*class=["'][^"']*\bmedia__img\b[^"']*["'][^>]*>[\s\S]*?<a\b[^>]*href=["']([^"']+)["']/i);
        const title = matchText(el, /<h2\b[^>]*>[\s\S]*?<a\b[^>]*class=["'][^"']*\bfleft\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i);

        if (!title) return;

        // Info line: "作者 / 出版日期 / 出版社 / 价格 / 装帧"
        const infoRaw = matchText(el, /<p\b[^>]*class=["'][^"']*\bsubject-abstract\b[^"']*\bcolor-gray\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
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
        const ratingRaw = matchText(el, /<p\b[^>]*class=["'][^"']*\bsubject-rating\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
        let rating = "";
        let review_count = 0;

        // Extract rating score only when Douban exposes a score-like number.
        // Unrated books often only show review counts, which should not become ratings.
        const scoreMatch = ratingRaw.match(/(?:评分|rating_num[^>]*>|rating_nums?[^>]*>|\b)(10(?:\.0)?|[0-9]\.[0-9])(?:\b|<)/i);
        if (scoreMatch) rating = scoreMatch[1];

        // Extract review count (e.g. "(380人评价)")
        const reviewMatch = ratingRaw.match(/\((\d+)人评价\)/);
        if (reviewMatch) review_count = parseInt(reviewMatch[1], 10) || 0;

        // Tags / genre (from div.subject-tags span)
        const tagText = matchText(el, /<div\b[^>]*class=["'][^"']*\bsubject-tags\b[^"']*["'][^>]*>[\s\S]*?<span\b[^>]*>([\s\S]*?)<\/span>/i);
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
          source_rank: books.length + 1,
          source_page: page,
          scraped_at: scrapeStartedAt,
        });
      });
    }

    if (books.length === 0) {
      return new Response(
        JSON.stringify({ error: "未解析到任何书籍数据，豆瓣页面结构可能已变化" }),
        { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    // Keep the source order from Douban's latest pages. This page order changes
    // more naturally than review_count, which otherwise makes the same books stick.
    const latestBooks = books.slice(0, DOUBAN_LATEST_PAGES * 20);

    // Upsert into douban_new_books
    const { error: upsertError } = await sb
      .from("douban_new_books")
      .upsert(latestBooks, { onConflict: "douban_url", ignoreDuplicates: false });

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
        count: latestBooks.length,
        synced_count: latestBooks.length,
        display_count: DISPLAY_BOOKS_LIMIT,
        total_parsed: books.length,
        cleaned: idsToDelete.length,
        warnings: pageWarnings,
        books: latestBooks,
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

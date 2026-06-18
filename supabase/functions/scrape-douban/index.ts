// Supabase Edge Function: Douban New Books Scraper
// Deploy: supabase functions deploy scrape-douban
// Set secret: supabase secrets set SB_SERVICE_ROLE_KEY=sb_xxx

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as cheerio from "npm:cheerio@1.0.0";

const DOUBAN_LATEST_URL = "https://book.douban.com/latest";
const SB_URL = "https://zugadhgezmqrnlwogomw.supabase.co";

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const force = body.force === true;

    const serviceRoleKey = Deno.env.get("SB_SERVICE_ROLE_KEY")!;

    if (!serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Server config missing: SB_SERVICE_ROLE_KEY" }),
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    const sb = createClient(SB_URL, serviceRoleKey);

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
            { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
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
        { status: 502, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
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

    // Parse both columns: fiction (first ul) and non-fiction (second ul with .pl20)
    const columns = [
      { selector: "ul.cover-col-4.clearfix li", type: "fiction" },
      { selector: 'ul.cover-col-4.pl20.clearfix li', type: "non-fiction" },
    ];

    for (const col of columns) {
      $(col.selector).each((_, el) => {
        const $el = $(el);

        const title = $el.find("h2 a").text().trim();
        const coverEl = $el.find("a.cover img");
        const cover_url = coverEl.attr("src") || "";
        const linkEl = $el.find("a.cover");
        const douban_url = linkEl.attr("href") || "";
        const infoRaw = $el.find("p.color-gray").text().trim();
        const ratingRaw = $el.find("p.rating").text().trim();
        const description = $el.find("p.detail").text().trim();

        if (!title) return;

        // Parse info line: "作者 / 译者 / 出版社 / 出版年 / 定价"
        const infoParts = infoRaw.split("/").map((s) => s.trim()).filter(Boolean);
        const author = infoParts[0] || "";
        // Translator detection: check if part 2 looks like a person name (Chinese 2-3 chars, not a year/number)
        let translator = "";
        const secondPart = infoParts[1] || "";
        const thirdPart = infoParts[2] || "";

        // Heuristic: if we have >=2 parts, part2 is likely translator (not a 4-digit year or price)
        const isPersonName = (s: string) => s.length <= 4 && !/^\d/.test(s) && !s.includes("元") && !s.includes("出版") && !s.includes("社");
        if (infoParts.length >= 3 && isPersonName(secondPart)) {
          translator = secondPart;
        }

        // Publisher is usually the part before year/price or a part containing 出版/社
        let publisher = "";
        for (let i = 1; i < infoParts.length; i++) {
          const p = infoParts[i];
          if (p.includes("出版") || p.includes("社") || p.includes("书局") || p.includes("书店")) {
            publisher = p;
            break;
          }
        }
        // Fallback: if no publisher found, use the part that doesn't look like author/translator/year/price
        if (!publisher && infoParts.length >= 3) {
          for (let i = infoParts.length - 1; i >= 0; i--) {
            const p = infoParts[i];
            if (p !== author && p !== translator && !/^\d{4}/.test(p) && !p.includes("元")) {
              publisher = p;
              break;
            }
          }
        }

        // Parse rating: "8.5 (1234人评价)" or just numbers
        let rating = "";
        let review_count = 0;
        const ratingMatch = ratingRaw.match(/([\d.]+)/);
        if (ratingMatch) {
          // Could be average rating or review count
          const nums = ratingRaw.match(/([\d.]+)/g);
          if (nums && nums.length >= 2) {
            rating = nums[0];
            review_count = parseInt(nums[1].replace(/\.\d+$/, ""), 10) || 0;
          } else if (nums && nums.length === 1) {
            rating = nums[0];
          }
        }

        books.push({
          title,
          cover_url,
          author: author || "",
          translator,
          publisher,
          description: description || "",
          douban_url,
          rating,
          review_count,
          fiction_type: col.type,
          scraped_at: new Date().toISOString(),
        });
      });
    }

    if (books.length === 0) {
      return new Response(
        JSON.stringify({ error: "未解析到任何书籍数据，豆瓣页面结构可能已变化" }),
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
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
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
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
      { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: "抓取失败", detail: message }),
      { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  }
});

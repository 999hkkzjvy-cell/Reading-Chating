// Supabase Edge Function: Fetch individual Douban book page metadata
// Deploy: supabase functions deploy fetch-douban-book

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as cheerio from "npm:cheerio@1.0.0";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function parseDoubanBookUrl(input: string) {
  let parsed: URL;
  try {
    parsed = new URL(input);
  } catch {
    return null;
  }
  if (!["http:", "https:"].includes(parsed.protocol)) return null;
  if (parsed.hostname !== "book.douban.com") return null;
  if (!parsed.pathname.startsWith("/subject/")) return null;
  return parsed.toString();
}

Deno.serve(async (req: Request) => {
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
    const { url } = await req.json();
    const doubanUrl = parseDoubanBookUrl(url || "");
    if (!doubanUrl) {
      return new Response(
        JSON.stringify({ error: "请提供有效的豆瓣链接" }),
        { status: 400, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    const res = await fetch(doubanUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "zh-CN,zh;q=0.9",
      },
      signal: AbortSignal.timeout(12000),
    });

    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: `豆瓣请求失败: HTTP ${res.status}` }),
        { status: 502, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
      );
    }

    const html = await res.text();
    const $ = cheerio.load(html);

    // Extract metadata
    const title = $("#wrapper h1 span").first().text().trim()
      || $('meta[property="og:title"]').attr("content") || "";

    const cover_url = $("#mainpic img").attr("src")
      || $('meta[property="og:image"]').attr("content") || "";

    // Author: find text in #info span after "作者" label
    let author = "";
    const infoText = $("#info").text();
    const authorMatch = infoText.match(/作者[\s:]*([^\n]+?)(?:出版社|出版年|译者|页数|装帧|ISBN|丛书|副标题|原作名)/);
    if (authorMatch) {
      author = authorMatch[1].trim().replace(/\/$/, "").trim();
    }
    if (!author) {
      // Fallback: first a in #info span .pl
      const authorLinks = $("#info span.pl")
        .filter((_, el) => $(el).text().includes("作者"))
        .nextAll("a").first().text().trim();
      if (authorLinks) author = authorLinks;
    }

    // Translator
    let translator = "";
    const translatorMatch = infoText.match(/译者[\s:]*([^\n]+?)(?:出版社|出版年|页数|装帧|ISBN|丛书|定价)/);
    if (translatorMatch) {
      translator = translatorMatch[1].trim().replace(/\/$/, "").trim();
    }

    // Publisher
    let publisher = "";
    const pubMatch = infoText.match(/出版社[\s:]*([^\n]+?)(?:出版年|译者|页数|装帧|ISBN|丛书|定价|$)/);
    if (pubMatch) {
      publisher = pubMatch[1].trim().replace(/\/$/, "").trim();
    }

    // Rating
    const rating = $(".rating_num").text().trim()
      || $('[property="v:average"]').text().trim() || "";

    // Review count
    let reviewCount = 0;
    const reviewText = $(".rating_people span").text().trim()
      || $('[property="v:votes"]').text().trim();
    const reviewMatch = reviewText.match(/(\d+)/);
    if (reviewMatch) reviewCount = parseInt(reviewMatch[1], 10) || 0;

    // Description / summary
    const description = $("#link-report .intro").text().trim()
      || $(".related_info .indent span").first().text().trim()
      || $('meta[property="og:description"]').attr("content") || "";

    // Page count
    let pages = "";
    const pagesMatch = infoText.match(/页数[\s:]*(\d+)/);
    if (pagesMatch) pages = pagesMatch[1];

    const result = {
      title: title || "",
      cover_url: cover_url || "",
      author: author || "",
      translator: translator || "",
      publisher: publisher || "",
      rating: rating || "",
      review_count: reviewCount,
      description: description?.slice(0, 200) || "",
      pages: pages || "",
      douban_url: doubanUrl,
      fetched_at: new Date().toISOString(),
    };

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SB_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (supabaseUrl && serviceRoleKey) {
      const sb = createClient(supabaseUrl, serviceRoleKey);
      await sb.from("douban_book_cache").upsert(result, { onConflict: "douban_url" });
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: result,
      }),
      { headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: "获取失败", detail: message }),
      { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
    );
  }
});

// Supabase Edge Function: Fetch individual Douban book page metadata
// Deploy: supabase functions deploy fetch-douban-book

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import * as cheerio from "npm:cheerio@1.0.0";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    const { url } = await req.json();
    if (!url || !url.includes("douban.com")) {
      return new Response(
        JSON.stringify({ error: "请提供有效的豆瓣链接" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    const res = await fetch(url, {
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
        { status: 502, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
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

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          title: title || "",
          cover_url: cover_url || "",
          author: author || "",
          translator: translator || "",
          publisher: publisher || "",
          rating: rating || "",
          review_count: reviewCount,
          description: description?.slice(0, 200) || "",
          pages: pages || "",
          douban_url: url,
          fetched_at: new Date().toISOString(),
        },
      }),
      { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: "获取失败", detail: message }),
      { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  }
});

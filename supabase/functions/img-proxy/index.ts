// Supabase Edge Function: Image Proxy (for Douban hotlink bypass)
// Deploy: supabase functions deploy img-proxy

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
      },
    });
  }

  try {
    const url = new URL(req.url).searchParams.get("url");
    if (!url) {
      return new Response("Missing url parameter", { status: 400 });
    }

    // Only allow Douban CDN
    if (!url.includes("doubanio.com")) {
      return new Response("Only doubanio.com URLs allowed", { status: 403 });
    }

    const img = await fetch(url, {
      headers: {
        "Referer": "https://book.douban.com/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      },
      signal: AbortSignal.timeout(10000),
    });

    if (!img.ok) {
      return new Response("Image fetch failed: " + img.status, { status: 502 });
    }

    const contentType = img.headers.get("Content-Type") || "image/jpeg";

    return new Response(img.body, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=86400",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (err) {
    return new Response("Proxy error: " + (err instanceof Error ? err.message : String(err)), {
      status: 500,
    });
  }
});

// Supabase Edge Function: Image Proxy (for Douban hotlink bypass)
// Deploy: supabase functions deploy img-proxy

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, Authorization, Content-Type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function parseAllowedImageUrl(input: string) {
  let parsed: URL;
  try {
    parsed = new URL(input);
  } catch {
    return null;
  }
  if (!["http:", "https:"].includes(parsed.protocol)) return null;
  const hostname = parsed.hostname.toLowerCase();
  if (hostname !== "doubanio.com" && !hostname.endsWith(".doubanio.com")) return null;
  return parsed.toString();
}

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: CORS_HEADERS,
    });
  }

  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405, headers: CORS_HEADERS });
  }

  try {
    const url = new URL(req.url).searchParams.get("url");
    if (!url) {
      return new Response("Missing url parameter", { status: 400 });
    }

    // Only allow Douban CDN
    const imageUrl = parseAllowedImageUrl(url);
    if (!imageUrl) {
      return new Response("Only doubanio.com URLs allowed", { status: 403 });
    }

    const img = await fetch(imageUrl, {
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
    if (!contentType.toLowerCase().startsWith("image/")) {
      return new Response("Unsupported content type", { status: 415 });
    }

    return new Response(img.body, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=86400",
        ...CORS_HEADERS,
      },
    });
  } catch (err) {
    return new Response("Proxy error: " + (err instanceof Error ? err.message : String(err)), {
      status: 500,
    });
  }
});

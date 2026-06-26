// Supabase Edge Function: DeepSeek API Proxy
// Deploy: supabase functions deploy deepseek-proxy
// Set secret: supabase secrets set DEEPSEEK_API_KEY=sk-xxx

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const DEEPSEEK_API_URL = "https://api.deepseek.com/v1/chat/completions";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function requireAdmin(req: Request) {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace(/^Bearer\s+/i, "");
  if (!token) return { ok: false, status: 401, error: "Unauthorized" };

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SB_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return { ok: false, status: 500, error: "Server config missing: SUPABASE_URL or service role key" };
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: userData, error: userError } = await adminClient.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return { ok: false, status: 401, error: "Invalid session" };

  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || profile?.role !== "admin") return { ok: false, status: 403, error: "Admin only" };
  return { ok: true, status: 200, error: "" };
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
    const adminCheck = await requireAdmin(req);
    if (!adminCheck.ok) {
      return new Response(JSON.stringify({ error: adminCheck.error }), {
        status: adminCheck.status,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      });
    }

    const body = await req.json();
    const { title, author } = body;

    if (!title || !author) {
      return new Response(JSON.stringify({ error: "Missing title or author" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      });
    }

    const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "API key not configured" }), {
        status: 500,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      });
    }

    const prompt = `请根据以下书籍信息，用中文生成内容。返回纯JSON格式，不要markdown代码块。

书名：《${title}》
作者：${author}

请生成以下三个字段：

1. 书籍简介（400-800字），可包括：书籍类型与文学流派、核心主题和思想、重要术语/概念解释、与其他作品的关联、成书过程中有趣的轶事。但避免透露具体情节转折、人物命运和故事结局。

2. 作者简介（400-800字），可包括：生卒年及重要生平事件、写作本书时的年龄和状态、主要成就（代表作品、获奖等）、写作风格特点、重要相关名人及关系。但避免透露具体情节转折、人物命运和故事结局。

3. 创作时代背景（300-600字），可包括：成书年代及出版年代的社会政治环境、经济文化背景、当时的文学/思想潮流、这些因素对作品的影响。但避免透露具体情节转折、人物命运和故事结局。

返回格式：{"description":"...","author_bio":"...","historical_context":"..."}`;

    const response = await fetch(DEEPSEEK_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "deepseek-chat",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7,
        max_tokens: 4000,
      }),
    });

    if (!response.ok) {
      const errText = await response.text().catch(() => "");
      return new Response(JSON.stringify({ error: `DeepSeek API error: ${response.status} ${errText.slice(0, 200)}` }), {
        status: 502,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      });
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content || "";

    // Try to parse JSON from response
    let result;
    try {
      result = JSON.parse(content);
    } catch {
      const match = content.match(/\{[\s\S]*\}/);
      if (match) {
        try { result = JSON.parse(match[0]); } catch { result = null; }
      }
    }

    if (!result || !result.description) {
      return new Response(JSON.stringify({ error: "Failed to parse AI response", raw: content.slice(0, 500) }), {
        status: 500,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      });
    }

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: "Internal error", detail: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  }
});

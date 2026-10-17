const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const categories = [
  "Pol\u00c3\u00b3", "Gall\u00c3\u00a9ros", "K\u00c3\u00b6t\u00c3\u00b6tt pulcsi", "zipup", "farmer", "nadr\u00c3\u00a1g",
  "dzseki", "hoodie", "quarter zip", "short", "jort", "other",
];

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return jsonResponse({ error: "AI service is not configured" }, 500);

  try {
    const body = await request.json();
    const task = body.task;
    const imageBase64 = body.imageBase64;
    const mimeType = body.mimeType;

    if (task !== "inventory" && task !== "search") {
      return jsonResponse({ error: "Unsupported analysis task" }, 400);
    }
    if (typeof imageBase64 !== "string" || imageBase64.length === 0 || imageBase64.length > 12_000_000) {
      return jsonResponse({ error: "Image is missing or too large" }, 400);
    }
    if (mimeType !== "image/jpeg" && mimeType !== "image/png" && mimeType !== "image/webp") {
      return jsonResponse({ error: "Unsupported image type" }, 400);
    }

    const prompt = task === "inventory"
      ? `Analyze this clothing item in Hungarian. Choose ONE category from: ${categories.join(", ")}. Return a JSON object with name (string), brand (string), category (string), price (number), color (string), pattern (string), condition (string, e.g. 'Új', 'Kiváló', 'Használt'), and size (string).`
      : `Analyze this clothing item. Identify its category (choose EXACTLY ONE from: ${categories.join(", ")}), its main color in Hungarian, and its pattern in Hungarian. Return a JSON object with category (string), color (string), and pattern (string).`;

    const geminiResponse = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }, { inlineData: { mimeType, data: imageBase64 } }] }],
          generationConfig: { responseMimeType: "application/json" },
        }),
      },
    );

    if (!geminiResponse.ok) {
      console.error("Gemini request failed", geminiResponse.status, await geminiResponse.text());
      return jsonResponse({ error: "Image analysis failed" }, 502);
    }

    const geminiData = await geminiResponse.json();
    const text = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== "string") return jsonResponse({ error: "AI returned no analysis" }, 502);
    const result = JSON.parse(text);
    if (result === null || typeof result !== "object" || Array.isArray(result)) {
      return jsonResponse({ error: "AI returned an invalid analysis" }, 502);
    }
    return jsonResponse(result);
  } catch (error) {
    console.error("Gemini vision function error", error);
    return jsonResponse({ error: "Could not analyze image" }, 500);
  }
});

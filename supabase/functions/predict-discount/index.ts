import Anthropic from "npm:@anthropic-ai/sdk@^0.27";
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@^2";

// ── 환경변수 검증 (모듈 로드 시 1회) ──────────────────────────────────────────

const SUPABASE_URL     = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANTHROPIC_API_KEY) {
  throw new Error(
    "Missing required environment variables: "
    + "SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ANTHROPIC_API_KEY"
  );
}

// ── 싱글톤 클라이언트 (요청마다 재생성 X) ───────────────────────────────────

const supabaseAdmin: SupabaseClient = createClient(
  SUPABASE_URL
, SERVICE_ROLE_KEY
, { auth: { persistSession: false } }
);

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

// ── Types ────────────────────────────────────────────────────────────────────

interface DiscountRecord {
  brand_id: string;
  start_date: string;
  end_date: string;
  discount_rate: number;
}

interface PredictionResult {
  brand_id: string;
  start_date: string;
  end_date: string;
  discount_rate: number;
  confidence: number;
  reasoning: string;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── CORS 헤더 ─────────────────────────────────────────────────────────────────

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin":  "*"           // 배포 시 실제 도메인으로 교체
, "Access-Control-Allow-Methods": "POST, OPTIONS"
, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }

  try {
    // ── 1. 요청 파싱 및 brand_id 검증 ─────────────────────────────────────
    // 일반 앱 사용자(비로그인)도 사용 가능 — anon key JWT로 호출됨
    const body = await req.json() as { brand_id?: string };
    const brand_id = body.brand_id?.trim() ?? "";

    if (!brand_id) {
      return errorResponse("brand_id is required", 400);
    }
    if (!UUID_RE.test(brand_id)) {
      return errorResponse("brand_id must be a valid UUID", 400);
    }

    // ── 2. 과거 할인 이력 조회 (service role로 RLS 우회) ─────────────────
    const { data: history, error: dbError } = await supabaseAdmin
      .from("discount_history")
      .select("brand_id, start_date, end_date, discount_rate")
      .eq("brand_id", brand_id)
      .eq("is_ai_predicted", false)
      .order("start_date", { ascending: true });

    if (dbError) return errorResponse(dbError.message, 500);
    if (!history || history.length === 0) {
      return errorResponse("No discount history found for this brand", 404);
    }

    // ── 3. Claude API로 다음 할인 예측 ───────────────────────────────────
    const historyText = (history as DiscountRecord[])
      .map((h) =>
        `- 시작: ${h.start_date}, 종료: ${h.end_date}`
        + `, 할인율: ${Math.round(h.discount_rate * 100)}%`
      )
      .join("\n");

    const prompt =
      `아래는 특정 브랜드의 과거 할인 이력입니다.\n\n${historyText}\n\n`
      + "위 패턴을 분석하여 다음 할인이 언제 시작되고 끝날지, "
      + "그리고 예상 할인율을 예측해줘.\n"
      + "반드시 아래 JSON 형식만 반환해. 다른 설명은 절대 포함하지 마.\n\n"
      + "{\n"
      + '  "start_date": "YYYY-MM-DD",\n'
      + '  "end_date": "YYYY-MM-DD",\n'
      + '  "discount_rate": 0.00,\n'
      + '  "confidence": 0.00,\n'
      + '  "reasoning": "한 문장 근거"\n'
      + "}";

    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5"   // 짧은 예측 작업엔 Haiku가 비용 효율적
    , max_tokens: 256
    , messages: [{ role: "user", content: prompt }]
    });

    const raw = (message.content[0] as { type: string; text: string }).text.trim();
    const jsonStr = raw
      .replace(/^```(?:json)?\n?/, "")
      .replace(/\n?```$/, "")
      .trim();

    const parsed = JSON.parse(jsonStr);

    // ── 4. 응답 검증 및 범위 보정 ─────────────────────────────────────────
    const startDate = String(parsed.start_date ?? "");
    const endDate   = String(parsed.end_date ?? "");

    if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate)) {
      return errorResponse("Claude returned invalid date format", 502);
    }
    if (new Date(endDate) < new Date(startDate)) {
      return errorResponse("Claude returned end_date before start_date", 502);
    }

    const result: PredictionResult = {
      brand_id
    , start_date: startDate
    , end_date: endDate
      // LLM이 범위 밖 값을 반환할 수 있으므로 [0, 1]로 클램핑
    , discount_rate: Math.min(1, Math.max(0, Number(parsed.discount_rate ?? 0)))
    , confidence:    Math.min(1, Math.max(0, Number(parsed.confidence    ?? 0.7)))
    , reasoning: String(parsed.reasoning ?? "")
    };

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json", ...CORS_HEADERS }
    });

  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return errorResponse(message, 500);
  }
});

// ── Helper ───────────────────────────────────────────────────────────────────

function errorResponse(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message })
  , { status, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
  );
}

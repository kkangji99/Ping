import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Anthropic from 'https://esm.sh/@anthropic-ai/sdk@0.27.3';

// ── 상수 ─────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*'
, 'Access-Control-Allow-Headers': 'authorization, content-type'
, 'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const CRAWL_TIMEOUT_MS = 15_000;  // 브랜드당 최대 15초
const MAX_HTML_CHARS   = 12_000;  // Claude에 보낼 HTML 최대 길이

// ── 싱글턴 클라이언트 ─────────────────────────────────────────────────────────

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!
, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY')! });

// ── 타입 ─────────────────────────────────────────────────────────────────────

interface Brand {
  id:        string;
  name:      string;
  crawl_url: string;
}

interface DiscountInfo {
  discount_rate: number;   // 0.0 ~ 1.0
  start_date:    string;   // YYYY-MM-DD
  end_date:      string;   // YYYY-MM-DD
  description?:  string;
}

// ── 메인 핸들러 ───────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  const results: Record<string, string> = {};

  try {
    // crawl_url이 있는 브랜드 목록 조회
    const { data: brands, error } = await supabaseAdmin
      .from('brands')
      .select('id, name, crawl_url')
      .not('crawl_url', 'is', null)
      .neq('crawl_url', '');

    if (error) throw error;
    if (!brands || brands.length === 0) {
      return new Response(JSON.stringify({ message: '크롤링할 브랜드 없음' }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
      });
    }

    // 브랜드별 순차 처리 (병렬 시 타임아웃 위험)
    for (const brand of brands as Brand[]) {
      try {
        const discounts = await crawlBrand(brand);
        if (discounts.length > 0) {
          await saveDiscounts(brand.id, discounts);
          results[brand.name] = `${discounts.length}건 저장`;
        } else {
          results[brand.name] = '할인 정보 없음';
        }
      } catch (e) {
        results[brand.name] = `오류: ${(e as Error).message}`;
        console.error(`[crawl] ${brand.name} 실패:`, e);
      }
    }

    return new Response(JSON.stringify({ ok: true, results }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });

  } catch (e) {
    console.error('[crawl] 전체 오류:', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500
    , headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }
});

// ── 브랜드 크롤링 ─────────────────────────────────────────────────────────────

async function crawlBrand(brand: Brand): Promise<DiscountInfo[]> {
  const controller = new AbortController();
  const timer      = setTimeout(() => controller.abort(), CRAWL_TIMEOUT_MS);

  let html: string;
  try {
    const res = await fetch(brand.crawl_url, {
      signal:  controller.signal
    , headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; PingBot/1.0)'
      , 'Accept':     'text/html,application/xhtml+xml'
      , 'Accept-Language': 'ko-KR,ko;q=0.9'
      }
    });
    html = await res.text();
  } finally {
    clearTimeout(timer);
  }

  // HTML 정제 (스크립트·스타일 제거, 길이 제한)
  const cleanHtml = cleanHtmlContent(html);

  // Claude로 할인 정보 추출
  return await extractDiscounts(brand.name, cleanHtml);
}

// ── HTML 정제 ─────────────────────────────────────────────────────────────────

function cleanHtmlContent(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_HTML_CHARS);
}

// ── Claude AI 할인 정보 추출 ──────────────────────────────────────────────────

async function extractDiscounts(
  brandName: string
, content:   string
): Promise<DiscountInfo[]> {
  const today     = new Date().toISOString().slice(0, 10);
  const twoMonths = new Date(Date.now() + 60 * 24 * 3600 * 1000).toISOString().slice(0, 10);

  const message = await anthropic.messages.create({
    model:      'claude-haiku-4-5'
  , max_tokens: 1024
  , messages: [{
      role:    'user'
    , content: `브랜드 "${brandName}"의 웹페이지 내용입니다. 현재 진행 중이거나 예정된 할인/세일 정보를 추출해주세요.

오늘 날짜: ${today}

웹페이지 내용:
${content}

다음 JSON 형식으로만 응답하세요 (다른 텍스트 없이):
{
  "discounts": [
    {
      "discount_rate": 0.3,
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD",
      "description": "할인 설명"
    }
  ]
}

규칙:
- discount_rate는 0.0~1.0 사이 소수 (30% → 0.30)
- 날짜가 명시되지 않으면 오늘부터 2주 후로 추정: start="${today}", end="${twoMonths}"
- 할인 정보가 없으면 discounts를 빈 배열로
- 최대 3개까지만 추출`
    }]
  });

  const text = message.content[0].type === 'text' ? message.content[0].text : '';

  try {
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return [];

    const parsed = JSON.parse(jsonMatch[0]) as { discounts: DiscountInfo[] };
    return (parsed.discounts ?? []).filter(validateDiscount);
  } catch {
    console.error('[extract] JSON 파싱 실패:', text);
    return [];
  }
}

// ── 할인 정보 유효성 검사 ─────────────────────────────────────────────────────

function validateDiscount(d: DiscountInfo): boolean {
  if (!d.discount_rate || !d.start_date || !d.end_date) return false;
  if (d.discount_rate <= 0 || d.discount_rate > 1)     return false;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d.start_date))      return false;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d.end_date))        return false;
  if (d.end_date < d.start_date)                        return false;
  return true;
}

// ── DB 저장 (중복 방지) ───────────────────────────────────────────────────────

async function saveDiscounts(
  brandId:   string
, discounts: DiscountInfo[]
): Promise<void> {
  for (const d of discounts) {
    // 같은 기간 데이터가 이미 있으면 스킵 (중복 방지)
    const { data: existing } = await supabaseAdmin
      .from('discount_history')
      .select('id')
      .eq('brand_id', brandId)
      .eq('start_date', d.start_date)
      .eq('is_ai_predicted', false)
      .maybeSingle();

    if (existing) continue;

    await supabaseAdmin.from('discount_history').insert({
      brand_id:       brandId
    , start_date:     d.start_date
    , end_date:       d.end_date
    , discount_rate:  Math.min(Math.max(d.discount_rate, 0), 1)
    , is_ai_predicted: false
    });
  }
}

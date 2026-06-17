import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── 상수 ─────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*'
, 'Access-Control-Allow-Headers': 'authorization, content-type'
, 'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const CRAWL_TIMEOUT_MS = 15_000;
const MAX_HTML_CHARS   = 5_000;

// ── 싱글턴 클라이언트 ─────────────────────────────────────────────────────────

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!
, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// ── 타입 ─────────────────────────────────────────────────────────────────────

interface Brand {
  id:        string;
  name:      string;
  crawl_url: string;
}

interface DiscountInfo {
  discount_rate: number;
  start_date:    string;
  end_date:      string;
}

interface HistoricalDiscount {
  start_date:    string;
  end_date:      string;
  discount_rate: number;
}

// ── 메인 핸들러 ───────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
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

    // 모든 브랜드 병렬 크롤링
    const crawlResults = await Promise.allSettled(
      (brands as Brand[]).map(async (brand) => ({
        brand
      , text: cleanHtml(await fetchHtml(brand.crawl_url))
      }))
    );

    const results: Record<string, string> = {};

    for (let i = 0; i < (brands as Brand[]).length; i++) {
      const brand = (brands as Brand[])[i];
      const crawl = crawlResults[i];

      if (crawl.status === 'rejected') {
        results[brand.name] = `크롤링 실패`;
        continue;
      }

      const { text } = crawl.value;
      const msgs: string[] = [];

      try {
        // 1단계: 현재 할인 추출
        const realDiscounts = extractCurrentDiscounts(text);
        if (realDiscounts.length > 0) {
          await saveDiscounts(brand.id, realDiscounts, false);
          msgs.push(`실제 ${realDiscounts.length}건`);
        }

        // brands.is_discounting을 실제 데이터 기반으로 업데이트
        await supabaseAdmin
          .from('brands')
          .update({ is_discounting: realDiscounts.length > 0 })
          .eq('id', brand.id);

        // 2단계: 과거 이력 기반 예측 (이력 있을 때만)
        const history = await fetchHistory(brand.id);
        if (history.length >= 2) {
          const predictions = predictDiscounts(history);
          if (predictions.length > 0) {
            await saveDiscounts(brand.id, predictions, true);
            msgs.push(`예측 ${predictions.length}건`);
          }
        }

        results[brand.name] = msgs.length > 0 ? msgs.join(' / ') : '정보 없음';
      } catch (e) {
        results[brand.name] = `오류: ${(e as Error).message}`;
      }
    }

    return new Response(JSON.stringify({ ok: true, results }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });

  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500
    , headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }
});

// ── HTML 크롤링 ───────────────────────────────────────────────────────────────

async function fetchHtml(url: string): Promise<string> {
  const controller = new AbortController();
  const timer      = setTimeout(() => controller.abort(), CRAWL_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal:  controller.signal
    , headers: {
        'User-Agent':      'Mozilla/5.0 (compatible; PingBot/1.0)'
      , 'Accept':          'text/html,application/xhtml+xml'
      , 'Accept-Language': 'ko-KR,ko;q=0.9'
      }
    });
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

function cleanHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_HTML_CHARS);
}

// ── 1단계: 현재 할인 추출 ─────────────────────────────────────────────────────
// 조건: 구체적인 퍼센트 할인율 + 날짜 범위가 모두 있어야 기록
// 단순 세일 키워드만으로는 기록하지 않음 (오탐 방지)

const RATE_PATTERNS = [
  /(\d{1,2})(?:~\d{1,2})?%\s*(?:할인|세일|OFF|off|DC)/g
, /최대\s*(\d{1,2})%\s*(?:할인|세일|OFF)/g
, /(\d{1,2})%\s*(?:추가|즉시)\s*할인/g
];

// 날짜 패턴: "6/1~6/30", "06.01~06.30", "2026-06-01~2026-06-30" 등
const DATE_RANGE_PATTERNS = [
  /(\d{1,2})[./](\d{1,2})\s*[~\-–]\s*(\d{1,2})[./](\d{1,2})/g   // 6/1~6/30
, /(\d{4})[.\-](\d{2})[.\-](\d{2})\s*[~\-–]\s*(\d{4})[.\-](\d{2})[.\-](\d{2})/g  // 2026-06-01~2026-06-30
];

function extractCurrentDiscounts(text: string): DiscountInfo[] {
  // 할인율 추출
  let maxRate = 0;
  for (const pattern of RATE_PATTERNS) {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const rate = parseInt(match[1]);
      if (rate > maxRate && rate >= 5 && rate <= 70) maxRate = rate;
    }
  }

  // 할인율 없으면 기록 안 함
  if (maxRate === 0) return [];

  // 날짜 범위 추출 시도
  const today    = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  let startDate  = todayStr;
  let endDate    = addDays(todayStr, 14);

  // ISO 날짜 범위 (2026-06-01~2026-06-30)
  const isoPattern = /(\d{4})[.\-](\d{2})[.\-](\d{2})\s*[~\-–]\s*(\d{4}[.\-]\d{2}[.\-]\d{2})/g;
  const isoMatch   = isoPattern.exec(text);
  if (isoMatch) {
    const sd = `${isoMatch[1]}-${isoMatch[2]}-${isoMatch[3]}`;
    const edRaw = isoMatch[4].replace(/\./g, '-');
    if (sd >= todayStr) {
      startDate = sd;
      endDate   = edRaw;
    }
  } else {
    // 월/일 범위 (6/1~6/30)
    const shortPattern = /(\d{1,2})[./](\d{1,2})\s*[~\-–]\s*(\d{1,2})[./](\d{1,2})/g;
    const shortMatch   = shortPattern.exec(text);
    if (shortMatch) {
      const year = today.getFullYear();
      const sm   = String(shortMatch[1]).padStart(2, '0');
      const sd_d = String(shortMatch[2]).padStart(2, '0');
      const em   = String(shortMatch[3]).padStart(2, '0');
      const ed_d = String(shortMatch[4]).padStart(2, '0');
      const sd   = `${year}-${sm}-${sd_d}`;
      const ed   = `${year}-${em}-${ed_d}`;
      // 날짜가 합리적 범위면 사용
      if (sd <= addDays(todayStr, 7) && ed >= todayStr) {
        startDate = sd >= todayStr ? sd : todayStr;
        endDate   = ed;
      }
    }
  }

  // end_date가 start_date 이전이면 무시
  if (endDate < startDate) return [];

  return [{
    discount_rate: parseFloat((maxRate / 100).toFixed(2))
  , start_date:    startDate
  , end_date:      endDate
  }];
}

// ── 2단계: 과거 이력 조회 ────────────────────────────────────────────────────

async function fetchHistory(brandId: string): Promise<HistoricalDiscount[]> {
  const { data } = await supabaseAdmin
    .from('discount_history')
    .select('start_date, end_date, discount_rate')
    .eq('brand_id', brandId)
    .eq('is_ai_predicted', false)
    .order('start_date', { ascending: false })
    .limit(20);

  return (data ?? []) as HistoricalDiscount[];
}

// ── 3단계: 이력 기반 예측 (이력 있을 때만, 시즌 폴백 없음) ─────────────────────

function predictDiscounts(history: HistoricalDiscount[]): DiscountInfo[] {
  const today    = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  const results: DiscountInfo[] = [];

  // 월별 출현 횟수·평균 할인율 집계
  const monthStats: Record<number, { count: number; totalRate: number }> = {};
  for (const h of history) {
    const month = new Date(h.start_date).getMonth();
    if (!monthStats[month]) monthStats[month] = { count: 0, totalRate: 0 };
    monthStats[month].count++;
    monthStats[month].totalRate += h.discount_rate;
  }

  // 향후 3개월 순회 → 패턴 있는 달만 예측
  for (let offset = 1; offset <= 3; offset++) {
    const futureDate = new Date(today);
    futureDate.setMonth(today.getMonth() + offset);
    const month = futureDate.getMonth();
    const stats = monthStats[month];
    if (!stats || stats.count < 2) continue;

    const y       = futureDate.getFullYear();
    const m       = String(month + 1).padStart(2, '0');
    const sd      = `${y}-${m}-01`;
    const ed      = `${y}-${m}-${lastDay(y, month)}`;
    const avgRate = stats.totalRate / stats.count;

    // 실제 이력과 겹치면 스킵
    if (sd <= todayStr) continue;
    if (overlapsHistory(sd, ed, history)) continue;

    results.push({
      discount_rate: parseFloat(avgRate.toFixed(2))
    , start_date:    sd
    , end_date:      ed
    });
  }

  return results.slice(0, 2);
}

function overlapsHistory(sd: string, ed: string, history: HistoricalDiscount[]): boolean {
  return history.some(h => ed >= h.start_date && sd <= h.end_date);
}

// ── 날짜 유틸 ─────────────────────────────────────────────────────────────────

function lastDay(year: number, month: number): string {
  return String(new Date(year, month + 1, 0).getDate()).padStart(2, '0');
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// ── DB 저장 ───────────────────────────────────────────────────────────────────

async function saveDiscounts(
  brandId:     string
, discounts:   DiscountInfo[]
, isPredicted: boolean
): Promise<void> {
  for (const d of discounts) {
    // 동일 기간 중복 체크 (start_date + brand_id + is_ai_predicted)
    const { data: existing } = await supabaseAdmin
      .from('discount_history')
      .select('id')
      .eq('brand_id', brandId)
      .eq('start_date', d.start_date)
      .eq('is_ai_predicted', isPredicted)
      .maybeSingle();

    if (existing) continue;

    await supabaseAdmin.from('discount_history').insert({
      brand_id:        brandId
    , start_date:      d.start_date
    , end_date:        d.end_date
    , discount_rate:   Math.min(Math.max(d.discount_rate, 0.01), 1)
    , is_ai_predicted: isPredicted
    });
  }
}

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── 상수 ─────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*'
, 'Access-Control-Allow-Headers': 'authorization, content-type'
, 'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const CRAWL_TIMEOUT_MS = 15_000;
const MAX_SMART_CHARS  = 15_000;

// ── Supabase 클라이언트 ────────────────────────────────────────────────────────

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
  label?:        string;
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
      , html: await fetchHtml(brand.crawl_url)
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

      const { html } = crawl.value;
      const msgs: string[] = [];

      try {
        // 1단계: 현재 할인 추출 (JSON-LD → 스마트 텍스트 순)
        const realDiscounts = extractAllDiscounts(html);
        if (realDiscounts.length > 0) {
          await saveDiscounts(brand.id, realDiscounts, false);
          msgs.push(`실제 ${realDiscounts.length}건`);
        }

        // brands.is_discounting 업데이트
        await supabaseAdmin
          .from('brands')
          .update({ is_discounting: realDiscounts.length > 0 })
          .eq('id', brand.id);

        // 2단계: 과거 이력 기반 예측
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
        'User-Agent':      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      , 'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      , 'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8'
      , 'Accept-Encoding': 'gzip, deflate, br'
      }
    });
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

// ── 통합 할인 추출 (JSON-LD 우선 → 스마트 텍스트 폴백) ──────────────────────────

function extractAllDiscounts(html: string): DiscountInfo[] {
  // 1순위: JSON-LD 구조화 데이터
  const jsonLdDiscounts = extractJsonLdDiscounts(html);
  if (jsonLdDiscounts.length > 0) return jsonLdDiscounts;

  // 2순위: 스마트 텍스트 추출 + 패턴 매칭
  const text = extractSmartText(html);
  return extractTextDiscounts(text);
}

// ── JSON-LD 구조화 데이터 파싱 ────────────────────────────────────────────────

function extractJsonLdDiscounts(html: string): DiscountInfo[] {
  const results: DiscountInfo[] = [];
  const scriptRe = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;

  while ((m = scriptRe.exec(html)) !== null) {
    try {
      const data  = JSON.parse(m[1]);
      const items = Array.isArray(data) ? data : [data];
      for (const item of items) {
        const d = parseJsonLdItem(item);
        if (d) results.push(d);
        // @graph 배열 처리
        if (item['@graph'] && Array.isArray(item['@graph'])) {
          for (const sub of item['@graph']) {
            const sd = parseJsonLdItem(sub);
            if (sd) results.push(sd);
          }
        }
      }
    } catch { /* JSON 파싱 실패 무시 */ }
  }

  return deduplicateDiscounts(results);
}

function parseJsonLdItem(item: Record<string, unknown>): DiscountInfo | null {
  const todayStr = new Date().toISOString().slice(0, 10);
  const type     = (item['@type'] as string | undefined)?.toLowerCase() ?? '';

  // Offer 타입
  if (type.includes('offer')) {
    const validFrom    = extractDateStr(item['validFrom']);
    const validThrough = extractDateStr(item['validThrough']) ?? extractDateStr(item['priceValidUntil']);
    const discount     = extractRateFromValue(item['discount'] ?? item['discountPercentage']);

    if (discount && validThrough && validThrough >= todayStr) {
      return {
        discount_rate: discount
      , start_date:    validFrom ?? todayStr
      , end_date:      validThrough
      , label:         extractStrVal(item['name']) ?? extractStrVal(item['description']) ?? undefined
      };
    }
  }

  // SaleEvent 타입
  if (type.includes('saleevent') || type.includes('event')) {
    const startDate = extractDateStr(item['startDate']);
    const endDate   = extractDateStr(item['endDate']);
    const name      = extractStrVal(item['name']);

    if (startDate && endDate && endDate >= todayStr && name) {
      const rate = extractRateFromText(name);
      if (rate) {
        return {
          discount_rate: rate
        , start_date:    startDate
        , end_date:      endDate
        , label:         name
        };
      }
    }
  }

  return null;
}

function extractDateStr(val: unknown): string | null {
  if (!val) return null;
  const m = String(val).match(/(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : null;
}

function extractStrVal(val: unknown): string | null {
  if (!val) return null;
  return String(val).trim().slice(0, 40) || null;
}

function extractRateFromValue(val: unknown): number | null {
  if (!val) return null;
  const n = parseFloat(String(val));
  if (isNaN(n)) return null;
  if (n >= 5 && n <= 70) return parseFloat((n / 100).toFixed(2));
  if (n > 0 && n < 1)    return n;
  return null;
}

// ── 스마트 HTML 텍스트 추출 ────────────────────────────────────────────────────

function extractSmartText(html: string): string {
  const parts: string[] = [];

  // 1. <title>
  const titleM = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (titleM) parts.push(stripTags(titleM[1]));

  // 2. <meta name="description">
  const metaM = html.match(/<meta[^>]*name=["']description["'][^>]*content=["']([^"']{0,300})/i)
             ?? html.match(/<meta[^>]*content=["']([^"']{0,300})[^>]*name=["']description["']/i);
  if (metaM) parts.push(metaM[1]);

  // 3. <meta property="og:description">
  const ogM = html.match(/<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']{0,300})/i);
  if (ogM) parts.push(ogM[1]);

  // 4. h1~h4 헤딩 (최대 30개)
  const headingRe = /<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/gi;
  let hm: RegExpExecArray | null;
  let hCount = 0;
  while ((hm = headingRe.exec(html)) !== null && hCount++ < 30) {
    const t = stripTags(hm[1]);
    if (t.length > 2) parts.push(t);
  }

  // 5. sale/discount 관련 클래스·ID를 가진 요소 (최대 20개)
  const saleRe = /<(?:div|section|article|span|p|li|a|button)[^>]*(?:class|id)=["'][^"']*(?:sale|discount|event|promo|offer|banner|세일|할인|이벤트|특가|프로모|행사)[^"']*["'][^>]*>([\s\S]{0,600}?)<\/(?:div|section|article|span|p|li|a|button)>/gi;
  let sm: RegExpExecArray | null;
  let sCount = 0;
  while ((sm = saleRe.exec(html)) !== null && sCount++ < 20) {
    const t = stripTags(sm[1]);
    if (t.length > 5) parts.push(t);
  }

  // 6. 일반 텍스트 폴백
  const generalText = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  parts.push(generalText.slice(0, 9_000));

  return parts.join('\n').slice(0, MAX_SMART_CHARS);
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

// ── 텍스트에서 복수 할인 추출 ─────────────────────────────────────────────────

const RATE_PATTERNS = [
  /(?:최대\s*)?(\d{1,2})(?:~\d{1,2})?%\s*(?:할인|세일|OFF|off|DC)/g
, /(\d{1,2})%\s*(?:추가|즉시)\s*할인/g
, /(\d{1,2})%\s*(?:쿠폰|적립|캐시백)/g
, /(\d{1,2})%\s*(?:UP|up)\s*할인/g
];

interface DateRange { start: string; end: string; }

function findNearbyDateRange(text: string, pos: number): DateRange | null {
  const today    = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  const window   = text.slice(Math.max(0, pos - 400), pos + 400);

  // ISO: 2026-06-01 ~ 2026-06-30
  const isoRe = /(\d{4})[.\-](\d{2})[.\-](\d{2})\s*[~\-–]\s*(\d{4})[.\-](\d{2})[.\-](\d{2})/;
  const isoM  = isoRe.exec(window);
  if (isoM) {
    const sd = `${isoM[1]}-${isoM[2]}-${isoM[3]}`;
    const ed = `${isoM[4]}-${isoM[5]}-${isoM[6]}`;
    if (ed >= todayStr && sd <= addDays(todayStr, 60)) {
      return { start: sd >= todayStr ? sd : todayStr, end: ed };
    }
  }

  // 단축: 6/1~6/30 또는 06.01~06.30
  const shortRe = /(\d{1,2})[./](\d{1,2})\s*[~\-–]\s*(\d{1,2})[./](\d{1,2})/;
  const shortM  = shortRe.exec(window);
  if (shortM) {
    const y    = today.getFullYear();
    const sd   = `${y}-${String(shortM[1]).padStart(2,'0')}-${String(shortM[2]).padStart(2,'0')}`;
    const ed   = `${y}-${String(shortM[3]).padStart(2,'0')}-${String(shortM[4]).padStart(2,'0')}`;
    if (ed >= todayStr && sd <= addDays(todayStr, 60)) {
      return { start: sd >= todayStr ? sd : todayStr, end: ed };
    }
  }

  // 한국어: 6월 1일 ~ 6월 30일
  const koRe = /(\d{1,2})월\s*(\d{1,2})일\s*[~\-–]\s*(\d{1,2})월\s*(\d{1,2})일/;
  const koM  = koRe.exec(window);
  if (koM) {
    const y  = today.getFullYear();
    const sd = `${y}-${String(koM[1]).padStart(2,'0')}-${String(koM[2]).padStart(2,'0')}`;
    const ed = `${y}-${String(koM[3]).padStart(2,'0')}-${String(koM[4]).padStart(2,'0')}`;
    if (ed >= todayStr) return { start: sd >= todayStr ? sd : todayStr, end: ed };
  }

  // 한국어: ~6월 30일 (종료일만)
  const koEndRe = /[~\-–]\s*(\d{1,2})월\s*(\d{1,2})일/;
  const koEndM  = koEndRe.exec(window);
  if (koEndM) {
    const y  = today.getFullYear();
    const ed = `${y}-${String(koEndM[1]).padStart(2,'0')}-${String(koEndM[2]).padStart(2,'0')}`;
    if (ed >= todayStr) return { start: todayStr, end: ed };
  }

  // 한국어: N월 한달 / N월 내내
  const koMonthRe = /(\d{1,2})월\s*(?:한달간?|내내|동안|전체|전월)/;
  const koMonthM  = koMonthRe.exec(window);
  if (koMonthM) {
    const y = today.getFullYear();
    const mo = parseInt(koMonthM[1]);
    const m  = String(mo).padStart(2,'0');
    const sd = `${y}-${m}-01`;
    const ed = `${y}-${m}-${lastDay(y, mo - 1)}`;
    if (ed >= todayStr) return { start: sd >= todayStr ? sd : todayStr, end: ed };
  }

  return null;
}

function findNearbyLabel(text: string, pos: number): string | undefined {
  const before = text.slice(Math.max(0, pos - 150), pos);
  const labelRe = /([가-힣a-zA-Z0-9][가-힣a-zA-Z0-9\s·\xd7]{1,25}(?:세일|이벤트|위크|페스타|데이|행사|특가|DAY|SALE|WEEK|FESTA|EVENT|FAIR|DAYS))/;
  const m = labelRe.exec(before);
  if (m) return m[1].trim().slice(0, 35);
  return undefined;
}

function extractRateFromText(text: string): number | null {
  for (const re of RATE_PATTERNS) {
    re.lastIndex = 0;
    const m = re.exec(text);
    if (m) {
      const rate = parseInt(m[1]);
      if (rate >= 5 && rate <= 70) return rate / 100;
    }
  }
  return null;
}

function extractTextDiscounts(text: string): DiscountInfo[] {
  const todayStr = new Date().toISOString().slice(0, 10);
  const results: DiscountInfo[] = [];

  for (const re of RATE_PATTERNS) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      const rate = parseInt(m[1]);
      if (rate < 5 || rate > 70) continue;

      const pos   = m.index;
      const dates = findNearbyDateRange(text, pos);
      if (!dates) continue;
      if (dates.end < todayStr) continue;

      const label = findNearbyLabel(text, pos);
      results.push({
        discount_rate: rate / 100
      , start_date:    dates.start
      , end_date:      dates.end
      , label
      });
    }
  }

  return deduplicateDiscounts(results).slice(0, 5);
}

function deduplicateDiscounts(discounts: DiscountInfo[]): DiscountInfo[] {
  const seen = new Set<string>();
  return discounts.filter(d => {
    const key = `${Math.round(d.discount_rate * 100)}-${d.start_date}-${d.end_date}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ── 과거 이력 조회 ────────────────────────────────────────────────────────────

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

// ── 이력 기반 예측 ────────────────────────────────────────────────────────────

function predictDiscounts(history: HistoricalDiscount[]): DiscountInfo[] {
  const today    = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  const results: DiscountInfo[] = [];

  const monthStats: Record<number, { count: number; totalRate: number }> = {};
  for (const h of history) {
    const month = new Date(h.start_date).getMonth();
    if (!monthStats[month]) monthStats[month] = { count: 0, totalRate: 0 };
    monthStats[month].count++;
    monthStats[month].totalRate += h.discount_rate;
  }

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
    , label:           d.label ?? null
    });
  }
}

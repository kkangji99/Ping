import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── 상수 ─────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*'
, 'Access-Control-Allow-Headers': 'authorization, content-type'
, 'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const FETCH_TIMEOUT_MS   = 10_000;
const STORAGE_BUCKET     = 'brand-logos';
const LOGOS_FOLDER       = 'logos';

// ── 싱글턴 ────────────────────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;

const supabaseAdmin = createClient(
  SUPABASE_URL
, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// ── 메인 핸들러 ───────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  const results: Record<string, string> = {};

  try {
    // crawl_url이 있는 브랜드 목록
    const { data: brands, error } = await supabaseAdmin
      .from('brands')
      .select('id, name, crawl_url, logo_url')
      .not('crawl_url', 'is', null)
      .neq('crawl_url', '');

    if (error) throw error;
    if (!brands || brands.length === 0) {
      return new Response(JSON.stringify({ message: '브랜드 없음' }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
      });
    }

    for (const brand of brands) {
      try {
        const storageUrl = await crawlAndUploadLogo(
          brand.id as string
        , brand.crawl_url as string
        );

        if (storageUrl && storageUrl !== brand.logo_url) {
          await supabaseAdmin
            .from('brands')
            .update({ logo_url: storageUrl })
            .eq('id', brand.id);
          results[brand.name] = storageUrl;
        } else {
          results[brand.name] = '변경 없음';
        }
      } catch (e) {
        results[brand.name] = `오류: ${(e as Error).message}`;
        console.error(`[logos] ${brand.name} 실패:`, e);
      }
    }

    return new Response(JSON.stringify({ ok: true, results }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });

  } catch (e) {
    console.error('[logos] 전체 오류:', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500
    , headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }
});

// ── 로고 크롤 + Storage 업로드 ────────────────────────────────────────────────

async function crawlAndUploadLogo(
  brandId: string
, siteUrl: string
): Promise<string | null> {
  // 1. 사이트에서 로고 URL 추출
  const logoUrl = await extractLogoUrl(siteUrl);
  if (!logoUrl) return null;

  // 2. 이미지 다운로드
  const imgRes = await fetchWithTimeout(logoUrl);
  if (!imgRes.ok) {
    throw new Error(`이미지 다운로드 실패: ${imgRes.status} ${logoUrl}`);
  }

  const contentType = imgRes.headers.get('content-type') ?? 'image/jpeg';
  // content-type 예: "image/png", "image/jpeg;charset=utf-8"
  const mimeBase = contentType.split(';')[0].trim();          // "image/png"
  const ext      = mimeToExt(mimeBase);                       // "png"

  const bytes    = new Uint8Array(await imgRes.arrayBuffer());
  const path     = `${LOGOS_FOLDER}/${brandId}.${ext}`;

  // 3. Supabase Storage 업로드 (upsert)
  const { error: uploadError } = await supabaseAdmin.storage
    .from(STORAGE_BUCKET)
    .upload(path, bytes, { contentType: mimeBase, upsert: true });

  if (uploadError) {
    throw new Error(`Storage 업로드 실패: ${uploadError.message}`);
  }

  // 4. public URL 반환
  const { data } = supabaseAdmin.storage
    .from(STORAGE_BUCKET)
    .getPublicUrl(path);

  return data.publicUrl;
}

// ── 로고 URL 추출 ─────────────────────────────────────────────────────────────

async function extractLogoUrl(siteUrl: string): Promise<string | null> {
  const res  = await fetchWithTimeout(siteUrl, { Accept: 'text/html' });
  const html = await res.text();

  // 우선순위: og:image → apple-touch-icon → favicon
  const ogImage = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)
                ?? html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  if (ogImage?.[1]) return resolveUrl(siteUrl, ogImage[1]);

  const touchIcon = html.match(/<link[^>]+apple-touch-icon[^>]+href=["']([^"']+)["']/i);
  if (touchIcon?.[1]) return resolveUrl(siteUrl, touchIcon[1]);

  const favicon = html.match(/<link[^>]+rel=["'][^"']*icon[^"']*["'][^>]+href=["']([^"']+)["']/i);
  if (favicon?.[1]) return resolveUrl(siteUrl, favicon[1]);

  return null;
}

// ── 유틸 ──────────────────────────────────────────────────────────────────────

async function fetchWithTimeout(
  url: string
, extraHeaders: Record<string, string> = {}
): Promise<Response> {
  const controller = new AbortController();
  const timer      = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, {
      signal:  controller.signal
    , headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; PingBot/1.0)'
      , ...extraHeaders
      }
    });
  } finally {
    clearTimeout(timer);
  }
}

function resolveUrl(base: string, path: string): string {
  if (path.startsWith('http')) return path;
  const origin = new URL(base).origin;
  return path.startsWith('/') ? `${origin}${path}` : `${origin}/${path}`;
}

function mimeToExt(mime: string): string {
  const map: Record<string, string> = {
    'image/jpeg':  'jpg'
  , 'image/jpg':   'jpg'
  , 'image/png':   'png'
  , 'image/webp':  'webp'
  , 'image/gif':   'gif'
  , 'image/svg+xml': 'svg'
  , 'image/x-icon':  'ico'
  , 'image/vnd.microsoft.icon': 'ico'
  };
  return map[mime] ?? 'jpg';
}

-- ============================================================
--  003_crawl_url_and_cron.sql
--  - brands 테이블에 crawl_url 컬럼 추가
--  - pg_cron + pg_net 익스텐션 활성화
--  - 매일 00:00, 12:00 KST 크롤링 스케줄 등록
-- ============================================================

-- ── 1. brands 테이블에 crawl_url 추가 ───────────────────────────

ALTER TABLE brands ADD COLUMN IF NOT EXISTS crawl_url text;

-- ── 2. 익스텐션 활성화 ──────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ── 3. 크롤링 스케줄 등록 ───────────────────────────────────────
-- KST 00:00 = UTC 15:00 (전날)
-- KST 12:00 = UTC 03:00

-- 기존 스케줄 있으면 제거
SELECT cron.unschedule('crawl-discounts-midnight') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'crawl-discounts-midnight'
);
SELECT cron.unschedule('crawl-discounts-noon') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'crawl-discounts-noon'
);

-- 자정 (KST 00:00 = UTC 15:00)
SELECT cron.schedule(
  'crawl-discounts-midnight'
, '0 15 * * *'
, $$
  SELECT net.http_post(
    url     := 'https://zwmlxypziqfvjibamrxs.supabase.co/functions/v1/crawl-discounts'
  , headers := jsonb_build_object(
        'Content-Type',  'application/json'
      , 'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      )
  , body    := '{}'::jsonb
  ) AS request_id;
  $$
);

-- 정오 (KST 12:00 = UTC 03:00)
SELECT cron.schedule(
  'crawl-discounts-noon'
, '0 3 * * *'
, $$
  SELECT net.http_post(
    url     := 'https://zwmlxypziqfvjibamrxs.supabase.co/functions/v1/crawl-discounts'
  , headers := jsonb_build_object(
        'Content-Type',  'application/json'
      , 'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      )
  , body    := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ── 4. 로고 크롤링 주간 스케줄 ──────────────────────────────────────
-- 매주 일요일 KST 12:00 = UTC 03:00

SELECT cron.unschedule('crawl-logos-weekly') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'crawl-logos-weekly'
);

SELECT cron.schedule(
  'crawl-logos-weekly'
, '0 3 * * 0'
, $$
  SELECT net.http_post(
    url     := 'https://zwmlxypziqfvjibamrxs.supabase.co/functions/v1/crawl-logos'
  , headers := jsonb_build_object(
        'Content-Type',  'application/json'
      , 'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      )
  , body    := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ============================================================
--  001_initial_schema.sql
--  Ping — AI 기반 브랜드 할인 예측 캘린더 앱
-- ============================================================

-- ── Extensions ──────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Tables ──────────────────────────────────────────────────

CREATE TABLE categories (
  id   uuid NOT NULL DEFAULT gen_random_uuid()
, name text NOT NULL
, CONSTRAINT categories_pkey PRIMARY KEY (id)
);

CREATE TABLE brands (
  id             uuid    NOT NULL DEFAULT gen_random_uuid()
, category_id   uuid    NOT NULL
, name          text    NOT NULL
, logo_url      text
, is_discounting boolean NOT NULL DEFAULT false
, CONSTRAINT brands_pkey             PRIMARY KEY (id)
, CONSTRAINT brands_category_id_fkey FOREIGN KEY (category_id)
    REFERENCES categories (id) ON DELETE CASCADE
);

CREATE TABLE discount_history (
  id              uuid          NOT NULL DEFAULT gen_random_uuid()
, brand_id        uuid          NOT NULL
, start_date      date          NOT NULL
, end_date        date          NOT NULL
, discount_rate   numeric(4, 2) NOT NULL
, is_ai_predicted boolean       NOT NULL DEFAULT false
, created_at      timestamptz   NOT NULL DEFAULT now()
, CONSTRAINT discount_history_pkey          PRIMARY KEY (id)
, CONSTRAINT discount_history_brand_fkey    FOREIGN KEY (brand_id)
    REFERENCES brands (id) ON DELETE CASCADE
, CONSTRAINT discount_history_rate_check
    CHECK (discount_rate >= 0 AND discount_rate <= 1)
, CONSTRAINT discount_history_date_check
    CHECK (end_date >= start_date)
);

CREATE TABLE user_favorites (
  id         uuid        NOT NULL DEFAULT gen_random_uuid()
, user_id    uuid        NOT NULL
, brand_id   uuid        NOT NULL
, created_at timestamptz NOT NULL DEFAULT now()
, CONSTRAINT user_favorites_pkey        PRIMARY KEY (id)
, CONSTRAINT user_favorites_user_fkey   FOREIGN KEY (user_id)
    REFERENCES auth.users (id) ON DELETE CASCADE
, CONSTRAINT user_favorites_brand_fkey  FOREIGN KEY (brand_id)
    REFERENCES brands (id) ON DELETE CASCADE
, CONSTRAINT user_favorites_unique      UNIQUE (user_id, brand_id)
);

-- ── Indexes ─────────────────────────────────────────────────

-- brands: 카테고리별 조회
CREATE INDEX idx_brands_category_id
    ON brands (category_id);

-- discount_history: 가장 빈번한 쿼리 패턴
--   WHERE brand_id = $1 AND is_ai_predicted = false ORDER BY start_date
--   Partial Index로 is_ai_predicted=false 행만 인덱싱 → 크기·속도 모두 개선
CREATE INDEX idx_discount_history_real
    ON discount_history (brand_id, start_date)
    WHERE is_ai_predicted = false;

-- discount_history: IN(brand_ids) 다중 브랜드 조회용
CREATE INDEX idx_discount_history_brands_date
    ON discount_history (brand_id, start_date, end_date);

-- user_favorites: 본인 즐겨찾기 조회
CREATE INDEX idx_user_favorites_user_id
    ON user_favorites (user_id);

-- user_favorites: 브랜드별 즐겨찾기 사용자 역조회
CREATE INDEX idx_user_favorites_brand_id
    ON user_favorites (brand_id);

-- ── Row Level Security ───────────────────────────────────────

ALTER TABLE categories       ENABLE ROW LEVEL SECURITY;
ALTER TABLE brands           ENABLE ROW LEVEL SECURITY;
ALTER TABLE discount_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_favorites   ENABLE ROW LEVEL SECURITY;

-- categories: 인증 사용자 읽기 가능
CREATE POLICY "categories_select_authenticated"
    ON categories FOR SELECT
    TO authenticated
    USING (true);

-- brands: 인증 사용자 읽기 가능
CREATE POLICY "brands_select_authenticated"
    ON brands FOR SELECT
    TO authenticated
    USING (true);

-- discount_history: 인증 사용자 읽기 가능 (AI 예측 포함)
CREATE POLICY "discount_history_select_authenticated"
    ON discount_history FOR SELECT
    TO authenticated
    USING (true);

-- discount_history: 서비스 롤(Edge Function)만 AI 예측 행 삽입 가능
--   service_role은 RLS를 우회하므로 별도 정책 불필요

-- user_favorites: 본인 데이터만 CRUD
CREATE POLICY "user_favorites_select_own"
    ON user_favorites FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "user_favorites_insert_own"
    ON user_favorites FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_favorites_delete_own"
    ON user_favorites FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- ── Seed Data (트랜잭션으로 원자성 보장) ─────────────────────

BEGIN;

INSERT INTO categories (id, name)
VALUES
  ('c1000000-0000-0000-0000-000000000001', '옷')
, ('c1000000-0000-0000-0000-000000000002', '신발')
, ('c1000000-0000-0000-0000-000000000003', '음식');

INSERT INTO brands (id, category_id, name, logo_url, is_discounting)
VALUES
  ('b1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'Zara',        null, true)
, ('b1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'H&M',         null, false)
, ('b1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'Uniqlo',      null, true)
, ('b1000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001', 'Musinsa',     null, false)
, ('b1000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000002', 'Nike',        null, false)
, ('b1000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000002', 'Adidas',      null, true)
, ('b1000000-0000-0000-0000-000000000007', 'c1000000-0000-0000-0000-000000000002', 'New Balance', null, false)
, ('b1000000-0000-0000-0000-000000000008', 'c1000000-0000-0000-0000-000000000002', 'Vans',        null, true)
, ('b1000000-0000-0000-0000-000000000009', 'c1000000-0000-0000-0000-000000000003', 'Starbucks',   null, true)
, ('b1000000-0000-0000-0000-000000000010', 'c1000000-0000-0000-0000-000000000003', 'McDonald''s', null, false)
, ('b1000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000003', 'Subway',      null, true)
, ('b1000000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000003', 'BBQ',         null, false);

INSERT INTO discount_history (brand_id, start_date, end_date, discount_rate, is_ai_predicted)
VALUES
  ('b1000000-0000-0000-0000-000000000001', '2025-12-20', '2025-12-31', 0.30, false)
, ('b1000000-0000-0000-0000-000000000001', '2026-03-10', '2026-03-22', 0.25, false)
, ('b1000000-0000-0000-0000-000000000001', '2026-06-10', '2026-06-22', 0.30, false)
, ('b1000000-0000-0000-0000-000000000003', '2025-11-01', '2025-11-20', 0.20, false)
, ('b1000000-0000-0000-0000-000000000003', '2026-02-14', '2026-02-28', 0.15, false)
, ('b1000000-0000-0000-0000-000000000003', '2026-06-05', '2026-06-25', 0.20, false)
, ('b1000000-0000-0000-0000-000000000006', '2025-12-01', '2025-12-31', 0.40, false)
, ('b1000000-0000-0000-0000-000000000006', '2026-03-01', '2026-03-15', 0.35, false)
, ('b1000000-0000-0000-0000-000000000006', '2026-06-12', '2026-06-30', 0.40, false)
, ('b1000000-0000-0000-0000-000000000009', '2025-12-01', '2025-12-31', 0.15, false)
, ('b1000000-0000-0000-0000-000000000009', '2026-03-01', '2026-03-31', 0.10, false)
, ('b1000000-0000-0000-0000-000000000009', '2026-06-01', '2026-06-30', 0.15, false);

COMMIT;

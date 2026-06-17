-- ============================================================
--  002_brand_categories_admin.sql
--  - 브랜드-카테고리 다대다(M:N) 관계 테이블 추가
--  - 기존 category_id 데이터 이관 후 컬럼 제거
--  - 비인증(anon) 공개 읽기 허용
--  - 인증(authenticated) 사용자 관리자 쓰기 허용
-- ============================================================

-- ── 1. brand_categories 중간 테이블 ─────────────────────────────

CREATE TABLE brand_categories (
  id          uuid NOT NULL DEFAULT gen_random_uuid()
, brand_id    uuid NOT NULL
, category_id uuid NOT NULL
, CONSTRAINT brand_categories_pkey   PRIMARY KEY (id)
, CONSTRAINT brand_categories_bfkey  FOREIGN KEY (brand_id)
    REFERENCES brands (id) ON DELETE CASCADE
, CONSTRAINT brand_categories_cfkey  FOREIGN KEY (category_id)
    REFERENCES categories (id) ON DELETE CASCADE
, CONSTRAINT brand_categories_unique UNIQUE (brand_id, category_id)
);

CREATE INDEX idx_brand_categories_brand
    ON brand_categories (brand_id);

CREATE INDEX idx_brand_categories_category
    ON brand_categories (category_id);

-- ── 2. 기존 category_id 데이터 이관 ─────────────────────────────

INSERT INTO brand_categories (brand_id, category_id)
SELECT id, category_id FROM brands;

-- ── 3. brands 테이블에서 category_id 컬럼 제거 ──────────────────

ALTER TABLE brands DROP COLUMN category_id;

-- ── 4. RLS 설정 ──────────────────────────────────────────────────

ALTER TABLE brand_categories ENABLE ROW LEVEL SECURITY;

-- 비인증(anon): categories, brands, discount_history, brand_categories 읽기 허용
CREATE POLICY "categories_select_anon"
    ON categories FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "brands_select_anon"
    ON brands FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "discount_history_select_anon"
    ON discount_history FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "brand_categories_select_anon"
    ON brand_categories FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "brand_categories_select_authenticated"
    ON brand_categories FOR SELECT
    TO authenticated
    USING (true);

-- 인증(authenticated): 카테고리 쓰기 (관리자 기능)
CREATE POLICY "categories_insert_authenticated"
    ON categories FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "categories_update_authenticated"
    ON categories FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "categories_delete_authenticated"
    ON categories FOR DELETE
    TO authenticated
    USING (true);

-- 인증(authenticated): 브랜드 쓰기 (관리자 기능)
CREATE POLICY "brands_insert_authenticated"
    ON brands FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "brands_update_authenticated"
    ON brands FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "brands_delete_authenticated"
    ON brands FOR DELETE
    TO authenticated
    USING (true);

-- 인증(authenticated): brand_categories 쓰기 (관리자 기능)
CREATE POLICY "brand_categories_insert_authenticated"
    ON brand_categories FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "brand_categories_delete_authenticated"
    ON brand_categories FOR DELETE
    TO authenticated
    USING (true);

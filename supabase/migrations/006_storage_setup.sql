-- ============================================================
--  006_storage_setup.sql
--  - brand-logos Storage 버킷 생성 (public)
--  - RLS 정책: 누구나 읽기 / 로그인 사용자(관리자)만 쓰기
-- ============================================================

-- ── 1. 버킷 생성 ─────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'brand-logos'
, 'brand-logos'
, true
, 5242880       -- 5 MB
, ARRAY['image/jpeg','image/png','image/webp','image/gif','image/svg+xml','image/x-icon']
)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ── 2. RLS 활성화 ─────────────────────────────────────────────
-- storage.objects 에는 이미 RLS가 활성화되어 있으므로 따로 ALTER 불필요

-- ── 3. 정책: 누구나 읽기 (public) ────────────────────────────
DROP POLICY IF EXISTS "brand_logos_public_read"  ON storage.objects;
CREATE POLICY "brand_logos_public_read"
ON storage.objects
FOR SELECT
USING (bucket_id = 'brand-logos');

-- ── 4. 정책: 로그인 사용자만 업로드 ─────────────────────────
DROP POLICY IF EXISTS "brand_logos_admin_insert" ON storage.objects;
CREATE POLICY "brand_logos_admin_insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'brand-logos');

-- ── 5. 정책: 로그인 사용자만 덮어쓰기 ───────────────────────
DROP POLICY IF EXISTS "brand_logos_admin_update" ON storage.objects;
CREATE POLICY "brand_logos_admin_update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'brand-logos');

-- ── 6. 정책: 로그인 사용자만 삭제 ───────────────────────────
DROP POLICY IF EXISTS "brand_logos_admin_delete" ON storage.objects;
CREATE POLICY "brand_logos_admin_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'brand-logos');

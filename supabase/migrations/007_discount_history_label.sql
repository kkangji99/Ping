-- discount_history 테이블에 label 컬럼 추가
-- 이벤트/할인 이름 저장용 (예: '여름 세일', '멤버십 위크', '아우터 30%' 등)

ALTER TABLE discount_history
  ADD COLUMN IF NOT EXISTS label text;

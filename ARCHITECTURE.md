# 시스템 아키텍처 및 데이터 모델

## 데이터 모델 (Database Schema)
1. Categories (id, name) -> 예: 옷, 신발, 음식
2. Brands (id, category_id, name, logo_url, is_discounting)
3. DiscountHistory (id, brand_id, start_date, end_date, discount_rate)
4. UserFavorites (id, user_id, brand_id)

## 주요 기능 및 화면 구조
1. **메인 홈 화면**: 카테고리별 탭 구성 및 브랜드 리스트 (하트 토글 기능)
2. **캘린더 화면**: 
   - 현재 할인 중인 브랜드 표시
   - AI 예측 할인 기간 표시 (캘린더 설정에서 ON/OFF 토글 가능)
3. **AI 예측 로직**: 과거 DiscountHistory 데이터를 기반으로 LLM 프롬프트를 통해 다음 예상 할인 시작일/종료일 도출
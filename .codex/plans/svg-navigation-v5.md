# Task: SVG v5 임시 길찾기 데이터셋 연결

## Acceptance Criteria
- [x] 제공된 SVG v5에서 벡터 지도, 노드, 간선을 JSON으로 생성한다.
- [x] 생성 JSON을 SQLite ETL로 적재할 수 있다.
- [x] 기존 FastAPI 층 지도, 그래프, 최단 경로 API가 test-center/1F를 응답한다.
- [x] 기존 테스트 코드는 수정하지 않고 회귀 테스트와 임시 데이터 API 호출을 검증한다.
- [ ] 이번 작업 파일만 커밋하여 원격 브랜치에 푸시한다.

## Tasks
1. SVG 변환기에 그래프/데이터셋 추출 추가 - api/scripts/convert_svg_floor_map.py - L
2. v5 SVG와 생성 JSON 추가 - api/app/data - M
3. ETL 및 API 응답 연결 보완 - api/scripts, api/app - M
4. 변환/ETL/API/회귀 검증 - S
5. 범위 제한 커밋 및 푸시 - S

## Dependencies
- 2는 1의 변환 결과에 의존한다.
- 3과 4는 생성된 navigation/vector JSON에 의존한다.

## Risks
- 실제 축척이 없어 0.05 m/px 임시 축척을 사용한다.
- 기존 작업 트리의 미추적 문서와 test-center/1f.svg는 이번 커밋에서 제외한다.

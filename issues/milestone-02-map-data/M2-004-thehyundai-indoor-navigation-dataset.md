# M2-004 · 더현대서울 실내 내비게이션 데이터셋 구축

- **상태**: Created
- **마일스톤**: M2 · 실내 지도 데이터와 기본 경로
- **권장 진행**: 2주차 후반
- **컴포넌트**: data / routing / demo
- **GitHub**: #18
- **선행 이슈**: M2-001, M2-003

## 설명

더현대서울 데모에서 사용할 실제 지도 데이터를 준비한다. VWorld GIS건물통합정보 SHP에서 건물 외곽을
추출하고, 현대백화점 모바일 층 안내도 공개 리소스를 수집한 뒤, PDR + Particle Filter 데모에서 사용할
topology 기반 indoor navigation map으로 후처리한다.

이 작업은 CAD 수준의 정밀 도면을 만드는 것이 아니라, 길찾기 가능한 수준의 node/edge/store/POI
데이터를 팀원이 같은 입력으로 확인하고 사용할 수 있게 만드는 것을 목표로 한다.

## 작업 내용

### 1. 원천 데이터 추출

- VWorld SHP에서 더현대서울 건물 외곽 polygon을 추출한다.
- 현대백화점 모바일 층 안내도 페이지에서 브라우저가 공개적으로 받는 이미지, JSON, SVG 리소스를 저장한다.
- 원천 추출 결과의 manifest와 summary를 생성한다.

### 2. 내비게이션 지도 후처리

- 층 안내도 이미지와 원본 지도 JSON을 이용해 매장, POI, OCR 후보를 추출한다.
- 복도와 주요 POI를 기반으로 길찾기용 navigation graph를 생성한다.
- node, edge, store, POI, OCR, confidence, manual review 후보를 분리된 JSON으로 저장한다.
- VWorld 건물 외곽 bbox를 기준으로 실내 local meter 좌표계를 부여한다.

### 3. 협업용 산출물 정리

- `thehyundai_indoor_navigation_dataset/`에 후처리된 결과 JSON과 preview를 보관한다.
- `navigation_map.json`은 split manifest로 유지하고, 실제 데이터는 `navigation_map_parts/*.json`에 분리한다.
- 원본 Dabeeo raw JSON, SHP, debug PNG 등 재생성 가능한 대용량 파일은 커밋하지 않는다.
- 팀원이 바로 확인할 수 있는 `preview.html`과 설명 문서를 포함한다.

## 수용 기준

- `thehyundai_indoor_navigation_dataset/navigation_map.json`이 split manifest로 생성된다.
- `navigation_map_parts/nodes.json`, `edges.json`, `stores.json`, `pois.json`이 생성되고 앱에서 바로 읽을 수 있다.
- `preview.html`에서 건물 외곽, graph, 매장, OCR, POI overlay를 확인할 수 있다.
- 데이터셋 폴더 안에 파일별 의미와 활용 방법이 문서화되어 있다.
- GitHub PR이 이 이슈와 연결되어 merge 시 자동으로 닫힌다.

## 검증

```bash
.venv/bin/python -m py_compile scripts/extract_thehyundai_building.py scripts/extract_ehyundai_floor_assets.py scripts/build_thehyundai_dataset.py scripts/build_navigation_map.py scripts/generate_preview.py
.venv/bin/python scripts/build_navigation_map.py
.venv/bin/python scripts/generate_preview.py
```

## 범위 밖

- 실측 CAD 수준의 도면 정합
- 실시간 PDR 현재 위치 추적
- Particle Filter 튜닝
- 다층/층간 길찾기 고도화
- 비공개 API 또는 로그인 우회 데이터 수집

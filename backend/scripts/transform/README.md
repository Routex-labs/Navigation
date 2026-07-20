# `scripts/transform` — 순수 변환 (파일→파일 / dict→dict)

**DB를 건드리지 않는** 변환기들. 파일을 읽어 파일을 쓰거나(`split_studio_export`, `make_glyphs`),
in-memory dict를 받아 dict를 돌려준다(`floor_alignment`, `vertical_transfers`).

> `seed/`(DB 적재)와 대비되는 계층. 여기 있는 것들은 Session도 엔진도 모른다.

---

## 구성 파일

| 파일 | 종류 | 역할 |
|---|---|---|
| `split_studio_export.py` | 파일→파일 (CLI) | Studio 통합 export 1개 → `{층}.json` + `stores_{층}.json` 2개 |
| `make_glyphs.js` | 파일→파일 (Node) | 폰트(.ttf) → MapLibre 글리프 `.pbf` (`resources/fonts/`) |
| `floor_alignment.py` | dict→dict (순수) | 층 `local_m` 프레임 → 건물 공통 프레임 아핀 피팅 |
| `vertical_transfers.py` | dict→dict (순수) | 인접 층의 엘리베이터/에스컬레이터를 이어 수직 전이 간선 생성 |
| `__init__.py` | 패키지 표식 | — |

---

## 각 변환

### `split_studio_export.py`
```
python -m scripts.transform.split_studio_export <통합export.json> --floor 1f
```
Studio(HTML)의 '현재 층 내보내기' 한 파일을 파이프라인이 먹는 2개로 쪼갠다.
편집기가 **source 좌표**로 저장한 폴리곤/테두리를 `source_to_local_m` 아핀으로 실제 `local_m`으로 변환한다.

### `floor_alignment.py` (순수)
`alignment_to_reference(studio, reference) -> (Affine, stats)`.
층마다 Studio가 좌표 변환을 따로 피팅해 스케일이 달라서, **엘리베이터를 대응점**으로 삼아 각 층을 기준층(1F) 프레임으로 맞추는 6-DOF 아핀을 최소자승으로 푼다. bbox 정규화 + 전역 탐욕 매칭으로 앵커를 짝짓는다.

### `vertical_transfers.py` (순수)
`build_transfers(floors) -> (transfers, unresolved)`.
정규화된 좌표에서 인접 층의 같은 수직 통로를 **위치 근접**으로 이어 전이 간선을 만든다(이름이 전부 "엘리베이터"라 이름으론 못 맞춤).

### `make_glyphs.js` (Node)
`node make_glyphs.js <font.ttf> <outDir>` — 심볼 레이어 텍스트용 256자 단위 글리프 `.pbf`를 생성. 결과는 `routers/fonts.py`가 서빙한다.

---

## 의존성 방향

```
transform/*  ──►  표준 라이브러리 / numpy 정도. app.core·app.models·DB 에 의존 안 함
                  (단 split_studio_export 는 파일 IO, make_glyphs 는 Node 런타임)

seed/studio_adapter  ──►  transform.floor_alignment, transform.vertical_transfers
```

- **순수·무상태라 단위 테스트가 쉽다.** `floor_alignment`/`vertical_transfers`는 dict만 주고받는다.
- `seed/`가 이 변환들을 호출해 적재 직전 좌표를 맞춘다. 반대 방향 의존은 없다.

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| Studio에서 새 층 내보냄 | `split_studio_export`로 2개 파일 생성 → `resources/studio/<building>/`에 배치 |
| 층 정합이 어긋남 | `floor_alignment`의 앵커 매칭/잔차. 실행 잔차는 `seed.studio_adapter` 출력에서 확인 |
| 글리프 범위 부족(한자 등) | `make_glyphs.js` 재생성 후 `resources/fonts/`에 커밋 |

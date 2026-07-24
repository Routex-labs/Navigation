# `scripts/transform` — 순수 변환 (파일→파일 / dict→dict)

**DB를 건드리지 않는** 변환기들. 파일을 읽어 파일을 쓰거나(`build_studio_from_dabeeo`,
`make_glyphs`), in-memory dict를 받아 dict를 돌려준다(`floor_alignment`, `vertical_transfers`).

> `seed/`(DB 적재)와 대비되는 계층. 여기 있는 것들은 Session도 엔진도 모른다.

---

## 구성 파일

| 파일 | 종류 | 역할 |
|---|---|---|
| `build_studio_from_dabeeo.py` | 파일→파일 (CLI) | 다베오 공식 payload → 12개 층 `{층}.json` + `stores_{층}.json` |
| `make_glyphs.js` | 파일→파일 (Node) | 폰트(.ttf) → MapLibre 글리프 `.pbf` (`resources/fonts/`) |
| `floor_alignment.py` | dict→dict (순수) | `local_m` 좌표에 2D 아핀 적용 |
| `vertical_transfers.py` | dict→dict (순수) | 엘리베이터/에스컬레이터를 이어 수직 전이 간선 생성 (에스컬레이터=방향 단방향, 엘리베이터=샤프트 직행, 층수 기반 비용) |
| `__init__.py` | 패키지 표식 | — |

---

## 각 변환

### `build_studio_from_dabeeo.py`
```powershell
python -m scripts.transform.build_studio_from_dabeeo <다베오payload.json>
```
다베오 공식 payload 하나에서 전 층(B6~6F)을 통째로 만든다. **모든 층이 다베오 원본
좌표계를 그대로 공유**하므로 층 정렬이 필요 없고, shear나 이방성이 구조적으로
생기지 않는다. 결과는 `resources/studio/thehyundai-seoul-dabeeo/`에 쓴다.

> 미해결: 절대 배율. `SCALE_M_PER_UNIT = 0.1` 기준 1F가 167x98m(16,182m²)인데 VWorld
> 실측은 7,062m²다. 형상과 층간 정합은 배율과 무관하므로 이 상수 한 곳만 고치면
> 전체가 따라온다.

### `floor_alignment.py` (순수)
`apply(affine, x, y)` / `apply_point(affine, point)` — `local_m` 좌표에 2D 아핀을 찍는다.

예전에는 여기서 층 정렬 아핀까지 피팅했다(엘리베이터 대응점, shear/잔차 게이트).
다베오 데이터가 전 층에 한 프레임을 물려주면서 정렬 단계가 사라졌다. 다른 좌표
프레임의 층을 섞어야 할 일이 생기면 커밋 `c81aad3` 이전 이력에서 되살릴 수 있다.

### `vertical_transfers.py` (순수)
`build_transfers(floors) -> (transfers, unresolved)`. 같은 수직 통로는 **위치 근접**으로
맞춘다(이름이 전부 "엘리베이터"라 이름으론 못 맞춤). 수단별로 다르게 잇는다.

- **에스컬레이터**: 원본 `trans_code`(`OB-ESCALATOR_UP`/`_DOWN`)로 방향을 읽어 **인접 층끼리
  단방향**(`bidirectional=False`) 간선을 만든다 → 상행 전용을 하행으로 타는 불가능 경로 제거.
- **엘리베이터**: 층을 가로질러 같은 자리를 **샤프트**로 묶고, 서비스하는 **모든 층쌍을 양방향
  직행** 연결한다.
- **비용(`length_m`)**: 에스컬 `20/홉`, 엘리베 `35 + 5×홉` → 1~2층은 에스컬레이터, 3층+는
  엘리베이터가 최단. 상수는 파일 상단에 근거와 함께 모여 있다.

> 설계·검증 기준: [`docs/backend/navigate/vertical-transfer-routing.md`](../../../docs/backend/navigate/vertical-transfer-routing.md).
> 서빙은 `building_queries.get_building_graph`(건물 전체 그래프 + `vertical` 정책)가 한다.

### `make_glyphs.js` (Node)
`node make_glyphs.js <font.ttf> <outDir>` — 심볼 레이어 텍스트용 256자 단위 글리프
`.pbf`를 생성. 결과는 `routers/fonts.py`가 서빙한다.

---

## 의존성 방향

```
transform/*  ──►  표준 라이브러리 정도. app.core·app.models·DB 에 의존 안 함
                  (단 build_studio_from_dabeeo 는 파일 IO, make_glyphs 는 Node 런타임)

seed/studio_adapter  ──►  transform.floor_alignment, transform.vertical_transfers
```

- **순수·무상태라 단위 테스트가 쉽다.** `floor_alignment`/`vertical_transfers`는 dict만 주고받는다.
- `seed/`가 이 변환들을 호출해 적재한다. 반대 방향 의존은 없다.

---

## 자주 하는 작업

| 하고 싶은 것 | 방법 |
|---|---|
| 다베오 payload가 갱신됨 | `build_studio_from_dabeeo` 재실행 → `reset_and_seed` |
| 건물 크기가 실측과 안 맞음 | `build_studio_from_dabeeo.SCALE_M_PER_UNIT` (현재 0.1, 미검증) |
| 글리프 범위 부족(한자 등) | `make_glyphs.js` 재생성 후 `resources/fonts/`에 커밋 |

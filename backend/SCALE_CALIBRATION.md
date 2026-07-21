# 거리 비율(절대 배율) 보정 가이드

경로(다익스트라)는 정상 동작하지만, **거리·ETA 값이 실제보다 약 1.5배 크게** 나온다.
원인은 절대 배율 `SCALE_M_PER_UNIT`이 미검증(`0.1`)으로 박혀 있기 때문. 아래 한 곳만 고치면
전체(노드 좌표·간선 길이·footprint·wgs84 affine)가 따라오도록 설계돼 있다.

## 현재 상태

- 설정 위치: [`scripts/transform/build_studio_from_dabeeo.py`](scripts/transform/build_studio_from_dabeeo.py) 30번째 줄
  ```python
  SCALE_M_PER_UNIT = 0.1   # payload scaleCm=10 / scalePx=1 기준. 미검증.
  ```
- 이 값(0.1)이면 1F LEVEL이 **167×98m (16,182m²)**
- VWorld 실측은 **126×68m (~7,062m²)**
- 즉 지금 거리가 **약 1.5배 과대**. 예: 화면에 25.3m로 뜬 경로 = 실제 ~17m

## 목표값(추정)

- 면적 기준: `0.1 × √(7062/16182) ≈ 0.066 m/unit`
- 치수 기준: 가로 `126/167 ≈ 0.75`, 세로 `68/98 ≈ 0.69` → 약 ×0.7
- 정밀값은 georeferencing 4개 코너로 다시 풀어 확정할 것(아래 "주의" 참고).

## 적용 절차 (도커 서빙 기준)

```bash
cd backend
# 1) 배율 상수 수정: SCALE_M_PER_UNIT 값을 목표값으로 변경

# 2) resources JSON 재생성 (이 단계만 수동 — 자동 안 됨)
python -m scripts.transform.build_studio_from_dabeeo

# 3) 이미지 재빌드 + 기동 (기동 커맨드가 reset_and_seed를 자동 실행)
docker compose up -d --build backend
```

### 왜 이 순서인가
- **`build_studio_from_dabeeo`는 자동 실행되지 않는다.** `resources/studio/*.json`을 다시 만드는
  생성 단계라 배율을 바꾼 뒤 반드시 직접 돌려야 한다.
- **`reset_and_seed`는 도커에서 자동이다.** compose command(`sh -c "python -m scripts.seed.reset_and_seed && uvicorn ..."`)에
  들어 있어 컨테이너가 뜰 때마다 실행된다. 별도로 칠 필요 없음.
- **`--build`가 필요한 이유:** 생성된 JSON이 이미지에 구워져 들어가고 볼륨 마운트가 없으므로,
  재빌드하지 않으면 새 JSON이 컨테이너에 반영되지 않는다.

로컬(비도커) 실행이라면 2단계 뒤에 `python -m scripts.seed.reset_and_seed`를 직접 실행.

## 주의 — wgs84 정합 재확인

배율을 바꾸면 `local_m` 좌표뿐 아니라 **`local_m_to_wgs84` affine 행렬도 같이 바뀐다**
([`build_studio_from_dabeeo.py`](scripts/transform/build_studio_from_dabeeo.py) 70~73번째 줄).
현재는 회전·배율은 검증값을 쓰고 평행이동만 실측으로 잡아 `status: unverified` 상태다.
배율 확정 후에는 **지도 오버레이 위 매장 위치가 실제와 맞는지 1회 눈으로 검증**할 것.

## 검증 방법

재시드 후 floor 응답으로 확인:

```bash
curl -s "http://localhost:8001/buildings/thehyundai-seoul/floors/1F" \
  -o floor.json
python -c "import json,io; d=json.load(io.open('floor.json',encoding='utf-8')); \
  fp=d.get('footprint_local_m'); \
  xs=[p['x'] for p in fp]; ys=[p['y'] for p in fp]; \
  print('footprint bbox: %.1f x %.1f m' % (max(xs)-min(xs), max(ys)-min(ys)))"
# 목표: 대략 126 x 68 m 근처로 나오는지 확인
```

## 관련 배경 (이번 작업에서 이미 해결된 것)

- **매장 `entrance_node_id` 누락 → 다익스트라 미동작**은 해결됨.
  [`scripts/seed/studio_adapter.py`](scripts/seed/studio_adapter.py)의 `_nearest_node_id`가
  입구 좌표를 가장 가까운 junction 노드에 스냅해 채운다. (배율과 무관, 이미 반영됨)
- 큰 현재위치 마커 크기는 **클라이언트** 이슈(`client/lib/widgets/location_marker.dart` 계열)로 여기 범위 아님.

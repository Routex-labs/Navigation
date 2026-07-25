# calibration

건물별 좌표 정합 입력 데이터. 이 폴더의 파일은 소스 오브 트루스가 아니라
"어떻게 정합을 뽑았는지"를 재현할 수 있게 남겨둔 원본 관측치다. 여기 값을 바꾸고
재정합 스크립트를 다시 돌리면 studio JSON의 `local_m_to_wgs84` 아핀이 갱신된다.

## 지금 있는 것

- `thehyundai-seoul-gcps.json` — 더현대 서울 GCP 4점(건물 북/서/남/동 꼭지점).
  `backend/scripts/tools/gcp_picker.html`에서 VWorld 위성 지도로 뽑은 lat/lng.

## GCP 다시 뽑는 법

1. `backend/scripts/tools/gcp_picker.html`을 로컬 HTTP로 열고 VWorld 인증키 입력
   ```
   python -m http.server -d backend/scripts/tools 8765
   ```
   그리고 <http://localhost:8765/gcp_picker.html>

2. 건물을 최대 줌으로 잡고 모서리 4~6점을 클릭. 라벨은 순서(1, 2, 3, ...) 또는 방위(N, W, S, E) 어느 쪽이든 좋음.

3. Export JSON으로 내려받아 이 폴더에 덮어쓰기.

4. 재정합 실행 (dry-run):
   ```
   cd backend
   python -m scripts.transform.refit_building_wgs84 \
       --studio resources/studio/thehyundai-seoul-dabeeo \
       --gcps resources/calibration/thehyundai-seoul-gcps.json
   ```
   잔차와 새 아핀을 출력한다. 자동 매칭이 이상하면 `--map "N=1,W=2,S=3,E=4"`처럼 명시.

5. 결과 만족스러우면 `--write`로 studio JSON들의 아핀을 덮어쓰기.

# calibration

건물별 좌표 정합 입력 데이터. 이 폴더의 파일은 소스 오브 트루스가 아니라
"어떻게 정합을 뽑았는지"를 재현할 수 있게 남겨둔 원본 관측치다. 여기 값을 바꾸고
재정합 스크립트를 다시 돌리면 studio JSON의 `local_m_to_wgs84` 아핀이 갱신된다.

## 지금 있는 것

- `thehyundai-seoul-gcps.json` — 더현대 서울 GCP 4점(건물 북/서/남/동 꼭지점).
  OSM Overpass(way 874639191, 더현대 서울 building=retail) 꼭지점에서 뽑은 lat/lng.
  클라이언트 base 지도가 OSM 타일이라 GCP도 OSM 좌표계로 잡아야 실내 오버레이가 base 타일 건물 외곽과 정렬된다.

## GCP 다시 뽑는 법

1. 건물 외곽 꼭지점의 lat/lng를 확보한다. 극점 4~6점(방위 N/W/S/E 또는 순서 1, 2, 3, ...)을 잡는다.
   - 기본: OSM에서 대상 건물 way를 찾아(Overpass 등) 극점 좌표를 뽑는다. base 타일이 OSM인 한 이 좌표계가 정렬 기준이다.
   - VWorld 위성 배경(vworldApiKey 설정 시)으로 배포한다면 대신 VWorld 위성 지도에서 같은 꼭지점을 클릭해 뽑는다.

2. 이 폴더 JSON 형식(`gcps[]`의 `label`/`compass`/`outdoor.lat`·`lng`)에 맞춰 값을 채워 덮어쓴다.

3. 재정합 실행 (dry-run):
   ```
   cd backend
   python -m scripts.transform.refit_building_wgs84 \
       --studio resources/studio/thehyundai-seoul-dabeeo \
       --gcps resources/calibration/thehyundai-seoul-gcps.json
   ```
   잔차와 새 아핀을 출력한다. 자동 매칭이 이상하면 `--map "N=1,W=2,S=3,E=4"`처럼 명시.

4. 결과 만족스러우면 `--write`로 studio JSON들의 아핀을 덮어쓰기.

# 로컬 개발 가이드

필요한 항목만 바로 확인하세요.

- [백엔드 실행](#백엔드-실행)
- [Flutter 실행](#flutter-실행)
- [실행 대상별 API 주소](#실행-대상별-api-주소)
- [API 키 주입](#api-키-주입)
- [문제 해결](#문제-해결)

## 백엔드 실행

저장소 루트에서 Docker Desktop을 실행한 뒤 다음 명령만 실행한다.

```powershell
docker compose up
```

API는 `http://127.0.0.1:8001`에서 실행되며, 컨테이너 시작 시 개발 DB와 기본 지도 데이터가 적재된다.

```powershell
Invoke-RestMethod http://127.0.0.1:8001/health
```

## Flutter 실행

`client/`에서 실행한다.

```powershell
Set-Location client
flutter pub get
flutter run
```

특정 기기를 지정하려면 다음을 사용한다.

```powershell
flutter devices
flutter run -d <device-id>
```

## 실행 대상별 API 주소

기본값은 Android 에뮬레이터용 `http://10.0.2.2:8001`이다.

| 실행 대상 | `API_BASE_URL` |
|---|---|
| Android 에뮬레이터 | 지정하지 않음 (`http://10.0.2.2:8001`) |
| Android 실기기 | `http://<개발-PC-LAN-IP>:8001` |
| iOS 시뮬레이터 / macOS 앱 | `http://127.0.0.1:8001` |
| iPhone 실기기 | `http://<Mac-LAN-IP>:8001` |

실기기는 개발 PC와 같은 Wi-Fi에 연결한 뒤 실행한다.

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8001
```

실기기 연결이 안 되면 PC 방화벽에서 Docker Desktop의 개인 네트워크 수신을 허용한다. 외부 공개 환경에서는 HTTP 대신 HTTPS 주소를 사용한다.

## API 키 주입

키는 소스에 넣지 않고 실행 시 주입한다.

```powershell
flutter run --dart-define=TMAP_APP_KEY=<TMAP_KEY> --dart-define=VWORLD_API_KEY=<VWORLD_KEY>
```

## 문제 해결

| 증상 | 먼저 확인할 것 |
|---|---|
| 앱에서 API 연결 실패 | `docker compose up` 실행 여부, `/health`, 포트 `8001`, `API_BASE_URL` |
| Android 에뮬레이터가 `localhost`를 못 찾음 | `localhost` 대신 기본값 `10.0.2.2` 사용 |
| Android 실기기에서 연결 실패 | 같은 Wi-Fi, PC LAN IP, 방화벽, HTTP cleartext 정책 |
| Docker 연결 실패 | Docker Desktop 실행 여부 |

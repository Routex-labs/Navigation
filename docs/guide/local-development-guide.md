# 로컬 개발 가이드

필요한 항목만 바로 확인하세요.

- [백엔드 실행](#백엔드-실행)
- [Flutter 실행](#flutter-실행)
- [실행 대상별 API 주소](#실행-대상별-api-주소)
- [API 키 주입](#api-키-주입)
- [문제 해결](#문제-해결)

## 백엔드 실행

일상 개발과 기능 검증은 Docker 대신 `backend/`의 로컬 Python 가상환경을 사용한다.
프로젝트 기준 버전은 Python 3.12다.
아래 PowerShell 블록은 각각 저장소 루트에서 시작한다.

최초 1회 또는 `requirements*.txt`가 바뀌었을 때:

```powershell
Set-Location backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

macOS:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

검증할 때마다 DB를 다시 적재하고 Uvicorn을 실행한다.

```powershell
Set-Location backend
.\.venv\Scripts\Activate.ps1
python -m scripts.seed.reset_and_seed
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; $_ | Out-File ..\backend-local.log -Append -Encoding utf8 }
```

macOS에서도 저장소 루트에서 `backend/`로 이동하고 같은 순서로 실행한다.

```bash
cd backend
source .venv/bin/activate
python -m scripts.seed.reset_and_seed
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | tee ../backend-local.log
```

API는 `http://127.0.0.1:8001`에서 실행된다.

```powershell
Invoke-RestMethod http://127.0.0.1:8001/health
```

Docker Compose는 일상 개발 실행에 사용하지 않는다. 배포 이미지·컨테이너 환경 호환성을 확인할
때만 사용하며, 실제 Cloud Run 배포는 [GCP 배포 문서](gcp-instance.md)를 따른다.

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

실기기 연결이 안 되면 PC 방화벽에서 Python/Uvicorn 또는 TCP 8001의 개인 네트워크 수신을 허용한다. 외부 공개 환경에서는 HTTP 대신 HTTPS 주소를 사용한다.

## API 키 주입

키는 소스에 넣지 않고 실행 시 주입한다.

```powershell
flutter run --dart-define=TMAP_APP_KEY=<TMAP_KEY> --dart-define=VWORLD_API_KEY=<VWORLD_KEY>
```

## 문제 해결

| 증상 | 먼저 확인할 것 |
|---|---|
| 앱에서 API 연결 실패 | Uvicorn 실행 여부, `/health`, 포트 `8001`, `API_BASE_URL` |
| Android 에뮬레이터가 `localhost`를 못 찾음 | `localhost` 대신 기본값 `10.0.2.2` 사용 |
| Android 실기기에서 연결 실패 | 같은 Wi-Fi, PC LAN IP, 방화벽, HTTP cleartext 정책 |
| `ModuleNotFoundError` 또는 명령을 못 찾음 | `.venv` 활성화 여부, `python -m pip install -r requirements.txt` |

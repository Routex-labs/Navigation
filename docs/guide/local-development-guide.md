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
# 콘솔을 UTF-8로 고정하고, python도 UTF-8로 출력하게 한다. 둘을 맞춰야 한글 로그가 안 깨진다
# (python은 파이프될 때 기본 CP949로 출력하므로 콘솔만 UTF-8로 바꾸면 오히려 깨진다).
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONUTF8 = '1'
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

`client/`에서 실행한다. 실행 값(배포 URL·API 키)은 [API 키 주입](#api-키-주입)의 `config.local.json`으로 넣는다.

```powershell
Set-Location client
# 콘솔 인코딩을 UTF-8로 고정한다. 안 하면 flutter의 한글 출력이 기본 코드페이지(CP949)로 디코딩돼 로그가 중국어처럼 깨진다.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
flutter pub get
# 콘솔엔 전부, frontend.log엔 UTF-8로 남긴다(PS 5.1 Tee-Object는 파일을 UTF-16으로 쓰므로 패스스루로 tee).
flutter run --dart-define-from-file=config.local.json 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
```

macOS 터미널은 기본 UTF-8이라 프렐류드가 필요 없다.

```bash
cd client
flutter pub get
flutter run --dart-define-from-file=config.local.json 2>&1 | tee frontend.log
```

특정 기기를 지정하려면 다음을 사용한다.

```powershell
flutter devices
flutter run -d <device-id> --dart-define-from-file=config.local.json
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

백엔드를 직접 수정하지 않는다면 로컬 서버를 띄우지 않고 **배포된 Cloud Run 백엔드**에 바로 붙어도 된다.
`API_BASE_URL`에 배포 서비스 URL을 넣으면 되고, 주소는 [GCP 배포 문서](gcp-instance.md)를 참고한다.

실기기 연결이 안 되면 PC 방화벽에서 Python/Uvicorn 또는 TCP 8001의 개인 네트워크 수신을 허용한다. 외부 공개 환경에서는 HTTP 대신 HTTPS 주소를 사용한다.

## API 키 주입

키·URL은 소스에 넣지 않고 실행 시 주입한다. 매번 길게 치지 않도록 git에 올리지 않는
`client/config.local.json` 하나에 모아 `--dart-define-from-file`로 넣는 방식을 권장한다.

```powershell
Set-Location client
# 최초 1회: 템플릿 복사 후 값 채우기 (config.local.json은 .gitignore로 커밋되지 않는다)
Copy-Item config.example.json config.local.json
# config.local.json의 API_BASE_URL·TMAP_APP_KEY·VWORLD_API_KEY를 채운 뒤:
flutter run --dart-define-from-file=config.local.json
```

`config.local.json` 예시(키를 비우면 각각 목업 경로 / OSM 배경지도로 자동 대체):

```json
{
  "API_BASE_URL": "http://localhost:8001",
  "TMAP_APP_KEY": "",
  "VWORLD_API_KEY": ""
}
```

키를 하나만 즉석에서 넘길 땐 단건 방식도 그대로 동작한다.

```powershell
Copy-Item client\config.example.json client\config.local.json
```

> **주입 값은 컴파일 타임에 박힌다.** 키·URL을 바꾸면 hot reload로는 안 먹으므로 `flutter run`을 재시작한다.

JSON이라 주석은 쓸 수 없고, 키 이름은 `api_config.dart`의 `String.fromEnvironment` 이름과
정확히 같아야 한다. `API_BASE_URL`을 Cloud Run 주소로 채우면 로컬 백엔드를 띄우지 않고도
붙는다.

## 문제 해결

| 증상 | 먼저 확인할 것 |
|---|---|
| 콘솔·`*.log`의 한글이 중국어처럼 깨짐 | 출력 주체와 콘솔 인코딩 불일치. flutter(항상 UTF-8 출력)는 콘솔을 UTF-8로 고정(`[Console]::OutputEncoding`), python은 여기에 `$env:PYTHONUTF8=1`까지 줘서 양쪽을 UTF-8로 맞춘다. 위 실행 블록의 프렐류드를 빠뜨리지 않았는지 확인한다 |
| 앱에서 API 연결 실패 | Uvicorn 실행 여부, `/health`, 포트 `8001`, `API_BASE_URL` |
| Android 에뮬레이터가 `localhost`를 못 찾음 | `localhost` 대신 기본값 `10.0.2.2` 사용 |
| Android 실기기에서 연결 실패 | 같은 Wi-Fi, PC LAN IP, 방화벽, HTTP cleartext 정책 |
| `ModuleNotFoundError` 또는 명령을 못 찾음 | `.venv` 활성화 여부, `python -m pip install -r requirements.txt` |

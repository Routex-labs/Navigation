# 로깅

백엔드는 요청 상태와 에러를 **stdout**으로 남긴다. 별도 파일 캡처는 없다 — Cloud Run 등
컨테이너 환경이 stdout을 자동 수집한다. 로컬에서는 창에 그대로 찍히고, 개발 실행에서는
`backend-local.log`로 tee 한다(AGENTS.md 참고).

## 무엇이 남는가

- **요청·상태 코드**: uvicorn access 로그. 예) `... "POST /query/ai HTTP/1.1" 422`
- **우리 코드 로그**(`app.*`): 각 모듈이 `logging.getLogger(__name__)`으로 찍는다.
- **4xx/422 상세**: 어느 필드가 왜 막혔는지, `HTTPException`의 `detail`. (`app/core/logging.py`)
- **500 트레이스백**: uvicorn이 `uvicorn.error`로 남긴다.

## 상세 로그 켜기

기본 레벨은 `INFO`다. 우리 코드의 상세 로그까지 보려면 `NAV_LOG_LEVEL=DEBUG`로 실행한다.

```powershell
# Windows
$env:NAV_LOG_LEVEL = 'DEBUG'
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001
```

```bash
# macOS/Linux
export NAV_LOG_LEVEL=DEBUG
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001
```

## 민감정보

로그에 비밀값(토큰·비밀번호 등)을 직접 찍지 않는다. TMAP처럼 Flutter가 외부 API로 직접
보내는 요청은 백엔드를 거치지 않으므로 이 로그에 나타나지 않는다.

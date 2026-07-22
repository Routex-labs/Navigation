# 개발 요청·SQL 로그

기본 실행에서는 진단 파일을 만들지 않는다. PowerShell에서 환경변수를 켠 뒤 서버를 시작한다.

```powershell
$env:NAV_SQL_ECHO = '1'
$env:NAV_HTTP_CAPTURE = '1'
uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001
```

- `D:\Navigation\sql\queries.sql`: SQLAlchemy가 DB에 전달한 SQL과 바인딩 파라미터
- `D:\Navigation\args\*.json`: API의 실제 GET/POST 요청 정보와 JSON 요청·응답 본문

`args` 로그의 GET 요청은 `query_string`에 쿼리 파라미터가 남고 `json`은 `null`이다. JSON이 아닌
응답(벡터 타일·글꼴 등)은 파일 크기와 민감 데이터 노출을 막기 위해 본문을 저장하지 않는다.

`Authorization`, `token`, `password`, `secret`, `api_key`/`apikey`를 포함하는 헤더·JSON 키·이름 있는
SQL 파라미터는 `***`로 마스킹된다. TMAP처럼 Flutter가 외부 API로 직접 보내는 요청은 백엔드를 거치지
않으므로 이 로그에 나타나지 않는다.

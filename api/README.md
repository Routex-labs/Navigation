# Navigation API

FastAPI 기반 백엔드 골격. 평면도 GeoJSON 서빙 및 RAG 엔드포인트(스텁) 제공.

## 요구 사항

- Python 3.12+

## 실행

```bash
cd api
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS/Linux
pip install -r requirements.txt
uvicorn app.main:app --reload
```

서버 기동 후 http://localhost:8000/docs 에서 Swagger UI 확인.

## 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/health` | 서버 상태 확인 |
| GET | `/buildings` | 건물 목록 |
| GET | `/buildings/{id}` | 건물 상세 |
| GET | `/buildings/{id}/floors/{floor}` | 층 GeoJSON |
| POST | `/query/destination` | 목적지 질의 (RAG 스텁) |
| POST | `/query/info` | 장소 정보 질의 (RAG 스텁) |

## 테스트

```bash
pytest
```

## SDK 버전

- fastapi 0.115.x
- uvicorn 0.32.x
- pydantic 2.9.x
- Python 3.12+

# HTTP 캐시 헤더(Cache-Control/ETag)와 If-None-Match 재검증 공용 헬퍼.
#
# 왜 필요한가 — 벡터 지도는 같은 리소스를 여러 번 요청하는 것이 정상 동작이다.
# MapLibre는 줌을 오갈 때마다 타일을, 스타일을 다시 로드할 때마다 글리프 범위를
# 통째로 다시 가져온다. 응답에 캐시 헤더가 없으면 그 전부가 서버까지 도달해
# 렌더링·파일 읽기를 매번 다시 시킨다. 한글 라벨은 글리프 범위만 40개가 넘고
# 파일 하나가 170KB대라, 헤더가 없는 것만으로 층을 전환할 때마다 수 MB가
# 다시 흐른다. 서버 쪽 메모리 캐시로는 이 왕복 자체를 없앨 수 없다.

from __future__ import annotations


# If-None-Match 헤더가 주어진 ETag와 맞는지 판정한다.
# 헤더에는 쉼표로 여러 ETag가 올 수 있고 "*"는 아무 표현형과도 맞는다(RFC 9110).
# 비교는 약한 비교를 쓴다 — 재검증 목적에는 규격상 그쪽이 맞고, W/ 접두사가
# 붙어 되돌아오는 프록시를 만나도 304를 놓치지 않는다.
def etag_matches(if_none_match: str | None, etag: str) -> bool:
    if not if_none_match:
        return False

    candidates = [part.strip() for part in if_none_match.split(",") if part.strip()]
    if "*" in candidates:
        return True
    return _drop_weak_prefix(etag) in {_drop_weak_prefix(c) for c in candidates}


def _drop_weak_prefix(etag: str) -> str:
    return etag[2:] if etag.startswith("W/") else etag


# 캐시 가능한 응답에 함께 붙일 헤더 묶음.
# 304 응답에도 같은 헤더를 붙여야 브라우저가 만료 시각을 갱신한다 — 안 붙이면
# 재검증 직후 곧바로 또 재검증하러 온다.
def cache_headers(etag: str, max_age: int) -> dict[str, str]:
    return {
        "Cache-Control": f"public, max-age={max_age}",
        "ETag": etag,
    }

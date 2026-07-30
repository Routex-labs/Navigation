"""If-None-Match 재검증 판정 단위 테스트.

여기서 잘못 판정하면 두 방향 모두 손해다. 너무 느슨하면 내용이 바뀐 리소스에
304를 줘서 낡은 타일이 화면에 남고, 너무 빡빡하면 재검증이 항상 실패해 캐시가
없는 것과 같아진다.
"""

from app.core.http_cache import cache_headers, etag_matches


def test_헤더가_없으면_맞지_않는다():
    assert etag_matches(None, '"abc"') is False
    assert etag_matches("", '"abc"') is False


def test_같은_ETag는_맞는다():
    assert etag_matches('"abc"', '"abc"') is True


def test_다른_ETag는_맞지_않는다():
    assert etag_matches('"abc"', '"def"') is False


# 브라우저는 캐시에 여러 표현형이 있으면 쉼표로 이어 보낸다(RFC 9110).
def test_쉼표로_이어진_목록에_있으면_맞는다():
    assert etag_matches('"aaa", "bbb", "ccc"', '"bbb"') is True
    assert etag_matches('"aaa","bbb"', '"zzz"') is False


def test_별표는_아무_표현형과도_맞는다():
    assert etag_matches("*", '"abc"') is True


# 프록시가 W/를 붙여 되돌려보내도 304를 놓치면 안 된다.
def test_약한_ETag_접두사는_무시한다():
    assert etag_matches('W/"abc"', '"abc"') is True
    assert etag_matches('"abc"', 'W/"abc"') is True
    assert etag_matches('W/"abc"', 'W/"abc"') is True


def test_공백만_있는_항목은_무시한다():
    assert etag_matches('  ,  "abc"  ', '"abc"') is True


def test_캐시_헤더는_max_age와_ETag를_담는다():
    headers = cache_headers('"abc"', 60)

    assert headers["Cache-Control"] == "public, max-age=60"
    assert headers["ETag"] == '"abc"'

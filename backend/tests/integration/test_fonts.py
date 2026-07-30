"""글리프(.pbf) 서빙 HTTP API 통합 테스트.

한글 라벨은 음절 범위만 40개가 넘고 파일 하나가 170KB대다. 스타일을 다시
로드할 때마다(층 전환 등) MapLibre가 이 범위를 통째로 다시 요청하므로,
캐시 헤더가 빠지면 그것만으로 수 MB가 매번 다시 흐른다.
"""

FONTSTACK = "Noto Sans KR Regular"
# resources/fonts/에 실제로 커밋되어 있는 범위(한글 음절 시작 구간).
EXISTING_RANGE = "44032-44287"
# 커밋 범위 밖 — 빈 200으로 떨어지는 경로.
MISSING_RANGE = "65024-65279"


def test_있는_글리프_범위를_돌려준다(api_client):
    response = api_client.get(f"/fonts/{FONTSTACK}/{EXISTING_RANGE}.pbf")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/x-protobuf"
    assert response.content


def test_글리프_응답에_캐시_헤더가_붙는다(api_client):
    response = api_client.get(f"/fonts/{FONTSTACK}/{EXISTING_RANGE}.pbf")

    assert response.headers["cache-control"] == "public, max-age=86400"
    assert response.headers["etag"]


def test_같은_글리프는_같은_ETag를_돌려준다(api_client):
    url = f"/fonts/{FONTSTACK}/{EXISTING_RANGE}.pbf"

    assert api_client.get(url).headers["etag"] == api_client.get(url).headers["etag"]


def test_ETag가_같으면_본문없는_304를_돌려준다(api_client):
    url = f"/fonts/{FONTSTACK}/{EXISTING_RANGE}.pbf"
    etag = api_client.get(url).headers["etag"]

    response = api_client.get(url, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.content == b""
    assert response.headers["cache-control"] == "public, max-age=86400"


def test_ETag가_다르면_본문을_다시_내려준다(api_client):
    url = f"/fonts/{FONTSTACK}/{EXISTING_RANGE}.pbf"

    response = api_client.get(url, headers={"If-None-Match": '"stale"'})

    assert response.status_code == 200
    assert response.content


# 없는 범위도 캐시해야 한다 — "비어 있음"을 확인하는 왕복은 있는 범위와
# 똑같이 비싸다.
def test_없는_범위도_캐시_헤더가_붙은_빈_200이다(api_client):
    response = api_client.get(f"/fonts/{FONTSTACK}/{MISSING_RANGE}.pbf")

    assert response.status_code == 200
    assert response.content == b""
    assert response.headers["cache-control"] == "public, max-age=86400"

    etag = response.headers["etag"]
    revalidated = api_client.get(
        f"/fonts/{FONTSTACK}/{MISSING_RANGE}.pbf",
        headers={"If-None-Match": etag},
    )
    assert revalidated.status_code == 304


def test_잘못된_범위는_잘못된요청_응답을_반환한다(api_client):
    response = api_client.get(f"/fonts/{FONTSTACK}/100-200.pbf")

    assert response.status_code == 400


# 경로 조작으로 fonts 디렉터리 밖 파일을 읽을 수 없어야 한다.
def test_경로_조작은_빈_응답으로_떨어진다(api_client):
    response = api_client.get(f"/fonts/..%2F..%2Fapp/{EXISTING_RANGE}.pbf")

    assert response.status_code in {200, 404}
    if response.status_code == 200:
        assert response.content == b""


# 역슬래시(Windows 구분자)로도 상위 디렉터리를 탈출할 수 없어야 한다.
def test_역슬래시_경로_조작도_막힌다(api_client):
    response = api_client.get(f"/fonts/..%5C..%5Capp/{EXISTING_RANGE}.pbf")

    assert response.status_code in {200, 404}
    if response.status_code == 200:
        assert response.content == b""


# 점으로 시작하는 이름(숨김/상위 참조)도 실 파일을 열지 않고 빈 응답으로 떨어진다.
def test_점으로_시작하는_폰트명은_빈_응답으로_떨어진다(api_client):
    response = api_client.get(f"/fonts/.hidden/{EXISTING_RANGE}.pbf")

    assert response.status_code in {200, 404}
    if response.status_code == 200:
        assert response.content == b""


# 여러 폰트 중 조작된 이름은 건너뛰고, 실재하는 폰트가 있으면 그걸 돌려준다.
def test_여러_폰트스택에서_조작된_이름은_건너뛴다(api_client):
    response = api_client.get(f"/fonts/.evil,{FONTSTACK}/{EXISTING_RANGE}.pbf")

    assert response.status_code == 200
    assert response.content

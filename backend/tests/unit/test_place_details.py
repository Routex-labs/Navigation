"""매장 상세 오버레이 로더 단위 테스트.

로더의 계약은 "디렉터리가 없어도 조용히 빈 dict"다. 데이터 작성이 API보다 늦게
끝나는 순서를 전제로 하기 때문이고, 이게 깨지면 데이터가 없는 동안 상세 API 전체가
500을 내며 클라이언트 작업이 막힌다.
"""

import json

from app.repositories.place_details import load_overlays


def test_디렉터리가_없으면_빈_dict를_반환한다(tmp_path):
    assert load_overlays(tmp_path / "없는폴더") == {}


def test_파일이_없어도_빈_dict를_반환한다(tmp_path):
    assert load_overlays(tmp_path) == {}


def test_오버레이_파일을_id로_병합한다(tmp_path):
    (tmp_path / "b1-food.json").write_text(
        json.dumps(
            {
                "PO-a": {"name": "가게A", "summary": "한 줄 소개"},
                "PO-b": {"name": "가게B", "tags": ["포장"]},
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    overlays = load_overlays(tmp_path)

    assert set(overlays) == {"PO-a", "PO-b"}
    assert overlays["PO-a"]["summary"] == "한 줄 소개"


# "_"로 시작하는 파일은 스키마 선언 같은 메타데이터다. 오버레이로 읽으면
# 스키마의 최상위 키가 매장 id로 둔갑한다.
def test_언더스코어로_시작하는_파일은_읽지_않는다(tmp_path):
    (tmp_path / "_schema.json").write_text(
        json.dumps({"sections": ["summary"]}), encoding="utf-8"
    )

    assert load_overlays(tmp_path) == {}

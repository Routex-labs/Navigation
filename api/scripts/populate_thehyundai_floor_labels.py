"""Populate readable store/facility labels for The Hyundai Seoul floor screenshots.

This keeps geometry empty on purpose. The screenshots are useful enough for
label transcription, but guessing polygons would pollute the map data.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


BASE = Path(__file__).resolve().parents[1] / "app" / "data" / "vector_maps" / "thehyundai-seoul"


STORES_BY_FLOOR: dict[str, list[str]] = {
    "2f": [
        "골든구스",
        "토템",
        "알렉산더 스튜디오",
        "빌리키안스키",
        "몰리넬 컬렉션",
        "아미(남/여)",
        "메종 마르지엘라(남/여)",
        "메종 미하라 야스히로",
        "투미",
        "에르노",
        "아워레가시",
        "운이(남/여)",
        "크먼폰(남/여)",
        "보아르오(남/여)",
        "지니후",
        "몽상",
        "플로스 데스토",
        "아조 바이 아크(여)",
        "R13",
        "MSGM",
        "아페쎄(남/여)",
        "옴므플리세",
        "스위트부스스키",
        "일레븐티",
        "스톤아일랜드",
        "맥스마라",
        "프라다(남)",
        "우영미",
        "군지",
        "두칸두칸",
        "언더커버",
        "드롤드무슈",
        "베이프",
        "Y-3",
        "질샌",
        "랩 플레이트",
        "젠조",
        "루이비통(남)",
        "크롬하츠",
        "라익 카",
        "PBG(클리닉)",
        "에이틴 클리닉",
        "몽클랑",
        "코스티",
        "시템포",
        "IWC",
        "오요가",
        "오프리밍",
        "루디",
        "티그르마이",
        "그림 선글라스",
    ],
    "3f": [
        "에브뉴준오(헤어숍)",
        "시스템",
        "SJSJ",
        "앤디스벨",
        "눈나 주얼리",
        "마인",
        "타임",
        "구호",
        "더 캐시미어",
        "조이그라이슨",
        "딘알마",
        "POP-UP STUDIO B",
        "이비엠",
        "데빈스텔",
        "쿠메",
        "TENC",
        "베로니카 비어드",
        "모드맨",
        "시프트G",
        "CP컴퍼니",
        "아이엠샵",
        "시리즈 코너",
        "스펠프",
        "벨벳트렁크",
        "에고",
        "버윅",
        "렌디",
        "로라스 블랑",
        "듀퐁",
        "클럽모나코",
        "아스페시",
        "준지",
        "송지오",
        "DKNY",
        "비이커",
        "프레이트",
        "띠어리",
        "슈트서플라이",
        "플로",
        "바버",
        "노이스",
        "온",
        "시스템 옴므",
        "타임옴므",
        "메종키츠네(남/여)",
        "솔리드옴므",
        "블루레몬",
    ],
    "4f": [
        "타이틀리스트",
        "제이린드버그",
        "브리핑골프",
        "세인트앤드류스",
        "크랙앤칼",
        "갤러웨이",
        "PXG",
        "나이키골프",
        "티노5",
        "만다리나덕",
        "라코스테",
        "반클",
        "휴고",
        "지포어",
        "웨일른",
        "렉켄",
        "스노우피크",
        "안다르",
        "가민",
        "휠라",
        "라이더",
        "써코니",
        "쿨러닝컴퍼니",
        "바르브",
        "두오모라이팅",
        "프롤라",
        "리바트 토탈",
        "윌슨",
        "시다스",
        "샤우스케어룸",
        "랑방블랑",
        "A.P.C 골프",
        "웨스트엘름",
        "일리얼스소노마",
        "리네로제",
        "에싸",
        "차이리네",
        "무브먼트랩",
        "씰리",
        "지누스",
        "시몬스",
        "템퍼",
    ],
    "5f": [
        "에뜨와",
        "THE AMBASSY OF VICTORY",
        "We.pet",
        "젤리캣",
        "다이슨 슈퍼소닉",
        "플레이인더박스",
        "레고LCS",
        "디즈니스토어",
        "LG 메가 스토어",
        "쁘띠플래닛(유아휴게실)",
        "쁘띠 스토리",
        "압소바",
        "스토케",
        "아이러브제이",
        "타티네쇼콜라",
        "랄프로렌 칠드런",
        "베네베네",
        "블루보틀",
        "번패티번",
        "사운즈포레스트(정원)",
        "마이크로 스토어",
        "파냐스낵",
        "세컨스킨",
        "버디프렌즈",
        "꼬모소이",
        "도레미",
        "오르시떼",
        "다르시",
        "쎈느",
        "로아앤제인",
        "다이슨",
        "에이스",
        "삼성스토어/바로서비스",
        "자스민 라운지",
    ],
    "6f": [
        "세이지 라운지",
        "TUNE",
        "ALT.1",
        "티켓 부스",
        "계시 가능장소",
        "SMT 라운지",
        "이탈리",
        "CH 1985",
        "카페 H",
        "이탈리 마켓",
        "나의가야",
        "리스토란테 에오",
        "고디바",
        "PDR",
        "도원스타일",
        "베르그",
        "오픈 YY",
        "팝마트",
        "나이키 라이즈",
        "점프프레이업",
        "솝",
        "사회화가",
        "상칼제",
        "ARKET",
        "ARKET CAFE",
        "케이스티파이",
        "ATTAG",
    ],
    "b1": [
        "마일스톤",
        "팡파리(포장)",
        "타스코 오렌지나무(문구)",
        "Wine Works",
        "베즐리",
        "카멜커피",
        "오르랭커",
        "정육",
        "수산",
        "야채",
        "과일",
        "프레쉬테이블 친환경농산물",
        "기프트가든",
        "후르츠온",
        "잭슨피자 압구",
        "정관장",
        "더플러스 하우스",
        "코코팜",
        "해리커피",
        "HMR/간편식/주류",
        "그로서리/음료/유제품/치즈",
        "오르베리",
        "마유유 마라탕",
        "카페 레이어드",
        "더테이블 베이커리",
        "먼데이글 무직업",
        "마츠노 하나",
        "김자바이린",
        "사브미당",
        "22 FOOD TRUCK PIAZZA",
        "조앤더주스",
        "푸마만",
        "공항",
        "효우섬",
        "메이루",
        "한솔냉면",
        "온드린",
        "전주선비빔",
        "본가스시",
        "공차",
        "빅코미",
        "유방녕",
        "테디뵈르하우스",
        "파이브가이즈",
        "강호연파 멤버님",
        "이오라진교",
        "베통스타코",
        "식품 행사장",
    ],
    "b2": [
        "뉴발란스",
        "HDEX",
        "노스페이스 화이트라벨",
        "CK 진",
        "POP-UP WEST",
        "아디다스 스튜디오",
        "코닥 x 디오디",
        "크록스",
        "나이스웨더",
        "MLB",
        "AAPE",
        "캉골클럽",
        "더샛",
        "THISISNEVERTHAT",
        "쿠어",
        "망고매니플리즈",
        "시에",
        "플리츠룸",
        "데우스 엑스 마키나",
        "인사일런스",
        "구호플러스",
        "세터",
        "산산기어",
        "포인트 오브 뷰",
        "프로그램",
        "PEER",
        "마뗑킴",
        "더채널",
        "하이츠 익스체인지",
        "BeCLEAN(비클린)",
        "스미스앤레더",
        "베호트",
        "필아이다이",
        "시티브리즈",
        "오픈 YY",
        "팝마트",
        "나이키 라이즈",
        "ARKET",
        "ARKET CAFE",
        "팝업 ICONIC B2",
        "마리떼프랑소와저버/LMC",
        "아프리카안경",
        "스탠드오일",
        "이기스",
        "YPHAUS",
    ],
}


AMENITIES_BY_FLOOR: dict[str, list[str]] = {
    "b3": ["parking_zone_labels_unverified", "elevator", "escalator", "restroom"],
    "b4": ["parking_zone_labels_unverified", "elevator", "escalator", "restroom"],
    "b5": ["parking_zone_labels_unverified", "elevator", "escalator", "restroom"],
    "b6": ["parking_zone_labels_unverified", "elevator", "escalator", "restroom"],
}


def slug(text: str) -> str:
    value = re.sub(r"[^0-9a-zA-Z가-힣]+", "-", text).strip("-").lower()
    return value or "label"


def populate_stores() -> None:
    for floor, names in STORES_BY_FLOOR.items():
        path = BASE / f"{floor}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["extraction_status"] = "labels_transcribed_manual_review_pending"
        data["stores"] = [
            {
                "id": f"store-{floor}-{idx:03d}-{slug(name)}",
                "name": name,
                "source": "manual_transcription_from_original_screenshot",
                "text_confidence": "unverified",
                "label_status": "pending_manual_review",
                "geometry_status": "pending_manual_trace",
                "geometry": None,
                "centroid": None,
            }
            for idx, name in enumerate(names, 1)
        ]
        notes = [
            note
            for note in data.get("notes", [])
            if "Store names are transcribed" not in note
        ]
        notes.append(
            "Store names are unverified manual transcriptions from the original screenshot; "
            "text and polygon associations remain pending manual review."
        )
        data["notes"] = notes
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def populate_parking_amenities() -> None:
    for floor, amenities in AMENITIES_BY_FLOOR.items():
        path = BASE / f"{floor}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["extraction_status"] = "parking_floor_registered_labels_unreliable"
        data["amenities"] = [
            {
                "id": f"amenity-{floor}-{idx:03d}-{slug(name)}",
                "type": name,
                "source": "manual_review_from_original_screenshot",
                "text_confidence": "unreliable_for_small_parking_slot_labels"
                if name == "parking_zone_labels_unverified"
                else "visible_icon_only",
                "geometry_status": "pending_manual_trace",
                "geometry": None,
                "centroid": None,
            }
            for idx, name in enumerate(amenities, 1)
        ]
        notes = [
            note
            for note in data.get("notes", [])
            if "Small parking stall/zone labels" not in note
        ]
        notes.append(
            "Small parking stall/zone labels are too faint to extract reliably "
            "from this screenshot; only coarse amenity classes are recorded."
        )
        data["notes"] = notes
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def main() -> None:
    populate_stores()
    populate_parking_amenities()


if __name__ == "__main__":
    main()

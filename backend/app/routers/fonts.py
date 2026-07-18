# MapLibre 글리프(SDF 폰트) 서빙 라우터.
#   GET /fonts/{fontstack}/{start}-{end}.pbf → 글리프 범위 파일
# MapLibre는 스타일의 glyphs 템플릿(.../fonts/{fontstack}/{range}.pbf)으로
# 심볼 레이어 텍스트에 필요한 256자 단위 범위를 그때그때 요청한다. 이 템플릿이
# 없거나 응답이 실패하면 심볼 레이어의 레이아웃이 끝나지 않아 같은 타일의 fill
# 레이어까지 통째로 렌더링되지 않으므로, 글리프는 지도 표시의 선택 사항이 아니다.
# 글리프 파일은 resources/fonts/<fontstack>/ 아래에 커밋되어 있다(scripts/transform/make_glyphs.js
# 가 Noto Sans KR에서 생성). 타일과 같은 출처에서 내려주므로 외부 폰트 CDN 없이
# 오프라인/사내망에서도 동작한다.

from pathlib import Path

from fastapi import APIRouter, HTTPException, Response

router = APIRouter(prefix="/fonts", tags=["fonts"])

FONTS_DIR = Path(__file__).resolve().parents[2] / "resources" / "fonts"

# 빈 glyphs 메시지의 PBF 인코딩. 커밋해 둔 범위 밖(예: 한자)을 요청받았을 때
# 404 대신 이걸 돌려준다 — MapLibre가 404를 스타일 오류로 보고 심볼 레이아웃을
# 멈추게 두지 않고, 해당 글자만 조용히 비게 만든다.
_EMPTY_GLYPHS_PBF = b""


# 글리프 범위 하나를 돌려준다. 없는 범위는 빈 200.
@router.get("/{fontstack}/{start}-{end}.pbf")
def get_glyph_range(fontstack: str, start: int, end: int) -> Response:
    if start < 0 or end < start or end > 65535 or end - start != 255:
        raise HTTPException(status_code=400, detail="Invalid glyph range")

    # fontstack은 쉼표로 여러 폰트가 올 수 있다(text-font 배열 그대로). 우리가
    # 가진 첫 폰트를 쓰고, 하나도 없으면 빈 응답으로 떨어뜨린다.
    for name in (part.strip() for part in fontstack.split(",")):
        # 경로 조작 방지: 디렉터리 이름 한 칸만 허용한다.
        if not name or "/" in name or "\\" in name or name.startswith("."):
            continue
        path = FONTS_DIR / name / f"{start}-{end}.pbf"
        try:
            resolved = path.resolve()
            resolved.relative_to(FONTS_DIR.resolve())
        except (OSError, ValueError):
            continue
        if resolved.is_file():
            return Response(content=resolved.read_bytes(), media_type="application/x-protobuf")

    return Response(content=_EMPTY_GLYPHS_PBF, media_type="application/x-protobuf")

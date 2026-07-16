"""개발 DB 초기화(drop_all → create_all)와 지도 데이터 시드를 한 번에 실행하는 CLI.

thehyundai-seoul(1F)은 legacy navigation_1f.json 대신 FloorGraph Studio 익스포트
(app/data/studio/thehyundai-seoul)로 시드한다. legacy JSON은 건물명 계승에만 쓰인다.

실행 방법 (api/ 디렉토리에서):
  python -m scripts.reset_and_seed
  python -m scripts.reset_and_seed --json app/data/navigation_test_center_1f.json
"""

from __future__ import annotations

import argparse
from pathlib import Path

from scripts import studio_adapter
from scripts.reset_database import reset_database
from scripts.seed_navigation import DEFAULT_VECTOR_DIR, seed_navigation

API_ROOT = Path(__file__).resolve().parents[1]

# 개발 DB에 기본으로 담는 legacy 건물 데이터셋 목록(thehyundai-seoul은 Studio로 별도 시드).
DEFAULT_DATASETS = [
    API_ROOT / "app" / "data" / "navigation_test_center_1f.json",
]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json",
        type=Path,
        action="append",
        help="적재할 legacy navigation JSON (여러 번 지정 가능, 미지정 시 기본 데이터셋 전체)",
    )
    parser.add_argument("--vector-dir", type=Path, default=DEFAULT_VECTOR_DIR)
    parser.add_argument(
        "--studio-floor",
        nargs="*",
        default=["1f"],
        help="Studio로 시드할 thehyundai-seoul 층 목록(빈 리스트면 Studio 시드를 건너뜀)",
    )
    args = parser.parse_args()

    datasets = args.json or DEFAULT_DATASETS

    reset_database()
    for json_path in datasets:
        seed_navigation(json_path, args.vector_dir)
        print(f"적재 완료: {json_path}")
    if args.studio_floor:
        studio_adapter.seed_studio(args.studio_floor, vector_path=args.vector_dir)
        print(f"적재 완료: studio/thehyundai-seoul {args.studio_floor}")
    print("개발 DB 초기화 및 지도 데이터 적재 완료")

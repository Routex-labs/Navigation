"""개발 DB 초기화(drop_all → create_all)와 지도 데이터 시드를 한 번에 실행하는 CLI.

실행 방법 (api/ 디렉토리에서):
  python -m scripts.reset_and_seed
  python -m scripts.reset_and_seed --json app/data/navigation_1f.json --json app/data/navigation_test_center_1f.json
"""

from __future__ import annotations

import argparse
from pathlib import Path

from scripts.reset_database import reset_database
from scripts.seed_navigation import DEFAULT_JSON, DEFAULT_VECTOR_DIR, seed_navigation

API_ROOT = Path(__file__).resolve().parents[1]

# 개발 DB에 기본으로 담는 건물 데이터셋 목록.
DEFAULT_DATASETS = [
    DEFAULT_JSON,
    API_ROOT / "app" / "data" / "navigation_test_center_1f.json",
]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json",
        type=Path,
        action="append",
        help="적재할 navigation JSON (여러 번 지정 가능, 미지정 시 기본 데이터셋 전체)",
    )
    parser.add_argument("--vector-dir", type=Path, default=DEFAULT_VECTOR_DIR)
    args = parser.parse_args()

    datasets = args.json or DEFAULT_DATASETS

    reset_database()
    for json_path in datasets:
        seed_navigation(json_path, args.vector_dir)
        print(f"적재 완료: {json_path}")
    print("개발 DB 초기화 및 지도 데이터 적재 완료")

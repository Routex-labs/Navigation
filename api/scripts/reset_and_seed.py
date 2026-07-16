"""개발 DB를 초기화하고 Studio 층 데이터만 적재하는 CLI.

현재 기본 범위는 더현대 서울 Studio 1F다. 레거시 navigation JSON은 적재하지 않는다.

실행 방법 (api/ 디렉토리에서):
  python -m scripts.reset_and_seed
  python -m scripts.reset_and_seed --floor 1f
"""

from __future__ import annotations

import argparse
from scripts.reset_database import reset_database
from scripts.studio_adapter import seed_studio

DEFAULT_FLOORS = ["1f"]


def reset_and_seed_studio(floors: list[str] = DEFAULT_FLOORS) -> None:
    """기존 DB를 비운 뒤 지정한 Studio 층만 적재한다."""
    reset_database()
    seed_studio(floors)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--floor",
        nargs="*",
        default=DEFAULT_FLOORS,
        help="적재할 Studio 층 코드(기본: 1f)",
    )
    args = parser.parse_args()

    reset_and_seed_studio(args.floor)
    print(f"개발 DB 초기화 및 Studio 데이터 적재 완료: {', '.join(args.floor)}")

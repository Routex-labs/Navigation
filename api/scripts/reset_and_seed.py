"""개발 DB를 초기화하고 더현대 서울 Studio 데이터를 적재하는 CLI.

적재 범위는 app/data/studio/thehyundai-seoul에 있는 층 전부다(현재 1F~4F).
층 목록은 studio_adapter가 디렉토리에서 찾는다.

실행 방법 (api/ 디렉토리에서):
  python -m scripts.reset_and_seed
"""

from __future__ import annotations

from scripts.reset_database import reset_database
from scripts.studio_adapter import seed_studio


def reset_and_seed_studio() -> None:
    """기존 DB를 비운 뒤 Studio 전 층을 적재한다."""
    reset_database()
    seed_studio()


if __name__ == "__main__":
    reset_and_seed_studio()
    print("개발 DB 초기화 및 Studio 데이터 적재 완료")

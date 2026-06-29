"""
app/repositories/memory_building_repository.py
==============================================
초기 운영용 MemoryBuildingRepository.

앱 시작 시 JSON 샘플 데이터를 Building 도메인 객체로 읽어 메모리에 보관한다.
나중에 SQL을 도입하면 같은 BuildingRepository 계약을 구현하는 SqlBuildingRepository로 교체한다.
"""

import json
from pathlib import Path

from app.domain.building import Building

_DEFAULT_DATA_PATH = Path(__file__).parent.parent / "data" / "sample_building.json"


class MemoryBuildingRepository:
    def __init__(
        self,
        buildings: list[Building] | None = None,
        data_path: Path = _DEFAULT_DATA_PATH,
    ):
        if buildings is None:
            buildings = [self._load_building(data_path)]
        self._buildings = {building.id: building for building in buildings}

    def find_all(self) -> list[Building]:
        return list(self._buildings.values())

    def find_by_id(self, building_id: str) -> Building | None:
        return self._buildings.get(building_id)

    def _load_building(self, data_path: Path) -> Building:
        with open(data_path, encoding="utf-8") as f:
            return Building.from_dict(json.load(f))

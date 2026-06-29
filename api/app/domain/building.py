"""
app/domain/building.py
======================
Building 도메인 객체.

FastAPI 응답 모델(Pydantic schema)과 분리해 서비스/저장소 내부에서 사용하는
순수 Python 객체를 둔다. 나중에 SQL 모델이 생겨도 서비스는 이 도메인 객체를 기준으로 동작한다.
"""

from copy import deepcopy
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Building:
    id: str
    name: str
    floors: list[int]
    floor_data: dict[str, dict[str, Any]]

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Building":
        return cls(
            id=data["id"],
            name=data["name"],
            floors=list(data["floors"]),
            floor_data=deepcopy(data["floor_data"]),
        )

    def to_summary(self) -> dict[str, Any]:
        return {"id": self.id, "name": self.name, "floors": list(self.floors)}

    def get_floor_geojson(self, floor: int) -> dict[str, Any] | None:
        geojson = self.floor_data.get(str(floor))
        if geojson is None:
            return None
        return deepcopy(geojson)

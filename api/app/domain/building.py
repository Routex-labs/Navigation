"""
app/domain/building.py
======================
Building 도메인 데이터 객체.

FastAPI 응답 모델(Pydantic schema)과 분리해 서비스/저장소 내부에서 사용하는
순수 Python 객체를 둔다. 비즈니스 로직은 Service가 담당하고, Domain은 데이터만 보관한다.
"""

from copy import deepcopy
from typing import Any


class Building:
    def __init__(
        self,
        id: str,
        name: str,
        floors: list[int],
        floor_data: dict[str, dict[str, Any]],
    ):
        self._id = id
        self._name = name
        self._floors = list(floors)
        self._floor_data = deepcopy(floor_data)

    @property
    def id(self) -> str:
        return self._id

    @id.setter
    def id(self, id: str) -> None:
        self._id = id

    @property
    def name(self) -> str:
        return self._name

    @name.setter
    def name(self, name: str) -> None:
        self._name = name

    @property
    def floors(self) -> list[int]:
        return list(self._floors)

    @floors.setter
    def floors(self, floors: list[int]) -> None:
        self._floors = list(floors)

    @property
    def floor_data(self) -> dict[str, dict[str, Any]]:
        return deepcopy(self._floor_data)

    @floor_data.setter
    def floor_data(self, floor_data: dict[str, dict[str, Any]]) -> None:
        self._floor_data = deepcopy(floor_data)

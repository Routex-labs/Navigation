"""
app/repositories/building_repository.py
=======================================
BuildingRepository 인터페이스 역할.

Python에서는 Spring Boot의 interface 대신 Protocol을 사용해 저장소가 제공해야 하는
메서드 계약을 표현한다.
"""

from typing import Protocol

from app.domain.building import Building


class BuildingRepository(Protocol):
    def find_all(self) -> list[Building]:
        """저장된 모든 건물 도메인 객체를 반환한다."""
        ...

    def find_by_id(self, building_id: str) -> Building | None:
        """building_id에 해당하는 건물 도메인 객체를 반환한다."""
        ...

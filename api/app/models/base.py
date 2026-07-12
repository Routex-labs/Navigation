"""모든 ORM 엔티티가 상속하는 공통 DeclarativeBase."""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass

from sqlalchemy.orm import DeclarativeBase


# 모든 ORM 엔티티가 상속하는 공통 DeclarativeBase.
class Base(DeclarativeBase):
    pass

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy.orm import Session


def get_db(request: Request) -> Iterator[Session]:
    """Uma sessão do SQLAlchemy por request. Os services fazem commit explícito;
    o que não foi commitado é descartado ao fechar."""
    db: Session = request.app.state.sessionmaker()
    try:
        yield db
    finally:
        db.close()

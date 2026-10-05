"""Autocomplete de artistas já usados nas sessões."""

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.models import SessionModel
from app.domain.text import normalize_artist
from app.schemas.artists import ArtistOut


class IdentityService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def search_artists(self, q: str | None, limit: int = 10) -> list[ArtistOut]:
        """Artistas agrupados pela forma normalizada ("Queen Official" = "queen"), mais usados
        primeiro. O nome exibido é a grafia usada na sessão mais recente."""
        key = normalize_artist(q)
        conditions = [SessionModel.artist_key != ""]
        if key:
            # Prefixo do nome ou de qualquer palavra dele.
            conditions.append(
                or_(
                    SessionModel.artist_key.startswith(key, autoescape=True),
                    SessionModel.artist_key.contains(f" {key}", autoescape=True),
                )
            )
        sessions_count = func.count().label("sessions")
        groups = self.db.execute(
            select(SessionModel.artist_key, sessions_count)
            .where(*conditions)
            .group_by(SessionModel.artist_key)
            .order_by(sessions_count.desc(), SessionModel.artist_key)
            .limit(limit)
        ).all()
        if not groups:
            return []

        names: dict[str, str] = {}
        rows = self.db.execute(
            select(SessionModel.artist_key, SessionModel.artist)
            .where(SessionModel.artist_key.in_([g.artist_key for g in groups]))
            .order_by(SessionModel.created_at.desc())
        ).all()
        for artist_key, artist in rows:
            names.setdefault(artist_key, artist)
        return [ArtistOut(name=names[g.artist_key], sessions=g.sessions) for g in groups]

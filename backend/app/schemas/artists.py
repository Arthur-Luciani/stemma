from pydantic import BaseModel


class ArtistOut(BaseModel):
    name: str
    # Quantas sessões já usaram esse artista.
    sessions: int

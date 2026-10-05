from pydantic import BaseModel, ConfigDict


class SearchResultOut(BaseModel):
    """Um resultado da busca. Os campos casam com o `SessionCreate` (rascunho)."""

    model_config = ConfigDict(from_attributes=True)

    source_url: str
    source_title: str
    source_channel: str | None
    duration_s: float | None
    thumbnail_url: str | None
    # Sugestões tiradas do título do vídeo/canal; o usuário confirma.
    artist: str
    title: str


class SearchOut(BaseModel):
    items: list[SearchResultOut]

"""Busca de fontes (Descobrir): texto ou link, via yt-dlp."""

from app.pipeline.download import YtDlpClient
from app.schemas.search import SearchResultOut


class SearchService:
    def __init__(self, client: YtDlpClient) -> None:
        self.client = client

    def search(self, query: str) -> list[SearchResultOut]:
        """Lista vazia = nenhum resultado; YouTube fora do ar levanta `youtube_unavailable`."""
        return [SearchResultOut.model_validate(r) for r in self.client.search(query)]

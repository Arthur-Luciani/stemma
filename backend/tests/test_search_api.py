from fastapi.testclient import TestClient

from app.api.deps import get_search_service
from app.domain.errors import AppError
from app.pipeline.download import SearchResult
from app.services.search import SearchService

RESULT = SearchResult(
    source_url="https://www.youtube.com/watch?v=abc123",
    source_title="Queen - Bohemian Rhapsody (Official Video)",
    source_channel="Queen Official",
    duration_s=359.0,
    thumbnail_url="https://i.ytimg.com/vi/abc123/hqdefault.jpg",
    artist="Queen",
    title="Bohemian Rhapsody",
)


class FakeClient:
    def __init__(self, results: list[SearchResult] | None = None, error: AppError | None = None):
        self.results = results or []
        self.error = error
        self.queries: list[str] = []

    def search(self, query: str) -> list[SearchResult]:
        self.queries.append(query)
        if self.error is not None:
            raise self.error
        return self.results


def use_client(client: TestClient, fake: FakeClient) -> None:
    client.app.dependency_overrides[get_search_service] = lambda: SearchService(fake)  # type: ignore[attr-defined,arg-type]


def test_busca_devolve_resultados_prontos_para_o_rascunho(client: TestClient) -> None:
    fake = FakeClient([RESULT])
    use_client(client, fake)

    response = client.get("/api/search", params={"q": "queen bohemian"})

    assert response.status_code == 200
    assert response.json() == {
        "items": [
            {
                "source_url": "https://www.youtube.com/watch?v=abc123",
                "source_title": "Queen - Bohemian Rhapsody (Official Video)",
                "source_channel": "Queen Official",
                "duration_s": 359.0,
                "thumbnail_url": "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
                "artist": "Queen",
                "title": "Bohemian Rhapsody",
            }
        ]
    }
    assert fake.queries == ["queen bohemian"]
    # O resultado vira rascunho sem conversão.
    draft = client.post("/api/sessions", json=response.json()["items"][0])
    assert draft.status_code == 201


def test_busca_sem_resultados(client: TestClient) -> None:
    use_client(client, FakeClient([]))

    response = client.get("/api/search", params={"q": "xyzxyz"})

    assert response.status_code == 200
    assert response.json() == {"items": []}


def test_youtube_indisponivel(client: TestClient) -> None:
    error = AppError("youtube_unavailable", "Não deu para falar com o YouTube agora.", 502)
    use_client(client, FakeClient(error=error))

    response = client.get("/api/search", params={"q": "queen"})

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "youtube_unavailable"


def test_busca_vazia_e_invalida(client: TestClient) -> None:
    assert client.get("/api/search", params={"q": ""}).status_code == 422
    assert client.get("/api/search").status_code == 422

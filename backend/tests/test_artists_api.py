from fastapi.testclient import TestClient

from tests.conftest import create_session


def test_autocomplete_agrupa_por_artista_normalizado(client: TestClient) -> None:
    create_session(client, artist="Queen Official", title="a")
    create_session(client, artist="queen", title="b")
    create_session(client, artist="Queen", title="c")
    create_session(client, artist="Oasis", title="d")

    body = client.get("/api/artists").json()

    # Mais usados primeiro; nome = grafia da sessão mais recente.
    assert body == [{"name": "Queen", "sessions": 3}, {"name": "Oasis", "sessions": 1}]


def test_autocomplete_por_prefixo_de_palavra_sem_acento(client: TestClient) -> None:
    create_session(client, artist="Legião Urbana")
    create_session(client, artist="Urbano Silva")
    create_session(client, artist="Suburbanos")

    names = [a["name"] for a in client.get("/api/artists", params={"q": "urba"}).json()]
    legiao = client.get("/api/artists", params={"q": "LEGIÃO"}).json()

    assert sorted(names) == ["Legião Urbana", "Urbano Silva"]
    assert legiao == [{"name": "Legião Urbana", "sessions": 1}]


def test_autocomplete_sem_resultados(client: TestClient) -> None:
    create_session(client, artist="Queen")

    assert client.get("/api/artists", params={"q": "zz"}).json() == []


def test_autocomplete_respeita_limite(client: TestClient) -> None:
    for name in ("A1", "A2", "A3"):
        create_session(client, artist=name)

    assert len(client.get("/api/artists", params={"limit": 2}).json()) == 2
    assert client.get("/api/artists", params={"limit": 0}).status_code == 422


def test_autocomplete_com_curinga_do_like(client: TestClient) -> None:
    create_session(client, artist="Queen")

    # `%` e `_` não podem virar curinga do LIKE.
    assert client.get("/api/artists", params={"q": "%"}).json() == [
        {"name": "Queen", "sessions": 1}
    ]

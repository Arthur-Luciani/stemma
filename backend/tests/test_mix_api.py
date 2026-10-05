import uuid
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from tests.conftest import create_session

STEMS = ("vocals", "drums", "bass", "other")


def _mix(**overrides: object) -> dict[str, object]:
    body: dict[str, object] = {
        "stems": {
            "vocals": {"volume": 0, "pan": 0, "mute": True, "solo": False},
            "drums": {"volume": 80, "pan": -0.5, "mute": False, "solo": False},
            "bass": {"volume": 100, "pan": 0.25, "mute": False, "solo": True},
            "other": {"volume": 64.5, "pan": 1, "mute": False, "solo": False},
        },
        "preset": "custom",
        "loop_a_s": 12.5,
        "loop_b_s": 30,
    }
    body.update(overrides)
    return body


def test_mix_padrao_quando_nao_salvo(client: TestClient) -> None:
    session = create_session(client)

    response = client.get(f"/api/sessions/{session['id']}/mix")

    assert response.status_code == 200
    assert response.json() == {
        "stems": {s: {"volume": 100, "pan": 0, "mute": False, "solo": False} for s in STEMS},
        "preset": "original",
        "loop_a_s": None,
        "loop_b_s": None,
        "updated_at": None,
    }


def test_salva_e_restaura_mix(client: TestClient) -> None:
    session = create_session(client)
    url = f"/api/sessions/{session['id']}/mix"

    saved = client.put(url, json=_mix())
    restored = client.get(url)

    assert saved.status_code == 200
    assert restored.json() == saved.json()
    body = restored.json()
    assert body["stems"]["other"]["volume"] == 64.5
    assert body["stems"]["bass"]["solo"] is True
    assert (body["loop_a_s"], body["loop_b_s"]) == (12.5, 30)
    assert datetime.fromisoformat(body["updated_at"]).tzinfo is not None


def test_salvar_de_novo_substitui(client: TestClient) -> None:
    session = create_session(client)
    url = f"/api/sessions/{session['id']}/mix"
    client.put(url, json=_mix())

    client.put(url, json=_mix(preset="no_vocals", loop_a_s=None, loop_b_s=None))

    body = client.get(url).json()
    assert body["preset"] == "no_vocals"
    assert body["loop_a_s"] is None


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        ({"loop_a_s": 10, "loop_b_s": None}, "loop precisa dos dois pontos"),
        ({"loop_a_s": 30, "loop_b_s": 10}, "ponto A do loop precisa vir antes"),
        ({"loop_a_s": -1, "loop_b_s": 10}, "loop_a_s"),
        ({"preset": "rock"}, "preset"),
        ({"stems": {"vocals": {"volume": 50}}}, "faltam os stems: drums, bass, other"),
    ],
)
def test_mix_invalido(client: TestClient, overrides: dict[str, object], expected: str) -> None:
    session = create_session(client)

    response = client.put(f"/api/sessions/{session['id']}/mix", json=_mix(**overrides))

    assert response.status_code == 422
    assert expected in response.json()["error"]["message"]


@pytest.mark.parametrize(
    "stem",
    [
        {"volume": 101},
        {"volume": -1},
        {"pan": 1.5},
        {"pan": -2},
        {"gain": 3},
    ],
)
def test_valores_de_stem_fora_da_faixa(client: TestClient, stem: dict[str, object]) -> None:
    session = create_session(client)
    body = _mix()
    body["stems"] = {s: stem for s in STEMS}

    response = client.put(f"/api/sessions/{session['id']}/mix", json=body)

    assert response.status_code == 422


def test_loop_alem_da_duracao(client: TestClient) -> None:
    session = create_session(client, duration_s=20)

    response = client.put(f"/api/sessions/{session['id']}/mix", json=_mix())

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "loop_out_of_range"


def test_mix_de_sessao_inexistente(client: TestClient) -> None:
    url = f"/api/sessions/{uuid.uuid4()}/mix"

    assert client.get(url).status_code == 404
    assert client.put(url, json=_mix()).status_code == 404

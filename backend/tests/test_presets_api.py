import uuid

from fastapi.testclient import TestClient

STEMS = ("vocals", "drums", "bass", "other")


def _stems(**overrides: dict[str, object]) -> dict[str, dict[str, object]]:
    base: dict[str, dict[str, object]] = {
        s: {"volume": 100, "pan": 0, "mute": False} for s in STEMS
    }
    base.update(overrides)
    return base


def _names(client: TestClient) -> list[str]:
    return [p["name"] for p in client.get("/api/presets").json()["items"]]


def test_lista_os_cinco_de_fabrica(client: TestClient) -> None:
    items = client.get("/api/presets").json()["items"]

    assert [p["name"] for p in items] == [
        "Original",
        "Sem voz",
        "Sem bateria",
        "Sem baixo",
        "Só voz",
    ]
    assert [p["position"] for p in items] == [0, 1, 2, 3, 4]
    assert all(p["visible"] for p in items)
    assert items[0]["stems"] == _stems()
    assert items[1]["stems"]["vocals"]["mute"] is True
    assert [s for s in STEMS if items[4]["stems"][s]["mute"]] == ["drums", "bass", "other"]


def test_cria_preset_no_fim_da_lista(client: TestClient) -> None:
    body = {
        "name": " Bateria baixa ",
        "stems": _stems(drums={"volume": 25, "pan": -0.5, "mute": False}),
    }

    response = client.post("/api/presets", json=body)

    assert response.status_code == 201
    created = response.json()
    assert created["name"] == "Bateria baixa"
    assert created["position"] == 5
    assert created["visible"] is True
    assert created["stems"]["drums"] == {"volume": 25, "pan": -0.5, "mute": False}
    assert _names(client)[-1] == "Bateria baixa"


def test_nome_repetido_409_sem_diferenciar_caixa(client: TestClient) -> None:
    response = client.post("/api/presets", json={"name": "sem VOZ", "stems": _stems()})

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "preset_name_taken"


def test_solo_nao_entra_e_stems_precisam_estar_completos(client: TestClient) -> None:
    solo = _stems(bass={"volume": 100, "pan": 0, "mute": False, "solo": True})
    assert client.post("/api/presets", json={"name": "x", "stems": solo}).status_code == 422
    faltando = {"vocals": {"volume": 50}}
    assert client.post("/api/presets", json={"name": "x", "stems": faltando}).status_code == 422


def test_nome_vazio_ou_longo_demais(client: TestClient) -> None:
    for name in ("", "x" * 41):
        assert (
            client.post("/api/presets", json={"name": name, "stems": _stems()}).status_code == 422
        )


def test_altera_nome_mix_e_visibilidade(client: TestClient) -> None:
    preset = client.get("/api/presets").json()["items"][0]

    response = client.patch(
        f"/api/presets/{preset['id']}",
        json={
            "name": "Padrão",
            "visible": False,
            "stems": _stems(bass={"volume": 60, "pan": 0, "mute": False}),
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert (body["name"], body["visible"], body["stems"]["bass"]["volume"]) == ("Padrão", False, 60)
    assert body["position"] == 0


def test_renomear_para_o_proprio_nome_ou_para_outro_existente(client: TestClient) -> None:
    items = client.get("/api/presets").json()["items"]
    first, second = items[0], items[1]

    same = client.patch(f"/api/presets/{first['id']}", json={"name": "ORIGINAL"})
    taken = client.patch(f"/api/presets/{first['id']}", json={"name": second["name"]})

    assert same.status_code == 200
    assert taken.status_code == 409


def test_exclui_inclusive_os_de_fabrica(client: TestClient) -> None:
    for preset in client.get("/api/presets").json()["items"]:
        assert client.delete(f"/api/presets/{preset['id']}").status_code == 204

    assert _names(client) == []


def test_inexistente_404(client: TestClient) -> None:
    missing = uuid.uuid4()
    assert client.patch(f"/api/presets/{missing}", json={"name": "a"}).status_code == 404
    assert client.delete(f"/api/presets/{missing}").status_code == 404


def test_reordena(client: TestClient) -> None:
    ids = [p["id"] for p in client.get("/api/presets").json()["items"]]

    response = client.put("/api/presets/order", json={"ids": list(reversed(ids))})

    assert response.status_code == 200
    assert [p["id"] for p in response.json()["items"]] == list(reversed(ids))
    assert _names(client)[0] == "Só voz"


def test_reordenar_exige_todos_os_ids(client: TestClient) -> None:
    ids = [p["id"] for p in client.get("/api/presets").json()["items"]]

    parcial = client.put("/api/presets/order", json={"ids": ids[:-1]})
    repetido = client.put("/api/presets/order", json={"ids": [*ids[:-1], ids[0]]})

    assert parcial.status_code == repetido.status_code == 422
    assert parcial.json()["error"]["code"] == "preset_order_invalid"


def test_novo_preset_depois_de_excluir_vai_para_o_fim(client: TestClient) -> None:
    first = client.get("/api/presets").json()["items"][0]
    client.delete(f"/api/presets/{first['id']}")

    created = client.post("/api/presets", json={"name": "Novo", "stems": _stems()}).json()

    assert created["position"] == 5
    assert _names(client)[-1] == "Novo"


def test_os_de_fabrica_vem_com_icone_e_cor(client: TestClient) -> None:
    items = client.get("/api/presets").json()["items"]

    assert [(p["icon"], p["color"]) for p in items] == [
        ("graphic_eq", None),
        ("mic_off", "vocals"),
        ("volume_off", "drums"),
        ("volume_off", "bass"),
        ("mic", "vocals"),
    ]


def test_cria_com_e_sem_marca(client: TestClient) -> None:
    com = client.post(
        "/api/presets",
        json={"name": "Treino", "stems": _stems(), "icon": "school", "color": "red"},
    ).json()
    sem = client.post("/api/presets", json={"name": "Liso", "stems": _stems()}).json()

    assert (com["icon"], com["color"]) == ("school", "red")
    assert (sem["icon"], sem["color"]) == (None, None)


def test_editar_marca_null_remove_e_omitido_mantem(client: TestClient) -> None:
    preset = client.get("/api/presets").json()["items"][1]
    url = f"/api/presets/{preset['id']}"

    trocado = client.patch(url, json={"icon": "star", "color": "yellow"}).json()
    so_nome = client.patch(url, json={"name": "Karaokê"}).json()
    sem_icone = client.patch(url, json={"icon": None}).json()

    assert (trocado["icon"], trocado["color"]) == ("star", "yellow")
    assert (so_nome["icon"], so_nome["color"]) == ("star", "yellow")
    assert (sem_icone["icon"], sem_icone["color"]) == (None, "yellow")
    assert client.get("/api/presets").json()["items"][1]["icon"] is None


def test_icone_ou_cor_fora_da_lista_422(client: TestClient) -> None:
    for extra in ({"icon": "rocket_launch"}, {"color": "#ff0000"}):
        response = client.post("/api/presets", json={"name": "x", "stems": _stems(), **extra})
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "validation_error"

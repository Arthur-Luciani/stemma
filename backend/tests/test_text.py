import pytest

from app.domain.text import normalize_artist, normalize_text, search_tokens


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Queen", "queen"),
        ("Queen Official", "queen"),
        ("RihannaVEVO", "rihannavevo"),
        ("Rihanna VEVO", "rihanna"),
        ("Legião Urbana", "legiao urbana"),
        ("Daft Punk - Topic", "daft punk"),
        ("  Os   Mutantes ", "os mutantes"),
        ("", ""),
        (None, ""),
    ],
)
def test_normalize_artist(raw: str | None, expected: str) -> None:
    assert normalize_artist(raw) == expected


def test_normalize_text_remove_ruido_de_titulo() -> None:
    assert normalize_text("Bohemian Rhapsody (Official Video) [Remastered 2011]") == (
        "bohemian rhapsody"
    )
    assert normalize_text("Get Lucky feat. Pharrell Williams") == "get lucky"


def test_search_tokens_tira_acento_sem_remover_palavras() -> None:
    assert search_tokens("Canção Remastered — Ao Vivo!") == "cancao remastered ao vivo"

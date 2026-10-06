from app.domain.releases import NoteSection, format_version, parse_release_notes, parse_version

BODY = (
    "## [1.4.1](https://github.com/Arthur-Luciani/stemma/compare/v1.4.0...v1.4.1) (2026-10-06)\n"
    "\n\n### Features\n\n"
    "* **mixer:** loop A–B no celular ([#30](https://github.com/x/y/issues/30)) "
    "([abc1234](https://github.com/x/y/commit/abc1234))\n"
    "* atualizar pelo [app](https://example.com)\n"
    "\n\n### Bug Fixes\n\n"
    "* portas no instalador (porta em uso, 443 de outro app) "
    "([#24](https://github.com/x/y/issues/24)) ([c2417f0](https://github.com/x/y/commit/c2417f0))\n"
    "\n### Miscellaneous Chores\n\n"
    "* qualquer coisa\n"
    "\n### Vazia\n\n"
)


def test_parse_version() -> None:
    assert parse_version("v1.4.2") == (1, 4, 2)
    assert parse_version(" 10.0.1 ") == (10, 0, 1)
    assert parse_version("v1.4") is None
    assert parse_version("1.4.2-beta") is None
    assert parse_version("") is None
    assert format_version((1, 4, 2)) == "1.4.2"


def test_versoes_comparam_como_numeros() -> None:
    assert parse_version("1.10.0") > parse_version("1.9.9")  # type: ignore[operator]


def test_notas_do_release_please_viram_texto_puro() -> None:
    assert parse_release_notes(BODY) == [
        NoteSection("Novidades", ["mixer: loop A–B no celular", "atualizar pelo app"]),
        NoteSection("Correções", ["portas no instalador (porta em uso, 443 de outro app)"]),
        NoteSection("Miscellaneous Chores", ["qualquer coisa"]),
    ]


def test_notas_sem_secoes() -> None:
    assert parse_release_notes("") == []
    assert parse_release_notes("* item solto sem seção") == []

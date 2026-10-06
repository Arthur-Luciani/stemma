"""Versões e notas de release (regras puras, sem rede). Usado pela atualização pelo app."""

import re
from dataclasses import dataclass

_VERSION = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
# Referências que o release-please põe no fim de cada item: `([#24](url))`, `([c2417f0](url))`.
_REF = re.compile(r"\s*\(\[[^\]]*\]\([^)]*\)\)")
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_BOLD = re.compile(r"\*\*([^*]+)\*\*")

# Títulos de seção do release-please (Conventional Commits) em PT-BR.
_SECTION_TITLES = {
    "features": "Novidades",
    "bug fixes": "Correções",
    "performance improvements": "Desempenho",
    "reverts": "Reversões",
    "documentation": "Documentação",
}

Version = tuple[int, int, int]


def parse_version(text: str) -> Version | None:
    """`v1.4.2` ou `1.4.2` → `(1, 4, 2)`; qualquer outra coisa → None."""
    match = _VERSION.match(text.strip())
    if match is None:
        return None
    major, minor, patch = (int(part) for part in match.groups())
    return (major, minor, patch)


def format_version(version: Version) -> str:
    return ".".join(str(part) for part in version)


@dataclass(frozen=True)
class NoteSection:
    title: str
    items: list[str]


def parse_release_notes(body: str) -> list[NoteSection]:
    """Corpo de uma release do release-please → seções com itens em texto puro.

    Ignora o cabeçalho (`## [1.4.1](…) (data)`), traduz os títulos conhecidos, tira links,
    negrito e as referências a PR/commit. Linhas fora de lista são descartadas."""
    sections: list[NoteSection] = []
    current: NoteSection | None = None
    for raw in body.splitlines():
        line = raw.strip()
        if line.startswith("### "):
            title = line[4:].strip()
            current = NoteSection(_SECTION_TITLES.get(title.lower(), title), [])
            sections.append(current)
        elif line.startswith(("* ", "- ")) and current is not None:
            item = _clean(line[2:])
            if item:
                current.items.append(item)
    return [section for section in sections if section.items]


def _clean(text: str) -> str:
    text = _REF.sub("", text)
    text = _LINK.sub(r"\1", text)
    text = _BOLD.sub(r"\1", text)
    return text.strip()

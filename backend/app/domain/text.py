"""Normalização de texto para busca e autocomplete (portada da v1).

Funções puras: minúsculas, sem acento, sem ruído de título do YouTube
("Official Video", "(Remastered)", "feat. ..."), só letras/dígitos separados por espaço.
"""

import re
import unicodedata

_BRACKET_RE = re.compile(r"[\(\[\{][^\)\]\}]*[\)\]\}]")
_TRAILING_DASH_TOPIC_RE = re.compile(r"-\s*topic\s*$", re.IGNORECASE)
_FEAT_RE = re.compile(r"\b(feat\.?|featuring|ft\.?)\b.*$", re.IGNORECASE)
_NOISE_PHRASES_RE = re.compile(
    r"\b(official\s+(music\s+)?video|official\s+audio|lyric(s)?\s+video|"
    r"remaster(ed)?(\s*\d{2,4})?|hd|4k)\b",
    re.IGNORECASE,
)
_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")
# Sufixos de nome de canal ("Queen Official", "Rihanna VEVO"): só fazem sentido no artista.
_ARTIST_CHANNEL_SUFFIX_RE = re.compile(r"\b(official|vevo)\b", re.IGNORECASE)


def _strip_diacritics(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def normalize_text(text: str | None) -> str:
    """Normalização base, usada para títulos e para a busca livre."""
    result = _strip_diacritics((text or "").lower())
    result = _TRAILING_DASH_TOPIC_RE.sub(" ", result)
    result = _BRACKET_RE.sub(" ", result)
    result = _FEAT_RE.sub("", result)
    result = _NOISE_PHRASES_RE.sub(" ", result)
    result = _NON_ALNUM_RE.sub(" ", result)
    return " ".join(result.split())


def normalize_artist(artist: str | None) -> str:
    """Chave de agrupamento de artistas: "Queen Official" e "queen" viram "queen"."""
    return normalize_text(_ARTIST_CHANNEL_SUFFIX_RE.sub(" ", artist or ""))


def search_tokens(text: str | None) -> str:
    """Normalização leve para a busca livre: sem acento e sem pontuação, mas sem
    remover palavras (o usuário pode procurar por "remaster" ou "live")."""
    result = _NON_ALNUM_RE.sub(" ", _strip_diacritics((text or "").lower()))
    return " ".join(result.split())

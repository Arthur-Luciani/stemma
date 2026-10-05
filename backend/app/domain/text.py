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

# Para sugerir a identidade: trechos entre parênteses que não fazem parte do título
# ("(Official Video)", "[Lyrics]"), separador "Artista - Título" e ruído de nome de canal.
_TITLE_NOISE_RE = re.compile(
    r"\s*[\(\[][^\)\]]*\b(official|oficial|video|vídeo|clipe|clip|audio|áudio|lyrics?|letra|"
    r"legendad[oa]|visuali[sz]er|hd|4k|remaster(ed)?|mv)\b[^\)\]]*[\)\]]",
    re.IGNORECASE,
)
_TITLE_SEPARATOR_RE = re.compile(r"\s+[-–—|]\s+")
_CHANNEL_NOISE_RE = re.compile(r"(\s*-\s*topic$|vevo$|\s+official$|\s+oficial$)", re.IGNORECASE)
# Caracteres proibidos em nome de arquivo no Windows.
_FILENAME_FORBIDDEN_RE = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


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


def guess_identity(source_title: str, channel: str | None) -> tuple[str, str]:
    """Sugere artista e título a partir do vídeo: "Queen - Bohemian Rhapsody (Official Video)"
    vira ("Queen", "Bohemian Rhapsody"); sem separador, o artista vem do canal."""
    clean = _TITLE_NOISE_RE.sub("", source_title).strip() or source_title.strip()
    parts = _TITLE_SEPARATOR_RE.split(clean, maxsplit=1)
    if len(parts) == 2 and parts[0].strip() and parts[1].strip():
        artist, title = parts[0].strip(), parts[1].strip()
        # "The Beatles - The Beatles - Let It Be": o artista repetido sai do título.
        again = _TITLE_SEPARATOR_RE.split(title, maxsplit=1)
        if len(again) == 2 and again[0].strip().casefold() == artist.casefold():
            title = again[1].strip()
    else:
        artist = _CHANNEL_NOISE_RE.sub("", channel or "").strip()
        title = clean
    return artist[:200], title[:200]


def safe_filename(name: str, max_length: int = 150) -> str:
    """Nome de arquivo válido no Windows, mantendo acentos."""
    cleaned = " ".join(_FILENAME_FORBIDDEN_RE.sub(" ", name).split()).strip(" .")
    return cleaned[:max_length].rstrip(" .") or "stemma"

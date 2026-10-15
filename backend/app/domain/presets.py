"""Regras puras dos presets de mix (ADR 0018)."""

from app.domain.enums import STEMS, Stem

MAX_PRESET_NAME = 40

# Presets que a migration 0005 cria (os cinco fixos de antes): nome e stems mudos.
# Os outros ficam em volume 100, pan no centro.
DEFAULT_PRESETS: tuple[tuple[str, tuple[Stem, ...]], ...] = (
    ("Original", ()),
    ("Sem voz", (Stem.VOCALS,)),
    ("Sem bateria", (Stem.DRUMS,)),
    ("Sem baixo", (Stem.BASS,)),
    ("Só voz", (Stem.DRUMS, Stem.BASS, Stem.OTHER)),
)


def default_preset_stems(muted: tuple[Stem, ...]) -> dict[str, dict[str, float | bool]]:
    return {s.value: {"volume": 100, "pan": 0, "mute": s in muted} for s in STEMS}

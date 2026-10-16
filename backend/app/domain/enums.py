"""Constantes de domínio. Definidas uma única vez; o resto do app importa daqui."""

from enum import StrEnum


class Stem(StrEnum):
    VOCALS = "vocals"
    DRUMS = "drums"
    BASS = "bass"
    OTHER = "other"

    @property
    def label(self) -> str:
        return _STEM_LABELS[self]


_STEM_LABELS = {
    Stem.VOCALS: "Voz",
    Stem.DRUMS: "Bateria",
    Stem.BASS: "Baixo",
    Stem.OTHER: "Outros",
}

# Ordem de exibição dos stems (mixer, exports).
STEMS: tuple[Stem, ...] = tuple(Stem)


class SessionState(StrEnum):
    DRAFT = "draft"
    QUEUED = "queued"
    DOWNLOADING = "downloading"
    SEPARATING = "separating"
    READY = "ready"
    FAILED = "failed"


# Etapas do job de processamento, na ordem. O estado da sessão acompanha a etapa.
PROCESS_STAGES: tuple[SessionState, ...] = (SessionState.DOWNLOADING, SessionState.SEPARATING)


class JobKind(StrEnum):
    PROCESS = "process"
    EXPORT = "export"


class JobState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    CANCELLED = "cancelled"


# Jobs que ainda vão (ou estão) rodando.
ACTIVE_JOB_STATES: frozenset[JobState] = frozenset({JobState.QUEUED, JobState.RUNNING})
# Jobs encerrados que aparecem no dock até o usuário descartar.
DISMISSABLE_JOB_STATES: frozenset[JobState] = frozenset({JobState.DONE, JobState.FAILED})


class EventType(StrEnum):
    """Tipos de evento enviados pelo `/ws`."""

    SESSION_UPDATED = "session.updated"
    SESSION_DELETED = "session.deleted"
    JOB_UPDATED = "job.updated"
    EXPORT_UPDATED = "export.updated"


class ExportState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"


class ExportFormat(StrEnum):
    WAV = "wav"
    MP3 = "mp3"


class SessionSort(StrEnum):
    NEWEST = "newest"
    OLDEST = "oldest"
    TITLE = "title"
    ARTIST = "artist"
    LONGEST = "longest"
    SHORTEST = "shortest"


class UpdateState(StrEnum):
    """Atualização disparada pelo app ou pela tarefa agendada (ADR 0015 e 0016)."""

    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class UpdateComponent(StrEnum):
    """O que uma linha de `system_updates` atualiza."""

    APP = "app"  # o Stemma inteiro, pelo instalador (ADR 0015)
    YTDLP = "ytdlp"  # só o yt-dlp do venv no ar (ADR 0016)


class PresetIcon(StrEnum):
    """Ícones que um preset pode ter: nomes do Material Symbols, numa lista curta (ADR 0019)."""

    GRAPHIC_EQ = "graphic_eq"
    MUSIC_NOTE = "music_note"
    MIC = "mic"
    MIC_OFF = "mic_off"
    RECORD_VOICE_OVER = "record_voice_over"
    VOLUME_OFF = "volume_off"
    VOLUME_DOWN = "volume_down"
    HEARING = "hearing"
    HEADPHONES = "headphones"
    PIANO = "piano"
    LYRICS = "lyrics"
    SCHOOL = "school"
    SPEED = "speed"
    REPEAT = "repeat"
    STAR = "star"
    BOLT = "bolt"


class PresetColor(StrEnum):
    """Cores que um preset pode ter: as dos stems e três extras (tokens `--preset-*`, ADR 0019)."""

    VOCALS = "vocals"
    DRUMS = "drums"
    BASS = "bass"
    OTHER = "other"
    RED = "red"
    YELLOW = "yellow"
    GRAY = "gray"

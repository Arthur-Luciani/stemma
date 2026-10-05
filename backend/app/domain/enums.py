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
    # Publicado a partir da F2b (exports reais).
    EXPORT_UPDATED = "export.updated"


class ExportState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"


class ExportFormat(StrEnum):
    WAV = "wav"
    MP3 = "mp3"


class MixPreset(StrEnum):
    ORIGINAL = "original"
    NO_VOCALS = "no_vocals"
    NO_DRUMS = "no_drums"
    NO_BASS = "no_bass"
    VOCALS_ONLY = "vocals_only"
    CUSTOM = "custom"


class SessionSort(StrEnum):
    NEWEST = "newest"
    OLDEST = "oldest"
    TITLE = "title"
    ARTIST = "artist"
    LONGEST = "longest"
    SHORTEST = "shortest"

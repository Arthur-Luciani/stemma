"""Handlers reais dos jobs: processamento (download → separação → MP3/peaks/métricas) e
export (mixdown). Registrados em `app.main.default_job_handlers`."""

import json
import logging
import shutil
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

from app.domain.enums import STEMS, ExportFormat, SessionState, Stem
from app.domain.errors import AppError
from app.pipeline.audio import Ffmpeg
from app.pipeline.download import Progress
from app.pipeline.proc import Attachable
from app.pipeline.queue import JobContext
from app.pipeline.separate import Separation
from app.schemas.mix import StemMix
from app.storage import Storage

logger = logging.getLogger(__name__)

# Fatias do progresso da etapa "separando".
_DEMUCS_SHARE = 90.0
_STEM_FILES_SHARE = 8.0


class Downloader(Protocol):
    def download(self, url: str, dest_dir: Path, ctx: Progress) -> Path: ...


class Separator(Protocol):
    def separate(
        self,
        source: Path,
        work_dir: Path,
        ctx: Attachable,
        on_progress: Callable[[float], None],
    ) -> Separation: ...


class ProcessHandler:
    def __init__(
        self, storage: Storage, downloader: Downloader, separator: Separator, ffmpeg: Ffmpeg
    ) -> None:
        self.storage = storage
        self.downloader = downloader
        self.separator = separator
        self.ffmpeg = ffmpeg

    def run(self, ctx: JobContext) -> None:
        session_id = ctx.session.id
        raw_dir = self.storage.resolve(Storage.raw_dir(session_id))
        work_dir = self.storage.resolve(Storage.work_dir(session_id))
        stems_dir = self.storage.resolve(Storage.stems_dir(session_id))
        # Reprocessar começa do zero: arquivos e resultado antigos saem antes.
        for folder in (raw_dir, work_dir, stems_dir):
            _remove(folder)
        ctx.save(session={"stems": None, "metrics": None})
        try:
            ctx.set_stage(SessionState.DOWNLOADING)
            source = self.downloader.download(ctx.session.source_url, raw_dir, ctx)

            ctx.set_stage(SessionState.SEPARATING)
            separation = self.separator.separate(
                source, work_dir, ctx, lambda pct: ctx.progress(pct * _DEMUCS_SHARE / 100)
            )
            logger.info("Sessão %s separada na %s", ctx.session.code, separation.device)

            stems: dict[str, str] = {}
            duration = 0.0
            for i, stem in enumerate(STEMS, start=1):
                wav = separation.stems[stem]
                mp3_rel = Storage.stem_audio(session_id, stem.value)
                self.ffmpeg.to_mp3(wav, self.storage.resolve(mp3_rel), ctx=ctx)
                peaks = self.ffmpeg.compute_peaks(wav, ctx=ctx)
                peaks_path = self.storage.resolve(Storage.stem_peaks(session_id, stem.value))
                peaks_path.write_text(json.dumps(peaks.to_json()), encoding="utf-8")
                duration = max(duration, peaks.duration_s)
                stems[stem.value] = mp3_rel
                ctx.progress(_DEMUCS_SHARE + _STEM_FILES_SHARE * i / len(STEMS))

            loudness = self.ffmpeg.measure_loudness(source, ctx=ctx)
            ctx.save(
                session={
                    "stems": stems,
                    "metrics": {"lufs": loudness.lufs, "true_peak_db": loudness.true_peak_db},
                    "duration_s": duration or ctx.session.duration_s,
                }
            )
        finally:
            _remove(raw_dir)
            _remove(work_dir)


class ExportHandler:
    def __init__(self, storage: Storage, ffmpeg: Ffmpeg) -> None:
        self.storage = storage
        self.ffmpeg = ffmpeg

    def run(self, ctx: JobContext) -> None:
        export = ctx.export
        if export is None:  # pragma: no cover - o runner sempre preenche
            raise AppError("export_not_found", "Export não encontrado.", 500)
        stems = {
            Stem(name): self.storage.resolve(rel)
            for name, rel in ctx.session.stems.items()
            if name in Stem.__members__.values()
        }
        if not stems or any(not path.is_file() for path in stems.values()):
            raise AppError(
                "stems_missing",
                "Os arquivos dos stems desta sessão sumiram. Reprocesse a sessão.",
            )
        levels = {Stem(name): StemMix.model_validate(v) for name, v in export.levels.items()}
        rel = Storage.export_file(ctx.session.id, export.id, export.format.value)
        dst = self.storage.resolve(rel)
        try:
            self.ffmpeg.mixdown(stems, levels, dst, ExportFormat(export.format), ctx=ctx)
            ctx.progress(80)
            loudness = self.ffmpeg.measure_loudness(dst, ctx=ctx)
            ctx.save(export={"path": rel, "size_bytes": dst.stat().st_size, "lufs": loudness.lufs})
        except BaseException:
            dst.unlink(missing_ok=True)
            raise


def _remove(folder: Path) -> None:
    shutil.rmtree(folder, ignore_errors=True)
    if folder.exists():
        logger.warning("Não deu para apagar %s", folder)

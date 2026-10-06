import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState, type CSSProperties } from 'react';

import { createExport, exportFileUrl } from '../../api/endpoints';
import type { Export, ExportFormat, Session } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';
import { STEMS, stemColorVar } from '../../audio/stems';
import { formatBytes, formatDb, formatStampDate } from '../../lib/format';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { Button } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { ProgressBar } from '../../ui/ProgressBar';
import { SegmentedControl } from '../../ui/SegmentedControl';
import styles from './ExportPanel.module.css';
import { useExports } from './hooks';
import { effectiveVolume, type MixerState } from './mixState';
import type { Mixer } from './useMixer';

const FORMAT_LABEL: Record<ExportFormat, string> = { wav: 'WAV', mp3: 'MP3' };

const isActive = (e: Export) => e.state === 'queued' || e.state === 'running';

/** O save do mix antes do export falhou (o toast do save já avisou). */
class MixNotSaved extends Error {}

function exportTitle(e: Export): string {
  const preset = e.preset ? strings.mixer.preset[e.preset] : strings.mixer.preset.custom;
  return `${preset} · ${FORMAT_LABEL[e.format]}`;
}

interface ExportPanelProps {
  session: Session;
  mixer: Mixer & { state: MixerState };
  /** `sheet` (M6, celular) mostra o resumo do mix e botões maiores. */
  variant: 'popover' | 'sheet';
}

/** Conteúdo comum do popover (desktop) e do sheet M6 (celular). */
export function ExportPanel({ session, mixer, variant }: ExportPanelProps) {
  const [format, setFormat] = useState<ExportFormat>('mp3');
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  const { data: exports = [] } = useExports(session.id);

  const create = useMutation({
    mutationFn: async (f: ExportFormat) => {
      // Sem `stems`, o backend exporta o mix salvo: o que está na tela precisa estar salvo.
      // Se o save falhou (o toast já saiu), não exporta um mix diferente do da tela.
      if (!(await mixer.flush())) throw new MixNotSaved();
      return createExport(session.id, f);
    },
    onSuccess: (created) => {
      // O `/ws` pode ter trazido um estado mais novo (running, done) antes da resposta.
      queryClient.setQueryData<Export[]>(queryKeys.exports(session.id), (list = []) =>
        list.some((e) => e.id === created.id) ? list : [created, ...list],
      );
    },
    onError: (error) => {
      if (!(error instanceof MixNotSaved)) onError(error);
    },
  });

  const active = exports.filter(isActive);
  const previous = exports.filter((e) => !isActive(e));
  const firstDone = previous.find((e) => e.state === 'done');
  const sheet = variant === 'sheet';

  return (
    <div className={cx(styles.panel, sheet && styles.sheet)}>
      {!sheet && (
        <div className={styles.head}>
          <h2 className={styles.title}>{strings.exports.title}</h2>
        </div>
      )}

      {sheet && (
        <div className={styles.summary}>
          <div className={styles.summaryHead}>
            <span className={styles.summaryPreset}>{strings.mixer.preset[mixer.preset]}</span>
            {session.metrics?.lufs != null && (
              <span className={styles.mono} title={strings.mixer.metricsHint}>
                {formatDb(session.metrics.lufs)} {strings.mixer.lufs}
                {session.metrics.true_peak_db != null &&
                  ` · ${formatDb(session.metrics.true_peak_db, true)} ${strings.mixer.dbtp}`}
              </span>
            )}
          </div>
          <div className={styles.levels}>
            {STEMS.map((stem) => {
              const level = effectiveVolume(mixer.state.stems, stem);
              return (
                <div key={stem} className={styles.level}>
                  <span
                    className={styles.levelBar}
                    style={
                      {
                        '--level': level / 100,
                        '--level-color': stemColorVar(stem),
                      } as CSSProperties
                    }
                  />
                  <span className={cx(styles.levelText, level === 0 && styles.levelOff)}>
                    {strings.stems[stem]} {level}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <SegmentedControl
        label={strings.exports.format}
        tone="neutral"
        className={styles.formats}
        value={format}
        onChange={setFormat}
        options={[
          { value: 'wav', label: strings.exports.wav },
          { value: 'mp3', label: strings.exports.mp3 },
        ]}
      />

      {active.map((e) => (
        <div key={e.id} className={styles.current}>
          <div className={styles.currentText}>
            <span>
              {e.state === 'queued'
                ? strings.exports.queued
                : strings.exports.generating(FORMAT_LABEL[e.format])}
            </span>
            <ProgressBar value={e.progress} tone="accent" thin label={exportTitle(e)} />
          </div>
          <span className={styles.mono}>{Math.round(e.progress)}%</span>
        </div>
      ))}

      <Button
        variant={active.length > 0 ? 'secondary' : 'primary'}
        icon="ios_share"
        block
        size={sheet ? 'lg' : 'md'}
        disabled={create.isPending}
        onClick={() => {
          create.mutate(format);
        }}
      >
        {strings.exports.start(format === 'wav' ? strings.exports.wav : strings.exports.mp3)}
      </Button>

      <div className={styles.list}>
        <h3 className={styles.listTitle}>
          {sheet ? strings.exports.previousMobile : strings.exports.previous}
        </h3>
        {previous.length === 0 && <p className={styles.none}>{strings.exports.none}</p>}
        <ul className={styles.items}>
          {previous.map((e) => (
            <li key={e.id} className={styles.item}>
              <div className={styles.itemText}>
                <span className={styles.itemTitle}>{exportTitle(e)}</span>
                <span className={cx(styles.mono, e.state === 'failed' && styles.failed)}>
                  {e.state === 'failed'
                    ? (e.error_message ?? strings.exports.failed)
                    : [
                        formatStampDate(e.finished_at ?? e.created_at),
                        formatBytes(e.size_bytes),
                        e.lufs != null ? `${formatDb(e.lufs)} ${strings.mixer.lufs}` : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                </span>
              </div>
              {e.state === 'done' && (
                <a
                  className={cx(
                    styles.download,
                    sheet && styles.downloadIcon,
                    e === firstDone && styles.downloadPrimary,
                  )}
                  href={exportFileUrl(e.id)}
                  download={e.file_name}
                  aria-label={strings.exports.downloadNamed(e.file_name)}
                >
                  {sheet ? <Icon name="download" /> : strings.exports.download}
                </a>
              )}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

interface ExportPopoverProps {
  session: Session;
  mixer: Mixer & { state: MixerState };
  open: boolean;
  onOpen: () => void;
  onClose: () => void;
}

/** Botão "Exportar" do transport (desktop) e o popover ancorado nele. */
export function ExportPopover({ session, mixer, open, onOpen, onClose }: ExportPopoverProps) {
  const wrapper = useRef<HTMLDivElement>(null);
  const { data: exports = [] } = useExports(session.id);
  const running = exports.some(isActive);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (event.target instanceof Node && !wrapper.current?.contains(event.target)) onClose();
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open, onClose]);

  return (
    <div ref={wrapper} className={styles.anchor}>
      <Button
        variant="secondary"
        icon="ios_share"
        aria-expanded={open}
        aria-haspopup="dialog"
        onClick={open ? onClose : onOpen}
      >
        {strings.exports.open}
        {running && <span className={styles.ring} aria-hidden="true" />}
      </Button>
      {open && (
        <div className={styles.popover} role="dialog" aria-label={strings.exports.title}>
          <ExportPanel session={session} mixer={mixer} variant="popover" />
        </div>
      )}
    </div>
  );
}

/** Sheet M6 (celular). */
export function ExportSheet({ session, mixer, open, onClose }: Omit<ExportPopoverProps, 'onOpen'>) {
  return (
    <BottomSheet open={open} onClose={onClose} label={strings.exports.title}>
      <h2 className={styles.sheetTitle}>{strings.exports.title}</h2>
      <ExportPanel session={session} mixer={mixer} variant="sheet" />
    </BottomSheet>
  );
}

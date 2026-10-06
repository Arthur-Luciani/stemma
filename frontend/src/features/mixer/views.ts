import type { Session, Stem, StemPeaks } from '../../api/types';
import type { AudioEngine } from '../../audio/AudioEngine';
import { formatDuration } from '../../lib/format';
import { strings } from '../../strings';
import type { MixerState } from './mixState';
import type { Mixer } from './useMixer';

/** O que toda variação do mixer (desktop, 1f, 1e, 1g) recebe. */
export interface MixerViewProps {
  session: Session;
  engine: AudioEngine | null;
  peaks: Partial<Record<Stem, StemPeaks>>;
  mixer: Mixer & { state: MixerState };
  duration: number;
  exportOpen: boolean;
  onOpenExport: () => void;
  onCloseExport: () => void;
  onEdit: () => void;
}

/** Nome do stem em PT-BR. */
export const stemLabel = (stem: Stem): string => strings.stems[stem];

/** Tempo do celular, sem décimos: `1:12`. */
export const formatShortClock = (seconds: number): string => formatDuration(Math.floor(seconds));

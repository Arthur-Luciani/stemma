import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import styles from './MuteSoloButton.module.css';

interface MuteSoloButtonProps {
  kind: 'mute' | 'solo';
  active: boolean;
  onToggle: () => void;
  /** Nome do stem (para o rótulo acessível). */
  stem: string;
  /** `sm`: 32×32 (desktop). `md`: 44×44 (celular). `wide`: ocupa a largura (console). */
  size?: 'sm' | 'md' | 'wide';
}

/** M ativo = bad; S ativo = solo. */
export function MuteSoloButton({ kind, active, onToggle, stem, size = 'md' }: MuteSoloButtonProps) {
  const label = kind === 'mute' ? strings.mixer.mute(stem) : strings.mixer.solo(stem);
  return (
    <button
      type="button"
      aria-pressed={active}
      aria-label={label}
      title={label}
      className={cx(styles.button, styles[kind], styles[size], active && styles.active)}
      onClick={onToggle}
    >
      {kind === 'mute' ? 'M' : 'S'}
    </button>
  );
}

import type { ReactNode } from 'react';

import styles from './BottomSheet.module.css';
import { cx } from './cx';
import { Icon } from './Icon';
import { Modal } from './Modal';

interface BottomSheetProps {
  open: boolean;
  onClose: () => void;
  label: string;
  children: ReactNode;
  /** Ocupa a altura toda até o topo (ex.: sheet de processamento). */
  tall?: boolean;
}

/** Sheet do celular: raised, raio 22 no topo e alça 40×5. */
export function BottomSheet({ open, onClose, label, children, tall }: BottomSheetProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      label={label}
      initialFocus="panel"
      layerClassName={styles.layer}
      panelClassName={cx(styles.panel, tall && styles.tall)}
    >
      <div className={styles.handle} aria-hidden="true" />
      <div className={styles.content}>{children}</div>
    </Modal>
  );
}

interface SheetActionProps {
  icon: string;
  label: string;
  onSelect: () => void;
  destructive?: boolean;
}

/** Item de ação de 52px dentro de um BottomSheet (equivalente ao Menu no celular). */
export function SheetAction({ icon, label, onSelect, destructive }: SheetActionProps) {
  return (
    <button
      type="button"
      className={cx(styles.action, destructive && styles.destructive)}
      onClick={onSelect}
    >
      <Icon name={icon} className={styles.actionIcon} />
      {label}
    </button>
  );
}

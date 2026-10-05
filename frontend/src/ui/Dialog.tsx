import type { ReactNode } from 'react';

import styles from './Dialog.module.css';
import { Modal } from './Modal';

interface DialogProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children?: ReactNode;
  /** Botões do rodapé, alinhados à direita. */
  actions: ReactNode;
}

/** Dialog centralizado (raised, raio 18), usado para confirmações e formulários curtos. */
export function Dialog({ open, onClose, title, children, actions }: DialogProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      label={title}
      layerClassName={styles.layer}
      panelClassName={styles.panel}
    >
      <h2 className={styles.title}>{title}</h2>
      {children && <div className={styles.body}>{children}</div>}
      <div className={styles.actions}>{actions}</div>
    </Modal>
  );
}

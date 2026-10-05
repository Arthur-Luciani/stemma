import { useEffect, useLayoutEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

import { cx } from './cx';
import styles from './Modal.module.css';

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  label: string;
  children: ReactNode;
  /** Classe do painel (Dialog centralizado ou BottomSheet). */
  panelClassName?: string;
  layerClassName?: string;
  /**
   * `first`: foca o primeiro controle (Dialog). `panel`: foca o painel, sem abrir o teclado
   * do celular num campo (BottomSheet). `[data-autofocus]` sempre tem prioridade.
   */
  initialFocus?: 'first' | 'panel';
}

/**
 * Base de Dialog e BottomSheet: portal, véu, Esc e clique fora fecham, foco preso no
 * painel e devolvido a quem abriu, rolagem do fundo travada.
 */
export function Modal({
  open,
  onClose,
  label,
  children,
  panelClassName,
  layerClassName,
  initialFocus = 'first',
}: ModalProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  useLayoutEffect(() => {
    onCloseRef.current = onClose;
  });

  useEffect(() => {
    if (!open) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const panel = panelRef.current;
    const autofocus = panel?.querySelector<HTMLElement>('[data-autofocus]');
    const first =
      initialFocus === 'first' ? panel?.querySelector<HTMLElement>(FOCUSABLE) : undefined;
    (autofocus ?? first ?? panel)?.focus();

    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (event.key !== 'Tab' || !panel) return;
      const items = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE));
      const first = items[0];
      const last = items[items.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, [open, initialFocus]);

  if (!open) return null;

  return createPortal(
    <div className={cx(styles.layer, layerClassName)}>
      <div
        className={styles.scrim}
        aria-hidden="true"
        data-testid="modal-scrim"
        onClick={() => {
          onCloseRef.current();
        }}
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        tabIndex={-1}
        className={cx(styles.panel, panelClassName)}
      >
        {children}
      </div>
    </div>,
    document.body,
  );
}

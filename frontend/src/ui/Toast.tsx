import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router';

import { strings } from '../strings';
import { Icon } from './Icon';
import styles from './Toast.module.css';
import { ToastContext, type ToastAction, type ToastInput, type ToastTone } from './toastContext';

interface ToastItem extends Required<Omit<ToastInput, 'action'>> {
  id: number;
  action?: ToastAction;
}

export const TOAST_DURATION_MS = 5_000;
const MAX_TOASTS = 3;

const icons: Record<ToastTone, string> = { good: 'check_circle', bad: 'error', info: 'info' };

function ToastView({ toast, onDismiss }: { toast: ToastItem; onDismiss: () => void }) {
  const onDismissRef = useRef(onDismiss);
  useEffect(() => {
    onDismissRef.current = onDismiss;
  });
  const { persistent } = toast;
  useEffect(() => {
    if (persistent) return;
    const timer = setTimeout(() => {
      onDismissRef.current();
    }, TOAST_DURATION_MS);
    return () => {
      clearTimeout(timer);
    };
  }, [persistent]);

  const { action } = toast;
  return (
    <div className={styles.toast} role={toast.tone === 'bad' ? 'alert' : 'status'}>
      <Icon name={icons[toast.tone]} size={20} className={styles[toast.tone]} />
      <div className={styles.message}>{toast.message}</div>
      {action?.to !== undefined ? (
        <Link className={styles.action} to={action.to} onClick={onDismiss}>
          {action.label}
        </Link>
      ) : action ? (
        <button
          type="button"
          className={styles.action}
          onClick={() => {
            action.onClick?.();
            onDismiss();
          }}
        >
          {action.label}
        </button>
      ) : null}
      <button
        type="button"
        className={styles.close}
        aria-label={strings.common.close}
        onClick={onDismiss}
      >
        <Icon name="close" size={18} />
      </button>
    </div>
  );
}

/** Provê `useToast()` e renderiza a pilha de toasts (acima da bottom nav no celular). */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const nextId = useRef(1);

  const dismiss = useCallback((id: number) => {
    setToasts((list) => list.filter((t) => t.id !== id));
  }, []);

  const show = useCallback((input: ToastInput) => {
    const id = nextId.current++;
    setToasts((list) => {
      const next = [
        ...list,
        { ...input, tone: input.tone ?? 'info', persistent: input.persistent ?? false, id },
      ];
      // Passou do limite: sai o mais antigo que não é persistente (o aviso de versão nova fica).
      while (next.length > MAX_TOASTS) {
        const oldest = next.findIndex((t) => !t.persistent);
        next.splice(oldest === -1 ? 0 : oldest, 1);
      }
      return next;
    });
  }, []);

  const api = useMemo(() => ({ show }), [show]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className={styles.region} aria-live="polite">
        {toasts.map((toast) => (
          <ToastView
            key={toast.id}
            toast={toast}
            onDismiss={() => {
              dismiss(toast.id);
            }}
          />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

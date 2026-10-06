import { createContext, useContext } from 'react';

export type ToastTone = 'good' | 'bad' | 'info';

export interface ToastAction {
  label: string;
  /** Navega para esta rota; ou chama `onClick`. */
  to?: string;
  onClick?: () => void;
}

export interface ToastInput {
  message: string;
  tone?: ToastTone;
  action?: ToastAction;
  /** Fica até o usuário fechar ou usar a ação (sem o tempo de 5 s). */
  persistent?: boolean;
}

export interface ToastApi {
  show: (toast: ToastInput) => void;
}

export const ToastContext = createContext<ToastApi | null>(null);

export function useToast(): ToastApi {
  const api = useContext(ToastContext);
  if (!api) throw new Error('useToast fora do ToastProvider');
  return api;
}

import type { ReactNode } from 'react';

import { cx } from './cx';
import styles from './EmptyState.module.css';
import { Icon } from './Icon';

interface StateCardProps {
  title: string;
  body?: string;
  /** Ícone Material Symbols; `bars` desenha as 4 barras apagadas (biblioteca vazia). */
  icon?: string;
  action?: ReactNode;
  className?: string;
}

function Bars() {
  return (
    <div className={styles.bars} aria-hidden="true">
      <span />
      <span />
      <span />
      <span />
    </div>
  );
}

function StateCard({
  title,
  body,
  icon,
  action,
  className,
  tone,
  role,
}: StateCardProps & { tone: 'muted' | 'bad'; role?: 'alert' }) {
  return (
    <div className={cx(styles.card, className)} role={role}>
      {icon === 'bars' ? (
        <Bars />
      ) : icon ? (
        <Icon name={icon} size={28} className={styles[tone]} />
      ) : null}
      <div className={styles.title}>{title}</div>
      {body && <div className={styles.body}>{body}</div>}
      {action && <div className={styles.action}>{action}</div>}
    </div>
  );
}

/** Vazio / nenhum resultado. */
export function EmptyState(props: StateCardProps) {
  return <StateCard icon="search_off" {...props} tone="muted" />;
}

/** Erro com ação de recuperação (ex.: "Tentar de novo"). */
export function ErrorState(props: StateCardProps) {
  return <StateCard icon="cloud_off" {...props} tone="bad" role="alert" />;
}

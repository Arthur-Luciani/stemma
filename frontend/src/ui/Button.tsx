import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react';
import { Link, type LinkProps } from 'react-router';

import styles from './Button.module.css';
import { cx } from './cx';
import { Icon } from './Icon';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'destructive';
export type ButtonSize = 'md' | 'sm' | 'lg';

interface CommonProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: string;
  /** Botão só com ícone (44×44): `label` vira o `aria-label`. */
  iconOnly?: boolean;
  label?: string;
  block?: boolean;
  className?: string;
  children?: ReactNode;
}

function classes({ variant = 'secondary', size = 'md', iconOnly, block, className }: CommonProps) {
  return cx(
    styles.button,
    styles[variant],
    styles[size],
    iconOnly && styles.iconOnly,
    block && styles.block,
    className,
  );
}

function content({ icon, iconOnly, label, children }: CommonProps) {
  return (
    <>
      {icon && <Icon name={icon} size={iconOnly ? 22 : 20} />}
      {iconOnly ? null : (children ?? label)}
    </>
  );
}

type ButtonProps = CommonProps & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'>;

/**
 * Variantes do design: `primary` (accent, uma por tela), `secondary` (soft + borda),
 * `ghost`, `danger` (borda bad) e `destructive` (fundo bad, confirmação de exclusão).
 */
export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant, size, icon, iconOnly, label, block, className, children, type = 'button', ...rest },
  ref,
) {
  const common = { variant, size, icon, iconOnly, label, block, className, children };
  return (
    <button
      ref={ref}
      type={type}
      className={classes(common)}
      aria-label={iconOnly ? label : rest['aria-label']}
      title={iconOnly ? label : rest.title}
      {...rest}
    >
      {content(common)}
    </button>
  );
});

type ButtonLinkProps = CommonProps & Omit<LinkProps, 'children' | 'className'>;

/** Mesmo visual do `Button`, mas navega (é um `<a>`). */
export function ButtonLink({
  variant,
  size,
  icon,
  iconOnly,
  label,
  block,
  className,
  children,
  ...rest
}: ButtonLinkProps) {
  const common = { variant, size, icon, iconOnly, label, block, className, children };
  return (
    <Link
      className={classes(common)}
      aria-label={iconOnly ? label : undefined}
      title={iconOnly ? label : undefined}
      {...rest}
    >
      {content(common)}
    </Link>
  );
}

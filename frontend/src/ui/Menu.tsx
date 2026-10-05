import { Fragment, useEffect, useId, useRef, useState, type KeyboardEvent } from 'react';

import { Button } from './Button';
import { cx } from './cx';
import { Icon } from './Icon';
import styles from './Menu.module.css';

export interface MenuItem {
  label: string;
  icon?: string;
  onSelect: () => void;
  destructive?: boolean;
  /** Marca o item escolhido (ex.: ordenação atual). */
  checked?: boolean;
}

interface MenuProps {
  /** Rótulo acessível do botão que abre o menu. */
  label: string;
  items: MenuItem[];
  /** Ícone do gatilho; sem ícone, o gatilho mostra `triggerText` + seta. */
  icon?: string;
  triggerText?: string;
  size?: 'md' | 'sm';
  className?: string;
}

/**
 * Menu suspenso (desktop): raised raio 12, itens de 40px com ícone, destrutivo em bad-text
 * separado por divisória. Setas navegam, Esc fecha, clique fora fecha.
 */
export function Menu({ label, items, icon, triggerText, size = 'md', className }: MenuProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const menuId = useId();

  useEffect(() => {
    if (!open) return;
    itemRefs.current[0]?.focus();
    const onPointer = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('pointerdown', onPointer);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
    };
  }, [open]);

  const close = (refocus: boolean) => {
    setOpen(false);
    if (refocus) triggerRef.current?.focus();
  };

  const onKeyDown = (event: KeyboardEvent, index: number) => {
    const count = items.length;
    let next: number | undefined;
    if (event.key === 'ArrowDown') next = (index + 1) % count;
    else if (event.key === 'ArrowUp') next = (index - 1 + count) % count;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = count - 1;
    else if (event.key === 'Escape' || event.key === 'Tab') {
      if (event.key === 'Escape') event.preventDefault();
      close(event.key === 'Escape');
      return;
    }
    if (next === undefined) return;
    event.preventDefault();
    itemRefs.current[next]?.focus();
  };

  return (
    <div ref={rootRef} className={cx(styles.root, className)}>
      {icon ? (
        <Button
          ref={triggerRef}
          variant="ghost"
          icon={icon}
          iconOnly
          label={label}
          className={cx(size === 'sm' && styles.small, open && styles.triggerOpen)}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={open ? menuId : undefined}
          onClick={() => {
            setOpen((v) => !v);
          }}
        />
      ) : (
        <Button
          ref={triggerRef}
          variant="ghost"
          size="sm"
          aria-label={label}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={open ? menuId : undefined}
          onClick={() => {
            setOpen((v) => !v);
          }}
        >
          {triggerText}
          <Icon name="expand_more" size={18} />
        </Button>
      )}
      {open && (
        <div id={menuId} role="menu" aria-label={label} className={styles.menu}>
          {items.map((item, index) => {
            const previous = items[index - 1];
            const divider = item.destructive && previous !== undefined && !previous.destructive;
            return (
              <Fragment key={item.label}>
                {divider && <div role="separator" className={styles.divider} />}
                <button
                  ref={(el) => {
                    itemRefs.current[index] = el;
                  }}
                  type="button"
                  role={item.checked === undefined ? 'menuitem' : 'menuitemradio'}
                  aria-checked={item.checked}
                  tabIndex={-1}
                  className={cx(styles.item, item.destructive && styles.destructive)}
                  onKeyDown={(event) => {
                    onKeyDown(event, index);
                  }}
                  onClick={() => {
                    close(true);
                    item.onSelect();
                  }}
                >
                  {item.icon && <Icon name={item.icon} size={18} className={styles.itemIcon} />}
                  <span className={styles.itemLabel}>{item.label}</span>
                  {item.checked && <Icon name="check" size={18} className={styles.check} />}
                </button>
              </Fragment>
            );
          })}
        </div>
      )}
    </div>
  );
}

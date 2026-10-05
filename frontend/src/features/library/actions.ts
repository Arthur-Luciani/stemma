import type { Session } from '../../api/types';
import { sessionPath } from '../../lib/session';
import { strings } from '../../strings';
import type { MenuItem } from '../../ui/Menu';
import { useToast } from '../../ui/toastContext';
import { useReprocessSession } from '../session/hooks';

export type SessionAct = 'menu' | 'edit' | 'delete';

export function canReprocess(session: Session): boolean {
  return session.state === 'ready' || session.state === 'failed';
}

export function useReprocessWithToast() {
  const reprocess = useReprocessSession();
  const toast = useToast();
  return {
    isPending: reprocess.isPending,
    run: (session: Session) => {
      reprocess.mutate(session.id, {
        onSuccess: () => {
          toast.show({
            tone: 'good',
            message: strings.library.reprocessed(session.code),
            action: { label: strings.identity.follow, to: sessionPath(session.id) },
          });
        },
      });
    },
  };
}

/** Itens do menu ⋯ (desktop: Menu; celular: o mesmo conteúdo num BottomSheet). */
export function useMenuItems(
  session: Session,
  open: (act: SessionAct, session: Session) => void,
): MenuItem[] {
  const reprocess = useReprocessWithToast();
  const items: MenuItem[] = [
    {
      label: strings.library.actions.edit,
      icon: 'edit',
      onSelect: () => {
        open('edit', session);
      },
    },
  ];
  if (canReprocess(session))
    items.push({
      label: strings.library.actions.reprocess,
      icon: 'refresh',
      onSelect: () => {
        reprocess.run(session);
      },
    });
  items.push({
    label: strings.library.actions.delete,
    icon: 'delete',
    destructive: true,
    onSelect: () => {
      open('delete', session);
    },
  });
  return items;
}

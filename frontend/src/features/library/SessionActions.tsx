import type { Session } from '../../api/types';
import { isActiveState, mixPath, sessionPath } from '../../lib/session';
import { strings } from '../../strings';
import { Button, ButtonLink } from '../../ui/Button';
import { Menu } from '../../ui/Menu';
import { useMenuItems, useReprocessWithToast, type SessionAct } from './actions';

/** Ação principal contextual: Abrir mixer / Acompanhar / Continuar / Tentar de novo. */
export function PrimaryAction({ session }: { session: Session }) {
  const reprocess = useReprocessWithToast();
  const size = 'sm';
  if (session.state === 'ready')
    return (
      <ButtonLink to={mixPath(session.id)} variant="secondary" size={size}>
        {strings.library.actions.openMixer}
      </ButtonLink>
    );
  if (session.state === 'failed')
    return (
      <Button
        variant="secondary"
        size={size}
        disabled={reprocess.isPending}
        onClick={() => {
          reprocess.run(session);
        }}
      >
        {strings.library.actions.retry}
      </Button>
    );
  return (
    <ButtonLink to={sessionPath(session.id)} variant="secondary" size={size}>
      {isActiveState(session.state)
        ? strings.library.actions.follow
        : strings.library.actions.continue}
    </ButtonLink>
  );
}

export function SessionMenu({
  session,
  open,
}: {
  session: Session;
  open: (act: SessionAct, session: Session) => void;
}) {
  const items = useMenuItems(session, open);
  return <Menu label={strings.common.more} icon="more_horiz" size="sm" items={items} />;
}

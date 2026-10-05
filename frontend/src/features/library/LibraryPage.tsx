import { useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router';

import type { Session } from '../../api/types';
import { useUrlParam } from '../../app/useUrlParam';
import { errorMessage } from '../../app/useErrorToast';
import { queuePositions } from '../../lib/session';
import { strings } from '../../strings';
import { BottomSheet, SheetAction } from '../../ui/BottomSheet';
import { Button, ButtonLink } from '../../ui/Button';
import { EmptyState, ErrorState } from '../../ui/EmptyState';
import { Icon } from '../../ui/Icon';
import { Menu } from '../../ui/Menu';
import { SegmentedControl } from '../../ui/SegmentedControl';
import { SkeletonList } from '../../ui/Skeleton';
import { useIsDesktop } from '../../ui/useMediaQuery';
import { useJobs } from '../processing/hooks';
import { useMenuItems, type SessionAct } from './actions';
import {
  FILTERS,
  filterCount,
  parseFilter,
  parseSort,
  SORTS,
  useLibrary,
  type LibraryFilter,
} from './hooks';
import styles from './LibraryPage.module.css';
import { DeleteSessionDialog, EditSessionDialog } from './SessionDialogs';
import { SessionCard, SessionRow } from './SessionItems';

function ActionsSheet({
  session,
  open,
  onClose,
}: {
  session: Session;
  open: (act: SessionAct, session: Session) => void;
  onClose: () => void;
}) {
  const items = useMenuItems(session, open);
  return (
    <BottomSheet open onClose={onClose} label={session.title}>
      <div className={styles.sheetTitle}>
        {session.title} · <span className={styles.mono}>{session.code}</span>
      </div>
      <div className={styles.sheetActions}>
        {items.map((item) => (
          <SheetAction
            key={item.label}
            icon={item.icon ?? 'more_horiz'}
            label={item.label}
            destructive={item.destructive}
            onSelect={item.onSelect}
          />
        ))}
      </div>
    </BottomSheet>
  );
}

/** Rola até o fim → carrega a próxima página (o botão fica de reserva). */
function useInfiniteSentinel(onVisible: () => void, enabled: boolean) {
  const ref = useRef<HTMLDivElement>(null);
  const callback = useRef(onVisible);
  useEffect(() => {
    callback.current = onVisible;
  });
  useEffect(() => {
    const node = ref.current;
    if (!enabled || !node || !('IntersectionObserver' in window)) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) callback.current();
      },
      { rootMargin: '400px' },
    );
    observer.observe(node);
    return () => {
      observer.disconnect();
    };
  }, [enabled]);
  return ref;
}

/** Biblioteca: busca, filtros por estado com contagem, ordenação, tabela/cards, ações. */
export function LibraryPage() {
  const isDesktop = useIsDesktop();
  const [params, setParams] = useSearchParams();
  const q = params.get('q') ?? '';
  const filter = parseFilter(params.get('f'));
  const sort = parseSort(params.get('sort'));

  const [draft, setDraft] = useState(q);
  const [syncedQ, setSyncedQ] = useState(q);
  // A URL mudou por fora (back/forward): o campo acompanha.
  if (syncedQ !== q) {
    setSyncedQ(q);
    setDraft(q);
  }
  const searchRef = useRef<HTMLInputElement>(null);
  const typingTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(
    () => () => {
      if (typingTimer.current !== null) clearTimeout(typingTimer.current);
    },
    [],
  );

  const update = (changes: Record<string, string | null>) => {
    setParams(
      (current) => {
        const next = new URLSearchParams(current);
        for (const [key, value] of Object.entries(changes)) {
          if (value === null || value === '') next.delete(key);
          else next.set(key, value);
        }
        return next;
      },
      { replace: true },
    );
  };

  // Busca digitada → URL com debounce, sem empilhar histórico.
  const onSearchChange = (value: string) => {
    setDraft(value);
    if (typingTimer.current !== null) clearTimeout(typingTimer.current);
    typingTimer.current = setTimeout(() => {
      typingTimer.current = null;
      update({ q: value.trim() });
    }, 300);
  };

  // `/` foca a busca (desktop), menos quando já se digita em algum campo.
  useEffect(() => {
    if (!isDesktop) return;
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const typing =
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target?.isContentEditable === true;
      if (event.key === '/' && !typing && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
    };
  }, [isDesktop]);

  const library = useLibrary({ q, filter, sort });
  const pages = library.data?.pages;
  const sessions = useMemo(() => pages?.flatMap((page) => page.items) ?? [], [pages]);
  const counts = pages?.[0]?.counts;
  const total = filterCount('all', counts);

  const { data: jobs } = useJobs();
  const positions = useMemo(() => queuePositions(jobs), [jobs]);

  // Menu/diálogos na URL (`?act=edit:<id>`): o back do Android fecha.
  const [act, setAct, clearAct] = useUrlParam('act');
  const [actKind, actId] = act ? (act.split(':') as [string, string | undefined]) : [];
  const actSession = sessions.find((s) => s.id === actId);
  const open = (kind: SessionAct, session: Session) => {
    // Do sheet para o diálogo troca o valor sem empilhar (fechar volta para a lista).
    setAct(`${kind}:${session.id}`);
  };

  const { fetchNextPage, hasNextPage, isFetchingNextPage } = library;
  const sentinel = useInfiniteSentinel(() => {
    if (hasNextPage && !isFetchingNextPage) void fetchNextPage();
  }, hasNextPage);

  const filterOptions = FILTERS.map((value) => ({
    value,
    label:
      value === 'active'
        ? strings.library.filterCount(strings.library.filters.active, filterCount('active', counts))
        : strings.library.filters[value],
  }));

  const sortItems = SORTS.map((value) => ({
    label: strings.library.sorts[value],
    checked: value === sort,
    onSelect: () => {
      update({ sort: value === 'newest' ? null : value });
    },
  }));

  let body;
  if (library.isPending) {
    body = <SkeletonList rows={5} thumb={false} label={strings.app.loading} />;
  } else if (library.isError) {
    body = (
      <ErrorState
        title={strings.errors.loadFailed}
        body={errorMessage(library.error)}
        action={
          <Button variant="secondary" onClick={() => void library.refetch()}>
            {strings.common.retry}
          </Button>
        }
      />
    );
  } else if (sessions.length === 0 && total === 0 && !q) {
    body = (
      <EmptyState
        icon="bars"
        title={strings.library.emptyTitle}
        body={strings.library.emptyBody}
        action={
          <ButtonLink to="/" variant="primary">
            {strings.library.emptyAction}
          </ButtonLink>
        }
      />
    );
  } else if (sessions.length === 0) {
    body = <EmptyState title={strings.library.noMatchTitle} body={strings.library.noMatchBody} />;
  } else if (isDesktop) {
    const c = strings.library.columns;
    body = (
      <table className={styles.table}>
        <thead>
          <tr>
            <th scope="col">{c.code}</th>
            <th scope="col">{c.song}</th>
            <th scope="col">{c.state}</th>
            <th scope="col">{c.duration}</th>
            <th scope="col">{c.created}</th>
            <th scope="col">
              <span className={styles.visuallyHidden}>{c.actions}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {sessions.map((session) => (
            <SessionRow
              key={session.id}
              session={session}
              position={positions.get(session.id)}
              open={open}
            />
          ))}
        </tbody>
      </table>
    );
  } else {
    body = (
      <ul className={styles.cards}>
        {sessions.map((session) => (
          <SessionCard
            key={session.id}
            session={session}
            position={positions.get(session.id)}
            open={open}
          />
        ))}
      </ul>
    );
  }

  return (
    <div className={styles.page}>
      <div className={styles.head}>
        <h1 className={styles.title}>{strings.library.title}</h1>
        {counts && <span className={styles.count}>{strings.library.count(total)}</span>}
        <label className={styles.search}>
          <Icon name="search" size={20} className={styles.searchIcon} />
          <input
            ref={searchRef}
            type="search"
            aria-label={strings.library.searchLabel}
            placeholder={strings.library.searchPlaceholder}
            className={styles.searchInput}
            value={draft}
            onChange={(event) => {
              onSearchChange(event.target.value);
            }}
          />
          {isDesktop && <kbd className={styles.kbd}>/</kbd>}
        </label>
      </div>
      <div className={styles.toolbar}>
        <SegmentedControl<LibraryFilter>
          label={strings.library.filtersLabel}
          options={filterOptions}
          value={filter}
          tone="neutral"
          variant={isDesktop ? 'segmented' : 'chips'}
          className={styles.filters}
          onChange={(value) => {
            update({ f: value === 'all' ? null : value });
          }}
        />
        <Menu
          label={strings.library.sortLabel}
          triggerText={strings.library.sorts[sort]}
          items={sortItems}
          className={styles.sort}
        />
      </div>
      {body}
      {hasNextPage && (
        <div ref={sentinel} className={styles.more}>
          <Button
            variant="ghost"
            disabled={isFetchingNextPage}
            onClick={() => void fetchNextPage()}
          >
            {strings.common.loadMore}
          </Button>
        </div>
      )}
      {actSession && actKind === 'menu' && (
        <ActionsSheet session={actSession} open={open} onClose={clearAct} />
      )}
      {actSession && actKind === 'edit' && (
        <EditSessionDialog key={actSession.id} session={actSession} onClose={clearAct} />
      )}
      {actSession && actKind === 'delete' && (
        <DeleteSessionDialog session={actSession} onClose={clearAct} />
      )}
    </div>
  );
}

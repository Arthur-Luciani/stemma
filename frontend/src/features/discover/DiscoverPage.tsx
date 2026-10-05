import { useEffect, useRef, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router';

import { isApiError } from '../../api/client';
import type { SearchResult, Session } from '../../api/types';
import { useUrlParam } from '../../app/useUrlParam';
import { MobileBrand } from '../../app/Navigation';
import { mixPath, sessionPath } from '../../lib/session';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { Button } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { EmptyState, ErrorState } from '../../ui/EmptyState';
import { Icon } from '../../ui/Icon';
import { SkeletonList } from '../../ui/Skeleton';
import { useIsDesktop } from '../../ui/useMediaQuery';
import styles from './DiscoverPage.module.css';
import { useRecentSessions, useSearch } from './hooks';
import { IdentityForm } from './IdentityForm';
import { SearchBox } from './SearchBox';
import { Thumbnail } from './Thumbnail';

const isLink = (q: string) => /^https?:\/\//i.test(q.trim());

function StemBars() {
  return (
    <span className={styles.bars} aria-hidden="true">
      <span />
      <span />
      <span />
      <span />
    </span>
  );
}

function RecentSessions() {
  const { data } = useRecentSessions();
  if (!data || data.length === 0) return null;
  const target = (s: Session) => (s.state === 'ready' ? mixPath(s.id) : sessionPath(s.id));
  return (
    <section className={styles.recent} aria-labelledby="recent-title">
      <h2 id="recent-title" className={styles.sectionTitle}>
        {strings.discover.recentTitle}
      </h2>
      <ul className={styles.recentList}>
        {data.map((session) => (
          <li key={session.id}>
            <Link to={target(session)} className={styles.recentItem}>
              <StemBars />
              <span className={styles.recentText}>
                <span className={styles.recentTitle}>{session.title}</span>
                <span className={styles.recentArtist}>{session.artist}</span>
              </span>
              <Icon name="chevron_right" className={styles.chevron} />
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}

function ResultList({
  results,
  selected,
  onSelect,
  isDesktop,
}: {
  results: SearchResult[];
  selected: number | null;
  onSelect: (index: number) => void;
  isDesktop: boolean;
}) {
  return (
    <>
      <div className={styles.count}>
        {strings.discover.results(results.length)}
        {!isDesktop && ` · ${strings.discover.resultsTapHint}`}
      </div>
      <ul className={styles.results} aria-label={strings.discover.resultsLabel}>
        {results.map((result, index) => (
          <li key={result.source_url}>
            <button
              type="button"
              aria-pressed={selected === index}
              className={cx(styles.result, selected === index && styles.selected)}
              onClick={() => {
                onSelect(index);
              }}
            >
              <Thumbnail result={result} size={isDesktop ? 'lg' : 'md'} />
              <span className={styles.resultText}>
                <span className={styles.resultTitle}>{result.source_title}</span>
                {result.source_channel && (
                  <span className={styles.resultChannel}>{result.source_channel}</span>
                )}
              </span>
              {selected === index && <Icon name="check_circle" filled className={styles.check} />}
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}

/** Descobrir: buscar (ou colar link) → escolher → confirmar identidade → Separar. */
export function DiscoverPage() {
  const isDesktop = useIsDesktop();
  const [params, setParams] = useSearchParams();
  const q = params.get('q') ?? '';
  const [pick, setPick, clearPick] = useUrlParam('pick');
  const search = useSearch(q);
  const results = search.data;

  const pickIndex = pick === null ? null : Number(pick);
  const picked =
    pickIndex !== null && Number.isInteger(pickIndex) ? (results?.[pickIndex] ?? null) : null;

  // Link colado: o único resultado já vem escolhido.
  // Só uma vez por busca: depois de fechar (ou separar), a escolha não pode voltar sozinha.
  const autoPickedFor = useRef<string | null>(null);
  useEffect(() => {
    if (!isLink(q) || results?.length !== 1 || pick !== null) return;
    if (autoPickedFor.current === q) return;
    autoPickedFor.current = q;
    setPick('0', { replace: isDesktop });
  }, [q, results, pick, isDesktop, setPick]);

  const onSearch = (next: string) => {
    if (next === q) {
      void search.refetch();
      return;
    }
    setParams({ q: next });
  };

  const onClear = () => {
    setParams({});
  };

  const select = (index: number) => {
    // No desktop a escolha só troca o card; no celular abre o sheet (o back fecha).
    setPick(String(index), { replace: isDesktop });
  };

  let body: ReactNode;
  if (!q) {
    body = <RecentSessions />;
  } else if (search.isPending) {
    body = <SkeletonList rows={3} label={strings.app.loading} />;
  } else if (search.isError) {
    const linkError = isApiError(search.error) && search.error.status === 422;
    body = (
      <ErrorState
        title={linkError ? strings.discover.linkErrorTitle : strings.discover.unavailableTitle}
        body={linkError ? search.error.message : strings.discover.unavailableBody}
        action={
          linkError ? undefined : (
            <Button
              variant="secondary"
              onClick={() => void search.refetch()}
              disabled={search.isFetching}
            >
              {strings.common.retry}
            </Button>
          )
        }
      />
    );
  } else if (results && results.length === 0) {
    body = <EmptyState title={strings.discover.emptyTitle(q)} body={strings.discover.emptyBody} />;
  } else if (results) {
    body = (
      <ResultList
        results={results}
        selected={picked ? pickIndex : null}
        onSelect={select}
        isDesktop={isDesktop}
      />
    );
  }

  return (
    <div className={styles.page}>
      {!isDesktop && !q && <MobileBrand />}
      <div className={styles.columns}>
        <div className={styles.main}>
          {(isDesktop || !q) && <h1 className={styles.title}>{strings.discover.title}</h1>}
          <SearchBox query={q} onSearch={onSearch} onClear={onClear} />
          {body}
        </div>
        {isDesktop && picked && (
          <aside className={styles.aside}>
            <IdentityForm
              key={picked.source_url}
              result={picked}
              variant="card"
              onSeparated={clearPick}
            />
          </aside>
        )}
      </div>
      {!isDesktop && (
        <BottomSheet open={picked !== null} onClose={clearPick} label={strings.identity.title}>
          {picked && (
            <IdentityForm
              key={picked.source_url}
              result={picked}
              variant="sheet"
              onSeparated={clearPick}
            />
          )}
        </BottomSheet>
      )}
    </div>
  );
}

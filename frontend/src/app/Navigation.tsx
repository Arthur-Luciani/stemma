import { NavLink, useMatch } from 'react-router';

import { mixPath } from '../lib/session';
import { strings } from '../strings';
import { cx } from '../ui/cx';
import { Icon } from '../ui/Icon';
import { useLastSession } from './lastSession';
import styles from './Navigation.module.css';

interface Destination {
  to: string;
  label: string;
  icon: string;
  active: boolean;
}

function useDestinations(): Destination[] {
  const lastSession = useLastSession();
  const onDiscover = useMatch('/') !== null;
  const onMixer = useMatch('/sessions/:id/mix') !== null;
  const onLibrary = useMatch('/sessions/*') !== null && !onMixer;
  return [
    { to: '/', label: strings.nav.discover, icon: 'travel_explore', active: onDiscover },
    { to: '/sessions', label: strings.nav.library, icon: 'library_music', active: onLibrary },
    {
      // O Mixer é a última sessão aberta; sem nenhuma ainda, leva à Biblioteca para escolher.
      to: lastSession ? mixPath(lastSession) : '/sessions',
      label: strings.nav.mixer,
      icon: 'tune',
      active: onMixer,
    },
  ];
}

function Logo() {
  return (
    <span className={styles.logo}>
      <span className={styles.mark} aria-hidden="true">
        <span />
        <span />
        <span />
        <span />
      </span>
      <span className={styles.wordmark}>{strings.app.name}</span>
    </span>
  );
}

/** Topbar do desktop (60px): logo + Descobrir · Biblioteca · Mixer. */
export function Topbar() {
  const destinations = useDestinations();
  return (
    <header className={styles.topbar}>
      <NavLink to="/" className={styles.home} aria-label={strings.nav.discover}>
        <Logo />
      </NavLink>
      <nav aria-label={strings.nav.label} className={styles.topnav}>
        {destinations.map((d) => (
          <NavLink
            key={d.label}
            to={d.to}
            aria-current={d.active ? 'page' : undefined}
            className={cx(styles.toplink, d.active && styles.topActive)}
          >
            {d.label}
          </NavLink>
        ))}
      </nav>
    </header>
  );
}

/** Logo no topo das telas do celular (o design mostra o lockup acima do título). */
export function MobileBrand() {
  return (
    <div className={styles.mobileBrand}>
      <Logo />
    </div>
  );
}

/** Bottom nav do celular, com safe area. */
export function BottomNav() {
  const destinations = useDestinations();
  return (
    <nav aria-label={strings.nav.label} className={styles.bottomnav}>
      {destinations.map((d) => (
        <NavLink
          key={d.label}
          to={d.to}
          aria-current={d.active ? 'page' : undefined}
          className={cx(styles.tab, d.active && styles.tabActive)}
        >
          <span className={styles.tabIcon}>
            <Icon name={d.icon} filled={d.active} />
          </span>
          <span className={styles.tabLabel}>{d.label}</span>
        </NavLink>
      ))}
    </nav>
  );
}

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { isRouteErrorResponse, useRouteError } from 'react-router';

import { strings } from '../strings';
import { Button, ButtonLink } from '../ui/Button';
import { EmptyState, ErrorState } from '../ui/EmptyState';
import styles from './RouteError.module.css';

function reload() {
  window.location.reload();
}

function UnexpectedError() {
  return (
    <div className={styles.page}>
      <ErrorState
        icon="error"
        title={strings.errors.title}
        body={strings.errors.unexpected}
        action={
          <Button variant="secondary" icon="refresh" onClick={reload}>
            {strings.common.reload}
          </Button>
        }
      />
    </div>
  );
}

export function NotFound() {
  return (
    <div className={styles.page}>
      <EmptyState
        icon="explore_off"
        title={strings.errors.notFoundTitle}
        body={strings.errors.notFoundBody}
        action={
          <ButtonLink to="/" variant="secondary">
            {strings.errors.backHome}
          </ButtonLink>
        }
      />
    </div>
  );
}

/** `errorElement` das rotas: erro de render ou de loader numa tela. */
export function RouteError() {
  const error = useRouteError();
  if (isRouteErrorResponse(error) && error.status === 404) return <NotFound />;
  console.error(error);
  return <UnexpectedError />;
}

/** Última barreira, fora do router (ex.: erro nos providers). */
export class RootErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error(error, info.componentStack);
  }

  render() {
    return this.state.failed ? <UnexpectedError /> : this.props.children;
  }
}

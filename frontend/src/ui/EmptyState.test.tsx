import { render, screen } from '@testing-library/react';

import { EmptyState, ErrorState } from './EmptyState';

describe('EmptyState / ErrorState', () => {
  it('EmptyState mostra título, texto e ação', () => {
    render(
      <EmptyState
        title="Nada para “x”"
        body="Confira a grafia."
        action={<button type="button">ok</button>}
      />,
    );
    expect(screen.getByText('Nada para “x”')).toBeInTheDocument();
    expect(screen.getByText('Confira a grafia.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'ok' })).toBeInTheDocument();
  });

  it('ErrorState é anunciado como alerta', () => {
    render(<ErrorState title="YouTube indisponível" />);
    expect(screen.getByRole('alert')).toHaveTextContent('YouTube indisponível');
  });
});

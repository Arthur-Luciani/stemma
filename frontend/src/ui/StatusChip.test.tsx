import { render, screen } from '@testing-library/react';

import { StatusChip } from './StatusChip';

describe('StatusChip', () => {
  it.each([
    ['draft', {}, 'Rascunho'],
    ['queued', { position: 2 }, 'Na fila · 2º'],
    ['queued', {}, 'Na fila'],
    ['separating', { progress: 61.6 }, 'Separando 62%'],
    ['downloading', { progress: 5 }, 'Baixando 5%'],
    ['ready', {}, 'Pronta'],
    ['failed', {}, 'Falhou'],
  ] as const)('%s → %s', (state, props, text) => {
    render(<StatusChip state={state} {...props} />);
    expect(screen.getByText(text)).toBeInTheDocument();
  });
});

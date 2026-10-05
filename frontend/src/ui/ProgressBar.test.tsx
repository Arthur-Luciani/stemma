import { render, screen } from '@testing-library/react';

import { ProgressBar } from './ProgressBar';
import { SkeletonList } from './Skeleton';
import { Spinner } from './Spinner';

describe('ProgressBar', () => {
  it('expõe o valor arredondado e limitado a 0–100', () => {
    render(<ProgressBar value={162.4} label="Separando" />);
    expect(screen.getByRole('progressbar', { name: 'Separando' })).toHaveAttribute(
      'aria-valuenow',
      '100',
    );
  });
});

describe('SkeletonList e Spinner', () => {
  it('skeleton é um status ocupado; spinner é decorativo', () => {
    const { container } = render(
      <>
        <SkeletonList rows={3} label="Carregando…" />
        <Spinner />
      </>,
    );
    expect(screen.getByRole('status', { name: 'Carregando…' })).toHaveAttribute(
      'aria-busy',
      'true',
    );
    expect(container.lastElementChild).toHaveAttribute('aria-hidden', 'true');
  });
});

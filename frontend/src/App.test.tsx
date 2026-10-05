import { render, screen } from '@testing-library/react';

import { App } from './App.tsx';

describe('App', () => {
  it('mostra o wordmark stemma', () => {
    render(<App />);

    expect(screen.getByRole('heading', { name: 'stemma' })).toBeInTheDocument();
  });
});

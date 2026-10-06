import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';

import { TOAST_DURATION_MS, ToastProvider } from './Toast';
import { useToast } from './toastContext';

function Trigger({ persistent }: { persistent?: boolean }) {
  const toast = useToast();
  return (
    <button
      type="button"
      onClick={() => {
        toast.show({
          tone: 'good',
          message: 'ST-044 entrou na fila',
          action: { label: 'Acompanhar', to: '/sessions/x' },
          persistent,
        });
      }}
    >
      mostrar
    </button>
  );
}

function setup({ persistent }: { persistent?: boolean } = {}) {
  render(
    <MemoryRouter>
      <ToastProvider>
        <Trigger persistent={persistent} />
      </ToastProvider>
    </MemoryRouter>,
  );
}

describe('Toast', () => {
  it('mostra mensagem com ação e fecha no botão', async () => {
    setup();
    await userEvent.click(screen.getByRole('button', { name: 'mostrar' }));
    expect(screen.getByRole('status')).toHaveTextContent('ST-044 entrou na fila');
    expect(screen.getByRole('link', { name: 'Acompanhar' })).toHaveAttribute('href', '/sessions/x');
    await userEvent.click(screen.getByRole('button', { name: 'Fechar' }));
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('some sozinho depois do tempo', () => {
    vi.useFakeTimers();
    try {
      setup();
      act(() => {
        screen.getByRole('button', { name: 'mostrar' }).click();
      });
      expect(screen.getByRole('status')).toBeInTheDocument();
      act(() => {
        vi.advanceTimersByTime(TOAST_DURATION_MS + 10);
      });
      expect(screen.queryByRole('status')).not.toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }
  });

  it('persistente fica até ser fechado', () => {
    vi.useFakeTimers();
    try {
      setup({ persistent: true });
      act(() => {
        screen.getByRole('button', { name: 'mostrar' }).click();
      });
      act(() => {
        vi.advanceTimersByTime(TOAST_DURATION_MS * 10);
      });
      expect(screen.getByRole('status')).toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }
  });
});

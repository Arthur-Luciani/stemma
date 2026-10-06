import { act, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { pwaFake } from '../test/pwaRegister';
import { renderWithProviders } from '../test/render';
import { UPDATE_CHECK_MS, UpdatePrompt } from './UpdatePrompt';

describe('UpdatePrompt', () => {
  it('não mostra nada sem versão nova', () => {
    renderWithProviders(<UpdatePrompt />);

    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('avisa da versão nova e recarrega com o SW novo', async () => {
    renderWithProviders(<UpdatePrompt />);

    act(() => {
      pwaFake.needRefresh(true);
    });

    expect(screen.getByRole('status')).toHaveTextContent('Nova versão disponível');
    await userEvent.click(screen.getByRole('button', { name: 'Recarregar' }));
    expect(pwaFake.updateServiceWorker).toHaveBeenCalledWith(true);
  });

  it('procura versão nova de hora em hora', () => {
    vi.useFakeTimers();
    try {
      renderWithProviders(<UpdatePrompt />);
      const registration = { update: vi.fn(() => Promise.resolve()) };

      pwaFake
        .options()
        ?.onRegisteredSW?.('/sw.js', registration as unknown as ServiceWorkerRegistration);
      vi.advanceTimersByTime(UPDATE_CHECK_MS);

      expect(registration.update).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });
});

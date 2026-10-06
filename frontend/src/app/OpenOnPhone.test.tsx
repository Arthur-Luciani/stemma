import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { OpenOnPhone } from './OpenOnPhone';

async function openDialog(origin: string) {
  render(<OpenOnPhone origin={origin} />);
  await userEvent.click(screen.getByRole('button', { name: 'Abrir no celular' }));
}

describe('OpenOnPhone', () => {
  it('mostra o QR do endereço do Tailscale', async () => {
    await openDialog('https://pc.tail1.ts.net');

    expect(screen.getByRole('dialog', { name: 'Abrir no celular' })).toBeInTheDocument();
    expect(
      screen.getByRole('img', { name: 'QR code de https://pc.tail1.ts.net' }),
    ).toBeInTheDocument();
    expect(screen.getByText('https://pc.tail1.ts.net')).toBeInTheDocument();
  });

  it('em localhost explica em vez de mostrar um QR inútil', async () => {
    await openDialog('http://127.0.0.1:8000');

    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(screen.getByText(/só funciona neste PC/)).toBeInTheDocument();
  });

  it('fecha pelo botão', async () => {
    await openDialog('https://pc.tail1.ts.net');
    await userEvent.click(screen.getByRole('button', { name: 'Fechar' }));

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});

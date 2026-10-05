import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { BottomSheet, SheetAction } from './BottomSheet';

describe('BottomSheet', () => {
  it('abre focando o painel (sem subir o teclado num campo) e fecha com Esc', async () => {
    const onClose = vi.fn();
    render(
      <BottomSheet open onClose={onClose} label="Ações">
        <input aria-label="Campo" />
      </BottomSheet>,
    );
    expect(screen.getByRole('dialog', { name: 'Ações' })).toHaveFocus();
    await userEvent.keyboard('{Escape}');
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('SheetAction chama onSelect', async () => {
    const onSelect = vi.fn();
    render(<SheetAction icon="delete" label="Excluir" destructive onSelect={onSelect} />);
    await userEvent.click(screen.getByRole('button', { name: 'Excluir' }));
    expect(onSelect).toHaveBeenCalledOnce();
  });
});

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { Button } from './Button';
import { Dialog } from './Dialog';

function renderDialog(onClose = vi.fn()) {
  render(
    <Dialog
      open
      onClose={onClose}
      title="Excluir “Do It”?"
      actions={<Button onClick={onClose}>Cancelar</Button>}
    >
      Não dá para desfazer.
    </Dialog>,
  );
  return onClose;
}

describe('Dialog', () => {
  it('é um dialog modal com título e foca o primeiro controle', () => {
    renderDialog();
    const dialog = screen.getByRole('dialog', { name: 'Excluir “Do It”?' });
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(screen.getByRole('button', { name: 'Cancelar' })).toHaveFocus();
  });

  it('Esc e clique fora fecham', async () => {
    const onClose = renderDialog();
    await userEvent.keyboard('{Escape}');
    await userEvent.click(screen.getByTestId('modal-scrim'));
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it('fechado não renderiza nada', () => {
    render(
      <Dialog open={false} onClose={vi.fn()} title="X" actions={null}>
        corpo
      </Dialog>,
    );
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});

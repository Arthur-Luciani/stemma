import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { Menu } from './Menu';

function setup() {
  const edit = vi.fn();
  const remove = vi.fn();
  render(
    <Menu
      label="Mais ações"
      icon="more_horiz"
      items={[
        { label: 'Editar', icon: 'edit', onSelect: edit },
        { label: 'Excluir…', icon: 'delete', destructive: true, onSelect: remove },
      ]}
    />,
  );
  return { edit, remove };
}

describe('Menu', () => {
  it('abre, foca o primeiro item e escolhe pelo teclado', async () => {
    const { remove } = setup();
    await userEvent.click(screen.getByRole('button', { name: 'Mais ações' }));
    expect(screen.getByRole('menuitem', { name: 'Editar' })).toHaveFocus();
    expect(screen.getByRole('separator')).toBeInTheDocument();
    await userEvent.keyboard('{ArrowDown}{Enter}');
    expect(remove).toHaveBeenCalledOnce();
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();
  });

  it('Esc fecha e devolve o foco ao botão', async () => {
    setup();
    const trigger = screen.getByRole('button', { name: 'Mais ações' });
    await userEvent.click(trigger);
    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });
});

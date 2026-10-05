import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';

import { Button, ButtonLink } from './Button';

describe('Button', () => {
  it('chama onClick e usa type="button" por padrão', async () => {
    const onClick = vi.fn();
    render(
      <Button variant="primary" onClick={onClick}>
        Separar
      </Button>,
    );
    const button = screen.getByRole('button', { name: 'Separar' });
    expect(button).toHaveAttribute('type', 'button');
    await userEvent.click(button);
    expect(onClick).toHaveBeenCalledOnce();
  });

  it('botão só de ícone usa o label como nome acessível', () => {
    render(<Button icon="close" iconOnly label="Fechar" />);
    expect(screen.getByRole('button', { name: 'Fechar' })).toBeInTheDocument();
  });

  it('desabilitado não dispara clique', async () => {
    const onClick = vi.fn();
    render(
      <Button disabled onClick={onClick}>
        Salvar
      </Button>,
    );
    await userEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(onClick).not.toHaveBeenCalled();
  });

  it('ButtonLink é um link', () => {
    render(
      <MemoryRouter>
        <ButtonLink to="/sessions">Biblioteca</ButtonLink>
      </MemoryRouter>,
    );
    expect(screen.getByRole('link', { name: 'Biblioteca' })).toHaveAttribute('href', '/sessions');
  });
});

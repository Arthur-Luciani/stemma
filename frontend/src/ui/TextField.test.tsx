import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { Icon } from './Icon';
import { TextField } from './TextField';

describe('TextField', () => {
  it('rótulo ligado ao campo e texto à direita', async () => {
    const onChange = vi.fn();
    render(<TextField label="Artista" trailing="já usado · 3 sessões" onChange={onChange} />);
    await userEvent.type(screen.getByLabelText('Artista'), 'Q');
    expect(onChange).toHaveBeenCalled();
    expect(screen.getByText('já usado · 3 sessões')).toBeInTheDocument();
  });
});

describe('Icon', () => {
  it('fica escondido dos leitores de tela', () => {
    render(<Icon name="search" />);
    expect(screen.getByText('search')).toHaveAttribute('aria-hidden', 'true');
  });
});

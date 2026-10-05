import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { SegmentedControl } from './SegmentedControl';

const options = [
  { value: 'a', label: 'Todas' },
  { value: 'b', label: 'Prontas' },
  { value: 'c', label: 'Falhou' },
] as const;

describe('SegmentedControl', () => {
  it('marca a opção atual e troca no clique', async () => {
    const onChange = vi.fn();
    render(<SegmentedControl label="Filtro" options={options} value="a" onChange={onChange} />);
    expect(screen.getByRole('radio', { name: 'Todas' })).toHaveAttribute('aria-checked', 'true');
    await userEvent.click(screen.getByRole('radio', { name: 'Prontas' }));
    expect(onChange).toHaveBeenCalledWith('b');
  });

  it('setas do teclado andam entre as opções (com volta)', async () => {
    const onChange = vi.fn();
    render(<SegmentedControl label="Filtro" options={options} value="a" onChange={onChange} />);
    screen.getByRole('radio', { name: 'Todas' }).focus();
    await userEvent.keyboard('{ArrowLeft}');
    expect(onChange).toHaveBeenLastCalledWith('c');
    await userEvent.keyboard('{Home}');
    expect(onChange).toHaveBeenLastCalledWith('a');
  });
});

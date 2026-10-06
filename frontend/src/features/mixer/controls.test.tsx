import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';

import { formatDb } from '../../lib/format';
import { Fader } from './Fader';
import { LoopABControl } from './LoopABControl';
import { MetricsBadge } from './MetricsBadge';
import type { PresetId } from './mixState';
import { MuteSoloButton } from './MuteSoloButton';
import { PanControl } from './PanControl';
import { PresetSelector } from './PresetSelector';
import { rulerTicks, useTimelineGesture } from './timeline';

/** Retângulo de 200×40 em (0, 0) para o elemento (o jsdom não faz layout). */
function stubRect(el: Element) {
  vi.spyOn(el, 'getBoundingClientRect').mockReturnValue({
    left: 0,
    top: 0,
    right: 200,
    bottom: 40,
    width: 200,
    height: 40,
    x: 0,
    y: 0,
    toJSON: () => ({}),
  });
}

function ControlledFader({ initial = 50 }: { initial?: number }) {
  const [value, setValue] = useState(initial);
  return (
    <Fader value={value} onChange={setValue} label="Volume de Voz" color="var(--stem-vocals)" />
  );
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Fader', () => {
  it('é um slider acessível que anda com o teclado', async () => {
    render(<ControlledFader />);
    const fader = screen.getByRole('slider', { name: 'Volume de Voz' });
    expect(fader).toHaveAttribute('aria-valuenow', '50');
    expect(fader).toHaveAttribute('aria-valuetext', '50%');
    fader.focus();
    await userEvent.keyboard('{ArrowRight}{ArrowRight}');
    expect(fader).toHaveAttribute('aria-valuenow', '52');
    await userEvent.keyboard('{PageDown}');
    expect(fader).toHaveAttribute('aria-valuenow', '42');
    await userEvent.keyboard('{Home}');
    expect(fader).toHaveAttribute('aria-valuenow', '0');
    await userEvent.keyboard('{End}{ArrowUp}');
    expect(fader).toHaveAttribute('aria-valuenow', '100');
  });

  it('arrastar leva ao ponto tocado', () => {
    render(<ControlledFader initial={30} />);
    const fader = screen.getByRole('slider');
    stubRect(fader);
    fireEvent.pointerDown(fader, { clientX: 50, pointerId: 1, button: 0 });
    expect(fader).toHaveAttribute('aria-valuenow', '25');
    fireEvent.pointerMove(fader, { clientX: 150, pointerId: 1 });
    expect(fader).toHaveAttribute('aria-valuenow', '75');
    fireEvent.pointerUp(fader, { clientX: 150, pointerId: 1 });
    // Sem captura, mover não muda nada.
    fireEvent.pointerMove(fader, { clientX: 10, pointerId: 1 });
    expect(fader).toHaveAttribute('aria-valuenow', '75');
  });

  it('duplo toque volta a 100%', () => {
    render(<ControlledFader initial={30} />);
    const fader = screen.getByRole('slider');
    stubRect(fader);
    fireEvent.pointerDown(fader, { clientX: 20, pointerId: 1, button: 0 });
    fireEvent.pointerUp(fader, { clientX: 20, pointerId: 1 });
    expect(fader).toHaveAttribute('aria-valuenow', '10');
    fireEvent.pointerDown(fader, { clientX: 20, pointerId: 2, button: 0 });
    expect(fader).toHaveAttribute('aria-valuenow', '100');
  });
});

describe('PanControl', () => {
  function ControlledPan({ variant }: { variant: 'slider' | 'knob' }) {
    const [value, setValue] = useState(0);
    return <PanControl value={value} onChange={setValue} label="Pan de Baixo" variant={variant} />;
  }

  it('mostra C/L/R e anda de 1% no teclado', async () => {
    render(<ControlledPan variant="slider" />);
    const pan = screen.getByRole('slider', { name: 'Pan de Baixo' });
    expect(pan).toHaveAttribute('aria-valuetext', 'C');
    pan.focus();
    await userEvent.keyboard('{ArrowLeft}{ArrowLeft}{ArrowLeft}');
    expect(pan).toHaveAttribute('aria-valuetext', 'L3');
    await userEvent.keyboard('{End}');
    expect(pan).toHaveAttribute('aria-valuetext', 'R100');
  });

  it('slider: clique leva ao ponto tocado', () => {
    render(<ControlledPan variant="slider" />);
    const pan = screen.getByRole('slider');
    stubRect(pan);
    fireEvent.pointerDown(pan, { clientX: 50, pointerId: 1, button: 0 });
    expect(pan).toHaveAttribute('aria-valuetext', 'L50');
  });

  it('knob: arrasto vertical (para cima = direita)', () => {
    render(<ControlledPan variant="knob" />);
    const pan = screen.getByRole('slider');
    fireEvent.pointerDown(pan, { clientY: 100, pointerId: 1, button: 0 });
    fireEvent.pointerMove(pan, { clientY: 60, pointerId: 1 });
    expect(pan).toHaveAttribute('aria-valuetext', 'R50');
  });

  it('duplo toque centraliza', () => {
    render(<ControlledPan variant="slider" />);
    const pan = screen.getByRole('slider');
    stubRect(pan);
    fireEvent.pointerDown(pan, { clientX: 150, pointerId: 1, button: 0 });
    fireEvent.pointerUp(pan, { clientX: 150, pointerId: 1 });
    expect(pan).toHaveAttribute('aria-valuetext', 'R50');
    fireEvent.pointerDown(pan, { clientX: 150, pointerId: 2, button: 0 });
    expect(pan).toHaveAttribute('aria-valuetext', 'C');
  });
});

describe('MuteSoloButton', () => {
  it('é um botão de alternar com rótulo do stem', async () => {
    const onToggle = vi.fn();
    render(<MuteSoloButton kind="solo" active stem="Bateria" onToggle={onToggle} />);
    const button = screen.getByRole('button', { name: 'Solo de Bateria' });
    expect(button).toHaveAttribute('aria-pressed', 'true');
    await userEvent.click(button);
    expect(onToggle).toHaveBeenCalledOnce();
  });
});

describe('PresetSelector', () => {
  it('marca o preset ativo e troca com clique e setas', async () => {
    const onChange = vi.fn<(preset: PresetId) => void>();
    render(<PresetSelector value="no_drums" onChange={onChange} />);
    expect(screen.getByRole('radio', { name: 'Sem bateria' })).toHaveAttribute(
      'aria-checked',
      'true',
    );
    expect(screen.queryByText('Personalizado')).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('radio', { name: 'Só voz' }));
    expect(onChange).toHaveBeenLastCalledWith('vocals_only');
    screen.getByRole('radio', { name: 'Sem bateria' }).focus();
    await userEvent.keyboard('{ArrowRight}');
    expect(onChange).toHaveBeenLastCalledWith('no_bass');
  });

  it('com mix fora dos presets mostra "Personalizado" e o primeiro recebe o Tab', async () => {
    render(<PresetSelector value="custom" onChange={vi.fn()} />);
    expect(screen.getByText('Personalizado')).toBeInTheDocument();
    expect(
      screen.getAllByRole('radio').every((r) => r.getAttribute('aria-checked') === 'false'),
    ).toBe(true);
    await userEvent.tab();
    expect(screen.getByRole('radio', { name: 'Original' })).toHaveFocus();
  });

  it('a grade do Modo prática sempre mostra "Personalizado"', () => {
    render(<PresetSelector value="original" onChange={vi.fn()} variant="grid" />);
    expect(screen.getByText('Personalizado')).toBeInTheDocument();
  });
});

describe('LoopABControl', () => {
  it('desktop: marca A e B, mostra o intervalo e limpa', async () => {
    const handlers = { onMarkA: vi.fn(), onMarkB: vi.fn(), onClear: vi.fn() };
    const { rerender } = render(
      <LoopABControl variant="bar" loop={null} pendingA={null} {...handlers} />,
    );
    expect(screen.getByText('Sem loop')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Marcar A' }));
    await userEvent.click(screen.getByRole('button', { name: 'Marcar B' }));
    expect(handlers.onMarkA).toHaveBeenCalledOnce();
    expect(handlers.onMarkB).toHaveBeenCalledOnce();

    rerender(<LoopABControl variant="bar" loop={null} pendingA={58} {...handlers} />);
    expect(screen.getByText('A em 0:58 · marque o B')).toBeInTheDocument();

    rerender(<LoopABControl variant="bar" loop={{ a: 58, b: 86 }} pendingA={null} {...handlers} />);
    expect(screen.getByText('0:58 → 1:26')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Limpar loop' }));
    expect(handlers.onClear).toHaveBeenCalledOnce();
  });

  it('celular: sem loop, ensina a arrastar; com loop, "Limpar"', () => {
    const handlers = { onMarkA: vi.fn(), onMarkB: vi.fn(), onClear: vi.fn() };
    const { rerender } = render(
      <LoopABControl variant="practice" loop={null} pendingA={null} {...handlers} />,
    );
    expect(screen.getByText('Arraste na waveform para marcar o loop A–B')).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    rerender(
      <LoopABControl variant="practice" loop={{ a: 1, b: 9 }} pendingA={null} {...handlers} />,
    );
    expect(screen.getByRole('button', { name: 'Limpar' })).toBeInTheDocument();
  });
});

describe('MetricsBadge', () => {
  it('formata LUFS e dBTP (positivo em destaque) e mostra — sem medida', () => {
    expect(formatDb(-10.64)).toBe('−10.6');
    expect(formatDb(0.9, true)).toBe('+0.9');
    const { rerender } = render(<MetricsBadge metrics={{ lufs: -10.6, true_peak_db: 0.9 }} />);
    expect(screen.getByText('+0.9')).toHaveClass(/clip/);
    rerender(<MetricsBadge metrics={null} />);
    expect(screen.getAllByText('—')).toHaveLength(2);
  });
});

describe('linha do tempo', () => {
  it('rulerTicks escolhe o passo para caber até 8 marcas', () => {
    expect(rulerTicks(221)).toEqual([0, 30, 60, 90, 120, 150, 180, 210]);
    expect(rulerTicks(40)).toEqual([0, 10, 20, 30]);
    expect(rulerTicks(0)).toEqual([]);
  });

  function Timeline({ onSeek, onLoop }: { onSeek: () => void; onLoop: () => void }) {
    const { handlers, preview } = useTimelineGesture({ duration: 100, onSeek, onLoop });
    return (
      <div data-testid="timeline" {...handlers}>
        {preview ? `${String(preview.a)}-${String(preview.b)}` : 'sem prévia'}
      </div>
    );
  }

  it('toque faz seek; arrastar mostra prévia e marca o loop', () => {
    const onSeek = vi.fn();
    const onLoop = vi.fn();
    render(<Timeline onSeek={onSeek} onLoop={onLoop} />);
    const el = screen.getByTestId('timeline');
    stubRect(el);

    fireEvent.pointerDown(el, { clientX: 100, pointerId: 1, button: 0 });
    fireEvent.pointerMove(el, { clientX: 103, pointerId: 1 });
    fireEvent.pointerUp(el, { clientX: 103, pointerId: 1 });
    expect(onSeek).toHaveBeenCalledWith(50);
    expect(onLoop).not.toHaveBeenCalled();

    fireEvent.pointerDown(el, { clientX: 100, pointerId: 2, button: 0 });
    fireEvent.pointerMove(el, { clientX: 40, pointerId: 2 });
    expect(el).toHaveTextContent('20-50');
    fireEvent.pointerUp(el, { clientX: 40, pointerId: 2 });
    expect(onLoop).toHaveBeenCalledWith({ a: 20, b: 50 });
    expect(el).toHaveTextContent('sem prévia');
    expect(onSeek).toHaveBeenCalledOnce();
  });
});

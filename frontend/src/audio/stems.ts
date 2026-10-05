import type { Stem } from '../api/types';

/** Ordem de exibição dos stems, igual à do backend (`domain/enums.py`). */
export const STEMS = ['vocals', 'drums', 'bass', 'other'] as const satisfies readonly Stem[];

/** Cor de cada stem (token do design). */
export const stemColorVar = (stem: Stem) => `var(--stem-${stem})`;

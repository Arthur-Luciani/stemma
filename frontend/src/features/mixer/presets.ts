import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import {
  createPreset,
  deletePreset,
  listPresets,
  reorderPresets,
  updatePreset,
} from '../../api/endpoints';
import type { MixPreset, PresetCreate, PresetStem, PresetUpdate, Stem } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { STEMS } from '../../audio/stems';
import type { StemsMix } from './mixState';

const NONE: MixPreset[] = [];

export const MAX_PRESET_NAME = 40;

export function usePresetsQuery() {
  return useQuery({ queryKey: queryKeys.presets, queryFn: ({ signal }) => listPresets(signal) });
}

/** Presets do usuário (globais), na ordem dele. Vazio até chegarem. */
export function usePresets(): MixPreset[] {
  return usePresetsQuery().data ?? NONE;
}

/** Volume, pan e mute do mix da tela (o solo não entra no preset). */
export function presetStemsFromMix(stems: StemsMix): Record<Stem, PresetStem> {
  return Object.fromEntries(
    STEMS.map((stem) => {
      const { volume, pan, mute } = stems[stem];
      return [stem, { volume, pan, mute }];
    }),
  ) as Record<Stem, PresetStem>;
}

/** Nome já usado por outro preset (sem diferenciar caixa, com acento). */
export function presetNameTaken(
  presets: readonly MixPreset[],
  name: string,
  exceptId?: string,
): MixPreset | undefined {
  const key = name.trim().toLowerCase();
  return presets.find((p) => p.id !== exceptId && p.name.toLowerCase() === key);
}

function useRefreshPresets() {
  const queryClient = useQueryClient();
  return () => queryClient.invalidateQueries({ queryKey: queryKeys.presets });
}

export function useCreatePreset() {
  const refresh = useRefreshPresets();
  return useMutation({
    mutationFn: (body: PresetCreate) => createPreset(body),
    onSuccess: refresh,
  });
}

export function useUpdatePreset() {
  const refresh = useRefreshPresets();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: PresetUpdate }) => updatePreset(id, patch),
    onSuccess: refresh,
  });
}

export function useDeletePreset() {
  const refresh = useRefreshPresets();
  return useMutation({
    mutationFn: (id: string) => deletePreset(id),
    onSuccess: refresh,
  });
}

/** A ordem vai na hora para a lista na tela; se o servidor recusar, volta. */
export function useReorderPresets() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (ids: string[]) => reorderPresets(ids),
    onMutate: async (ids) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.presets });
      const previous = queryClient.getQueryData<MixPreset[]>(queryKeys.presets);
      if (previous) {
        const byId = new Map(previous.map((p) => [p.id, p]));
        queryClient.setQueryData<MixPreset[]>(
          queryKeys.presets,
          ids.flatMap((id) => byId.get(id) ?? []),
        );
      }
      return { previous };
    },
    onError: (_error, _ids, context) => {
      if (context?.previous) queryClient.setQueryData(queryKeys.presets, context.previous);
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: queryKeys.presets }),
  });
}

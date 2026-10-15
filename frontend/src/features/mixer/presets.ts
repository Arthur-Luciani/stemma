import { useQuery } from '@tanstack/react-query';

import { listPresets } from '../../api/endpoints';
import type { MixPreset } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';

const NONE: MixPreset[] = [];

/** Presets do usuário (globais), na ordem dele. Vazio até chegarem. */
export function usePresets(): MixPreset[] {
  const query = useQuery({
    queryKey: queryKeys.presets,
    queryFn: ({ signal }) => listPresets(signal),
  });
  return query.data ?? NONE;
}

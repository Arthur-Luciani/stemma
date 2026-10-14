import { useQuery } from '@tanstack/react-query';

import { getDiskUsage } from '../../api/endpoints';
import { queryKeys } from '../../app/queryKeys';

/** Uso de disco; só consulta com a tela aberta (o servidor percorre as pastas). */
export function useDiskUsage(enabled: boolean) {
  return useQuery({
    queryKey: queryKeys.diskUsage,
    queryFn: ({ signal }) => getDiskUsage(signal),
    enabled,
    staleTime: 0,
    retry: false,
  });
}

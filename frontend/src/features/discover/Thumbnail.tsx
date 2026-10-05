import { useState } from 'react';

import type { SearchResult } from '../../api/types';
import { formatDuration } from '../../lib/format';
import { cx } from '../../ui/cx';
import styles from './Thumbnail.module.css';

interface ThumbnailProps {
  result: Pick<SearchResult, 'thumbnail_url' | 'duration_s'>;
  /** `lg` 128×72 (desktop), `md` 112×63 (lista do celular), `sm` 80×45 (sheet). */
  size?: 'lg' | 'md' | 'sm';
}

/** Miniatura do vídeo com a duração no canto; sem imagem, o listrado do design. */
export function Thumbnail({ result, size = 'md' }: ThumbnailProps) {
  const [failed, setFailed] = useState(false);
  const showImage = result.thumbnail_url !== null && !failed;
  return (
    <div className={cx(styles.thumb, styles[size])}>
      {showImage && (
        <img
          src={result.thumbnail_url ?? undefined}
          alt=""
          loading="lazy"
          referrerPolicy="no-referrer"
          className={styles.image}
          onError={() => {
            setFailed(true);
          }}
        />
      )}
      {size !== 'sm' && result.duration_s !== null && (
        <span className={styles.duration}>{formatDuration(result.duration_s)}</span>
      )}
    </div>
  );
}

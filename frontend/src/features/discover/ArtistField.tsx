import { useId, useState, type KeyboardEvent } from 'react';

import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { TextField } from '../../ui/TextField';
import styles from './ArtistField.module.css';
import { useArtistSuggestions } from './hooks';

interface ArtistFieldProps {
  value: string;
  onChange: (value: string) => void;
  /** Mostra "já usado · N sessões" dentro do campo quando bate com um artista existente. */
  showUsedHint?: boolean;
}

const normalize = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .trim()
    .toLowerCase();

/** Campo de artista com autocomplete (combobox ARIA) dos artistas já usados + contagem. */
export function ArtistField({ value, onChange, showUsedHint }: ArtistFieldProps) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const listId = useId();
  const { data } = useArtistSuggestions(value);
  const suggestions = data ?? [];
  const exact = suggestions.find((a) => normalize(a.name) === normalize(value));
  // Não sugere o que já está escrito igualzinho.
  const visible = suggestions.filter((a) => a.name !== value);
  const expanded = open && visible.length > 0;

  const choose = (name: string) => {
    onChange(name);
    setOpen(false);
    setActive(-1);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setOpen(true);
      setActive((i) => Math.min(i + 1, visible.length - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActive((i) => Math.max(i - 1, -1));
    } else if (event.key === 'Enter' && expanded && active >= 0) {
      const artist = visible[active];
      if (artist) {
        event.preventDefault();
        choose(artist.name);
      }
    } else if (event.key === 'Escape' && expanded) {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
    }
  };

  return (
    <div className={styles.wrap}>
      <TextField
        label={strings.identity.artist}
        value={value}
        autoComplete="off"
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={expanded}
        aria-controls={listId}
        aria-activedescendant={expanded && active >= 0 ? `${listId}-${String(active)}` : undefined}
        trailing={showUsedHint && exact ? strings.identity.usedBefore(exact.sessions) : undefined}
        onChange={(event) => {
          onChange(event.target.value);
          setOpen(true);
          setActive(-1);
        }}
        onFocus={() => {
          setOpen(true);
        }}
        onBlur={() => {
          setOpen(false);
        }}
        onKeyDown={onKeyDown}
      />
      {expanded && (
        <ul id={listId} role="listbox" aria-label={strings.identity.artist} className={styles.list}>
          {visible.map((artist, index) => (
            <li
              key={artist.name}
              id={`${listId}-${String(index)}`}
              role="option"
              aria-selected={index === active}
              className={cx(styles.option, index === active && styles.active)}
              // `mousedown` antes do `blur` do input, senão a lista fecha antes do clique.
              onMouseDown={(event) => {
                event.preventDefault();
                choose(artist.name);
              }}
            >
              <span className={styles.name}>{artist.name}</span>
              <span className={styles.count}>{strings.identity.sessions(artist.sessions)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

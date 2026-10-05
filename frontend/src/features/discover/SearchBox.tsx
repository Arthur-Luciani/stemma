import { useState, type FormEvent } from 'react';

import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/Icon';
import styles from './SearchBox.module.css';

interface SearchBoxProps {
  /** Busca atual (vem da URL). */
  query: string;
  onSearch: (q: string) => void;
  onClear: () => void;
}

/** Busca de 56/60px: texto ou link do YouTube; botão de colar e de limpar. */
export function SearchBox({ query, onSearch, onClear }: SearchBoxProps) {
  const [draft, setDraft] = useState(query);
  const [synced, setSynced] = useState(query);
  // A URL mudou por fora (back/forward): o campo acompanha.
  if (synced !== query) {
    setSynced(query);
    setDraft(query);
  }

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const q = draft.trim();
    if (q) onSearch(q);
  };

  const paste = async () => {
    try {
      const text = (await navigator.clipboard.readText()).trim();
      if (!text) return;
      setDraft(text);
      onSearch(text);
    } catch {
      // Sem permissão de leitura do clipboard: o usuário cola no campo.
    }
  };

  return (
    <form role="search" className={styles.box} onSubmit={submit}>
      <Icon name="search" className={styles.icon} />
      <input
        type="search"
        enterKeyHint="search"
        aria-label={strings.discover.searchLabel}
        placeholder={strings.discover.searchPlaceholder}
        className={styles.input}
        value={draft}
        onChange={(event) => {
          setDraft(event.target.value);
        }}
      />
      {draft ? (
        <Button
          variant="ghost"
          icon="close"
          iconOnly
          label={strings.discover.clear}
          onClick={() => {
            setDraft('');
            onClear();
          }}
        />
      ) : (
        <Button
          variant="ghost"
          icon="content_paste"
          aria-label={strings.discover.paste}
          className={styles.paste}
          onClick={() => void paste()}
        >
          <span className={styles.pasteText}>{strings.discover.pasteHint}</span>
        </Button>
      )}
    </form>
  );
}

/** `items[index]` que falha o teste em vez de devolver `undefined`. */
export function nth<T>(items: readonly T[], index: number): T {
  const item = items[index];
  if (item === undefined)
    throw new Error(`item ${String(index)} não existe (há ${String(items.length)})`);
  return item;
}

/** Primeiro elemento cujo texto contém `text`; falha o teste se não houver. */
export function withText<T extends Element>(items: readonly T[], text: string): T {
  const item = items.find((el) => el.textContent.includes(text));
  if (!item) throw new Error(`nenhum elemento com o texto "${text}"`);
  return item;
}

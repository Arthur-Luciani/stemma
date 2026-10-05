/** Junta classes ignorando vazias (as classes de CSS Module são `string | undefined`). */
export function cx(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(' ');
}

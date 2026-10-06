/** Endereços que só existem neste PC: um QR deles não abre nada no celular. */
export function isLocalOrigin(origin: string): boolean {
  const host = new URL(origin).hostname;
  return host === 'localhost' || host === '[::1]' || host.startsWith('127.');
}

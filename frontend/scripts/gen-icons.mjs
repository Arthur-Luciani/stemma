// Gera os ícones do PWA em public/ a partir de public/favicon.svg e pwa/icon-maskable.svg (`npm run gen:icons`).
// Os PNGs são commitados; rode de novo só se a marca mudar.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import sharp from 'sharp';

const root = fileURLToPath(new URL('..', import.meta.url));
const BG = '#121416';

const icon = await readFile(`${root}public/favicon.svg`);
const maskable = await readFile(`${root}pwa/icon-maskable.svg`);

/** @type {Array<{ file: string; svg: Buffer; size: number; flatten?: boolean }>} */
const outputs = [
  // "any": a marca com borda e cantos transparentes (launcher e splash do Android).
  { file: 'pwa-192x192.png', svg: icon, size: 192 },
  { file: 'pwa-512x512.png', svg: icon, size: 512 },
  // "maskable": fundo cheio; o Android recorta no formato do launcher.
  { file: 'maskable-icon-512x512.png', svg: maskable, size: 512 },
  // iOS arredonda os cantos sozinho e não aceita transparência.
  { file: 'apple-touch-icon-180x180.png', svg: maskable, size: 180, flatten: true },
  { file: 'favicon-32x32.png', svg: icon, size: 32 },
  { file: 'favicon-16x16.png', svg: icon, size: 16 },
];

for (const { file, svg, size, flatten } of outputs) {
  let image = sharp(svg, { density: Math.ceil((72 * size) / 160) * 2 }).resize(size, size);
  if (flatten) image = image.flatten({ background: BG });
  await image.png({ compressionLevel: 9 }).toFile(`${root}public/${file}`);
  console.log(`public/${file}`);
}

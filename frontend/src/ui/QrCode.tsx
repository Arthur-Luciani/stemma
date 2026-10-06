import { useMemo } from 'react';
import { encode } from 'uqr';

import styles from './QrCode.module.css';

interface QrCodeProps {
  /** Texto codificado (um endereço). */
  value: string;
  /** Rótulo acessível da imagem. */
  label: string;
}

/** Zona de silêncio exigida pela norma, em módulos. */
const QUIET = 4;

/** QR code em SVG: módulos escuros sobre fundo claro (leitura confiável em qualquer câmera). */
export function QrCode({ value, label }: QrCodeProps) {
  const { path, size } = useMemo(() => {
    const qr = encode(value, { ecc: 'M', border: 0 });
    let d = '';
    qr.data.forEach((row, y) => {
      row.forEach((dark, x) => {
        if (dark) d += `M${String(x + QUIET)} ${String(y + QUIET)}h1v1h-1z`;
      });
    });
    return { path: d, size: qr.size + 2 * QUIET };
  }, [value]);

  return (
    <svg
      className={styles.qr}
      viewBox={`0 0 ${String(size)} ${String(size)}`}
      role="img"
      aria-label={label}
      shapeRendering="crispEdges"
    >
      <rect className={styles.quiet} width={size} height={size} />
      <path className={styles.modules} d={path} />
    </svg>
  );
}

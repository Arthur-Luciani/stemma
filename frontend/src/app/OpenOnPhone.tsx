import { useState } from 'react';

import { isLocalOrigin } from '../lib/origin';
import { strings } from '../strings';
import { Button } from '../ui/Button';
import { Dialog } from '../ui/Dialog';
import { QrCode } from '../ui/QrCode';
import styles from './OpenOnPhone.module.css';

interface OpenOnPhoneProps {
  /** Endereço do app (padrão: o desta página). */
  origin?: string;
}

/** Botão discreto da topbar (só desktop): QR do endereço atual para abrir no celular. */
export function OpenOnPhone({ origin = window.location.origin }: OpenOnPhoneProps) {
  const [open, setOpen] = useState(false);
  const local = isLocalOrigin(origin);

  return (
    <>
      <Button
        variant="ghost"
        icon="qr_code_2"
        iconOnly
        label={strings.phone.open}
        onClick={() => {
          setOpen(true);
        }}
      />
      <Dialog
        open={open}
        onClose={() => {
          setOpen(false);
        }}
        title={strings.phone.open}
        actions={
          <Button
            onClick={() => {
              setOpen(false);
            }}
          >
            {strings.common.close}
          </Button>
        }
      >
        {local ? (
          <p className={styles.text}>{strings.phone.localOnly}</p>
        ) : (
          <>
            <p className={styles.text}>{strings.phone.hint}</p>
            <div className={styles.code}>
              <QrCode value={origin} label={strings.phone.qrLabel(origin)} />
            </div>
          </>
        )}
        <p className={styles.url}>{origin}</p>
      </Dialog>
    </>
  );
}

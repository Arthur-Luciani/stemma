import { useState } from 'react';

import type { MixPreset } from '../../api/types';
import { useErrorToast } from '../../app/useErrorToast';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Dialog } from '../../ui/Dialog';
import { EmptyState, ErrorState } from '../../ui/EmptyState';
import { Icon } from '../../ui/Icon';
import { Menu } from '../../ui/Menu';
import { Modal } from '../../ui/Modal';
import { SkeletonList } from '../../ui/Skeleton';
import { Switch } from '../../ui/Switch';
import { useToast } from '../../ui/toastContext';
import { PresetMark } from './PresetMark';
import { presetDelta } from './presetText';
import {
  presetStemsFromMix,
  useDeletePreset,
  usePresetsQuery,
  useReorderPresets,
  useUpdatePreset,
} from './presets';
import styles from './PresetManager.module.css';
import { SavePresetDialog } from './SavePresetDialog';
import { StemSummary } from './StemSummary';
import type { Mixer } from './useMixer';

interface PresetManagerProps {
  mixer: Pick<Mixer, 'state' | 'preset' | 'dispatch'> & { state: NonNullable<Mixer['state']> };
  onClose: () => void;
  onSaveCurrent: () => void;
}

type Pending =
  | { kind: 'edit'; preset: MixPreset }
  | { kind: 'update'; preset: MixPreset }
  | { kind: 'remove'; preset: MixPreset };

/**
 * Gaveta (desktop) ou tela cheia (celular) com todos os presets. Fica sobre o mixer, então a
 * música continua tocando e "Aplicar" funciona como prévia.
 */
export function PresetManager({ mixer, onClose, onSaveCurrent }: PresetManagerProps) {
  const query = usePresetsQuery();
  const presets = query.data ?? [];
  const [pending, setPending] = useState<Pending | null>(null);
  const update = useUpdatePreset();
  const remove = useDeletePreset();
  const reorder = useReorderPresets();
  const toast = useToast();
  const onError = useErrorToast();
  const active = mixer.preset;

  const move = (index: number, delta: number) => {
    const ids = presets.map((p) => p.id);
    const [moved] = ids.splice(index, 1);
    if (!moved) return;
    ids.splice(index + delta, 0, moved);
    reorder.mutate(ids, {
      onError: () => {
        toast.show({
          tone: 'bad',
          message: strings.mixer.preset.reorderFailed,
          action: {
            label: strings.common.retry,
            onClick: () => {
              move(index, delta);
            },
          },
        });
      },
    });
  };

  const body = () => {
    if (query.isPending)
      return <SkeletonList rows={4} thumb={false} label={strings.common.reload} />;
    if (query.isError) {
      return (
        <ErrorState
          title={strings.mixer.preset.managerLoadFailed}
          action={
            <Button
              onClick={() => {
                void query.refetch();
              }}
            >
              {strings.common.retry}
            </Button>
          }
        />
      );
    }
    if (presets.length === 0) {
      return (
        <EmptyState
          title={strings.mixer.preset.empty}
          body={strings.mixer.preset.emptyBody}
          action={
            <Button variant="primary" icon="bookmark_add" onClick={onSaveCurrent}>
              {strings.mixer.preset.saveAs}
            </Button>
          }
        />
      );
    }
    return (
      <ul className={styles.list}>
        {presets.map((preset, index) => {
          const isActive = preset.id === active?.id;
          return (
            <li key={preset.id} className={styles.row}>
              <PresetMark preset={preset} className={styles.mark} />
              <span className={styles.name}>{preset.name}</span>
              <StemSummary stems={preset.stems} className={styles.summary} />
              <span className={styles.delta}>{presetDelta(preset)}</span>
              {isActive ? (
                <span className={styles.applied}>
                  <Icon name="check" size={18} />
                  {strings.mixer.preset.applied}
                </span>
              ) : (
                <Button
                  size="sm"
                  className={styles.apply}
                  aria-label={strings.mixer.preset.applyNamed(preset.name)}
                  onClick={() => {
                    mixer.dispatch({ type: 'preset', preset });
                  }}
                >
                  {strings.mixer.preset.apply}
                </Button>
              )}
              <Switch
                label={strings.mixer.preset.showInSelector(preset.name)}
                className={styles.visible}
                checked={preset.visible}
                onChange={(visible) => {
                  update.mutate({ id: preset.id, patch: { visible } }, { onError });
                }}
              />
              <Menu
                icon="more_vert"
                label={strings.mixer.preset.actionsFor(preset.name)}
                className={styles.more}
                items={[
                  {
                    label: strings.mixer.preset.updateWithMix,
                    icon: 'sync',
                    onSelect: () => {
                      setPending({ kind: 'update', preset });
                    },
                  },
                  {
                    label: strings.mixer.preset.edit,
                    icon: 'edit',
                    onSelect: () => {
                      setPending({ kind: 'edit', preset });
                    },
                  },
                  ...(index > 0
                    ? [
                        {
                          label: strings.mixer.preset.moveUp,
                          icon: 'arrow_upward',
                          onSelect: () => {
                            move(index, -1);
                          },
                        },
                      ]
                    : []),
                  ...(index < presets.length - 1
                    ? [
                        {
                          label: strings.mixer.preset.moveDown,
                          icon: 'arrow_downward',
                          onSelect: () => {
                            move(index, 1);
                          },
                        },
                      ]
                    : []),
                  {
                    label: strings.mixer.preset.remove,
                    icon: 'delete',
                    destructive: true,
                    onSelect: () => {
                      setPending({ kind: 'remove', preset });
                    },
                  },
                ]}
              />
            </li>
          );
        })}
      </ul>
    );
  };

  return (
    <>
      <Modal
        open
        onClose={onClose}
        label={strings.mixer.preset.managerTitle}
        layerClassName={styles.layer}
        panelClassName={styles.panel}
      >
        <header className={styles.head}>
          <h2 className={styles.title}>{strings.mixer.preset.managerTitle}</h2>
          <Button variant="secondary" size="sm" icon="bookmark_add" onClick={onSaveCurrent}>
            {strings.mixer.preset.save}
          </Button>
          <Button
            variant="ghost"
            icon="close"
            iconOnly
            label={strings.common.close}
            onClick={onClose}
          />
        </header>
        <div className={styles.body}>{body()}</div>
      </Modal>

      {pending?.kind === 'edit' && (
        <SavePresetDialog
          mode="edit"
          preset={pending.preset}
          presets={presets}
          onClose={() => {
            setPending(null);
          }}
        />
      )}
      {pending?.kind === 'update' && (
        <Dialog
          open
          onClose={() => {
            setPending(null);
          }}
          title={strings.mixer.preset.updateTitle(pending.preset.name)}
          actions={
            <>
              <Button
                variant="ghost"
                data-autofocus
                onClick={() => {
                  setPending(null);
                }}
              >
                {strings.common.cancel}
              </Button>
              <Button
                variant="primary"
                disabled={update.isPending}
                onClick={() => {
                  update.mutate(
                    {
                      id: pending.preset.id,
                      patch: { stems: presetStemsFromMix(mixer.state.stems) },
                    },
                    {
                      onSuccess: () => {
                        toast.show({
                          tone: 'good',
                          message: strings.mixer.preset.updated(pending.preset.name),
                        });
                      },
                      onError,
                      onSettled: () => {
                        setPending(null);
                      },
                    },
                  );
                }}
              >
                {strings.common.update}
              </Button>
            </>
          }
        >
          <p className={styles.confirmText}>{strings.mixer.preset.updateBody}</p>
          <div className={styles.compare}>
            <span>{strings.mixer.preset.before}</span>
            <StemSummary stems={pending.preset.stems} />
            <span>{strings.mixer.preset.after}</span>
            <StemSummary stems={presetStemsFromMix(mixer.state.stems)} />
          </div>
        </Dialog>
      )}
      {pending?.kind === 'remove' && (
        <Dialog
          open
          onClose={() => {
            setPending(null);
          }}
          title={strings.mixer.preset.removeTitle(pending.preset.name)}
          actions={
            <>
              <Button
                variant="ghost"
                data-autofocus
                onClick={() => {
                  setPending(null);
                }}
              >
                {strings.common.cancel}
              </Button>
              <Button
                variant="destructive"
                disabled={remove.isPending}
                onClick={() => {
                  remove.mutate(pending.preset.id, {
                    onSuccess: () => {
                      toast.show({
                        tone: 'good',
                        message: strings.mixer.preset.removed(pending.preset.name),
                      });
                    },
                    onError,
                    onSettled: () => {
                      setPending(null);
                    },
                  });
                }}
              >
                {strings.mixer.preset.remove}
              </Button>
            </>
          }
        >
          <p className={styles.confirmText}>{strings.mixer.preset.removeBody}</p>
        </Dialog>
      )}
    </>
  );
}

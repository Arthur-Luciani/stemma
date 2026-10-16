import { useState, type FormEvent } from 'react';

import type { MixPreset, PresetColor, PresetIcon, PresetStem, Stem } from '../../api/types';
import { errorMessage } from '../../app/useErrorToast';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Dialog } from '../../ui/Dialog';
import { Switch } from '../../ui/Switch';
import { TextField } from '../../ui/TextField';
import { useToast } from '../../ui/toastContext';
import { PresetMarkPicker } from './PresetMarkPicker';
import { MAX_PRESET_NAME, presetNameTaken, useCreatePreset, useUpdatePreset } from './presets';
import styles from './SavePresetDialog.module.css';

const FORM_ID = 'save-preset-form';

type SavePresetDialogProps = {
  presets: readonly MixPreset[];
  onClose: () => void;
} & ({ mode: 'create'; stems: Record<Stem, PresetStem> } | { mode: 'edit'; preset: MixPreset });

/** Salva o mix atual como preset novo, ou edita nome, ícone e cor de um existente. */
export function SavePresetDialog(props: SavePresetDialogProps) {
  const { presets, onClose } = props;
  const edit = props.mode === 'edit';
  const [name, setName] = useState(edit ? props.preset.name : '');
  const [icon, setIcon] = useState<PresetIcon | null>(edit ? props.preset.icon : null);
  const [color, setColor] = useState<PresetColor | null>(edit ? props.preset.color : null);
  const [visible, setVisible] = useState(true);
  const create = useCreatePreset();
  const update = useUpdatePreset();
  const toast = useToast();
  const pending = create.isPending || update.isPending;
  const failure = create.error ?? update.error;

  const trimmed = name.trim();
  const taken = trimmed
    ? presetNameTaken(presets, trimmed, edit ? props.preset.id : undefined)
    : undefined;
  const tooLong = name.length > MAX_PRESET_NAME;
  const error = tooLong
    ? strings.mixer.preset.nameTooLong(MAX_PRESET_NAME)
    : taken
      ? strings.mixer.preset.nameTaken
      : null;
  const valid = trimmed.length > 0 && error === null;

  const submit = () => {
    if (!valid || pending) return;
    if (props.mode === 'edit') {
      update.mutate(
        { id: props.preset.id, patch: { name: trimmed, icon, color } },
        {
          onSuccess: () => {
            toast.show({ tone: 'good', message: strings.mixer.preset.edited });
            onClose();
          },
        },
      );
    } else {
      create.mutate(
        { name: trimmed, stems: props.stems, visible, icon, color },
        {
          onSuccess: (saved) => {
            toast.show({ tone: 'good', message: strings.mixer.preset.saved(saved.name) });
            onClose();
          },
        },
      );
    }
  };

  const updateInstead = () => {
    if (props.mode !== 'create' || !taken) return;
    update.mutate(
      { id: taken.id, patch: { stems: props.stems } },
      {
        onSuccess: () => {
          toast.show({ tone: 'good', message: strings.mixer.preset.updated(taken.name) });
          onClose();
        },
      },
    );
  };

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    submit();
  };

  return (
    <Dialog
      open
      onClose={onClose}
      title={edit ? strings.mixer.preset.editTitle : strings.mixer.preset.saveTitle}
      actions={
        <>
          <Button variant="ghost" onClick={onClose}>
            {strings.common.cancel}
          </Button>
          <Button type="submit" form={FORM_ID} variant="primary" disabled={!valid || pending}>
            {strings.common.save}
          </Button>
        </>
      }
    >
      <form id={FORM_ID} className={styles.form} onSubmit={onSubmit} noValidate>
        <TextField
          label={strings.mixer.preset.name}
          value={name}
          placeholder={strings.mixer.preset.namePlaceholder}
          autoComplete="off"
          aria-invalid={error !== null}
          aria-describedby="preset-name-hint"
          onChange={(event) => {
            setName(event.target.value);
          }}
          trailing={
            <span className={tooLong ? styles.over : styles.counter}>
              {strings.mixer.preset.counter(name.length, MAX_PRESET_NAME)}
            </span>
          }
        />
        <p id="preset-name-hint" role={error ? 'alert' : undefined} className={styles.error}>
          {error}
        </p>
        {!edit && taken && (
          <Button variant="secondary" size="sm" onClick={updateInstead} disabled={pending}>
            {strings.mixer.preset.updateInstead(taken.name)}
          </Button>
        )}
        <PresetMarkPicker
          icon={icon}
          color={color}
          stems={edit ? props.preset.stems : props.stems}
          onIcon={setIcon}
          onColor={setColor}
        />
        {!edit && (
          <div className={styles.toggle}>
            <span>{strings.mixer.preset.showToggle}</span>
            <Switch
              label={strings.mixer.preset.showToggle}
              checked={visible}
              onChange={setVisible}
            />
          </div>
        )}
        {failure && (
          <p role="alert" className={styles.error}>
            {errorMessage(failure)}
          </p>
        )}
      </form>
    </Dialog>
  );
}

"""mix_presets: presets editáveis do usuário (ADR 0018)

Cria `mix_presets` com os cinco presets de antes, passa `exports.preset` de enum para o nome
(texto) e remove `mix_states.preset` (o preset passa a ser derivado na tela).

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-15 12:00:00.000000

"""

import uuid
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0005"
down_revision: str | Sequence[str] | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_STEMS = ("vocals", "drums", "bass", "other")

# (valor antigo do enum, nome do preset, stems mudos). Congelado aqui: a migration não importa
# o app, que muda depois.
_PRESETS = (
    ("original", "Original", ()),
    ("no_vocals", "Sem voz", ("vocals",)),
    ("no_drums", "Sem bateria", ("drums",)),
    ("no_bass", "Sem baixo", ("bass",)),
    ("vocals_only", "Só voz", ("drums", "bass", "other")),
)
# `custom` nunca foi um preset de verdade; no histórico vira o nome que a tela mostrava.
_LEGACY_NAMES = {**{old: name for old, name, _ in _PRESETS}, "custom": "Personalizado"}

_OLD_ENUM = sa.Enum(
    "original",
    "no_vocals",
    "no_drums",
    "no_bass",
    "vocals_only",
    "custom",
    name="mixpreset",
    native_enum=False,
    length=16,
)


def upgrade() -> None:
    presets = op.create_table(
        "mix_presets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=40), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("visible", sa.Boolean(), server_default="1", nullable=False),
        sa.Column("stems", sa.JSON(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_mix_presets")),
        sa.UniqueConstraint("name", name=op.f("uq_mix_presets_name")),
    )
    op.bulk_insert(
        presets,
        [
            {
                "id": uuid.uuid4(),
                "name": name,
                "position": position,
                "visible": True,
                "stems": {
                    stem: {"volume": 100, "pan": 0, "mute": stem in muted} for stem in _STEMS
                },
            }
            for position, (_, name, muted) in enumerate(_PRESETS)
        ],
    )

    with op.batch_alter_table("exports", schema=None) as batch_op:
        batch_op.alter_column(
            "preset",
            existing_type=_OLD_ENUM,
            type_=sa.String(length=40),
            existing_nullable=True,
        )
    for old, name in _LEGACY_NAMES.items():
        op.execute(
            sa.text("UPDATE exports SET preset = :name WHERE preset = :old").bindparams(
                name=name, old=old
            )
        )

    with op.batch_alter_table("mix_states", schema=None) as batch_op:
        batch_op.drop_column("preset")


def downgrade() -> None:
    with op.batch_alter_table("mix_states", schema=None) as batch_op:
        batch_op.add_column(sa.Column("preset", _OLD_ENUM, server_default="custom", nullable=False))

    reverse = {name: old for old, name in _LEGACY_NAMES.items()}
    for name, old in reverse.items():
        op.execute(
            sa.text("UPDATE exports SET preset = :old WHERE preset = :name").bindparams(
                name=name, old=old
            )
        )
    # Nomes que o usuário criou não existem no enum antigo.
    op.execute(
        sa.text("UPDATE exports SET preset = 'custom' WHERE preset NOT IN :known").bindparams(
            sa.bindparam("known", expanding=True, value=list(_LEGACY_NAMES.keys()))
        )
    )
    with op.batch_alter_table("exports", schema=None) as batch_op:
        batch_op.alter_column(
            "preset",
            existing_type=sa.String(length=40),
            type_=_OLD_ENUM,
            existing_nullable=True,
        )

    op.drop_table("mix_presets")

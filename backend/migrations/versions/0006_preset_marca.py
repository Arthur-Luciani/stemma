"""mix_presets: ícone e cor do preset (ADR 0019)

Adiciona `icon` e `color` (opcionais) e dá ícone e cor aos cinco presets que a 0005 criou,
desde que ainda tenham o nome original e nenhuma marca.

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-16 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0006"
down_revision: str | Sequence[str] | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# (nome, ícone, cor). Congelado aqui: a migration não importa o app, que muda depois.
_DEFAULTS = (
    ("Original", "graphic_eq", None),
    ("Sem voz", "mic_off", "vocals"),
    ("Sem bateria", "volume_off", "drums"),
    ("Sem baixo", "volume_off", "bass"),
    ("Só voz", "mic", "vocals"),
)


def upgrade() -> None:
    with op.batch_alter_table("mix_presets", schema=None) as batch_op:
        batch_op.add_column(sa.Column("icon", sa.String(length=32), nullable=True))
        batch_op.add_column(sa.Column("color", sa.String(length=16), nullable=True))
    for name, icon, color in _DEFAULTS:
        op.execute(
            sa.text(
                "UPDATE mix_presets SET icon = :icon, color = :color"
                " WHERE name = :name AND icon IS NULL AND color IS NULL"
            ).bindparams(name=name, icon=icon, color=color)
        )


def downgrade() -> None:
    with op.batch_alter_table("mix_presets", schema=None) as batch_op:
        batch_op.drop_column("color")
        batch_op.drop_column("icon")

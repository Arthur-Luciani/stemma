"""system_updates: componente (app ou yt-dlp, ADR 0016)

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-14 15:30:57.374779

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("system_updates", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "component",
                sa.Enum("app", "ytdlp", name="updatecomponent", native_enum=False, length=16),
                server_default="app",
                nullable=False,
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("system_updates", schema=None) as batch_op:
        batch_op.drop_column("component")

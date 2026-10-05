"""jobs: etapa, durações e descarte

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-05 14:43:01.048925

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("jobs", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "stage",
                sa.Enum(
                    "draft",
                    "queued",
                    "downloading",
                    "separating",
                    "ready",
                    "failed",
                    name="sessionstate",
                    native_enum=False,
                    length=16,
                ),
                nullable=True,
            )
        )
        batch_op.add_column(sa.Column("stage_started_at", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("stage_durations", sa.JSON(), nullable=True))
        batch_op.add_column(sa.Column("dismissed_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("jobs", schema=None) as batch_op:
        batch_op.drop_column("dismissed_at")
        batch_op.drop_column("stage_durations")
        batch_op.drop_column("stage_started_at")
        batch_op.drop_column("stage")

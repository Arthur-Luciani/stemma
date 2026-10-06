"""system_updates: atualizações pedidas pelo app (ADR 0015)

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-06 15:51:38.970608

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "system_updates",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("from_version", sa.String(length=32), nullable=False),
        sa.Column("target_version", sa.String(length=32), nullable=False),
        sa.Column(
            "state",
            sa.Enum(
                "running", "succeeded", "failed", name="updatestate", native_enum=False, length=16
            ),
            nullable=False,
        ),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_system_updates")),
    )


def downgrade() -> None:
    op.drop_table("system_updates")

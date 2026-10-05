"""baseline: sessões, jobs, eventos, mix states e exports

Revision ID: 0001
Revises:
Create Date: 2026-10-05 14:02:48.902777

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    counters = op.create_table(
        "counters",
        sa.Column("name", sa.String(length=32), nullable=False),
        sa.Column("value", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("name", name=op.f("pk_counters")),
    )
    # Sequência dos códigos ST-###: o primeiro será ST-001.
    op.bulk_insert(counters, [{"name": "session_code", "value": 0}])
    op.create_table(
        "sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(length=16), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=False),
        sa.Column("source_title", sa.Text(), nullable=True),
        sa.Column("source_channel", sa.Text(), nullable=True),
        sa.Column("thumbnail_url", sa.Text(), nullable=True),
        sa.Column("artist", sa.String(length=200), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("artist_key", sa.String(length=200), nullable=False),
        sa.Column("search_key", sa.Text(), nullable=False),
        sa.Column("duration_s", sa.Double(), nullable=True),
        sa.Column(
            "state",
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
            nullable=False,
        ),
        sa.Column("progress", sa.Double(), nullable=False),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("stems", sa.JSON(), nullable=True),
        sa.Column("metrics", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sessions")),
        sa.UniqueConstraint("code", name=op.f("uq_sessions_code")),
    )
    with op.batch_alter_table("sessions", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_sessions_artist_key"), ["artist_key"], unique=False)
        batch_op.create_index(batch_op.f("ix_sessions_created_at"), ["created_at"], unique=False)
        batch_op.create_index(batch_op.f("ix_sessions_state"), ["state"], unique=False)

    op.create_table(
        "exports",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column(
            "format",
            sa.Enum("wav", "mp3", name="exportformat", native_enum=False, length=16),
            nullable=False,
        ),
        sa.Column(
            "preset",
            sa.Enum(
                "original",
                "no_vocals",
                "no_drums",
                "no_bass",
                "vocals_only",
                "custom",
                name="mixpreset",
                native_enum=False,
                length=16,
            ),
            nullable=True,
        ),
        sa.Column("levels", sa.JSON(), nullable=False),
        sa.Column(
            "state",
            sa.Enum(
                "queued",
                "running",
                "done",
                "failed",
                name="exportstate",
                native_enum=False,
                length=16,
            ),
            nullable=False,
        ),
        sa.Column("progress", sa.Double(), nullable=False),
        sa.Column("path", sa.Text(), nullable=True),
        sa.Column("size_bytes", sa.Integer(), nullable=True),
        sa.Column("lufs", sa.Double(), nullable=True),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_exports_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_exports")),
    )
    with op.batch_alter_table("exports", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_exports_session_id"), ["session_id"], unique=False)

    op.create_table(
        "mix_states",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("stems", sa.JSON(), nullable=False),
        sa.Column(
            "preset",
            sa.Enum(
                "original",
                "no_vocals",
                "no_drums",
                "no_bass",
                "vocals_only",
                "custom",
                name="mixpreset",
                native_enum=False,
                length=16,
            ),
            nullable=False,
        ),
        sa.Column("loop_a_s", sa.Double(), nullable=True),
        sa.Column("loop_b_s", sa.Double(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_mix_states_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("session_id", name=op.f("pk_mix_states")),
    )
    op.create_table(
        "session_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("type", sa.String(length=64), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_session_events_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_session_events")),
    )
    with op.batch_alter_table("session_events", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_session_events_session_id"), ["session_id"], unique=False
        )

    op.create_table(
        "jobs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "kind",
            sa.Enum("process", "export", name="jobkind", native_enum=False, length=16),
            nullable=False,
        ),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("export_id", sa.Uuid(), nullable=True),
        sa.Column(
            "state",
            sa.Enum(
                "queued",
                "running",
                "done",
                "failed",
                "cancelled",
                name="jobstate",
                native_enum=False,
                length=16,
            ),
            nullable=False,
        ),
        sa.Column("progress", sa.Double(), nullable=False),
        sa.Column("attempt", sa.Integer(), nullable=False),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["export_id"],
            ["exports.id"],
            name=op.f("fk_jobs_export_id_exports"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["sessions.id"],
            name=op.f("fk_jobs_session_id_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_jobs")),
    )
    with op.batch_alter_table("jobs", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_jobs_session_id"), ["session_id"], unique=False)
        batch_op.create_index(
            batch_op.f("ix_jobs_state_created_at"), ["state", "created_at"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("jobs", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_jobs_state_created_at"))
        batch_op.drop_index(batch_op.f("ix_jobs_session_id"))

    op.drop_table("jobs")
    with op.batch_alter_table("session_events", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_session_events_session_id"))

    op.drop_table("session_events")
    op.drop_table("mix_states")
    with op.batch_alter_table("exports", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_exports_session_id"))

    op.drop_table("exports")
    with op.batch_alter_table("sessions", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_sessions_state"))
        batch_op.drop_index(batch_op.f("ix_sessions_created_at"))
        batch_op.drop_index(batch_op.f("ix_sessions_artist_key"))

    op.drop_table("sessions")
    op.drop_table("counters")

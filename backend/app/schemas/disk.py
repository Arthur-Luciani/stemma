from pydantic import BaseModel


class DiskUsageOut(BaseModel):
    """Uso de disco do `STORAGE_ROOT` por categoria e espaço do volume dele (em bytes)."""

    total_bytes: int
    free_bytes: int
    stems_bytes: int
    exports_bytes: int
    backups_bytes: int
    # Limites de retenção em vigor (`EXPORTS_KEEP` por sessão, `BACKUPS_KEEP`).
    exports_keep: int
    backups_keep: int

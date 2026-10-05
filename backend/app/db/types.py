import time
from datetime import UTC, datetime

from sqlalchemy import DateTime, Dialect
from sqlalchemy.types import TypeDecorator


class UTCDateTime(TypeDecorator[datetime]):
    """Datetime sempre com timezone. O SQLite não guarda fuso: grava em UTC sem tz e
    devolve com `UTC`. Recusa datetime ingênuo para não misturar fusos por engano."""

    impl = DateTime
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("datetime sem timezone")
        return value.astimezone(UTC).replace(tzinfo=None)

    def process_result_value(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        return value.replace(tzinfo=UTC)


# No Windows (Python 3.12) o relógio de parede anda em degraus de 15,6 ms: registros criados
# em sequência empatariam no `created_at` e a ordem da fila e das listas ficaria aleatória.
# O relógio daqui é a âncora de parede + o `perf_counter` (resolução de µs), reancorado se
# os dois se afastarem mais que `_MAX_DRIFT_NS` (ex.: ajuste de NTP).
_MAX_DRIFT_NS = 1_000_000_000
_anchor = (time.time_ns(), time.perf_counter_ns())


def utcnow() -> datetime:
    global _anchor
    wall_anchor, perf_anchor = _anchor
    ns = wall_anchor + time.perf_counter_ns() - perf_anchor
    if abs(ns - time.time_ns()) > _MAX_DRIFT_NS:
        _anchor = (time.time_ns(), time.perf_counter_ns())
        ns = _anchor[0]
    seconds, rest = divmod(ns, 1_000_000_000)
    return datetime.fromtimestamp(seconds, UTC).replace(microsecond=rest // 1000)

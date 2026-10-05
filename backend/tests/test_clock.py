from datetime import UTC, datetime, timedelta

from app.db.types import utcnow


def test_utcnow_tem_timezone_e_acompanha_o_relogio() -> None:
    now = utcnow()

    assert now.tzinfo is UTC
    assert abs(now - datetime.now(UTC)) < timedelta(seconds=1)


def test_utcnow_nao_empata_em_chamadas_seguidas() -> None:
    # O relógio de parede do Windows anda de 15,6 em 15,6 ms; a fila depende da ordem.
    stamps = [utcnow() for _ in range(1000)]

    assert stamps == sorted(stamps)
    assert len(set(stamps)) > 900

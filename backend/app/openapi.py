"""Exporta o schema OpenAPI sem subir servidor: `python -m app.openapi <saída.json>`.

O frontend gera `src/api/schema.d.ts` a partir desse arquivo (`npm run gen:api`).
A saída é determinística (chaves ordenadas, LF) para o CI acusar drift com `git diff`.
"""

import json
import sys
from pathlib import Path

from app.main import create_app


def render() -> str:
    schema = create_app().openapi()
    # A versão muda a cada release; fora do contrato para não gerar drift falso.
    schema["info"].pop("version", None)
    return json.dumps(schema, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        sys.stderr.write("uso: python -m app.openapi <saída.json>\n")
        return 2
    Path(argv[0]).write_text(render(), encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

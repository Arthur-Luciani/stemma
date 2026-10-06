"""Build do frontend servido pelo próprio backend, na mesma origem da API (ADR 0002).

Arquivo que existe no `dist` é servido como está; qualquer outro path vira o `index.html`
(fallback da SPA, para o React Router). `/api`, `/ws` e `/health` nunca caem no fallback.
"""

import logging
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse

logger = logging.getLogger(__name__)

# Prefixos do backend: um path desconhecido aqui é 404 da API, não tela do app.
_BACKEND_PREFIXES = ("api", "ws", "health")
# Vite gera `assets/<nome>-<hash>.<ext>`: o conteúdo nunca muda no mesmo nome.
_IMMUTABLE = "public, max-age=31536000, immutable"
# Precisam ser revalidados a cada carga para uma versão nova aparecer.
_NO_CACHE_FILES = {"index.html", "sw.js", "registerSW.js", "manifest.webmanifest"}
_NO_CACHE = "no-cache"
_SHORT = "public, max-age=86400"


def _cache_control(rel: str) -> str:
    if rel.startswith("assets/"):
        return _IMMUTABLE
    if rel in _NO_CACHE_FILES or rel.startswith("workbox-"):
        return _NO_CACHE
    return _SHORT


def install_spa(app: FastAPI, dist_dir: Path) -> None:
    """Registra a rota coringa; chame **depois** de incluir os routers da API."""
    root = dist_dir.resolve()
    index = root / "index.html"
    if not index.is_file():
        logger.warning("SERVE_FRONTEND_DIR sem index.html (%s): frontend não será servido", root)
        return

    @app.api_route("/{path:path}", methods=["GET", "HEAD"], include_in_schema=False)
    def spa(path: str) -> FileResponse:
        if path.split("/", 1)[0] in _BACKEND_PREFIXES:
            raise HTTPException(status_code=404)
        if path:
            candidate = (root / path).resolve()
            if candidate.is_relative_to(root) and candidate.is_file():
                rel = candidate.relative_to(root).as_posix()
                return FileResponse(candidate, headers={"Cache-Control": _cache_control(rel)})
        return FileResponse(index, headers={"Cache-Control": _NO_CACHE})

    logger.info("Frontend servido de %s", root)

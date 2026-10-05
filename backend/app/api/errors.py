"""Handlers que garantem o formato único de erro: `{"error": {"code", "message"}}`."""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.domain.errors import AppError
from app.schemas.errors import ErrorOut

logger = logging.getLogger(__name__)

# Para documentar no OpenAPI as respostas de erro de cada rota.
ERROR_RESPONSES: dict[int | str, dict[str, Any]] = {
    404: {"model": ErrorOut, "description": "Não encontrado"},
    409: {"model": ErrorOut, "description": "Conflito com o estado atual"},
    422: {"model": ErrorOut, "description": "Entrada inválida"},
}

_HTTP_CODES = {
    404: ("not_found", "Recurso não encontrado."),
    405: ("method_not_allowed", "Método não permitido."),
}


def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": message}})


def _translate(err: dict[str, Any]) -> str:
    """Mensagem do Pydantic → PT-BR (os tipos de erro que a API realmente produz)."""
    kind = err.get("type", "")
    ctx = err.get("ctx") or {}
    match kind:
        case "missing":
            return "obrigatório"
        case "uuid_parsing" | "uuid_type" | "uuid_version":
            return "identificador inválido"
        case "string_too_short":
            return "não pode ficar vazio"
        case "string_too_long":
            return f"máximo de {ctx.get('max_length')} caracteres"
        case "greater_than_equal":
            return f"deve ser maior ou igual a {ctx.get('ge')}"
        case "less_than_equal":
            return f"deve ser menor ou igual a {ctx.get('le')}"
        case "greater_than":
            return f"deve ser maior que {ctx.get('gt')}"
        case "less_than":
            return f"deve ser menor que {ctx.get('lt')}"
        case "enum" | "literal_error":
            return "valor não permitido"
        case "url_parsing" | "url_scheme" | "url_type":
            return "URL inválida"
        case "float_parsing" | "float_type" | "int_parsing" | "int_type" | "finite_number":
            return "número inválido"
        case "bool_parsing" | "bool_type":
            return "deve ser verdadeiro ou falso"
        case "string_type":
            return "deve ser texto"
        case "extra_forbidden":
            return "campo não permitido"
        case "json_invalid":
            return "JSON inválido"
        case "value_error" if "error" in ctx:
            return str(ctx["error"])
        case _:
            return "inválido"


def _describe_validation(exc: RequestValidationError) -> str:
    parts = []
    for err in exc.errors()[:3]:
        loc = ".".join(str(p) for p in err.get("loc", ()) if p not in ("body", "query", "path"))
        parts.append(f"{loc}: {_translate(err)}" if loc else _translate(err))
    return "Dados inválidos — " + "; ".join(parts) + "." if parts else "Dados inválidos."


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_request: Request, exc: AppError) -> JSONResponse:
        if exc.status >= 500:
            logger.error("Erro %s: %s", exc.code, exc.message)
        return _error(exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_request: Request, exc: RequestValidationError) -> JSONResponse:
        return _error(422, "validation_error", _describe_validation(exc))

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_request: Request, exc: StarletteHTTPException) -> JSONResponse:
        code, message = _HTTP_CODES.get(exc.status_code, ("http_error", str(exc.detail)))
        return _error(exc.status_code, code, message)

    @app.exception_handler(Exception)
    async def _unexpected(_request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Erro inesperado", exc_info=exc)
        return _error(500, "internal_error", "Erro interno do servidor.")

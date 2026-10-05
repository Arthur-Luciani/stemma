"""Erros de domínio. A API serializa qualquer `AppError` como `{"error": {"code", "message"}}`."""


class AppError(Exception):
    """Erro esperado, com código estável para o cliente e mensagem em PT-BR."""

    status: int = 400

    def __init__(self, code: str, message: str, status: int | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        if status is not None:
            self.status = status


class NotFoundError(AppError):
    status = 404


class ConflictError(AppError):
    status = 409


class InvalidInputError(AppError):
    status = 422


def session_not_found() -> NotFoundError:
    return NotFoundError("session_not_found", "Sessão não encontrada.")


def job_not_found() -> NotFoundError:
    return NotFoundError("job_not_found", "Job não encontrado.")

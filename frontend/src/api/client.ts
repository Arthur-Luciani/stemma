import createClient from 'openapi-fetch';

import type { paths } from './schema';

/** Erro da API já normalizado de `{"error": {"code", "message"}}`. */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

export const NETWORK_ERROR = 'network_error';
const NETWORK_MESSAGE = 'Sem conexão com o servidor.';
const UNKNOWN_MESSAGE = 'Algo deu errado. Tente de novo.';

/** A API e o frontend dividem a mesma origem (proxy do Vite em dev, uvicorn em produção). */
export const apiClient = createClient<paths>({
  baseUrl: typeof window === 'undefined' ? '' : window.location.origin,
  // Busca o `fetch` a cada chamada: os testes trocam o global (MSW) depois do import.
  fetch: (request) => globalThis.fetch(request),
});

function isErrorBody(body: unknown): body is { error: { code: string; message: string } } {
  if (typeof body !== 'object' || body === null || !('error' in body)) return false;
  const error = body.error;
  return (
    typeof error === 'object' &&
    error !== null &&
    typeof (error as { code?: unknown }).code === 'string' &&
    typeof (error as { message?: unknown }).message === 'string'
  );
}

export function toApiError(status: number, body: unknown): ApiError {
  if (isErrorBody(body)) return new ApiError(status, body.error.code, body.error.message);
  return new ApiError(status, 'unknown_error', UNKNOWN_MESSAGE);
}

interface FetchResult<T> {
  data?: T;
  error?: unknown;
  response: Response;
}

/**
 * Executa uma chamada do `apiClient` e devolve os dados, ou lança `ApiError`.
 * Falha de rede vira `network_error`.
 */
export async function call<T>(request: () => Promise<FetchResult<T>>): Promise<T> {
  let result: FetchResult<T>;
  try {
    result = await request();
  } catch (cause) {
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new ApiError(0, NETWORK_ERROR, NETWORK_MESSAGE);
  }
  if (!result.response.ok) throw toApiError(result.response.status, result.error);
  return result.data as T;
}

export function isApiError(error: unknown, code?: string): error is ApiError {
  return error instanceof ApiError && (code === undefined || error.code === code);
}

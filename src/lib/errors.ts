export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const badRequest = (message: string) => new AppError(400, 'BAD_REQUEST', message);
export const unauthorized = (message = 'unauthorized') => new AppError(401, 'UNAUTHORIZED', message);
export const forbidden = (message = 'forbidden') => new AppError(403, 'FORBIDDEN', message);
export const notFound = (message = 'not found') => new AppError(404, 'NOT_FOUND', message);
export const conflict = (message = 'conflict') => new AppError(409, 'CONFLICT', message);
export const rateLimited = (message = 'too many requests') => new AppError(429, 'RATE_LIMITED', message);

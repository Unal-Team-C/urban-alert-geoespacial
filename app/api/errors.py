"""Domain exceptions and handlers that normalize every error to {code, message[, details]}."""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.schemas import ErrorDetail, ErrorResponse
from app.db.repository import DB_UNAVAILABLE_ERRORS


class NotFoundError(Exception):
    message = "Not found"


class CoordinateNotFoundError(NotFoundError):
    message = "Coordinate not found"


class ConflictError(Exception):
    message = "Report already has a different location"


class ServiceUnavailableError(Exception):
    message = "Service unavailable"


def error_response(code: int, message: str, details: list[ErrorDetail] | None = None) -> JSONResponse:
    body = ErrorResponse(code=code, message=message, details=details)
    return JSONResponse(status_code=code, content=body.model_dump(exclude_none=True))


def _validation_details(exc: RequestValidationError) -> list[ErrorDetail]:
    # Only location and reason: the offending input is never echoed back.
    details = []
    for error in exc.errors():
        loc = [str(part) for part in error.get("loc", ()) if part not in ("body", "query", "path")]
        reason = str(error.get("msg", "invalid value")).removeprefix("Value error, ")
        details.append(ErrorDetail(field=".".join(loc) or "request", reason=reason))
    return details


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def _invalid(_: Request, exc: RequestValidationError) -> JSONResponse:
        return error_response(400, "Invalid parameter", _validation_details(exc))

    @app.exception_handler(NotFoundError)
    async def _not_found(_: Request, exc: NotFoundError) -> JSONResponse:
        return error_response(404, exc.message)

    @app.exception_handler(ConflictError)
    async def _conflict(_: Request, exc: ConflictError) -> JSONResponse:
        return error_response(409, exc.message)

    async def _unavailable(_: Request, __: Exception) -> JSONResponse:
        return error_response(503, ServiceUnavailableError.message)

    for error_type in (ServiceUnavailableError, *DB_UNAVAILABLE_ERRORS):
        app.add_exception_handler(error_type, _unavailable)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        return error_response(exc.status_code, str(exc.detail))

FROM docker.io/library/python:3.13-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app ./app
COPY db/schema.sql ./db/schema.sql
RUN chmod -R a+rX /srv && useradd --create-home --uid 10001 appuser
USER appuser
EXPOSE 8000
# Exec form keeps uvicorn as PID 1 so it receives SIGTERM from ECS; graceful timeout < ECS stopTimeout (30 s).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--no-access-log", "--timeout-graceful-shutdown", "20", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]

FROM runtime AS test
USER root
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY pyproject.toml .
COPY tests ./tests
RUN chmod -R a+rX /srv
USER appuser
CMD ["pytest", "-q"]

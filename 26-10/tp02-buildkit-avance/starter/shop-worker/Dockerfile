# syntax=docker/dockerfile:1
# L'index PyPI authentifié passe par un secret mount, jamais par un ARG.
# Le cache pip est séparé par architecture pour les builds multi-plateformes.

FROM python:3.12-slim-bookworm AS builder

ARG TARGETARCH

WORKDIR /app

COPY requirements.txt ./

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    pip install -r requirements.txt

FROM builder AS test

ARG TARGETARCH

COPY requirements-dev.txt ./
COPY worker ./worker
COPY tests ./tests

RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    pip install -r requirements-dev.txt \
 && python -m pytest -q tests \
 && ruff check worker tests

FROM python:3.12-slim-bookworm AS runtime

ARG APP_VERSION=dev
ARG GIT_SHA=local

LABEL org.opencontainers.image.title="shop-worker" \
      org.opencontainers.image.description="Worker de traitement des commandes Shop SAS" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="https://github.com/HugoBerrier/Docker-ex"

RUN useradd --uid 1000 --create-home --shell /usr/sbin/nologin worker

WORKDIR /app

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

COPY --from=builder /opt/venv /opt/venv
COPY --from=test --chown=1000:1000 /app/worker ./worker

USER 1000
EXPOSE 9100

CMD ["python", "-m", "worker.main"]

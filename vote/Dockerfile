# base: Python runtime + dependencies, shared by the dev and final stages.
# Pinned to Python 3.13 on Debian 13 (trixie) so builds are repeatable.
FROM python:3.13-slim-trixie@sha256:b3575dcf816cdacc5292df77a6e3e59b8941631078373a045efa2ac1e9c5c3b2 AS base

# curl is used by the container healthcheck
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# a normal user to run the app (fixed UID so Kubernetes can check runAsNonRoot)
RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /usr/local/app

# install the pinned requirements first so this layer is cached between code changes
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# dev: used by docker compose, reloads when files change
FROM base AS dev
RUN pip install --no-cache-dir watchdog==6.0.0
ENV FLASK_ENV=development
USER app
CMD ["python", "app.py"]

# final: what gets shipped
FROM base AS final

# pip (and the packages it bundles, like urllib3) is only needed to install
# dependencies, never at runtime. Removing it takes its vulnerabilities out of
# the image that gets shipped (Trivy flagged HIGH CVEs in pip's bundled copies).
RUN python -m pip uninstall -y pip setuptools wheel

COPY --chown=app:app . .

USER app

# 8080, not 80: a non-root user cannot bind to ports below 1024
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fs http://localhost:8080/ || exit 1

CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8080", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]

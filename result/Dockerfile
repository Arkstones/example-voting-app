# base: Node.js 24 (LTS) on Debian 13 (trixie), pinned so builds are repeatable
FROM node:24-trixie-slim@sha256:43b9ba1142b8dcf33fa8f922ca1be85714adc444e0586c7cf7726daaeabc1bea AS base

# curl for the healthcheck, tini so Ctrl+C / SIGTERM stop node cleanly
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app

# install exact versions from package-lock.json, production packages only.
# node_modules lives outside the app folder so a dev bind mount doesn't hide it.
COPY package*.json ./
RUN npm ci --omit=dev && \
    npm cache clean --force && \
    mv /usr/local/app/node_modules /node_modules

ENV PORT=8080
EXPOSE 8080

# dev: used by docker compose, restarts on file changes
FROM base AS dev
RUN npm install -g nodemon@3.1.14
# the official node image already has a non-root "node" user (uid 1000)
USER node
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["nodemon", "--inspect=0.0.0.0", "server.js"]

# final: what gets shipped
FROM base AS final
COPY --chown=node:node . .
USER node

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fs http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]

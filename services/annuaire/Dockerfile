# ---- Stage 1 : build / install des dépendances ----
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json* ./

# npm ci si lock présent, sinon npm install
RUN if [ -f package-lock.json ]; then \
        npm ci --omit=dev; \
    else \
        npm install --omit=dev; \
    fi

COPY src ./src

# ---- Stage 2 : image runtime ----
FROM node:20-alpine AS runtime

LABEL org.opencontainers.image.source="https://github.com/ViartFelix/infra-2-bz"

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src
COPY --from=build /app/package.json ./package.json

RUN addgroup -g 1001 app && adduser -D -u 1001 -G app app \
    && chown -R app:app /app
USER 1001

ENV PORT=8080 \
    LOG_LEVEL=info \
    NODE_ENV=production

EXPOSE 8080

CMD ["node", "src/index.js"]
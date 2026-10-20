# Game server image. Build from the repository root (it needs data/):
#   docker build -f server/Dockerfile .
FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY server/package.json server/package-lock.json server/
RUN cd server && npm ci --omit=dev && npm cache clean --force
COPY data data
COPY site site
COPY client/i18n client/i18n
COPY server/tsconfig.json server/
COPY server/migrations server/migrations
COPY server/src server/src
WORKDIR /app/server
USER node
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:8080/health').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"
CMD ["npx", "tsx", "src/server.ts"]

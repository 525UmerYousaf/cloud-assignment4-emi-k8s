# Loan EMI calculator image (emi-web).
# Official slim base, production dependencies only, runs as a non-root user.
FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# Dependencies first: this layer is cached until package*.json changes.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Application code (node_modules, tests, git files etc. are excluded by .dockerignore).
COPY app.js emi.js server.js ./
COPY public ./public

# The version shown in the page title and footer: 1.0 by default,
# build 1.1 with  --build-arg APP_VERSION=1.1  for the rolling update.
ARG APP_VERSION=1.0
ENV APP_VERSION=${APP_VERSION} \
    PORT=8080

# The official node image ships an unprivileged user called "node" (uid 1000).
# Files stay owned by root, so the running process cannot modify its own code.
USER node

EXPOSE 8080
CMD ["node", "server.js"]

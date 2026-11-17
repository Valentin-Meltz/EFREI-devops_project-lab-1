# Lightweight base image: Node.js LTS on Alpine Linux
FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

WORKDIR /app

# Install only production dependencies first, so this layer is cached
# as long as package*.json don't change
COPY --chown=node:node package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy the application source
COPY --chown=node:node src ./src

# Run as the non-root "node" user provided by the official image
USER node

EXPOSE 3000

CMD ["node", "src/server.js"]

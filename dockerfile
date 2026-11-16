FROM node:26-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY . .
RUN npm run build

FROM node:26-alpine
WORKDIR /app
COPY --from=builder /app ./
EXPOSE 3000 4000 5000
ENV NODE_ENV=development
USER root
CMD ["node", "server.js"]

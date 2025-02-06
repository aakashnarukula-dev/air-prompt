FROM node:20-alpine AS pwa-build
WORKDIR /app
COPY mobile-pwa/package.json mobile-pwa/package-lock.json ./mobile-pwa/
COPY shared ./shared
RUN cd mobile-pwa && npm ci
COPY mobile-pwa ./mobile-pwa
ARG VITE_FIREBASE_API_KEY
ARG VITE_FIREBASE_AUTH_DOMAIN
ARG VITE_FIREBASE_PROJECT_ID
ARG VITE_FIREBASE_APP_ID
ARG VITE_BACKEND_WS_URL
RUN cd mobile-pwa && npm run build

FROM node:20-alpine AS backend-build
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./backend/
COPY shared ./shared
RUN cd backend && npm ci
COPY backend ./backend
RUN cd backend && npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=backend-build /app/backend/node_modules ./backend/node_modules
COPY --from=backend-build /app/backend/dist ./backend/dist
COPY --from=backend-build /app/backend/migrations ./backend/migrations
COPY --from=backend-build /app/backend/package.json ./backend/
COPY --from=pwa-build /app/mobile-pwa/dist ./mobile-pwa/dist
COPY shared ./shared
EXPOSE 8787
CMD ["node", "backend/dist/backend/src/server.js"]

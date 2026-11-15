FROM node:22-slim
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx prisma generate && npm run build
RUN chown -R node:node /app
USER node
EXPOSE 3000
CMD ["node", "dist/src/main.js"]

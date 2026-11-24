FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# Instala apenas as dependências de produção, exatamente as do package-lock.json
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY index.js ./

# Executa sem privilégios de root
USER node

EXPOSE 5000

# Saudável = API respondendo E conectada ao MongoDB (ver rota /health)
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||5000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "index.js"]

# Etapa 1: construção da aplicação React
FROM node:22-alpine AS build

WORKDIR /app

# Instala exatamente as dependências do package-lock.json
COPY package*.json ./
RUN npm ci --no-audit --no-fund

COPY public ./public
COPY src ./src

# Sem REACT_APP_API_URL, a interface chama a API por caminhos relativos
# (/todos), no mesmo endereço servido por este Nginx.
RUN npm run build

# Etapa 2: Nginx servindo a interface e encaminhando a API
FROM nginx:1.27-alpine

COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY proxy_api.conf /etc/nginx/proxy_api.conf

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]

# Versão fixa: "latest" poderia trocar a versão principal do MongoDB numa
# atualização e tornar os dados existentes incompatíveis.
FROM mongo:7.0

COPY demo-todos.js /opt/todo/demo-todos.js
COPY init-mongo.js /docker-entrypoint-initdb.d/

EXPOSE 27017

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD mongosh --quiet --eval "quit(db.adminCommand('ping').ok ? 0 : 1)" || exit 1

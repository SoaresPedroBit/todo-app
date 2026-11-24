// Executado pelo MongoDB SOMENTE na primeira inicialização (pasta de dados vazia).
// Atualizações da aplicação não passam por aqui e, portanto, não apagam tarefas.

load('/opt/todo/demo-todos.js');

db = db.getSiblingDB('todo-app');

// Credencial própria da aplicação: só lê e grava o banco todo-app.
// A senha vem de arquivo (produção) ou de variável de ambiente (desenvolvimento).
const fs = require('fs');
let appPassword = process.env.MONGO_APP_PASSWORD;
if (process.env.MONGO_APP_PASSWORD_FILE) {
  appPassword = fs.readFileSync(process.env.MONGO_APP_PASSWORD_FILE, 'utf8').trim();
}
if (appPassword) {
  db.createUser({
    user: 'todo_app',
    pwd: appPassword,
    roles: [{ role: 'readWrite', db: 'todo-app' }],
  });
  print('Usuário todo_app criado');
} else {
  print('AVISO: senha da aplicação não informada; usuário todo_app não criado');
}

db.createCollection('todos');
db.todos.insertMany(DEMO_TODOS);

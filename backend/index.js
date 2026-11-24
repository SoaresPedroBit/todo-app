const fs = require('fs');
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

// ---------------------------------------------------------------------------
// Configuração por ambiente
// ---------------------------------------------------------------------------
// A string de conexão contém a senha do banco, então ela nunca fica no código.
// Em produção vem de um arquivo montado como segredo (MONGO_URI_FILE); em
// desenvolvimento pode vir diretamente da variável MONGO_URI.
function lerMongoUri() {
  if (process.env.MONGO_URI_FILE) {
    return fs.readFileSync(process.env.MONGO_URI_FILE, 'utf8').trim();
  }
  if (process.env.MONGO_URI) {
    return process.env.MONGO_URI;
  }
  throw new Error('Defina MONGO_URI ou MONGO_URI_FILE com a conexão do MongoDB');
}

const port = Number(process.env.PORT) || 5000;
const mongoUri = lerMongoUri();

// O frontend e a API ficam no mesmo endereço (o Nginx encaminha /todos), então
// CORS não é necessário. Só é habilitado se CORS_ORIGIN listar origens.
const corsOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

// ---------------------------------------------------------------------------
// Conexão com o MongoDB com novas tentativas
// ---------------------------------------------------------------------------
// O banco pode demorar a ficar pronto (ou reiniciar). Em vez de falhar uma vez
// e ficar sem banco, a API tenta de novo até conseguir. Enquanto isso, /health
// responde 503 e as rotas de tarefas devolvem 503.
let encerrando = false;

async function conectar(tentativa = 1) {
  try {
    await mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 5000 });
    console.log('Conectado ao MongoDB');
  } catch (err) {
    // Apenas a mensagem: o objeto de erro pode carregar detalhes da conexão.
    const espera = Math.min(30, 2 ** Math.min(tentativa, 5));
    console.error(`Erro ao conectar ao MongoDB (tentativa ${tentativa}): ${err.message}. Nova tentativa em ${espera}s`);
    if (!encerrando) {
      setTimeout(() => conectar(tentativa + 1), espera * 1000);
    }
  }
}

mongoose.connection.on('disconnected', () => {
  if (!encerrando) console.warn('Conexão com o MongoDB perdida; o driver tentará reconectar');
});
mongoose.connection.on('reconnected', () => console.log('Reconectado ao MongoDB'));

const bancoConectado = () => mongoose.connection.readyState === 1;

// ---------------------------------------------------------------------------
// Aplicação
// ---------------------------------------------------------------------------
const app = express();
app.disable('x-powered-by');
app.set('trust proxy', true);

if (corsOrigins.length > 0) {
  app.use(cors({ origin: corsOrigins }));
}
app.use(express.json({ limit: '10kb' }));

// Verificação de saúde: inclui um ping no banco, para que "saudável" signifique
// que a API consegue de fato atender as tarefas.
app.get('/health', async (req, res) => {
  if (!bancoConectado()) {
    return res.status(503).json({ status: 'erro', api: 'ok', banco: 'desconectado' });
  }
  try {
    await mongoose.connection.db.admin().ping();
    return res.json({ status: 'ok', api: 'ok', banco: 'ok' });
  } catch (err) {
    return res.status(503).json({ status: 'erro', api: 'ok', banco: 'sem resposta' });
  }
});

// Sem banco, as rotas de tarefas respondem 503 imediatamente em vez de esperar
// o tempo limite do driver.
app.use('/todos', (req, res, next) => {
  if (!bancoConectado()) {
    return res.status(503).json({ message: 'Banco de dados indisponível no momento' });
  }
  return next();
});

// Definindo o modelo de Tarefa (To-do)
const TodoSchema = new mongoose.Schema({
  text: { type: String, required: true, trim: true, maxlength: 280 },
  completed: { type: Boolean, default: false },
});

const Todo = mongoose.model('Todo', TodoSchema);

const idValido = (id) => mongoose.Types.ObjectId.isValid(id);

// Rota para obter todas as tarefas (GET)
app.get('/todos', async (req, res) => {
  try {
    const todos = await Todo.find(); // Retorna todas as tarefas do banco
    res.json(todos);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rota para adicionar uma nova tarefa (POST)
app.post('/todos', async (req, res) => {
  const { text } = req.body || {}; // Obtém o texto da tarefa do corpo da requisição

  // Verifica se o campo "text" está presente
  if (typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ message: 'O campo "text" é obrigatório' });
  }

  const todo = new Todo({
    text,
    completed: false,
  });

  try {
    const newTodo = await todo.save(); // Salva a tarefa no banco
    return res.status(201).json(newTodo); // Retorna a tarefa criada
  } catch (err) {
    return res.status(400).json({ message: err.message }); // Retorna erro se houver falha de validação
  }
});

// Rota para concluir ou reabrir uma tarefa (PATCH)
app.patch('/todos/:id', async (req, res) => {
  if (!idValido(req.params.id)) {
    return res.status(404).json({ message: 'Tarefa não encontrada' });
  }
  try {
    const todo = await Todo.findById(req.params.id); // Encontra a tarefa pelo ID

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    // Alterna o status de "completed" da tarefa
    todo.completed = !todo.completed;
    await todo.save(); // Salva a tarefa modificada
    return res.json(todo); // Retorna a tarefa atualizada
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

// Rota para excluir uma tarefa (DELETE)
app.delete('/todos/:id', async (req, res) => {
  if (!idValido(req.params.id)) {
    return res.status(404).json({ message: 'Tarefa não encontrada' });
  }
  try {
    const todo = await Todo.findByIdAndDelete(req.params.id); // Deleta a tarefa pelo ID

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    return res.json({ message: 'Tarefa excluída com sucesso' }); // Retorna uma mensagem de sucesso
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

// JSON malformado ou corpo grande demais: responde 400/413 sem stack trace.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  const status = err.status || err.statusCode || 500;
  res.status(status).json({ message: status === 500 ? 'Erro interno' : err.message });
});

// ---------------------------------------------------------------------------
// Inicialização e encerramento
// ---------------------------------------------------------------------------
const server = app.listen(port, () => {
  console.log(`Servidor rodando na porta ${port}`);
});
conectar();

function encerrar(sinal) {
  encerrando = true;
  console.log(`${sinal} recebido, encerrando`);
  server.close(() => {
    mongoose.disconnect().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => encerrar('SIGTERM'));
process.on('SIGINT', () => encerrar('SIGINT'));

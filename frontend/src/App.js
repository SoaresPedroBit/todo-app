import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

// A API é acessada pelo mesmo endereço da interface: o Nginx encaminha /todos
// para o backend. Por isso a base padrão é vazia (caminhos relativos).
// REACT_APP_API_URL só é necessária se a API estiver em outro endereço.
const API_URL = process.env.REACT_APP_API_URL || '';

function App() {
  const [todos, setTodos] = useState([]);
  const [task, setTask] = useState("");
  const [erro, setErro] = useState("");

  const executar = async (acao) => {
    try {
      await acao();
      setErro("");
    } catch (err) {
      setErro("Não foi possível falar com o servidor. Tente novamente em instantes.");
    }
  };

  // Função para carregar os todos da API
  const fetchTodos = () => executar(async () => {
    const response = await axios.get(`${API_URL}/todos`);
    setTodos(response.data);
  });

  // Função para adicionar uma nova tarefa
  const addTodo = () => executar(async () => {
    if (task.trim()) {
      const response = await axios.post(`${API_URL}/todos`, { text: task });
      setTodos((atuais) => [...atuais, response.data]);
      setTask("");
    }
  });

  // Função para marcar a tarefa como concluída ou reabri-la
  const toggleComplete = (id) => executar(async () => {
    const response = await axios.patch(`${API_URL}/todos/${id}`);
    setTodos((atuais) => atuais.map((todo) => (todo._id === id ? response.data : todo)));
  });

  // Função para excluir a tarefa
  const deleteTodo = (id) => executar(async () => {
    await axios.delete(`${API_URL}/todos/${id}`);
    setTodos((atuais) => atuais.filter((todo) => todo._id !== id));
  });

  // Carregar a lista de todos ao iniciar o componente
  useEffect(() => {
    fetchTodos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="App">
      <h1>Lista de Tarefas</h1>
      <div>
        <input
          type="text"
          value={task}
          maxLength={280}
          onChange={(e) => setTask(e.target.value)}
          placeholder="Adicione uma tarefa"
        />
        <button onClick={addTodo}>Adicionar</button>
      </div>
      {erro && <p role="alert">{erro}</p>}
      <ul>
        {todos.map((todo) => (
          <li key={todo._id} style={{ textDecoration: todo.completed ? "line-through" : "none" }}>
            <span onClick={() => toggleComplete(todo._id)}>{todo.text}</span>
            <button onClick={() => deleteTodo(todo._id)}>Excluir</button>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default App;

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import axios from 'axios';
import App from './App';

// A fábrica evita carregar o axios real (pacote ESM que o Jest do CRA não lê).
jest.mock('axios', () => ({
  get: jest.fn(),
  post: jest.fn(),
  patch: jest.fn(),
  delete: jest.fn(),
}));

beforeEach(() => {
  jest.resetAllMocks();
});

test('lista as tarefas usando caminho relativo (mesmo endereço da interface)', async () => {
  axios.get.mockResolvedValue({ data: [{ _id: '1', text: 'Estudar Cloud', completed: false }] });

  render(<App />);

  expect(await screen.findByText('Estudar Cloud')).toBeInTheDocument();
  expect(axios.get).toHaveBeenCalledWith('/todos');
});

test('adiciona, conclui e exclui uma tarefa', async () => {
  axios.get.mockResolvedValue({ data: [] });
  axios.post.mockResolvedValue({ data: { _id: '2', text: 'Nova tarefa', completed: false } });
  axios.patch.mockResolvedValue({ data: { _id: '2', text: 'Nova tarefa', completed: true } });
  axios.delete.mockResolvedValue({ data: { message: 'ok' } });

  render(<App />);
  await waitFor(() => expect(axios.get).toHaveBeenCalled());

  fireEvent.change(screen.getByPlaceholderText('Adicione uma tarefa'), { target: { value: 'Nova tarefa' } });
  fireEvent.click(screen.getByText('Adicionar'));
  const item = await screen.findByText('Nova tarefa');
  expect(axios.post).toHaveBeenCalledWith('/todos', { text: 'Nova tarefa' });

  fireEvent.click(item);
  await waitFor(() => expect(item.closest('li')).toHaveStyle('text-decoration: line-through'));
  expect(axios.patch).toHaveBeenCalledWith('/todos/2');

  fireEvent.click(screen.getByText('Excluir'));
  await waitFor(() => expect(screen.queryByText('Nova tarefa')).not.toBeInTheDocument());
  expect(axios.delete).toHaveBeenCalledWith('/todos/2');
});

test('mostra aviso quando a API está indisponível', async () => {
  axios.get.mockRejectedValue(new Error('Network Error'));

  render(<App />);

  expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível falar com o servidor');
});

//
//  ContentView.swift
//  WebSocket
//
//  Created by Roman Romanov on 11.06.2026.
//

import SwiftUI

// MARK: - Модель сообщения

/// Одно сообщение в чате.
///
/// `Identifiable` с уникальным `UUID` нужен для `ForEach`: SwiftUI
/// однозначно сопоставляет элементы списка с view при вставке и удалении.
/// Использование `id: \.self` на строках приводит к «разрывам» в списке,
/// если тексты совпадают или меняются асинхронно.
struct ChatMessage: Identifiable {
	/// Уникальный идентификатор, генерируется при создании сообщения.
	let id = UUID()
	/// Текст для отображения в пузыре (уже с префиксом «Отправлено:» / «Получено:»).
	let text: String
}

// MARK: - WebSocket-менеджер

/// Управляет жизненным циклом WebSocket-соединения и списком сообщений.
///
/// `@Observable` — Swift Observation: изменения `messages` и `isConnected`
/// автоматически обновляют SwiftUI-view, подписанные на этот объект.
/// `@MainActor` — все свойства и методы выполняются на главном потоке,
/// что безопасно для UI и для вызовов из `Task { @MainActor in ... }`.
@Observable
@MainActor
final class WebSocketManager {
	/// История сообщений чата (отправленные и полученные).
	var messages: [ChatMessage] = []
	/// `true`, пока соединение открыто и цикл приёма активен.
	var isConnected: Bool = false

	/// Активная задача WebSocket; `nil` после отключения.
	private var webSocketTask: URLSessionWebSocketTask?
	/// Публичный echo-сервер для тестирования: отправленный текст возвращается обратно.
	private let url = URL(string: "wss://echo.websocket.org")!

	/// Открывает соединение и запускает непрерывный приём входящих сообщений.
	///
	/// Повторный вызов игнорируется, пока `isConnected == true`.
	func connect() {
		guard !isConnected else { return }

		// URLSession создаёт задачу; `resume()` фактически открывает handshake.
		webSocketTask = URLSession.shared.webSocketTask(with: url)
		webSocketTask?.resume()

		isConnected = true
		// Рекурсивный цикл `receive` — единственный способ слушать поток на URLSession.
		receiveMessages()
	}

	/// Отправляет текстовое сообщение на сервер.
	///
	/// Сообщение в UI добавляется отдельно в `ContentView`, чтобы сразу
	/// показать «Отправлено: …» до ответа echo-сервера.
	func sendMessage(_ text: String) {
		guard isConnected else { return }

		let message = URLSessionWebSocketTask.Message.string(text)
		webSocketTask?.send(message) { error in
			if let error {
				print("Ошибка отправки: \(error.localizedDescription)")
			}
		}
	}

	/// Регистрирует следующий callback приёма и обрабатывает результат.
	///
	/// После каждого успешного сообщения снова вызывает себя — так поддерживается
	/// постоянное прослушивание канала. Callback приходит на фоновом потоке URLSession,
	/// поэтому обновление UI оборачивается в `Task { @MainActor in ... }`.
	private func receiveMessages() {
		webSocketTask?.receive { [weak self] result in
			Task { @MainActor [weak self] in
				guard let self else { return }

				switch result {
				case .success(let message):
					switch message {
					case .string(let text):
						messages.append(ChatMessage(text: "Получено: \(text)"))
					case .data(let data):
						// Бинарные кадры echo-сервером не используются, но обрабатываем на всякий случай.
						messages.append(ChatMessage(text: "Получено: данные: \(data.count) байт"))
					@unknown default:
						break
					}
					// Слушаем следующее сообщение, пока соединение живо.
					receiveMessages()
				case .failure(let error):
					isConnected = false
					messages.append(ChatMessage(text: "Ошибка получения: \(error.localizedDescription)"))
				}
			}
		}
	}

	/// Корректно закрывает соединение и освобождает задачу.
	func disconnect() {
		guard isConnected else { return }
		webSocketTask?.cancel(with: .normalClosure, reason: nil)
		webSocketTask = nil
		isConnected = false
	}
}

// MARK: - Главный экран

/// Экран чата: список сообщений, поле ввода и кнопка подключения в toolbar.
struct ContentView: View {
	/// Менеджер сокета; `@State` владеет объектом на протяжении жизни view.
	@State private var socketManager = WebSocketManager()
	/// Текст в поле ввода до отправки.
	@State private var inputMessage = ""

	var body: some View {
		NavigationStack {
			// Прокручиваемая область с историей сообщений.
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 8) {
					ForEach(socketManager.messages) { message in
						Text(message.text)
							.padding()
							.background(Color.blue.opacity(0.1))
							.clipShape(RoundedRectangle(cornerRadius: 12))
					}
				}
				.padding()
			}
			.background(Color.gray.opacity(0.1))
			.clipShape(RoundedRectangle(cornerRadius: 12))
			.padding()

			// Панель ввода: текстовое поле и кнопка отправки.
			HStack {
				TextField("Введите сообщение", text: $inputMessage)

				Button {
					guard !inputMessage.isEmpty else { return }
					socketManager.sendMessage(inputMessage)
					// Оптимистичное отображение: сразу показываем отправленный текст в списке.
					socketManager.messages.append(ChatMessage(text: "Отправлено: \(inputMessage)"))
					inputMessage = ""
				} label: {
					Image(systemName: "paperplane.fill")
						.font(.headline)
						.padding(10)
						.foregroundStyle(.white)
						.background(
							Circle()
								// Серая кнопка, если поле пустое или нет соединения.
								.fill(inputMessage.isEmpty || !socketManager.isConnected ? Color.gray : Color.blue)
						)
						.shadow(radius: 4)
				}
				.disabled(inputMessage.isEmpty || !socketManager.isConnected)
			}
			.padding()
			// Модификаторы навигации должны быть на контенте внутри NavigationStack,
			// иначе заголовок и toolbar не появятся в симуляторе.
			.navigationTitle("Websocket chat")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						socketManager.isConnected ? socketManager.disconnect() : socketManager.connect()
					} label: {
						Text(socketManager.isConnected ? "Отключить" : "Подключить")
							.foregroundStyle(socketManager.isConnected ? .red : .blue)
					}
				}
			}
		}
		.onAppear {
			// Автоподключение при открытии экрана.
			socketManager.connect()
		}
		.onDisappear {
			// Закрываем сокет, когда экран уходит с иерархии (например, при dismiss).
			socketManager.disconnect()
		}
	}
}

#if DEBUG
#Preview {
	ContentView()
}
#endif

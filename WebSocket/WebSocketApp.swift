//
//  WebSocketApp.swift
//  WebSocket
//
//  Created by Roman Romanov on 11.06.2026.
//

import SwiftUI

/// Точка входа приложения.
///
/// `@main` помечает структуру как entry point: система создаёт один экземпляр `App`
/// и вызывает `body` для конфигурации сцен (окон).
@main
struct WebSocketApp: App {
	var body: some Scene {
		// `WindowGroup` — стандартная сцена для iOS/macOS: одно или несколько окон
		// с одинаковым корневым view. На iPhone обычно одно окно на весь экран.
		WindowGroup {
			ContentView()
		}
	}
}

//
//  HighlightState.swift
//  SUIRA
//
//  Created by Павел Калинин on 10.05.2026.
//
import SwiftUI

private final class HighlightState {
    var count: Int = 0
    var color: Color = .green
}

struct SuiraAutoHighlightModifier: ViewModifier {
    let label: String
    let isEnabled: Bool
    
    @State private var state = HighlightState()
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        if isEnabled {
            DispatchQueue.main.async { scheduleFlash() }
        }
        
        return content
            .overlay {
                // @ViewBuilder внутри overlay гарантирует единый возвращаемый тип
                if isEnabled {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(state.color.opacity(opacity), lineWidth: 2.5)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
    }
    
    private func scheduleFlash() {
        // Асинхронный апдейт предотвращает "Modifying state during view update"
        DispatchQueue.main.async {
            state.count += 1
            state.color = state.count >= 15 ? .red : (state.count >= 5 ? .orange : .green)
            opacity = 0.8
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 0.0
            }
        }
    }
}

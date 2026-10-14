import SwiftUI

/// A three-step introduction shown the first time the app opens.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let steps = WelcomeStep.all

    var body: some View {
        let current = steps[step]
        VStack(spacing: 0) {
            VStack(spacing: Metrics.exchangeSpacing) {
                SymbolBadge(systemImage: current.symbol)
                    .frame(height: 96)
                VStack(spacing: Metrics.statusSpacing * 2) {
                    Text(current.title)
                        .font(.title2.bold())
                    Text(current.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }
            .id(step)
            .transition(.opacity)
            .frame(maxHeight: .infinity)

            PageDots(count: steps.count, current: step)
                .padding(.bottom, Metrics.exchangeSpacing)

            HStack {
                Button("Omitir", action: finish)
                    .opacity(step < steps.count - 1 ? 1 : 0)
                Spacer()
                if step > 0 {
                    Button("Atrás", action: back)
                }
                Button(step < steps.count - 1 ? "Siguiente" : "Empezar", action: next)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(Metrics.contentInset * 1.5)
        .frame(width: 520, height: 420)
        .animation(.smooth(duration: 0.25), value: step)
        #if DEBUG
        .onDebugAction("#next") { _ in next() }
        // Closes without marking the guide as seen, so test runs don't affect real use.
        .onDebugAction("#close") { _ in dismiss() }
        #endif
    }

    private func next() {
        if step < steps.count - 1 { step += 1 } else { finish() }
    }

    private func back() {
        if step > 0 { step -= 1 }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: AppSettings.hasSeenWelcomeKey)
        dismiss()
    }
}

struct WelcomeStep {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    static let all: [WelcomeStep] = [
        WelcomeStep(
            symbol: "apple.terminal",
            title: "Una terminal que conversa contigo",
            message: "Escribe un comando como si enviaras un mensaje. La respuesta llega en una burbuja, con una explicación de lo que hizo el comando."
        ),
        WelcomeStep(
            symbol: "apple.intelligence",
            title: "Pídelo con tus palabras",
            message: "¿No sabes el comando? Escribe lo que quieres, como “comprime este audio”, y Apple Intelligence te propone cómo hacerlo, aquí en tu Mac."
        ),
        WelcomeStep(
            symbol: "folder",
            title: "Siempre sabes dónde estás",
            message: "Arriba ves la carpeta en la que trabajas. Cámbiala con el botón de carpeta, arrastrando una carpeta al chat o haciendo clic en una carpeta de la lista."
        ),
        WelcomeStep(
            symbol: "lightbulb",
            title: "Ayuda en cada paso",
            message: "Tab completa lo que escribes. Si algo falla, te explicamos por qué y te sugerimos qué probar. Antes de un comando riesgoso, te pedimos confirmación."
        ),
    ]
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Metrics.composerSpacing) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Paso \(current + 1) de \(count)")
    }
}

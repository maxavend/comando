import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.notifyAfterKey) private var notifyAfter = AppSettings.defaultNotifyAfter
    @AppStorage(AppSettings.interactiveCommandsKey) private var interactiveCommands = AppSettings.defaultInteractiveCommands
    @AppStorage(AppSettings.confirmRiskyCommandsKey) private var confirmRiskyCommands = true
    @AppStorage(AppSettings.assistantEnabledKey) private var assistantEnabled = true

    var body: some View {
        Form {
            Section("Texto") {
                LabeledContent("Tamaño de la letra") {
                    HStack {
                        Slider(value: $fontSize, in: 10...20, step: 1) {
                            Text("Tamaño de la letra")
                        }
                        .labelsHidden()
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                HStack {
                    Text("Vista previa")
                    Spacer()
                    CommandBubble(command: "ls -la")
                }
            }

            Section {
                Picker("Avisar cuando un comando tarde más de", selection: $notifyAfter) {
                    Text("5 segundos").tag(5.0)
                    Text("10 segundos").tag(10.0)
                    Text("30 segundos").tag(30.0)
                    Text("1 minuto").tag(60.0)
                    Text("5 minutos").tag(300.0)
                }
            } header: {
                Text("Notificaciones")
            } footer: {
                Text("Solo se avisa si NativeTerminal no está en primer plano o estás en otra sesión.")
            }

            Section {
                Toggle("Entender pedidos con tus palabras", isOn: $assistantEnabled)
                    .disabled(!AssistantEngine.isAvailable)
            } header: {
                Text("Asistente")
            } footer: {
                Text(AssistantEngine.unavailableReason
                     ?? String(localized: "Usa Apple Intelligence en este Mac para proponerte comandos, recetas y herramientas, y para responder tus preguntas. Nada se ejecuta sin que lo apruebes."))
            }

            Section {
                Toggle("Pedir confirmación antes de comandos riesgosos", isOn: $confirmRiskyCommands)
            } header: {
                Text("Seguridad")
            } footer: {
                Text("Por ejemplo, borrar carpetas completas, usar sudo o descartar cambios de Git.")
            }

            Section {
                TextField("Comandos", text: $interactiveCommands, axis: .vertical)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .font(.body)
                    .lineLimit(2...5)
            } header: {
                Text("Terminal integrada")
            } footer: {
                Text("Estos comandos se abren directamente en una terminal completa. Los programas de pantalla completa, como vim o top, se detectan solos.")
            }
        }
        .formStyle(.grouped)
        // Opens with nothing focused, so the commands field isn't selected.
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.windows
                .first { $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true }?
                .makeFirstResponder(nil)
        }
        // With scrolling off, the grouped form reports its full height and the
        // settings window fits it exactly.
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

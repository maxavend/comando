import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.notifyAfterKey) private var notifyAfter = AppSettings.defaultNotifyAfter
    @AppStorage(AppSettings.interactiveCommandsKey) private var interactiveCommands = AppSettings.defaultInteractiveCommands

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
                Text("ls -la")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.tint, in: .rect(cornerRadius: 17))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Vista previa")
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
                TextField("Comandos", text: $interactiveCommands, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(2...5)
            } header: {
                Text("Terminal integrada")
            } footer: {
                Text("Estos comandos se abren directamente en una terminal completa. Los programas de pantalla completa, como vim o top, se detectan solos.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

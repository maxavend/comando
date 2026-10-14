import Foundation
import Observation

@MainActor
protocol ShellSessionDelegate: AnyObject {
    func shellSession(_ session: ShellSession, didChangeDirectory directory: String)
    func shellSession(_ session: ShellSession, didFinish result: CommandResult)
    func shellSessionDidExit(_ session: ShellSession)
}

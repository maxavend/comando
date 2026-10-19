import Foundation
import Testing
@testable import NativeTerminal

@Suite struct AgentTests {
    private func reply(_ lines: [String], agent: AgentKind) -> (AgentReply, [AgentEvent]) {
        var parser = agent.makeParser()
        var reply = AgentReply()
        var events: [AgentEvent] = []
        for line in lines {
            for event in parser.parse(line) {
                events.append(event)
                reply.apply(event, agent: agent)
            }
        }
        return (reply, events)
    }

    /// Recorded from agy 1.4: it lists the folder, then can't create a file
    /// because headless mode can't ask for permission.
    @Test func agyStreamBecomesTextToolsAndDenials() {
        let lines = [
            #"{"event":"init","conversation_id":"c1","init":{"cwd":"/tmp/vacia","permission_mode":"request-review"}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":0,"state":"DONE","step_type":"user_input"}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"ls -la"}}}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":2,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"ls -la"},"output":"total 8\r\n-rw-r--r--  1 demo  wheel  5 notas.txt\r\n"}}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":3,"state":"ACTIVE","step_type":"agent_response","text_delta":"En esta carpeta "}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":3,"state":"DONE","step_type":"agent_response","text_delta":"está **notas.txt**.\n"}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":6,"state":"ACTIVE","step_type":"tool","tool_name":"write_to_file","tool_info":{"name":"write_to_file","parameters":{"TargetFile":"/tmp/vacia/saludo.txt"}}}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c1","step_index":6,"state":"ERROR","step_type":"tool","tool_name":"write_to_file","tool_info":{"name":"write_to_file","parameters":{"TargetFile":"/tmp/vacia/saludo.txt"},"error":{"type":"TOOL_ERROR","message":"user denied permission"}}}}"#,
            #"{"event":"result","result":{"conversation_id":"c1","status":"SUCCESS","response":"","denied_actions":[{"action":"write_file","display_name":"WriteToFile"}]}}"#,
        ]
        let (reply, events) = reply(lines, agent: .agy)
        #expect(events.first == .conversation("c1"))
        #expect(reply.isFinished)
        #expect(reply.error == nil)
        #expect(reply.denied == ["write_file"])
        #expect(reply.steps.map(\.kind) == [.tool, .text, .tool])
        #expect(reply.steps[0].text == "Ejecutó un comando")
        #expect(reply.steps[0].detail == "ls -la")
        #expect(reply.steps[0].output?.contains("\r") == false)
        #expect(reply.steps[1].text == "En esta carpeta está **notas.txt**.")
        #expect(reply.steps[2].text == "Creó saludo.txt")
        #expect(reply.steps[2].state == .failed)
        #expect(DeniedAction.describe("write_file") == "crear o editar archivos")
    }

    @Test func agyErrorsEndTheTurn() {
        let (reply, _) = reply([#"{"event":"result","result":{"status":"ERROR","error":"quota exceeded"}}"#], agent: .agy)
        #expect(reply.isFinished)
        #expect(reply.error == "quota exceeded")
    }

    /// Claude Code with partial messages: text streams, then the whole
    /// message repeats it, and only the stream must count.
    @Test func claudeStreamDoesNotRepeatText() {
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"s1"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Voy a "}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"mirar."}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Voy a mirar."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"notas.txt","is_error":false}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Write","input":{"file_path":"/tmp/a/saludo.txt","content":"hola"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"Listo","session_id":"s1","permission_denials":[{"tool_name":"Write"}]}"#,
        ]
        let (reply, events) = reply(lines, agent: .claude)
        #expect(events.first == .conversation("s1"))
        #expect(reply.text == "Voy a mirar.")
        #expect(reply.steps.map(\.kind) == [.text, .tool, .tool])
        #expect(reply.steps[1].output == "notas.txt")
        #expect(reply.steps[2].text == "Creó saludo.txt")
        #expect(reply.denied == ["Write"])
    }

    /// Without partial messages (Qwen), text comes in whole messages.
    @Test func claudeFormatWithoutStreaming() {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hola."}]}}"#,
            #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"No hay sesión"}"#,
        ]
        let (reply, _) = reply(lines, agent: .qwen)
        #expect(reply.text == "Hola.")
        #expect(reply.error == "No hay sesión")
    }

    @Test func codexItemsAndReadableErrors() {
        let lines = [
            #"{"type":"thread.started","thread_id":"th1"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"bash -lc ls","status":"in_progress"}}"#,
            #"{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"bash -lc ls","aggregated_output":"notas.txt\n","exit_code":0,"status":"completed"}}"#,
            #"{"type":"item.completed","item":{"id":"i2","type":"agent_message","text":"Hay un archivo."}}"#,
            #"{"type":"turn.completed","usage":{}}"#,
        ]
        let (reply, events) = reply(lines, agent: .codex)
        #expect(events.first == .conversation("th1"))
        #expect(reply.steps.map(\.kind) == [.tool, .text])
        #expect(reply.steps[0].detail == "bash -lc ls")
        #expect(reply.steps[0].state == .done)
        #expect(reply.text == "Hay un archivo.")

        let failed = #"{"type":"turn.failed","error":{"message":"{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The 'gpt-6.1-sol' model is not supported.\"}}"}}"#
        let (error, _) = self.reply([failed], agent: .codex)
        #expect(error.error == "The 'gpt-6.1-sol' model is not supported.")
    }

    @Test func onlyBareAgentCommandsOpenAsChat() {
        #expect(AgentKind(command: "agy") == .agy)
        #expect(AgentKind(command: "  claude ") == .claude)
        #expect(AgentKind(command: "codex") == .codex)
        #expect(AgentKind(command: "agy models") == nil)
        #expect(AgentKind(command: "claude --resume abc") == nil)
        #expect(AgentKind(command: "gemini") == nil)
        #expect(AgentKind(command: "ls") == nil)
        #expect(AgentKind(command: "./claude") == nil)
        #expect(AgentKind(command: "/opt/homebrew/bin/codex") == nil)
    }

    @Test func eachAgentStartsHeadless() {
        #expect(AgentKind.agy.arguments(conversation: "c1", permission: .edits, message: nil)
                == ["--input-format=stream-json", "--output-format=stream-json", "--print=", "--conversation", "c1", "--mode", "accept-edits"])
        #expect(AgentKind.claude.arguments(conversation: nil, permission: .ask, message: nil).contains("--include-partial-messages"))
        #expect(AgentKind.codex.arguments(conversation: "th1", permission: .ask, message: "hola")
                == ["exec", "resume", "th1", "--json", "--skip-git-repo-check", "hola"])
        let line = AgentKind.agy.inputLine("hola")
        #expect(line.hasSuffix("\n"))
        let decoded = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        #expect(decoded?["event"] as? String == "user")
        #expect((decoded?["message"] as? [String: Any])?["content"] as? String == "hola")
        #expect(AgentKind.claude.terminalCommand(resuming: "s1") == "claude --resume s1")
    }

    @MainActor @Test func agentMarkdownShowsListsAndCode() {
        let text = String(AgentTextFormat.markdown("Archivos:\n- notas.txt\n```text\nhola\n```").characters)
        #expect(text == "Archivos:\n• notas.txt\nhola")
    }
}

import Foundation

/// Sets up a `ZDOTDIR` that loads the user's own zsh startup files and then
/// installs hooks that report command boundaries to the app.
///
/// The hooks emit standard semantic-prompt sequences (OSC 133) and the current
/// directory (OSC 7), plus a private OSC with `$PATH` for autocompletion:
///
///     OSC 133;C        command output starts      (preexec)
///     OSC 133;D;<code> command finished           (precmd)
///     OSC 7;file://... current directory          (precmd)
///     OSC 133;A        shell is ready for input   (precmd)
///     OSC 6973;path;.. $PATH, only when it changes (precmd)
nonisolated enum ShellIntegration {
    static let pathOSC = "6973;path;"

    static var directory: URL {
        URL.applicationSupportDirectory
            .appending(path: "NativeTerminal", directoryHint: .isDirectory)
            .appending(path: "zsh", directoryHint: .isDirectory)
    }

    /// Writes the integration files. Safe to call on every launch.
    static func install() throws {
        let directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        try BuiltInTools.install()
    }

    /// Environment for a new shell, based on the app's own environment.
    static func environment(userZDOTDIR: String? = ProcessInfo.processInfo.environment["ZDOTDIR"]) -> [String] {
        var environment = ProcessInfo.processInfo.environment
        // Variables that only make sense for the app process itself.
        for key in ["__CFBundleIdentifier", "XPC_SERVICE_NAME", "XPC_FLAGS", "OS_ACTIVITY_DT_MODE", "TERM_SESSION_ID"] {
            environment.removeValue(forKey: key)
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Comando"
        environment["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        environment["CLICOLOR"] = "1"
        // Pagers make no sense in a chat: the bubble already scrolls.
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        environment["MANPAGER"] = "cat"
        if environment["LANG"] == nil {
            environment["LANG"] = defaultLanguage
        }
        environment["NATIVETERM_USER_ZDOTDIR"] = userZDOTDIR ?? NSHomeDirectory()
        environment["NATIVETERM_INTEGRATION_DIR"] = directory.path(percentEncoded: false)
        environment["ZDOTDIR"] = directory.path(percentEncoded: false)
        environment["NATIVETERM_TOOLS_DIR"] = BuiltInTools.directory.path(percentEncoded: false).trimmingSuffix("/")
        return environment.map { "\($0.key)=\($0.value)" }
    }

    private static var defaultLanguage: String {
        let locale = Locale.current
        return language(for: locale.language.languageCode?.identifier, region: locale.region?.identifier)
    }

    /// A `LANG` the system actually has. Many regions have no locale of their
    /// own (there is no es_CL.UTF-8, and `cal` or `git` then complain), so it
    /// falls back to the language's main region, then any region, then English.
    static func language(for language: String?, region: String?,
                         available: Set<String> = installedLocales) -> String {
        guard let language else { return "en_US.UTF-8" }
        let candidates = [region.map { "\(language)_\($0).UTF-8" }, "\(language)_\(language.uppercased()).UTF-8"]
        if let match = candidates.compactMap({ $0 }).first(where: available.contains) {
            return match
        }
        return available.filter { $0.hasPrefix("\(language)_") && $0.hasSuffix(".UTF-8") }.sorted().first
            ?? "en_US.UTF-8"
    }

    private static var installedLocales: Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: "/usr/share/locale")) ?? [])
    }

    /// Each wrapper sources the user's file with `ZDOTDIR` pointing at the
    /// user's directory, then points it back at ours so zsh keeps loading our
    /// wrappers for the next startup phase.
    private static func wrapper(for file: String) -> String {
        """
        # NativeTerminal shell integration — generated, do not edit.
        ZDOTDIR="${NATIVETERM_USER_ZDOTDIR:-$HOME}"
        if [[ -f "$ZDOTDIR/\(file)" ]]; then
          builtin source "$ZDOTDIR/\(file)"
        fi
        NATIVETERM_USER_ZDOTDIR="$ZDOTDIR"
        ZDOTDIR="$NATIVETERM_INTEGRATION_DIR"

        """
    }

    private static let hooks = #"""
    # --- NativeTerminal hooks ---------------------------------------------
    if [[ -z "$__nativeterm_installed" ]]; then
      typeset -g __nativeterm_installed=1
      typeset -g __nativeterm_last_path=""
      [[ -z "$HISTFILE" ]] && HISTFILE="$NATIVETERM_USER_ZDOTDIR/.zsh_history"

      __nativeterm_osc() { builtin printf '\e]%s\a' "$1"; }

      __nativeterm_precmd() {
        local code=$?
        __nativeterm_osc "133;D;$code"
        __nativeterm_osc "7;file://${HOST}${PWD}"
        if [[ "$PATH" != "$__nativeterm_last_path" ]]; then
          __nativeterm_last_path="$PATH"
          __nativeterm_osc "6973;path;$PATH"
        fi
        # The app draws its own UI, so the shell prompt stays empty.
        PROMPT=""
        RPROMPT=""
        PS2=""
        __nativeterm_osc "133;A"
      }

      __nativeterm_preexec() {
        __nativeterm_osc "133;C"
      }

      autoload -Uz add-zsh-hook
      add-zsh-hook preexec __nativeterm_preexec
      # Bracketed paste is how the app submits commands, so keep it enabled.
      zle_bracketed_paste=($'\e[?2004h' $'\e[?2004l')
      unsetopt PROMPT_SP 2>/dev/null
    fi
    # Comando's own commands (comprimir-pdf), after whatever the user's files set.
    if [[ -n "$NATIVETERM_TOOLS_DIR" ]]; then
      path=(${path:#$NATIVETERM_TOOLS_DIR} "$NATIVETERM_TOOLS_DIR")
    fi
    # Run last, after any prompt theme, so the prompt stays empty.
    precmd_functions=(${precmd_functions:#__nativeterm_precmd} __nativeterm_precmd)

    """#

    private static var files: [(String, String)] {
        [
            (".zshenv", wrapper(for: ".zshenv")),
            (".zprofile", wrapper(for: ".zprofile")),
            (".zshrc", wrapper(for: ".zshrc") + hooks),
            (".zlogin", wrapper(for: ".zlogin") + hooks + """
            # Child shells should use the user's own configuration directly.
            ZDOTDIR="$NATIVETERM_USER_ZDOTDIR"
            unset NATIVETERM_INTEGRATION_DIR

            """),
        ]
    }
}

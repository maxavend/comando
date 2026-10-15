# SwiftTerm (vendored)

Copy of [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.11.2
(commit b1262db), MIT license (see LICENSE).

The only change is in `Sources/SwiftTerm/Pty.swift`: `fork(andExec:)` used to
build the C argument arrays in the child process, after `forkpty`. In a
multithreaded app that can deadlock or crash (“crashed on child side of fork
pre-exec”), because allocating memory or instantiating Swift metadata takes
locks another thread may have held at the moment of the fork. Now everything
is prepared before forking and the child only calls `chdir`, `execve` and
`_exit`.

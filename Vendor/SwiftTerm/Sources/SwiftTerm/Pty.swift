//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 3/4/20.
//

import Foundation
#if !os(iOS) && !os(tvOS) && !os(Windows)

/**
 * APIs to assist in controlling a Unix pseudo-terminal from Swift.
 *
 *This provides a wrapper for
 * the libc `forkpty`API in the form of `fork(andExec:args:env:desiredWindowSize:` method,
 * `setWinSize` and `availableBytes`
 */
public class PseudoTerminalHelpers {
    
    /* Taken from Swift's StdLib: https://github.com/apple/swift/blob/master/stdlib/private/SwiftPrivate/SwiftPrivate.swift */
    static func scan<
      S : Sequence, U
    >(_ seq: S, _ initial: U, _ combine: (U, S.Iterator.Element) -> U) -> [U] {
      var result: [U] = []
      result.reserveCapacity(seq.underestimatedCount)
      var runningResult = initial
      for element in seq {
        runningResult = combine(runningResult, element)
        result.append(runningResult)
      }
      return result
    }

    /* Taken from Swift's StdLib: https://github.com/apple/swift/blob/master/stdlib/private/SwiftPrivate/SwiftPrivate.swift */
    static func withArrayOfCStrings<R>(
      _ args: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R
    ) -> R {
      let argsCounts = Array(args.map { $0.utf8.count + 1 })
      let argsOffsets = [ 0 ] + scan(argsCounts, 0, +)
      let argsBufferSize = argsOffsets.last!

      var argsBuffer: [UInt8] = []
      argsBuffer.reserveCapacity(argsBufferSize)
      for arg in args {
        argsBuffer.append(contentsOf: arg.utf8)
        argsBuffer.append(0)
      }

      return argsBuffer.withUnsafeMutableBufferPointer {
        (argsBuffer) in
        let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(
          to: CChar.self, capacity: argsBuffer.count)
        var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
        cStrings[cStrings.count - 1] = nil
        return body(cStrings)
      }
    }

    /**
     * This method both forks and executes the provided command under a Pseudo Terminal (pty)
     * - Parameter andExec: the name of the executable to run
     * - Parameter args: arguments to be passed to the executable
     * - Parameter env: the environment variables for the child process
     * - Parameter desiredWindowSize: the window size that will be set on the pseudo terminal.
     *
     * - Returns: nil on error, or a tuple containing the process ID, and the file descriptor to the primary side of the newly created pseudo-terminal.
     */
    public static func fork (andExec: String, args: [String], env: [String], currentDirectory: String? = nil, desiredWindowSize: inout winsize) -> (pid: pid_t, masterFd: Int32)?
    {
        // Comando: everything the child needs is prepared here, before the
        // fork. After forkpty, the child of a multithreaded process may only
        // call async-signal-safe functions: allocating memory or instantiating
        // Swift metadata there can deadlock or crash on locks that another
        // thread held at the moment of the fork.
        var master: Int32 = 0
        var size = desiredWindowSize
        let directory = currentDirectory ?? ""
        let changesDirectory = currentDirectory != nil
        let pid: pid_t = withArrayOfCStrings(args) { pargs in
            withArrayOfCStrings(env) { penv in
                pargs.withUnsafeBufferPointer { argv in
                    penv.withUnsafeBufferPointer { envp in
                        andExec.withCString { executable in
                            directory.withCString { cwd in
                                let pid = forkpty(&master, nil, nil, &size)
                                if pid == 0 {
                                    if changesDirectory { _ = chdir(cwd) }
                                    _ = execve(executable, argv.baseAddress, envp.baseAddress)
                                    _exit(127)
                                }
                                return pid
                            }
                        }
                    }
                }
            }
        }
        desiredWindowSize = size
        if pid < 0 {
            return nil
        }
        return (pid, master)
    }

    /**
     * Sets the window size of the underlying pseudo terminal.
     * - Parameter masterPtyDescriptor: a pseudo-terminal master file descriptor, as returned by fork(andExec:)
     * - Returns: the value from calling the ioctl
     */
    public static func setWinSize (masterPtyDescriptor: Int32, windowSize: inout winsize) -> Int32
    {
#if os(macOS)
        return ioctl(masterPtyDescriptor, TIOCSWINSZ, &windowSize)
#else
	return ioctl(masterPtyDescriptor, UInt(TIOCSWINSZ), &windowSize)
#endif
    }
    
    /**
     * Returns the number of available bytes to be read from the file descriptor
     */
    public static func availableBytes (fd: Int32) -> (status: Int32, size: Int32)
    {
        var size: Int32 = 0
        let status = ioctl (fd, 0x4004667f /* FIONREAD */, &size)
        return (status, size)
    }
}
#endif

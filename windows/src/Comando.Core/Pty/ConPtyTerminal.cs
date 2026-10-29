using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Comando.Core.Pty;

/// <summary>
/// A process attached to a Windows pseudoconsole (ConPTY), the equivalent
/// of a PTY on macOS: programs believe they run in a real console, so they
/// keep their colors, progress bars and full-screen modes.
/// </summary>
[SupportedOSPlatform("windows10.0.17763")]
public sealed class ConPtyTerminal : IPseudoTerminal
{
    private IntPtr _pseudoConsole;
    private SafeFileHandle? _inputWrite;
    private SafeFileHandle? _outputRead;
    private FileStream? _input;
    private IntPtr _process;
    private IntPtr _thread;
    private RegisteredWaitHandle? _exitWait;
    private int _running;
    private readonly object _lock = new();

    public event Action<byte[]>? DataReceived;
    public event Action<int?>? Exited;

    public bool IsRunning => Volatile.Read(ref _running) == 1;

    public void Start(PtyStartInfo info)
    {
        if (!Native.CreatePipe(out var inputRead, out var inputWrite, IntPtr.Zero, 0)
            || !Native.CreatePipe(out var outputRead, out var outputWrite, IntPtr.Zero, 0))
        {
            throw new InvalidOperationException("No se pudo crear la consola.", Marshal.GetExceptionForHR(Marshal.GetHRForLastWin32Error()));
        }

        var result = Native.CreatePseudoConsole(Size(info.Columns, info.Rows), inputRead, outputWrite, 0, out _pseudoConsole);
        // The pseudoconsole keeps its own copies of its ends of the pipes.
        inputRead.Dispose();
        outputWrite.Dispose();
        if (result != 0)
        {
            inputWrite.Dispose();
            outputRead.Dispose();
            throw new InvalidOperationException("No se pudo crear la consola.", Marshal.GetExceptionForHR(result));
        }
        _inputWrite = inputWrite;
        _outputRead = outputRead;
        _input = new FileStream(inputWrite, FileAccess.Write, bufferSize: 0);

        StartProcess(info);
        Volatile.Write(ref _running, 1);

        var reader = new Thread(ReadLoop) { IsBackground = true, Name = "Comando ConPTY" };
        reader.Start();
    }

    public void Write(ReadOnlySpan<byte> bytes)
    {
        if (!IsRunning || _input is null) return;
        lock (_lock)
        {
            try
            {
                _input.Write(bytes);
                _input.Flush();
            }
            catch (IOException)
            {
                // The shell is gone; Exited follows.
            }
        }
    }

    public void Resize(int columns, int rows)
    {
        if (_pseudoConsole != IntPtr.Zero)
        {
            _ = Native.ResizePseudoConsole(_pseudoConsole, Size(columns, rows));
        }
    }

    public void Dispose()
    {
        _exitWait?.Unregister(null);
        _exitWait = null;
        if (IsRunning && _process != IntPtr.Zero)
        {
            Native.TerminateProcess(_process, 1);
        }
        Volatile.Write(ref _running, 0);
        ClosePseudoConsole();
        _input?.Dispose();
        _input = null;
        CloseHandle(ref _thread);
        CloseHandle(ref _process);
    }

    private void StartProcess(PtyStartInfo info)
    {
        var attributeListSize = IntPtr.Zero;
        Native.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeListSize);
        var attributeList = Marshal.AllocHGlobal(attributeListSize);
        var environment = IntPtr.Zero;
        try
        {
            if (!Native.InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeListSize)
                || !Native.UpdateProcThreadAttribute(attributeList, 0, (IntPtr)Native.ProcThreadAttributePseudoConsole,
                    _pseudoConsole, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
            {
                throw new InvalidOperationException("No se pudo conectar la consola.", Marshal.GetExceptionForHR(Marshal.GetHRForLastWin32Error()));
            }

            var startupInfo = new Native.StartupInfoEx
            {
                StartupInfo = new Native.StartupInfo
                {
                    cb = Marshal.SizeOf<Native.StartupInfoEx>(),
                    // Without this the child would use the app's own (empty)
                    // standard handles instead of the pseudoconsole.
                    dwFlags = Native.StartfUseStdHandles,
                },
                lpAttributeList = attributeList,
            };

            environment = Marshal.StringToHGlobalUni(WindowsCommandLine.EnvironmentBlock(info.Environment));
            var commandLine = new StringBuilder(WindowsCommandLine.Build(info.Executable, info.Arguments));
            var workingDirectory = System.IO.Directory.Exists(info.WorkingDirectory) ? info.WorkingDirectory : null;

            if (!Native.CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, false,
                    Native.ExtendedStartupInfoPresent | Native.CreateUnicodeEnvironment,
                    environment, workingDirectory, ref startupInfo, out var processInfo))
            {
                throw new InvalidOperationException($"No se pudo abrir {Path.GetFileName(info.Executable)}.",
                    Marshal.GetExceptionForHR(Marshal.GetHRForLastWin32Error()));
            }
            _process = processInfo.hProcess;
            _thread = processInfo.hThread;

            var exited = new ManualResetEvent(false) { SafeWaitHandle = new SafeWaitHandle(_process, ownsHandle: false) };
            _exitWait = ThreadPool.RegisterWaitForSingleObject(exited, (_, _) => OnProcessExited(), null, Timeout.Infinite, executeOnlyOnce: true);
        }
        finally
        {
            Native.DeleteProcThreadAttributeList(attributeList);
            Marshal.FreeHGlobal(attributeList);
            if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
        }
    }

    private void ReadLoop()
    {
        if (_outputRead is null) return;
        using var output = new FileStream(_outputRead, FileAccess.Read, bufferSize: 0);
        var buffer = new byte[16 * 1024];
        while (true)
        {
            int count;
            try
            {
                count = output.Read(buffer, 0, buffer.Length);
            }
            catch (IOException)
            {
                break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            if (count <= 0) break;
            DataReceived?.Invoke(buffer[..count]);
        }
    }

    private void OnProcessExited()
    {
        int? code = Native.GetExitCodeProcess(_process, out var exitCode) ? (int)exitCode : null;
        Volatile.Write(ref _running, 0);
        // Closing the pseudoconsole ends the read loop once the last output is
        // drained. It can block on older Windows, so it stays off the UI thread.
        ClosePseudoConsole();
        Exited?.Invoke(code);
    }

    private void ClosePseudoConsole()
    {
        var console = Interlocked.Exchange(ref _pseudoConsole, IntPtr.Zero);
        if (console != IntPtr.Zero) Native.ClosePseudoConsole(console);
    }

    private static void CloseHandle(ref IntPtr handle)
    {
        var value = Interlocked.Exchange(ref handle, IntPtr.Zero);
        if (value != IntPtr.Zero) Native.CloseHandle(value);
    }

    private static Native.Coord Size(int columns, int rows) =>
        new() { X = (short)Math.Clamp(columns, 1, short.MaxValue), Y = (short)Math.Clamp(rows, 1, short.MaxValue) };

    private static class Native
    {
        public const int ProcThreadAttributePseudoConsole = 0x00020016;
        public const uint ExtendedStartupInfoPresent = 0x00080000;
        public const uint CreateUnicodeEnvironment = 0x00000400;
        public const int StartfUseStdHandles = 0x00000100;

        [StructLayout(LayoutKind.Sequential)]
        public struct Coord
        {
            public short X;
            public short Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct StartupInfo
        {
            public int cb;
            public IntPtr lpReserved;
            public IntPtr lpDesktop;
            public IntPtr lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct StartupInfoEx
        {
            public StartupInfo StartupInfo;
            public IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ProcessInformation
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern int CreatePseudoConsole(Coord size, SafeFileHandle hInput, SafeFileHandle hOutput, uint dwFlags, out IntPtr phPC);

        [DllImport("kernel32.dll")]
        public static extern int ResizePseudoConsole(IntPtr hPC, Coord size);

        [DllImport("kernel32.dll")]
        public static extern void ClosePseudoConsole(IntPtr hPC);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CreatePipe(out SafeFileHandle hReadPipe, out SafeFileHandle hWritePipe, IntPtr lpPipeAttributes, int nSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, uint dwFlags, IntPtr attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CreateProcessW(string? lpApplicationName, StringBuilder lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string? lpCurrentDirectory,
            ref StartupInfoEx lpStartupInfo, out ProcessInformation lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);
    }
}

/// <summary>How Windows expects a process's command line and environment.</summary>
internal static class WindowsCommandLine
{
    /// <summary>"name=value\0name=value\0\0", sorted the way Windows expects.</summary>
    internal static string EnvironmentBlock(IReadOnlyDictionary<string, string> environment)
    {
        var builder = new StringBuilder();
        foreach (var (key, value) in environment.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
        {
            builder.Append(key).Append('=').Append(value).Append('\0');
        }
        builder.Append('\0');
        return builder.ToString();
    }

    /// <summary>Quotes each argument the way <c>CommandLineToArgvW</c> reads it back.</summary>
    internal static string Build(string executable, IEnumerable<string> arguments) =>
        string.Join(' ', new[] { executable }.Concat(arguments).Select(Quote));

    internal static string Quote(string argument)
    {
        if (argument.Length > 0 && argument.IndexOfAny([' ', '\t', '"']) < 0) return argument;
        var builder = new StringBuilder("\"");
        var backslashes = 0;
        foreach (var character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
            }
            else
            {
                builder.Append('\\', backslashes);
            }
            backslashes = 0;
            builder.Append(character);
        }
        builder.Append('\\', backslashes * 2);
        builder.Append('"');
        return builder.ToString();
    }
}

using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    static async Task Main()
    {
        Console.WriteLine("Enter PowerShell commands (type 'exit' to quit):");

        // Set up PowerShell process
        using (var PowerShellProcess = new Process())
        {
            PowerShellProcess.StartInfo.FileName = "powershell";
            PowerShellProcess.StartInfo.RedirectStandardInput = true;
            PowerShellProcess.StartInfo.RedirectStandardOutput = true;
            PowerShellProcess.StartInfo.RedirectStandardError = true;
            PowerShellProcess.StartInfo.UseShellExecute = false;
            PowerShellProcess.StartInfo.CreateNoWindow = true;

            PowerShellProcess.Start();

            // Create cancellation token source for stopping background threads
            var cancellationTokenSource = new CancellationTokenSource();

            // Asynchronously read output and error
            Task<string> readOutputTask = ReadStreamAsync(PowerShellProcess.StandardOutput, cancellationTokenSource.Token);
            Task<string> readErrorTask = ReadStreamAsync(PowerShellProcess.StandardError, cancellationTokenSource.Token);

            // Buffer to accumulate characters until newline
            var outputBuffer = new StringBuilder();

            // Background thread for reading output
            _ = Task.Run(() => ReadOutputBackground(PowerShellProcess.StandardOutput, outputBuffer, cancellationTokenSource.Token));

            while (true)
            {
                // Read a PowerShell command from the console
                Console.Write("PS> ");
                string input = Console.ReadLine();

                // Check if the user wants to exit
                if (string.Equals(input, "exit", StringComparison.OrdinalIgnoreCase))
                    break;

                // Send the command to the PowerShell process
                PowerShellProcess.StandardInput.WriteLine(input);

                // Wait for the previous output to complete
                string output = await readOutputTask;
                Console.WriteLine(output);

                // Check for errors
                string error = await readErrorTask;
                if (!string.IsNullOrEmpty(error))
                {
                    Console.WriteLine($"Error: {error}");
                }
            }

            // Stop background threads
            cancellationTokenSource.Cancel();

            // Close the PowerShell process
            PowerShellProcess.Close();
        }
    }

    static async Task<string> ReadStreamAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        var buffer = new char[4096];
        var outputBuilder = new StringBuilder();

        // Asynchronously read output or error
        while (!cancellationToken.IsCancellationRequested)
        {
            int bytesRead = await reader.ReadAsync(buffer, 0, buffer.Length);
            if (bytesRead == 0)
                break;

            outputBuilder.Append(buffer, 0, bytesRead);
        }

        return outputBuilder.ToString();
    }

    static void ReadOutputBackground(StreamReader reader, StringBuilder outputBuffer, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            char nextChar = (char)reader.Read();
            if (nextChar == '\n')
            {
                Console.WriteLine(outputBuffer.ToString());
                outputBuffer.Clear();
            }
            else
            {
                outputBuffer.Append(nextChar);
            }

            // Check if the character indicates the end of the output
            if (nextChar == '\0' || nextChar == '\r')
                break;
        }
    }
}

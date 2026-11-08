import Darwin
import Foundation
import VeilUsage

@main
enum VeilCLI {
  static func main() async {
    let command: Command
    do {
      command = try Command(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch {
      try? FileHandle.standardError.write(
        contentsOf: Data("veil: \(error.message)\nTry 'veil --help'.\n".utf8))
      exit(2)
    }

    let output: String
    let status: Int32
    if command.help {
      output = Command.helpText
      status = 0
    } else {
      let report = await command.run(source: LiveUsageSource())
      do {
        output = try command.json ? report.json() : report.text()
        status = report.exitCode
      } catch {
        try? FileHandle.standardError.write(
          contentsOf: Data("veil: could not encode output.\n".utf8))
        exit(1)
      }
    }

    signal(SIGPIPE, SIG_IGN)
    do {
      try FileHandle.standardOutput.write(contentsOf: Data((output + "\n").utf8))
    } catch {
      exit(1)
    }
    exit(status)
  }
}

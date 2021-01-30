//
//  TributeCLI.swift
//  Tribute
//
//  Created by Nick Lockwood on 30/11/2020.
//

import Tribute

private enum Command: String, CaseIterable {
    case export
    case list
    case check
    case help
    case version

    var help: String {
        switch self {
        case .help: return "Display general or command-specific help"
        case .list: return "Display list of libraries and licenses found in project"
        case .export: return "Export license information for project"
        case .check: return "Check that exported license info is correct"
        case .version: return "Display the current version of Tribute"
        }
    }
}

private extension String {
    func addingTrailingSpace(toWidth width: Int) -> String {
        self + String(repeating: " ", count: width - count)
    }
}

extension Tribute {
    // Parse a flat array of command-line arguments into a dictionary of flags and values
    static func preprocessArguments(_ args: [String]) throws -> [Argument: [String]] {
        let arguments = Argument.allCases
        let argumentNames = arguments.map { $0.rawValue }
        var namedArgs: [Argument: [String]] = [:]
        var name: Argument?
        for arg in args {
            if arg.hasPrefix("--") {
                // Long argument names
                let key = String(arg.unicodeScalars.dropFirst(2))
                guard let argument = Argument(rawValue: key) else {
                    guard let match = bestMatches(for: key, in: argumentNames).first else {
                        throw TributeError("Unknown option --\(key).")
                    }
                    throw TributeError("Unknown option --\(key). Did you mean --\(match)?")
                }
                name = argument
                namedArgs[argument] = namedArgs[argument] ?? []
                continue
            } else if arg.hasPrefix("-") {
                // Short argument names
                let flag = String(arg.unicodeScalars.dropFirst())
                guard let match = arguments.first(where: { $0.rawValue.hasPrefix(flag) }) else {
                    throw TributeError("Unknown flag -\(flag).")
                }
                name = match
                namedArgs[match] = namedArgs[match] ?? []
                continue
            }
            var arg = arg
            let hasTrailingComma = arg.hasSuffix(",") && arg != ","
            if hasTrailingComma {
                arg = String(arg.dropLast())
            }
            let existing = namedArgs[name ?? .anonymous] ?? []
            namedArgs[name ?? .anonymous] = existing + [arg]
        }
        return namedArgs
    }

    static func getHelp(with arg: String?) throws -> String {
        guard let arg = arg else {
            let width = Command.allCases.map { $0.rawValue.count }.max(by: <) ?? 0
            return """
            Available commands:

            \(Command.allCases.map {
                "   \($0.rawValue.addingTrailingSpace(toWidth: width))   \($0.help)"
            }.joined(separator: "\n"))

            (Type 'tribute help [command]' for more information)
            """
        }
        guard let command = Command(rawValue: arg) else {
            let commands = Command.allCases.map { $0.rawValue }
            if let closest = bestMatches(for: arg, in: commands).first {
                throw TributeError("Unrecognized command '\(arg)'. Did you mean '\(closest)'?")
            }
            throw TributeError("Unrecognized command '\(arg)'.")
        }
        let detailedHelp: String
        switch command {
        case .help:
            detailedHelp = """
               [command]  The command to display help for.
            """
        case .export:
            detailedHelp = """
               [filepath]   Path to the file that the licenses should be exported to. If omitted
                            then the licenses will be written to stdout.

               --exclude    One or more directories to be excluded from the library search.
                            Paths should be relative to the current directory, and may include
                            wildcard/glob syntax.

               --skip       One or more libraries to be skipped. Use this for libraries that do
                            not require attribution, or which are used in the build process but
                            are not actually shipped to the end-user.

               --allow      A list of libraries that should be included even if their licenses
                            are not supported/recognized.

               --template   A template string or path to a template file to use for generating
                            the licenses file. The template should contain one or more of the
                            following placeholder strings:

                            $name        The name of the library
                            $type        The license type (e.g. MIT, Apache, BSD)
                            $text        The text of the license itself
                            $start       The start of the license template (after the header)
                            $end         The end of the license template (before the footer)
                            $separator   A delimiter to be included between each license

               --format     How the output should be formatted (json, xml or text). If omitted
                            this will be inferred automatically from the template contents.
            """
        case .check:
            detailedHelp = """
               [filepath]   The path to the licenses file that will be compared against the
                            libraries found in the project (required). An error will be returned
                            if any libraries are missing from the file, or if the format doesn't
                            match the other parameters.

               --exclude    One or more directories to be excluded from the library search.
                            Paths should be relative to the current directory, and may include
                            wildcard/glob syntax.

               --skip       One or more libraries to be skipped. Use this for libraries that do
                            not require attribution, or which are used in the build process but
                            are not actually shipped to the end-user.
            """
        case .list, .version:
            return command.help
        }

        return command.help + ".\n\n" + detailedHelp + "\n"
    }

    static func listLibraries(in directory: String, with arguments: [Argument: [String]]) throws -> String {
        let libraries = try fetchLibraries(in: directory, with: arguments)
        let nameWidth = libraries.map { $0.name.count }.max() ?? 0
        return libraries.map {
            let name = $0.name + String(repeating: " ", count: nameWidth - $0.name.count)
            var type = ($0.licenseType?.rawValue ?? "Unknown")
            type += String(repeating: " ", count: 7 - type.count)
            return "\(name)  \(type)  \($0.licensePath)"
        }.joined(separator: "\n")
    }

    static func run(in directory: String, with args: [String] = CommandLine.arguments) throws -> String {
        let arg = args.count > 1 ? args[1] : Command.help.rawValue
        guard let command = Command(rawValue: arg) else {
            let commands = Command.allCases.map { $0.rawValue }
            if let closest = bestMatches(for: arg, in: commands).first {
                throw TributeError("Unrecognized command '\(arg)'. Did you mean '\(closest)'?")
            }
            throw TributeError("Unrecognized command '\(arg)'.")
        }

        let arguments = try preprocessArguments(args)

        switch command {
        case .help:
            return try getHelp(with: args.count > 2 ? args[2] : nil)
        case .list:
            return try listLibraries(in: directory, with: arguments)
        case .export:
            return try export(in: directory, with: arguments)
        case .check:
            return try check(in: directory, with: arguments)
        case .version:
            return "0.2.1"
        }
    }
}

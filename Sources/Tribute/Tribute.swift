//
//  Tribute.swift
//  Tribute
//
//  Created by Nick Lockwood on 30/11/2020.
//

import Foundation

public struct TributeError: Error, CustomStringConvertible {
    public let description: String

    public init(_ message: String) {
        self.description = message
    }
}

public enum Argument: String, CaseIterable {
    case anonymous = ""
    case allow
    case skip
    case exclude
    case template
    case format
}

public enum LicenseType: String, CaseIterable {
    case bsd = "BSD"
    case mit = "MIT"
    case isc = "ISC"
    case zlib = "Zlib"
    case apache = "Apache"

    private var matchStrings: [String] {
        switch self {
        case .bsd:
            return [
                "BSD License",
                "Redistribution and use in source and binary forms, with or without modification",
                "THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR",
            ]
        case .mit:
            return [
                "The MIT License",
                "Permission is hereby granted, free of charge, to any person",
                "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR",
            ]
        case .isc:
            return [
                "Permission to use, copy, modify, and/or distribute this software for any",
            ]
        case .zlib:
            return [
                "Altered source versions must be plainly marked as such, and must not be",
            ]
        case .apache:
            return [
                "Apache License",
            ]
        }
    }

    init?(licenseText: String) {
        let preprocessedText = Self.preprocess(licenseText)
        guard let type = Self.allCases.first(where: {
            $0.matches(preprocessedText: preprocessedText)
        }) else {
            return nil
        }
        self = type
    }

    func matches(_ licenseText: String) -> Bool {
        matches(preprocessedText: Self.preprocess(licenseText))
    }

    private func matches(preprocessedText: String) -> Bool {
        matchStrings.contains {
            preprocessedText.range(of: $0, options: .caseInsensitive) != nil
        }
    }

    private static func preprocess(_ licenseText: String) -> String {
        licenseText.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

public struct Library {
    public let name: String
    public let licensePath: String
    public let licenseType: LicenseType?
    public let licenseText: String
}

public enum Tribute {
    // Find best match for a given string in a list of options
    public static func bestMatches(for query: String, in options: [String]) -> [String] {
        let lowercaseQuery = query.lowercased()
        // Sort matches by Levenshtein edit distance
        return options
            .compactMap { option -> (String, Int)? in
                let lowercaseOption = option.lowercased()
                let distance = editDistance(lowercaseOption, lowercaseQuery)
                guard distance <= lowercaseQuery.count / 2 ||
                    !lowercaseOption.commonPrefix(with: lowercaseQuery).isEmpty
                else {
                    return nil
                }
                return (option, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// The Levenshtein edit-distance between two strings
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        var dist = [[Int]]()
        for i in 0 ... lhs.count {
            dist.append([i])
        }
        for j in 1 ... rhs.count {
            dist[0].append(j)
        }
        for i in 1 ... lhs.count {
            let lhs = lhs[lhs.index(lhs.startIndex, offsetBy: i - 1)]
            for j in 1 ... rhs.count {
                if lhs == rhs[rhs.index(rhs.startIndex, offsetBy: j - 1)] {
                    dist[i].append(dist[i - 1][j - 1])
                } else {
                    dist[i].append(min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1))
                }
            }
        }
        return dist[lhs.count][rhs.count]
    }

    public static func fetchLibraries(in directory: String, with arguments: [Argument: [String]]) throws -> [Library] {
        let globs = (arguments[.exclude] ?? []).map { expandGlob($0, in: directory) }
        let path = "."
        let directoryURL = expandPath(path, in: directory)
        return try fetchLibraries(in: directoryURL, excluding: globs)
    }

    static func fetchLibraries(in directory: URL, excluding: [Glob],
                               includingPackages: Bool = true) throws -> [Library]
    {
        let standardizedDirectory = directory.standardized
        let directoryPath = standardizedDirectory.path

        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: standardizedDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            throw TributeError("Unable to process directory at \(directoryPath).")
        }

        // Fetch libraries
        var libraries = [Library]()
        for case let licenceFile as URL in enumerator {
            if excluding.contains(where: { $0.matches(licenceFile.path) }) {
                continue
            }
            let licensePath = licenceFile.path.dropFirst(directoryPath.count)
            if includingPackages {
                if licenceFile.lastPathComponent == "Package.resolved" {
                    libraries += try fetchLibraries(forResolvedPackageAt: licenceFile)
                    continue
                }
                if licenceFile.lastPathComponent == "Package.swift",
                   !manager.fileExists(
                       atPath: licenceFile.deletingPathExtension()
                           .appendingPathExtension("resolved").path
                   )
                {
                    guard let string = try? String(contentsOf: licenceFile) else {
                        throw TributeError("Unable to read Package.swift at \(licensePath).")
                    }
                    if string.range(of: ".package(") != nil {
                        throw TributeError(
                            "Found unresolved Package.swift at \(licensePath). Run 'swift package resolve' to resolve dependencies."
                        )
                    }
                }
            }
            let name = licenceFile.deletingLastPathComponent().lastPathComponent
            if libraries.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                continue
            }
            let ext = licenceFile.pathExtension
            let fileName = licenceFile.deletingPathExtension().lastPathComponent.lowercased()
            guard ["license", "licence"].contains(fileName),
                  ["", "text", "txt", "md"].contains(ext)
            else {
                continue
            }
            var isDirectory: ObjCBool = false
            _ = manager.fileExists(atPath: licenceFile.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                continue
            }
            do {
                let licenseText = try String(contentsOf: licenceFile)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let library = Library(
                    name: name,
                    licensePath: String(licensePath),
                    licenseType: LicenseType(licenseText: licenseText),
                    licenseText: licenseText
                )
                libraries.append(library)
            } catch {
                throw TributeError("Unable to read license file at \(licensePath).")
            }
        }

        return libraries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func fetchLibraries(forResolvedPackageAt url: URL) throws -> [Library] {
        struct Pin: Decodable {
            let package: String
            let repositoryURL: URL
        }
        struct Object: Decodable {
            let pins: [Pin]
        }
        struct Resolved: Decodable {
            let object: Object
        }
        let filter: Set<String>
        do {
            let data = try Data(contentsOf: url)
            let resolved = try JSONDecoder().decode(Resolved.self, from: data)
            filter = Set(resolved.object.pins.flatMap {
                [
                    $0.package.lowercased(),
                    $0.repositoryURL.deletingPathExtension().lastPathComponent.lowercased(),
                ]
            })
        } catch {
            throw TributeError("Unable to read Swift Package file at \(url.path).")
        }
        guard let derivedDataDirectory = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Developer/Xcode/DerivedData")
        else {
            throw TributeError("Unable to locate ~/Library/Developer/Xcode/DerivedData directory.")
        }
        let libraries = try fetchLibraries(
            in: derivedDataDirectory,
            excluding: [],
            includingPackages: false
        )
        return libraries.filter { filter.contains($0.name.lowercased()) }
    }

    public static func check(in directory: String, with arguments: [Argument: [String]]) throws -> String {
        let skip = (arguments[.skip] ?? []).map { $0.lowercased() }
        let globs = (arguments[.exclude] ?? []).map { expandGlob($0, in: directory) }

        // Directory
        let path = "."
        let directoryURL = expandPath(path, in: directory)
        var libraries = try fetchLibraries(in: directoryURL, excluding: globs)
        let libraryNames = libraries.map { $0.name.lowercased() }

        if let name = skip.first(where: { !libraryNames.contains($0) }) {
            if let closest = bestMatches(for: name.lowercased(), in: libraryNames).first {
                throw TributeError("Unknown library '\(name)'. Did you mean '\(closest)'?")
            }
            throw TributeError("Unknown library '\(name)'.")
        }

        // Filtering
        libraries = libraries.filter { !skip.contains($0.name.lowercased()) }

        // File path
        let anon = arguments[.anonymous] ?? []
        guard let inputURL = (anon.count > 2 ? anon[2] : nil).map({
            expandPath($0, in: directory)
        }) else {
            throw TributeError("Missing path to licenses file.")
        }

        // Check
        guard var licensesText = try? String(contentsOf: inputURL) else {
            throw TributeError("Unable to read licenses file at \(inputURL.path).")
        }
        licensesText = licensesText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if let library = libraries.first(where: { !licensesText.contains($0.name) }) {
            throw TributeError("License for '\(library.name)' is missing from licenses file.")
        }
        return "Licenses file is up-to-date."
    }

    public static func export(in directory: String, with arguments: [Argument: [String]]) throws -> String {
        let allow = (arguments[.allow] ?? []).map { $0.lowercased() }
        let skip = (arguments[.skip] ?? []).map { $0.lowercased() }
        let globs = (arguments[.exclude] ?? []).map { expandGlob($0, in: directory) }
        let rawFormat = arguments[.format]?.first

        // File
        let anon = arguments[.anonymous] ?? []
        let outputURL = (anon.count > 2 ? anon[2] : nil).map { expandPath($0, in: directory) }

        // Template
        let template: Template
        if let pathOrTemplate = arguments[.template]?.first {
            if pathOrTemplate.contains("$name") {
                template = Template(rawValue: pathOrTemplate)
            } else {
                let templateFile = expandPath(pathOrTemplate, in: directory)
                let templateText = try String(contentsOf: templateFile)
                template = Template(rawValue: templateText)
            }
        } else {
            template = .default(
                for: rawFormat.flatMap(Format.init) ??
                    outputURL.flatMap { .infer(from: $0) } ?? .text
            )
        }

        // Format
        let format: Format
        if let rawFormat = rawFormat {
            guard let _format = Format(rawValue: rawFormat) else {
                let formats = Format.allCases.map { $0.rawValue }
                if let closest = bestMatches(for: rawFormat, in: formats).first {
                    throw TributeError("Unsupported output format '\(rawFormat)'. Did you mean '\(closest)'?")
                }
                throw TributeError("Unsupported output format '\(rawFormat)'.")
            }
            format = _format
        } else {
            format = .infer(from: template)
        }

        // Directory
        let path = "."
        let directoryURL = expandPath(path, in: directory)
        var libraries = try fetchLibraries(in: directoryURL, excluding: globs)
        let libraryNames = libraries.map { $0.name.lowercased() }

        if let name = (allow + skip).first(where: { !libraryNames.contains($0) }) {
            if let closest = bestMatches(for: name.lowercased(), in: libraryNames).first {
                throw TributeError("Unknown library '\(name)'. Did you mean '\(closest)'?")
            }
            throw TributeError("Unknown library '\(name)'.")
        }

        // Filtering
        libraries = try libraries.filter { library in
            if skip.contains(library.name.lowercased()) {
                return false
            }
            let name = library.name
            guard allow.contains(name.lowercased()) || library.licenseType != nil else {
                let escapedName = (name.contains(" ") ? "\"\(name)\"" : name).lowercased()
                throw TributeError(
                    "Unrecognized license at \(library.licensePath). "
                        + "Use '--allow \(escapedName)' or '--skip \(escapedName)' to bypass."
                )
            }
            return true
        }

        // Output
        let result = try template.render(libraries, as: format)
        if let outputURL = outputURL {
            do {
                try result.write(to: outputURL, atomically: true, encoding: .utf8)
                return "License data successfully written to \(outputURL.path)."
            } catch {
                throw TributeError("Unable to write output to \(outputURL.path). \(error).")
            }
        } else {
            return result
        }
    }

    public static func run(in directory: String, with args: [String] = CommandLine.arguments) throws -> String {
        let arg = args.count > 1 ? args[1] : Command.help.rawValue
        guard let command = Command(rawValue: arg) else {
            let commands = Command.allCases.map { $0.rawValue }
            if let closest = bestMatches(for: arg, in: commands).first {
                throw TributeError("Unrecognized command '\(arg)'. Did you mean '\(closest)'?")
            }
            throw TributeError("Unrecognized command '\(arg)'.")
        }
        switch command {
        case .help:
            return try getHelp(with: args.count > 2 ? args[2] : nil)
        case .list:
            return try listLibraries(in: directory, with: args)
        case .export:
            return try export(in: directory, with: args)
        case .check:
            return try check(in: directory, with: args)
        case .version:
            return "0.2.2"
        }
    }
}

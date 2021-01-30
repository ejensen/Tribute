//
//  main.swift
//  Tribute
//
//  Created by Nick Lockwood on 30/11/2020.
//

import Foundation
import Tribute

enum ExitCode: Int32 {
    case ok = 0 // EX_OK
    case error = 70 // EX_SOFTWARE
}

do {
    print(try Tribute.run(in: FileManager.default.currentDirectoryPath))
    exit(ExitCode.ok.rawValue)
} catch {
    print("error: \(error)")
    exit(ExitCode.error.rawValue)
}

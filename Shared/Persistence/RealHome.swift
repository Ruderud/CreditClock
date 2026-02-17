import Foundation

/// Returns the real user home directory, bypassing sandbox container redirection.
func realHomeDirectory() -> String {
    if let pw = getpwuid(getuid()) {
        return String(cString: pw.pointee.pw_dir)
    }
    return NSHomeDirectory()
}

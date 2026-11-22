import Darwin
import Foundation

// The event helper holds a shared lock only while its retry timer is armed.
// Exiting the process also releases it, even after an abnormal shutdown.
enum RetryActivity {
    static func begin(identityPath: String) -> Int32 {
        let fd = open(identityPath + ".retry.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return -1 }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    static func isActive(identityPath: String) -> Bool {
        let fd = open(identityPath + ".retry.lock", O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return flock(fd, LOCK_EX | LOCK_NB) == -1 && errno == EWOULDBLOCK
    }
}

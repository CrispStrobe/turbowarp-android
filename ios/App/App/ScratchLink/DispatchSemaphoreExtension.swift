import Foundation

extension DispatchSemaphore {
    func mutex<T>(_ task: () throws -> T) rethrows -> T {
        self.wait()
        defer { self.signal() }
        return try task()
    }
}

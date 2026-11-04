import Darwin
import Foundation

/// Watches the top-level Application folders and reports a burst of changes once.
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let queue = DispatchQueue(label: "com.jimmythefallony.GridBack.watcher")
    private var pending: DispatchWorkItem?

    func start(paths: [String], onChange: @escaping () -> Void) {
        stop()
        for path in paths {
            let fd = Darwin.open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.schedule(onChange)
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    private func schedule(_ onChange: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem {
            DispatchQueue.main.async(execute: onChange)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

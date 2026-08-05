import AppKit
import Network

/// An address the phone can post a picture to, straight onto the shelf.
///
/// AirDrop cannot be aimed by a shortcut: iOS offers it only through the share
/// sheet, which costs a tap and a choice of device every single time. A
/// shortcut can POST a file anywhere, though — so the shortest path from the
/// Action button to the shelf is somewhere to post it. This is that somewhere.
/// One port, one path, nothing in between: the picture goes phone → Wi-Fi →
/// this Mac, without an account, a cloud, or a working internet connection.
///
/// Off until switched on. A listening socket is not something to open behind
/// the user's back, however small it is.
@MainActor
final class DropInbox {
    /// Files that just arrived.
    var onArrival: (([URL]) -> Void)?

    static let enabledKey = "phoneInbox"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Unassigned by anything, and above 1024 so no privileges are needed.
    static let port: UInt16 = 17321

    private static let secretKey = "phoneInboxSecret"

    /// Random, made once and kept. The port answers the whole local network,
    /// and this is what separates the phone from everyone else on the same
    /// café Wi-Fi. Cheap, and proportionate: what is behind it can only write
    /// a picture into one folder.
    static var secret: String {
        let defaults = UserDefaults.standard
        if let kept = defaults.string(forKey: secretKey), kept.count == 16 { return kept }
        let fresh = String((0..<16).map { _ in "0123456789abcdef".randomElement()! })
        defaults.set(fresh, forKey: secretKey)
        return fresh
    }

    /// What goes into the shortcut on the phone. `.local` resolves over mDNS,
    /// so it keeps working when the router hands out a different address.
    static var address: String {
        "http://\(ProcessInfo.processInfo.hostName):\(port)/drop/\(secret)"
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.cyclop.inbox")

    // MARK: - Lifecycle

    func start() {
        guard Self.isEnabled, listener == nil else { return }
        let path = "/drop/\(Self.secret)"
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            // This is a thing for the local network and nowhere else.
            parameters.prohibitedInterfaceTypes = [.cellular]
            guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }
            let listener = try NWListener(using: parameters, on: port)

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                Intake(connection: connection, queue: self.queue, path: path) { data, ext in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.received(data, ext: ext) }
                    }
                }.start()
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Cyclop: inbox failed: \(error.localizedDescription)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Cyclop: cannot listen on \(Self.port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func received(_ data: Data, ext: String) {
        guard let url = ScreenshotVault.save(data, named: "Снимок с телефона", ext: ext) else { return }
        onArrival?([url])
    }
}

/// One request: read to the end, answered, closed.
///
/// Confined to the listener's queue — every callback Network hands back arrives
/// on the queue the connection was started with, so nothing here needs a lock.
/// It keeps itself alive through the closures until the reply has gone out.
private final class Intake {
    /// Room for a screenshot at any resolution, and far short of anything worth
    /// filling a disk with.
    private static let limit = 40 * 1024 * 1024

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let path: String
    private let onImage: (Data, String) -> Void

    private var buffer = Data()
    private var answered = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        path: String,
        onImage: @escaping (Data, String) -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.path = path
        self.onImage = onImage
    }

    func start() {
        // The router keeps the outside out, but saying so costs one comparison:
        // whatever reaches this port is answered only if it lives on this net.
        guard isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                buffer.append(data)
                guard buffer.count <= Self.limit else { return reply("413 Payload Too Large") }
                if handle() { return }
            }
            guard error == nil, !isComplete else { return connection.cancel() }
            receive()
        }
    }

    /// True once the request is whole and has been answered.
    private func handle() -> Bool {
        guard let blank = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }

        let head = String(decoding: buffer[..<blank.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        guard request.count >= 2 else { reply("400 Bad Request"); return true }

        var length = 0
        var type = ""
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { length = Int(value) ?? 0 }
            if name == "content-type" { type = value }
        }

        // The secret lives in the path, so a wrong one is simply a wrong
        // address — nothing here says whether it was close.
        guard request[0] == "POST", request[1] == path else {
            reply("404 Not Found")
            return true
        }
        guard length > 0, length <= Self.limit else { reply("400 Bad Request"); return true }
        // Body still on its way.
        guard buffer.distance(from: blank.upperBound, to: buffer.endIndex) >= length else { return false }

        let body = Data(buffer[blank.upperBound..<buffer.index(blank.upperBound, offsetBy: length)])
        guard let picture = Self.picture(in: body, contentType: type) else {
            reply("415 Unsupported Media Type")
            return true
        }
        onImage(picture.data, picture.ext)
        reply("200 OK", body: "ok")
        return true
    }

    private func reply(_ status: String, body: String = "") {
        guard !answered else { return }
        answered = true
        let payload = Data(body.utf8)
        let head = """
            HTTP/1.1 \(status)\r
            Content-Length: \(payload.count)\r
            Connection: close\r
            \r\n
            """
        connection.send(
            content: Data(head.utf8) + payload,
            completion: .contentProcessed { [connection] _ in connection.cancel() }
        )
    }

    // MARK: - Reading the picture out

    /// Shortcuts sends the file as the raw body when the request body is set to
    /// "File", and wraps it in a multipart envelope when set to "Form". Both are
    /// one setting apart in the same menu, so both are unwrapped here rather
    /// than made into a rule someone has to remember.
    private static func picture(in body: Data, contentType: String) -> (data: Data, ext: String)? {
        var payload = body
        if contentType.lowercased().contains("multipart/form-data"),
           let marker = contentType.range(of: "boundary="),
           case let boundary = contentType[marker.upperBound...]
               .trimmingCharacters(in: CharacterSet(charactersIn: "\" ")),
           !boundary.isEmpty,
           let inner = part(in: body, boundary: boundary) {
            payload = inner
        }
        guard let ext = self.ext(of: payload) else { return nil }
        return (payload, ext)
    }

    private static func part(in body: Data, boundary: String) -> Data? {
        let opening = Data("--\(boundary)".utf8)
        let closing = Data("\r\n--\(boundary)".utf8)
        guard let first = body.range(of: opening),
              let blank = body.range(of: Data("\r\n\r\n".utf8), in: first.upperBound..<body.endIndex),
              let end = body.range(of: closing, in: blank.upperBound..<body.endIndex)
        else { return nil }
        return Data(body[blank.upperBound..<end.lowerBound])
    }

    /// By content, not by what the sender claimed. The extension has to match
    /// the bytes or QuickLook will not preview the card on the shelf, and a
    /// shortcut sending something that is not a picture at all is turned away
    /// here rather than left on disk.
    private static func ext(of data: Data) -> String? {
        let head = [UInt8](data.prefix(12))
        guard head.count >= 12 else { return nil }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        // ISO base media: the brand sits at offset 4, after the box length.
        if Array(head[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: head[8..<12], as: UTF8.self)
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") || brand.hasPrefix("msf") { return "heic" }
        }
        return nil
    }

    // MARK: - Peer

    private func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            let bytes = [UInt8](address.rawValue)
            guard bytes.count == 4 else { return false }
            if bytes[0] == 127 || bytes[0] == 10 { return true }
            if bytes[0] == 192 && bytes[1] == 168 { return true }
            if bytes[0] == 172 && (16...31).contains(bytes[1]) { return true }
            // Link-local, for a cable straight between the two.
            return bytes[0] == 169 && bytes[1] == 254
        case .ipv6(let address):
            return address.isLoopback || address.isLinkLocal
                // Unique local, fc00::/7 — the v6 counterpart of 192.168.
                || ([UInt8](address.rawValue).first ?? 0) & 0xFE == 0xFC
        default:
            return false
        }
    }
}

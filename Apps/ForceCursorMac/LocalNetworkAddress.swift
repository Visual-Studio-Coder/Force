import Darwin
import Foundation

enum LocalNetworkAddress {
    static func preferredIPv4() -> String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [(priority: Int, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            let priority = name == "en0" ? 0 : (name.hasPrefix("en") ? 1 : 2)
            let addressBytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            candidates.append((priority, String(decoding: addressBytes, as: UTF8.self)))
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }
}

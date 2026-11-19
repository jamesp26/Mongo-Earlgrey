import Foundation
import dnssd

public struct SRVRecord: Sendable {
    public let target: String
    public let port: UInt16
    public let priority: UInt16
    public let weight: UInt16
}

public enum SRVResolver {
    public static func resolveMongoSRVAsync(domain: String, timeout: TimeInterval = 4.0) async -> (hosts: [(String, UInt16)], txtOptions: [String: String]) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = resolveMongoSRV(domain: domain, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    public static func resolveMongoSRV(domain: String, timeout: TimeInterval = 4.0) -> (hosts: [(String, UInt16)], txtOptions: [String: String]) {
        let srvService = "_mongodb._tcp.\(domain)"
        let srvRecords = querySRV(name: srvService, timeout: timeout)
        let sortedHosts = srvRecords
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.weight > $1.weight
            }
            .map { ($0.target, $0.port) }

        let txtStrings = queryTXT(name: domain, timeout: min(timeout, 2.5))
        var options: [String: String] = [:]
        for txt in txtStrings {
            for pair in txt.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    options[kv[0]] = kv[1]
                }
            }
        }
        return (sortedHosts, options)
    }

    private final class QueryContext {
        var srvRecords: [SRVRecord] = []
        var txtRecords: [String] = []
        var moreComing: Bool = false
    }

    private static func querySRV(name: String, timeout: TimeInterval) -> [SRVRecord] {
        let context = QueryContext()
        var sdRef: DNSServiceRef?
        let unmanaged = Unmanaged.passUnretained(context).toOpaque()

        let callback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, rrtype, _, rdlen, rdata, _, ctx in
            guard errorCode == kDNSServiceErr_NoError,
                  rrtype == UInt16(kDNSServiceType_SRV),
                  rdlen > 6,
                  let rdata = rdata,
                  let ctx = ctx else { return }

            let queryCtx = Unmanaged<QueryContext>.fromOpaque(ctx).takeUnretainedValue()
            queryCtx.moreComing = (flags & DNSServiceFlags(kDNSServiceFlagsMoreComing)) != 0
            let bytes = Array(UnsafeBufferPointer(start: rdata.assumingMemoryBound(to: UInt8.self), count: Int(rdlen)))
            let priority = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let weight = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
            let port = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])

            var offset = 6
            var labels: [String] = []
            while offset < bytes.count {
                let len = Int(bytes[offset])
                offset += 1
                if len == 0 { break }
                guard offset + len <= bytes.count else { break }
                let label = String(decoding: bytes[offset..<(offset + len)], as: UTF8.self)
                labels.append(label)
                offset += len
            }
            let target = labels.joined(separator: ".")
            if !target.isEmpty {
                queryCtx.srvRecords.append(SRVRecord(target: target, port: port, priority: priority, weight: weight))
            }
        }

        let err = DNSServiceQueryRecord(
            &sdRef,
            0,
            0,
            name,
            UInt16(kDNSServiceType_SRV),
            UInt16(kDNSServiceClass_IN),
            callback,
            unmanaged
        )

        guard err == kDNSServiceErr_NoError, let ref = sdRef else {
            return []
        }
        defer { DNSServiceRefDeallocate(ref) }

        pumpDNSService(ref: ref, timeout: timeout) {
            !context.srvRecords.isEmpty && !context.moreComing
        }

        return context.srvRecords
    }

    private static func queryTXT(name: String, timeout: TimeInterval) -> [String] {
        let context = QueryContext()
        var sdRef: DNSServiceRef?
        let unmanaged = Unmanaged.passUnretained(context).toOpaque()

        let callback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, rrtype, _, rdlen, rdata, _, ctx in
            guard errorCode == kDNSServiceErr_NoError,
                  rrtype == UInt16(kDNSServiceType_TXT),
                  rdlen > 0,
                  let rdata = rdata,
                  let ctx = ctx else { return }

            let queryCtx = Unmanaged<QueryContext>.fromOpaque(ctx).takeUnretainedValue()
            queryCtx.moreComing = (flags & DNSServiceFlags(kDNSServiceFlagsMoreComing)) != 0
            let bytes = Array(UnsafeBufferPointer(start: rdata.assumingMemoryBound(to: UInt8.self), count: Int(rdlen)))
            var offset = 0
            var parts: [String] = []
            while offset < bytes.count {
                let len = Int(bytes[offset])
                offset += 1
                guard offset + len <= bytes.count else { break }
                let str = String(decoding: bytes[offset..<(offset + len)], as: UTF8.self)
                parts.append(str)
                offset += len
            }
            let joined = parts.joined()
            if !joined.isEmpty {
                queryCtx.txtRecords.append(joined)
            }
        }

        let err = DNSServiceQueryRecord(
            &sdRef,
            0,
            0,
            name,
            UInt16(kDNSServiceType_TXT),
            UInt16(kDNSServiceClass_IN),
            callback,
            unmanaged
        )

        guard err == kDNSServiceErr_NoError, let ref = sdRef else {
            return []
        }
        defer { DNSServiceRefDeallocate(ref) }

        pumpDNSService(ref: ref, timeout: timeout) {
            !context.txtRecords.isEmpty && !context.moreComing
        }

        return context.txtRecords
    }

    private static func pumpDNSService(ref: DNSServiceRef, timeout: TimeInterval, shouldStop: () -> Bool) {
        let fd = DNSServiceRefSockFD(ref)
        guard fd >= 0 else { return }
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remainingMs = Int32(max(50, deadline.timeIntervalSinceNow * 1000))
            let ready = poll(&pfd, 1, min(remainingMs, 250))
            if ready > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                DNSServiceProcessResult(ref)
                if shouldStop() {
                    // Brief extra poll for additional records in the same packet
                    var pfd2 = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    if poll(&pfd2, 1, 40) > 0 {
                        DNSServiceProcessResult(ref)
                    }
                    break
                }
            } else if ready < 0 {
                break
            }
        }
    }
}

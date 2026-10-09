import Foundation

/// Google encoded polylines (HAFAS `cfg.polyEnc:"GPA"`, field `crdEncYX`; SPEC §A3.4).
public enum Polyline {
    /// Decodes an encoded polyline (lat/lon order, precision 1e5 by default). A truncated string stops at the last
    /// complete point instead of failing.
    public static func decode(_ encoded: String, precision: Int = 5) -> [GeoPoint] {
        let bytes = Array(encoded.utf8)
        let factor = pow(10.0, Double(precision))
        var points: [GeoPoint] = []
        points.reserveCapacity(bytes.count / 4)
        var index = 0, lat = 0, lon = 0

        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                guard b >= 0 else { return nil }
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
                if shift > 60 { return nil }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            points.append(GeoPoint(latitude: Double(lat) / factor, longitude: Double(lon) / factor))
        }
        return points
    }

    /// A leg's shape: all `polyG.polyXL` segments in order. A segment's first point is dropped when it equals the
    /// previous segment's last point (ÖBB sends DOT stub · SOLID main line · DOT stub).
    public static func concatenate(_ segments: [[GeoPoint]]) -> [GeoPoint] {
        var out: [GeoPoint] = []
        for seg in segments where !seg.isEmpty {
            if let last = out.last, last == seg[0] {
                out.append(contentsOf: seg.dropFirst())
            } else {
                out.append(contentsOf: seg)
            }
        }
        return out
    }
}

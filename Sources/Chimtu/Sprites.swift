import AppKit

/// Pre-decoded animation frames. Decoding once up front means the per-frame
/// work is just swapping a CALayer's contents pointer, which is nearly free.
struct Animation {
    let name: String
    let frames: [CGImage]
    let fps: Double
}

enum Sprites {
    /// Sprite cell size in points; the window adds headroom above for the speech bubble.
    static let size = CGSize(width: 112, height: 96)
    static let bubbleHeight: CGFloat = 34
    static var windowSize: CGSize { CGSize(width: size.width, height: size.height + bubbleHeight) }

    static func hat(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: "hat_\(name)", withExtension: "png", subdirectory: "frames"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func load() -> [String: Animation] {
        let specs: [(String, Int, Double)] = [
            ("idle", 6, 4), ("idle_left", 6, 4), ("idle_right", 6, 4),
            ("walk_right", 6, 12), ("walk_left", 6, 12), ("run_right", 6, 16), ("run_left", 6, 16),
            ("sit", 4, 3), ("sleep", 2, 1), ("wave", 4, 6),
            ("jump", 6, 10), ("scratch", 6, 6), ("yawn", 6, 4), ("alert", 6, 6), ("happy", 6, 8),
            ("held", 4, 4), ("land", 4, 10), ("spin", 6, 7), ("dance", 6, 8), ("shake", 6, 12), ("sad", 6, 3), ("tired", 6, 3),
            ("eat", 6, 6), ("love", 6, 6), ("howl", 6, 5), ("sneeze", 6, 8), ("dig", 6, 8), ("roll", 6, 6),
            ("sniff", 6, 8), ("fetch", 6, 6), ("bark", 6, 8), ("beg", 6, 4), ("typing", 6, 10), ("groove", 6, 8), ("focus", 6, 3), ("wink", 4, 6), ("celebrate", 6, 10),
            ("stretch", 6, 5), ("peek", 6, 5), ("think", 6, 3), ("laugh", 6, 10), ("pout", 6, 3), ("salute", 6, 6), ("hiccup", 6, 9), ("chase", 6, 10),
        ]
        var out: [String: Animation] = [:]
        for (name, count, fps) in specs {
            var frames: [CGImage] = []
            for i in 0..<count {
                let file = String(format: "%@_%02d", name, i)
                guard let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "frames")
                        ?? Bundle.main.url(forResource: file, withExtension: "png"),
                      let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
                else { continue }
                frames.append(img)
            }
            if !frames.isEmpty { out[name] = Animation(name: name, frames: frames, fps: fps) }
        }
        return out
    }
}

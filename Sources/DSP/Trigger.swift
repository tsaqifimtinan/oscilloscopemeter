enum TriggerEdge: String, CaseIterable {
    case rising = "Rising", falling = "Falling"
}

enum TriggerMode: String, CaseIterable {
    case auto = "Auto", normal = "Normal"
}

// ponytail: no holdoff, hysteresis, Single mode or sub-sample interpolation yet. Add hysteresis
// if noisy signals make the trace jump, interpolation if a steady tone jitters at small windows.

/// Latest index `i` in `1...maxIndex` where `x` crosses `level` on `edge`.
func findTrigger(_ x: UnsafeBufferPointer<Float>, level: Float, edge: TriggerEdge, maxIndex: Int) -> Int? {
    var i = min(maxIndex, x.count - 1)
    while i >= 1 {
        let a = x[i - 1], b = x[i]
        switch edge {
        case .rising: if a < level && b >= level { return i }
        case .falling: if a > level && b <= level { return i }
        }
        i -= 1
    }
    return nil
}

/// Start of the `window` samples to display from snapshot `x`, with the trigger at the left edge.
/// Auto free-runs on the newest samples when nothing triggers; Normal returns nil (hold the last frame).
func frameStart(_ x: UnsafeBufferPointer<Float>, window: Int, level: Float,
                edge: TriggerEdge, mode: TriggerMode) -> Int? {
    let newest = x.count - window
    if let i = findTrigger(x, level: level, edge: edge, maxIndex: newest) { return i }
    return mode == .auto ? newest : nil
}

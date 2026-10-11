import Foundation

/// Index selection for very small charts.
public enum SparklineSampling {
    /// Indices of at most `maxPoints` evenly spaced elements out of `count`, always including the first
    /// and the last. Returns every index when `count <= maxPoints`, and `[]` when `count == 0` or
    /// `maxPoints < 1`. With `maxPoints == 1` only the last index is returned.
    ///
    /// For `k = maxPoints >= 2` and `n = count`, the i-th pick is `(i * (n - 1)) / (k - 1)` using integer
    /// division, which is strictly increasing when `n > k`.
    public static func indices(count: Int, maxPoints: Int) -> [Int] {
        guard count > 0, maxPoints >= 1 else { return [] }
        if count <= maxPoints { return Array(0..<count) }
        if maxPoints == 1 { return [count - 1] }
        var result: [Int] = []
        result.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            result.append(i * (count - 1) / (maxPoints - 1))
        }
        return result
    }
}

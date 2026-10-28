import Foundation

public enum RefractionFit {
    public static func estimate(_ thresholds: [MeridianThreshold]) throws -> ResearchEstimate {
        guard thresholds.count >= 12 else { throw MeasurementError.invalid(L("需要六个方向、各两次完整的远点测量。")) }
        let groups = Dictionary(grouping: thresholds, by: { $0.meridian })
        guard Set(groups.keys) == Set([0.0,30,60,90,120,150]),
              groups.values.allSatisfy({ $0.count == 2 && Set($0.map(\.repeatIndex)) == Set([0,1]) }) else {
            throw MeasurementError.invalid(L("方向覆盖或重复测量不足。"))
        }
        guard thresholds.allSatisfy({ $0.meridian.isFinite && (0..<180).contains($0.meridian) &&
            $0.power.isFinite && (-5 ... -1.0/3).contains($0.power) &&
            $0.uncertainty.isFinite && $0.uncertainty > 0 && $0.uncertainty <= 0.20 &&
            $0.nearPassPower.isFinite && $0.farFailPower.isFinite &&
            $0.nearPassPower > $0.farFailPower && $0.nearPassPower - $0.farFailPower <= 0.126 &&
            abs($0.power + ($0.nearPassPower + $0.farFailPower)/2) < 1e-6 }) else {
            throw MeasurementError.invalid(L("远点数据或距离误差不满足计算要求。"))
        }
        let repeatDifference = groups.values.map { values in
            (values.map(\.power).max() ?? 0) - (values.map(\.power).min() ?? 0)
        }.max() ?? 0
        guard repeatDifference <= 0.50 else { throw MeasurementError.invalid(L("重复测量相差超过0.50D，请休息后重新测试。")) }
        var normal = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        var rhs = Array(repeating: 0.0, count: 3)
        for point in thresholds {
            let angle = point.meridian * .pi / 90
            let x = [1.0, cos(angle), sin(angle)]
            let weight = 1 / pow(point.uncertainty, 2)
            for i in 0..<3 {
                rhs[i] += weight * x[i] * point.power
                for j in 0..<3 { normal[i][j] += weight * x[i] * x[j] }
            }
        }
        let solution = try solve(normal, rhs)
        let vector = PowerVector(m: solution[0], j0: solution[1], j45: solution[2])
        let rmse = sqrt(thresholds.map { pow($0.power - vector.power(at: $0.meridian), 2) }.reduce(0,+) / Double(thresholds.count - 3))
        guard rmse <= 0.25 else { throw MeasurementError.invalid(L("不同方向的数据不符合规则散光模型，暂不输出度数。")) }
        guard vector.sphere < -1.0/3, vector.sphere + vector.cylinder > -5 else {
            throw MeasurementError.invalid(L("拟合结果接近或超出测量边界，暂不输出度数。"))
        }
        // Do not make random distance error look as if it eliminates shared calibration error.
        let error = max(thresholds.map(\.uncertainty).max() ?? 0.15, rmse)
        return ResearchEstimate(vector: vector, residualRMSE: rmse, maximumRepeatDifference: repeatDifference,
                                instrumentStandardError: error,
                                axisReportable: abs(vector.cylinder) >= max(0.50, 4 * error))
    }
    private static func solve(_ matrix: [[Double]], _ rhs: [Double]) throws -> [Double] {
        var a = zip(matrix, rhs).map { $0 + [$1] }
        for col in 0..<3 {
            let pivot = (col..<3).max(by: { abs(a[$0][col]) < abs(a[$1][col]) })!
            guard abs(a[pivot][col]) > 1e-8 else { throw MeasurementError.invalid(L("方向分布不足，无法求解。")) }
            a.swapAt(col, pivot)
            let divisor = a[col][col]
            for j in col..<4 { a[col][j] /= divisor }
            for row in 0..<3 where row != col {
                let factor = a[row][col]
                for j in col..<4 { a[row][j] -= factor * a[col][j] }
            }
        }
        return a.map { $0[3] }
    }
}

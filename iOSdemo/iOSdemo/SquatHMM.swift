// SquatHMM.swift
import Foundation
import Vision

// MARK: - Gaussian utilities

struct Gaussian1D: Codable {
    let mean: Double
    let std: Double

    private var var2: Double { 2.0 * std * std }
    private var logNorm: Double { -0.5 * log(2.0 * Double.pi * std * std) }

    init(mean: Double, std: Double) {
        self.mean = mean
        self.std = max(std, 1e-6) // avoid zero
    }

    func logProb(_ x: Double) -> Double {
        let diff = x - mean
        return logNorm - (diff * diff) / var2
    }

    func zScore(_ x: Double) -> Double {
        return (x - mean) / std
    }
}

struct DiagonalGaussian: Codable {
    // Independent Gaussian per feature dimension
    let means: [Double]
    let stds: [Double]

    func logProb(_ x: [Double]) -> Double {
        precondition(x.count == means.count && means.count == stds.count)
        var total = 0.0
        for i in 0..<x.count {
            let g = Gaussian1D(mean: means[i], std: stds[i])
            total += g.logProb(x[i])
        }
        return total
    }

    func zScores(_ x: [Double]) -> [Double] {
        precondition(x.count == means.count && means.count == stds.count)
        return (0..<x.count).map { i in
            Gaussian1D(mean: means[i], std: stds[i]).zScore(x[i])
        }
    }
}

// MARK: - HMM Model

struct HMMModel: Codable {
    let numStates: Int
    let numFeatures: Int

    // logPrior[s]
    let logPrior: [Double]
    // logTrans[sFrom][sTo]
    let logTrans: [[Double]]

    // emissions[s]
    let emissions: [DiagonalGaussian]

    // For classification thresholding
    let meanLogLikelihood: Double
    let stdLogLikelihood: Double
    let thresholdSigma: Double  // e.g. 2.0

    // Main entry point for raw feature sequences
    func classify(sequence: [[Double]]) -> (states: [Int], logLike: Double, isCorrect: Bool, jointErrors: [JointError]) {
        let (path, logP, perFeatureError) = viterbiWithPerFeatureError(sequence: sequence)
        let z = (logP - meanLogLikelihood) / stdLogLikelihood
        let isCorrect = z >= -thresholdSigma

        let jointErrors = JointError.fromFeatureErrors(perFeatureError: perFeatureError)
        return (path, logP, isCorrect, jointErrors)
    }

    // Convenience: classify a sequence of VN observations directly
    func classify(observations: [VNHumanBodyPoseObservation]) -> (states: [Int], logLike: Double, isCorrect: Bool, jointErrors: [JointError]) {
        // Convert each observation to feature vector using SquatFeatureExtractor
        let featureSeq: [[Double]] = observations.compactMap { obs in
            guard let pts = try? obs.recognizedPoints(.all) else { return nil }
            return SquatFeatureExtractor.featureVector(from: pts)
        }

        guard !featureSeq.isEmpty else {
            return ([], -Double.infinity, false, [])
        }

        return classify(sequence: featureSeq)
    }

    // Convenience: classify sequence of joint dictionaries (if you already have recognizedPoints(.all) outside)
    func classify(poseSequence: [[VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]]) -> (states: [Int], logLike: Double, isCorrect: Bool, jointErrors: [JointError]) {
        let featureSeq: [[Double]] = poseSequence.compactMap { SquatFeatureExtractor.featureVector(from: $0) }

        guard !featureSeq.isEmpty else {
            return ([], -Double.infinity, false, [])
        }

        return classify(sequence: featureSeq)
    }

    // Standard Viterbi in log space, extended to accumulate per-feature error
    private func viterbiWithPerFeatureError(sequence: [[Double]]) -> (path: [Int], logLike: Double, perFeatureError: [Double]) {
        guard !sequence.isEmpty else { return ([], -Double.infinity, Array(repeating: 0.0, count: numFeatures)) }
        let T = sequence.count

        var dp = Array(repeating: Array(repeating: -Double.infinity, count: numStates), count: T)
        var backpointer = Array(repeating: Array(repeating: -1, count: numStates), count: T)

        // Initialization
        let x0 = sequence[0]
        for s in 0..<numStates {
            let logEmit = emissions[s].logProb(x0)
            dp[0][s] = logPrior[s] + logEmit
            backpointer[0][s] = -1
        }

        // Recurrence
        for t in 1..<T {
            let xt = sequence[t]
            for s in 0..<numStates {
                var bestPrev = -1
                var bestVal = -Double.infinity

                for sp in 0..<numStates {
                    let candidate = dp[t - 1][sp] + logTrans[sp][s]
                    if candidate > bestVal {
                        bestVal = candidate
                        bestPrev = sp
                    }
                }

                let logEmit = emissions[s].logProb(xt)
                dp[t][s] = bestVal + logEmit
                backpointer[t][s] = bestPrev
            }
        }

        // Termination
        var bestFinalState = 0
        var bestLogP = dp[T - 1][0]
        for s in 1..<numStates {
            if dp[T - 1][s] > bestLogP {
                bestLogP = dp[T - 1][s]
                bestFinalState = s
            }
        }

        // Backtrace
        var path = Array(repeating: 0, count: T)
        var state = bestFinalState
        for t in stride(from: T - 1, through: 0, by: -1) {
            path[t] = state
            state = backpointer[t][state]
            if state < 0 && t > 0 { break }
        }

        // Per-feature error accumulation along path
        var perFeatureError = Array(repeating: 0.0, count: numFeatures)
        for t in 0..<T {
            let s = path[t]
            let xt = sequence[t]
            let z = emissions[s].zScores(xt) // per-feature
            for d in 0..<numFeatures {
                perFeatureError[d] += z[d] * z[d] // squared z
            }
        }

        return (path, bestLogP, perFeatureError)
    }
}

// MARK: - Loading model JSON from Python training

extension HMMModel {
    /// Load HMMModel from raw Data (e.g. contents of squat_hmm_model.json).
    static func load(from data: Data) throws -> HMMModel {
        let decoder = JSONDecoder()
        return try decoder.decode(HMMModel.self, from: data)
    }

    /// Load HMMModel from a file URL (e.g. Bundle.main.url(forResource: "squat_hmm_model", withExtension: "json")).
    static func load(from url: URL) throws -> HMMModel {
        let data = try Data(contentsOf: url)
        return try HMMModel.load(from: data)
    }
}

// MARK: - Mapping feature errors to joints

enum SquatJoint: String, CaseIterable, Codable {
    case leftShoulder
    case rightShoulder
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

struct JointError: Codable {
    let joint: SquatJoint
    let errorScore: Double

    static func fromFeatureErrors(perFeatureError: [Double]) -> [JointError] {
        precondition(perFeatureError.count == 16, "Expecting 16 features (x,y for 8 joints).")

        // d = 2 * jointIndex, 2 * jointIndex + 1
        let joints: [SquatJoint] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]

        var out: [JointError] = []
        for (jIndex, joint) in joints.enumerated() {
            let dx = perFeatureError[2 * jIndex]
            let dy = perFeatureError[2 * jIndex + 1]
            out.append(JointError(joint: joint, errorScore: dx + dy))
        }

        return out.sorted { $0.errorScore > $1.errorScore }
    }
}

// MARK: - Feature extraction from Vision joints

struct SquatFeatureExtractor {

    /// Extracts a 16-dim normalized feature vector from Vision joints:
    /// [ls.x, ls.y, rs.x, rs.y, lh.x, lh.y, rh.x, rh.y,
    ///  lk.x, lk.y, rk.x, rk.y, la.x, la.y, ra.x, ra.y]
    /// using hip center as origin and shoulder-hip distance as scale.
    static func featureVector(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> [Double]? {

        func g(_ name: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            // Lowered confidence threshold from 0.3 to 0.2 to handle unstable tracking
            guard let p = points[name], p.confidence > 0.2 else { return nil }
            return p
        }

        guard
            let ls = g(.leftShoulder),
            let rs = g(.rightShoulder),
            let lh = g(.leftHip),
            let rh = g(.rightHip),
            let lk = g(.leftKnee),
            let rk = g(.rightKnee),
            let la = g(.leftAnkle),
            let ra = g(.rightAnkle)
        else {
            return nil
        }

        func mid(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> (Double, Double) {
            return ((Double(a.x) + Double(b.x)) / 2.0,
                    (Double(a.y) + Double(b.y)) / 2.0)
        }

        func dist(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
            let dx = a.0 - b.0
            let dy = a.1 - b.1
            return sqrt(dx*dx + dy*dy)
        }

        let hipCenter = mid(lh, rh)
        let shoulderCenter = mid(ls, rs)
        var scale = dist(hipCenter, shoulderCenter)
        if scale < 1e-3 {
            // Fallback: use hip distance
            let hipsDist = dist((Double(lh.x), Double(lh.y)), (Double(rh.x), Double(rh.y)))
            scale = max(hipsDist, 1e-3)
        }

        func norm(_ p: VNRecognizedPoint) -> (Double, Double) {
            let x = (Double(p.x) - hipCenter.0) / scale
            let y = (Double(p.y) - hipCenter.1) / scale
            return (x, y)
        }

        let (lsx, lsy) = norm(ls)
        let (rsx, rsy) = norm(rs)
        let (lhx, lhy) = norm(lh)
        let (rhx, rhy) = norm(rh)
        let (lkx, lky) = norm(lk)
        let (rkx, rky) = norm(rk)
        let (lax, lay) = norm(la)
        let (rax, ray) = norm(ra)

        return [
            lsx, lsy,
            rsx, rsy,
            lhx, lhy,
            rhx, rhy,
            lkx, lky,
            rkx, rky,
            lax, lay,
            rax, ray
        ]
    }
}
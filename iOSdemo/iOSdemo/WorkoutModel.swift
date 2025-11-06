import Foundation

// MARK: - Workout Types

enum WorkoutType: String, CaseIterable, Identifiable {
    case squats = "Squats"
    case pullups = "Pull-ups"
    case shoulderPress = "Shoulder Press"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .squats:
            return "figure.strengthtraining.traditional"
        case .pullups:
            return "figure.climbing"
        case .shoulderPress:
            return "figure.arms.open"
        }
    }

    var imageName: String {
        switch self {
        case .squats:
            return "squats"
        case .pullups:
            return "pullups"
        case .shoulderPress:
            return "shoulderpress"
        }
    }

    var videoFileName: String {
        switch self {
        case .squats:
            return "squats_professional.mp4"
        case .pullups:
            return "pullups_professional.mp4"
        case .shoulderPress:
            return "shoulderpress_professional.mp4"
        }
    }

    var description: String {
        switch self {
        case .squats:
            return "Lower body strength exercise"
        case .pullups:
            return "Upper body pulling exercise"
        case .shoulderPress:
            return "Shoulder and arm exercise"
        }
    }
}

// MARK: - Workout Mode

enum WorkoutMode {
    case alone      // Single video with ghost overlay
    case partner    // Side-by-side comparison

    var title: String {
        switch self {
        case .alone:
            return "Ghost (Alone)"
        case .partner:
            return "Ghost (Partner)"
        }
    }

    var description: String {
        switch self {
        case .alone:
            return "Single video with ghost overlay of your motion"
        case .partner:
            return "Side-by-side comparison with professional video"
        }
    }

    var systemImageName: String {
        switch self {
        case .alone:
            return "person.fill"
        case .partner:
            return "person.2.fill"
        }
    }
}

// MARK: - Workout Session

struct WorkoutSession {
    let workout: WorkoutType
    let mode: WorkoutMode
    let timestamp: Date

    init(workout: WorkoutType, mode: WorkoutMode) {
        self.workout = workout
        self.mode = mode
        self.timestamp = Date()
    }
}

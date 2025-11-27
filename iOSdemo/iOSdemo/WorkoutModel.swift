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

    private var tutorialVideoResource: (name: String, ext: String) {
        switch self {
        case .squats:
            return ("squats", "MOV")
        case .pullups:
            return ("pullups_professional", "mp4")
        case .shoulderPress:
            return ("shoulderpress_professional", "mp4")
        }
    }

    var videoResourceName: String {
        tutorialVideoResource.name
    }

    var videoFileExtension: String {
        tutorialVideoResource.ext
    }

    var videoFileName: String {
        "\(tutorialVideoResource.name).\(tutorialVideoResource.ext)"
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
    case alone      // Ghost overlay recording
    case tutorial   // Watch professional video

    var title: String {
        switch self {
        case .alone:
            return "Ghost (Alone)"
        case .tutorial:
            return "Tutorial Video"
        }
    }

    var description: String {
        switch self {
        case .alone:
            return "Single video with ghost overlay of your motion"
        case .tutorial:
            return "Watch the professional demonstration video"
        }
    }

    var systemImageName: String {
        switch self {
        case .alone:
            return "person.fill"
        case .tutorial:
            return "play.rectangle.fill"
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

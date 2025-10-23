import UIKit
import Accelerate
import AVFoundation
import Accelerate.vImage

// TODO: necessary functions for taking photos
struct ImageUtils {
}

// Might not need
private extension UIImage {
    func resize(to target: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(target, false, 1)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: target))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

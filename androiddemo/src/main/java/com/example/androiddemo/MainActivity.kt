package com.example.androiddemo

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.media.MediaScannerConnection
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import com.example.androiddemo.databinding.ActivityMainBinding
import com.example.tonguedetector.DetectionService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min

class MainActivity : AppCompatActivity() {
    companion object {
        private const val INPUT_SIZE = 640
        private const val DETECTION_THRESHOLD = 0.7f // Sensitivity for Neural Network. 0.7 is standard for moving object

        private const val CENTER_THRESHOLD = INPUT_SIZE * 0.5f
        private const val BLUR_VAR_THRESHOLD = 0.022f // Increase for higher focus required
        private const val BRIGHTNESS_THRESHOLD = 0.32f // Increase for more brightness required
        private const val CAPTURE_DURATION_MS = 1000L // Roughly 4 - 5 frames captured
        private const val SAMPLE_INTERVAL = 1 // Sample interval from captured frames (1 = all frames)
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var detector: DetectionService

    // Camera selection (default)
    private var cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

    // Frame-buffering for video capture
    private val frameBuffer = mutableListOf<Bitmap>()
    private var isCapturingFrames = false

    // Requires 1 full frame with conditions met for photo to capture. Increasing makes capture more difficult
    private val REQUIRED_GOOD_FRAMES = 1
    private var goodFrameCount = 0
    private var takePhotoInProgress = false

    // Requesting permissions (camera + storage)
    private val storagePermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {}

    private val cameraPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            startCamera()
        } else {
            finish()
        }
    }

    // Launch camera and storage permissions. Initialize DetectionService
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        detector = DetectionService()
        binding.previewView.scaleType = PreviewView.ScaleType.FIT_CENTER

        // Camera selector listener
        binding.switchCameraButton.setOnClickListener {
            cameraSelector = if (cameraSelector == CameraSelector.DEFAULT_FRONT_CAMERA) {
                CameraSelector.DEFAULT_BACK_CAMERA
            } else {
                CameraSelector.DEFAULT_FRONT_CAMERA
            }
            startCamera()
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            startCamera()
        } else {
            cameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    // Start the camera
    private fun startCamera() {
        ProcessCameraProvider.getInstance(this).addListener({
            val provider = ProcessCameraProvider.getInstance(this).get()

            val preview = Preview.Builder()
                .setTargetResolution(Size(INPUT_SIZE, INPUT_SIZE))
                .build()
                .also { it.setSurfaceProvider(binding.previewView.surfaceProvider) }

            val analysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(INPUT_SIZE, INPUT_SIZE))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { it.setAnalyzer(ContextCompat.getMainExecutor(this), ::analyzeImage) }

            provider.unbindAll()
            provider.bindToLifecycle(
                this,
                cameraSelector,
                preview,
                analysis
            )
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyzeImage(image: ImageProxy) {
        val buf = image.planes[0].buffer
        val bmp = createBitmap(image.width, image.height)
        bmp.copyPixelsFromBuffer(buf)
        image.close()

        val rot = image.imageInfo.rotationDegrees.toFloat()
        val rotated = Bitmap.createBitmap(
            bmp, 0, 0, bmp.width, bmp.height,
            Matrix().apply { postRotate(rot) }, true
        )

        // Handling horizontal flip
        val finalBmp = if (cameraSelector == CameraSelector.DEFAULT_FRONT_CAMERA) {
            val matrix = Matrix().apply { preScale(-1f, 1f) }
            Bitmap.createBitmap(rotated, 0, 0, rotated.width, rotated.height, matrix, true)
        } else {
            // No back camera flip
            rotated
        }

        val inputBmp = finalBmp.scale(INPUT_SIZE, INPUT_SIZE)

        // If conditions were met, save the current frame
        if (isCapturingFrames) {
            frameBuffer.add(inputBmp)
        }

        // Check for minimum brightness and focus, update user via feedback
        val brightnessOk = avgBrightness(inputBmp) > BRIGHTNESS_THRESHOLD
        val focusOk = computeGradientSharpness(inputBmp) > BLUR_VAR_THRESHOLD
        updateStatus(binding.statusBrightness, brightnessOk, "Image is bright enough")
        updateStatus(binding.statusFocus, focusOk, "Image is in focus")

        // Try to detect tongue in camera feed
        val dets = detector.detect(inputBmp, DETECTION_THRESHOLD)
        if (dets.isEmpty()) {
            // Reset if no tongue found, update user via feedback
            goodFrameCount = 0
            updateStatus(binding.statusPosition, false, "Tongue in correct position")
            return
        }

        // If tongue found, record the location
        val d = dets.first()
        val cx = d.x + d.w/2f
        val cy = d.y + d.h/2f

        // Check if tongue is close enough to center of screen
        val distance = hypot(cx - INPUT_SIZE/2f, cy - INPUT_SIZE/2f)
        val centered = distance < (INPUT_SIZE * CENTER_THRESHOLD)

        // Check if tongue is close enough/not too close
        val area = d.w * d.h
        val feedArea = INPUT_SIZE * INPUT_SIZE
        val positionOk = centered && area in (feedArea/6f..feedArea/2f)

        // Update user if tongue is centered and at a good distance
        updateStatus(binding.statusPosition, positionOk, "Tongue in correct position")

        // If all conditions met, start saving frames
        val allGood = brightnessOk && focusOk && positionOk
        if (allGood) {
            goodFrameCount++
            if (goodFrameCount >= REQUIRED_GOOD_FRAMES) {
                goodFrameCount = 0
                captureVideoFrames()
            }
        } else {
            goodFrameCount = 0
        }
    }

    private fun captureVideoFrames() {
        // Make sure multiple instances of this function don't run at the same time
        if (takePhotoInProgress) return
        takePhotoInProgress = true
        frameBuffer.clear()
        isCapturingFrames = true

        // Wait long enough to capture sufficient frames. Edit time via global variable at top of file
        Handler(Looper.getMainLooper()).postDelayed({
            isCapturingFrames = false
            val sampled = frameBuffer.filterIndexed { i, _ -> i % SAMPLE_INTERVAL == 0 }
            if (sampled.isEmpty()) {
                takePhotoInProgress = false
                Toast.makeText(this, "No frames captured", Toast.LENGTH_SHORT).show()
            } else {
                processFrames(sampled)
            }
        }, CAPTURE_DURATION_MS)
    }

    // Make sure the captured frames meet conditions (conditions more strict here)
    private fun processFrames(frames: List<Bitmap>) {
        // For testing how many frames get captured within time delay
        //println("CAP_FRAME_COUNT ${frames.size} frames")

        // Only keep frames where the tongue is detected
        val withDet = frames.mapNotNull { bmp ->
            detector.detect(bmp, DETECTION_THRESHOLD).firstOrNull()?.let { det -> bmp to det }
        }
        if (withDet.isEmpty()) {
            takePhotoInProgress = false
            Toast.makeText(this, "No tongue detected", Toast.LENGTH_SHORT).show()
            return
        }

        // For each candidate frame with a tongue detected:
        // First crop around the bounding box (tongue) with a 10% buffer
        data class Candidate(val bmp: Bitmap, val brightness: Float, val sharpness: Float)
        val candidates = withDet.mapNotNull { (bmp, d) ->
            val buf = 0.1f * maxOf(d.w, d.h)
            val cx = d.x + d.w/2f
            val cy = d.y + d.h/2f
            var half = maxOf(d.w, d.h)/2f + buf
            half = min(half, INPUT_SIZE/2f)
            val size = (half*2).toInt()

            val left = (cx-half).toInt().coerceIn(0, INPUT_SIZE-size)
            val top  = (cy-half).toInt().coerceIn(0, INPUT_SIZE-size)
            val crop = Bitmap.createBitmap(bmp, left, top, size, size)

            // Make sure the cropped region is sufficiently bright and in focus
            val bVal = avgBrightness(crop)
            val sVal = computeGradientSharpness(crop)
            // More strict conditions for actual photo
            if (bVal <= 1.2f*BRIGHTNESS_THRESHOLD || sVal <= 1.3f*BLUR_VAR_THRESHOLD) null
            else Candidate(crop, bVal, sVal)
        }

        // If no captured frames work, let user know what the issue is via feedback
        if (candidates.isEmpty()) {
            takePhotoInProgress = false
            val anyBright = withDet.any { (bmp, _) -> avgBrightness(bmp)>BRIGHTNESS_THRESHOLD }
            val anySharp = withDet.any { (bmp, _) -> computeGradientSharpness(bmp)>1.2f*BLUR_VAR_THRESHOLD }
            val msg = when {
                !anyBright && !anySharp -> "All shots failed brightness & focus"
                !anySharp               -> "All shots failed focus"
                !anyBright              -> "All shots failed brightness"
                else                     -> "Capture failed"
            }
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            return
        }

        // From the frames that meet all the conditions, save the best one
        // This really only ranks them by sharpness with a slight factor for brightness 40:1
        val best = candidates.maxByOrNull { it.brightness + 40f*it.sharpness }!!
        val dir = File(getExternalMediaDirs().first(), "androiddemoDemo").apply { if (!exists()) mkdirs() }
        val name = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".jpg"
        val file = File(dir, name)
        file.outputStream().use { best.bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null)

        // Reset so app can continue taking photos
        takePhotoInProgress = false
        Toast.makeText(this, "Best image saved", Toast.LENGTH_SHORT).show()
    }

    // Helper function to compute brightness
    private fun avgBrightness(b: Bitmap): Float {
        val px = IntArray(b.width*b.height)
        b.getPixels(px, 0, b.width, 0, 0, b.width, b.height)
        var sum = 0f
        for (p in px) {
            val r = (p shr 16) and 0xFF
            val g = (p shr 8)  and 0xFF
            val bl= (p      ) and 0xFF
            sum += (r+g+bl)/3f
        }
        return sum/px.size/255f
    }

    // Helper function to compute focus
    private fun computeGradientSharpness(bmp: Bitmap): Float {
        val w = bmp.width; val h = bmp.height
        val px = IntArray(w*h).also { bmp.getPixels(it,0,w,0,0,w,h) }
        val lum = FloatArray(px.size) { i -> ((px[i] shr 16) and 0xFF + (px[i] shr 8) and 0xFF + (px[i]) and 0xFF)/(3f*255f) }
        var sum=0f; var c=0
        for (y in 1 until h-1) for (x in 1 until w-1) {
            val i = y*w+x
            val dx = lum[i+1]-lum[i-1]
            val dy = lum[i+w]-lum[i-w]
            sum += abs(dx)+abs(dy); c++
        }
        return if (c>0) sum/c else 0f
    }

    // Used for UI
    private fun updateStatus(view: TextView, ok: Boolean, label: String) {
        view.text = (if (ok) "✓ " else "✗ ") + label
        view.setTextColor(if (ok) Color.GREEN else Color.RED)
    }
}
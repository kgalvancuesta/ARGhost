# Assets Upload Guide - ARGhost Fitness App

## 📁 Directory Structure

```
iOSdemo/iOSdemo/
├── Assets.xcassets/
│   └── WorkoutImages/
│       ├── squats.imageset/
│       │   ├── Contents.json
│       │   └── squats.jpg          ← PUT YOUR SQUATS IMAGE HERE
│       ├── pullups.imageset/
│       │   ├── Contents.json
│       │   └── pullups.jpg         ← PUT YOUR PULL-UPS IMAGE HERE
│       └── shoulderpress.imageset/
│           ├── Contents.json
│           └── shoulderpress.jpg   ← PUT YOUR SHOULDER PRESS IMAGE HERE
│
└── Resources/
    └── ProfessionalVideos/
        ├── squats_professional.mp4         ← PUT YOUR SQUATS VIDEO HERE
        ├── pullups_professional.mp4        ← PUT YOUR PULL-UPS VIDEO HERE
        └── shoulderpress_professional.mp4  ← PUT YOUR SHOULDER PRESS VIDEO HERE
```

---

## 🖼️ WORKOUT IMAGES (Thumbnails for Horizontal Scroll)

### Where to Upload:
Place your workout thumbnail images in these exact locations:

1. **Squats Image:**
   ```
   iOSdemo/iOSdemo/Assets.xcassets/WorkoutImages/squats.imageset/squats.jpg
   ```

2. **Pull-ups Image:**
   ```
   iOSdemo/iOSdemo/Assets.xcassets/WorkoutImages/pullups.imageset/pullups.jpg
   ```

3. **Shoulder Press Image:**
   ```
   iOSdemo/iOSdemo/Assets.xcassets/WorkoutImages/shoulderpress.imageset/shoulderpress.jpg
   ```

### Image Specifications:
- **Format:** JPG or PNG
- **Recommended Size:** 400x400 pixels (square) or 600x600 pixels
- **Aspect Ratio:** Square (1:1) works best
- **File Names:** MUST be exactly as shown above (lowercase)
- **Content:** Clear photo showing the exercise being performed

### File Naming Rules:
- ✅ `squats.jpg` or `squats.png`
- ✅ `pullups.jpg` or `pullups.png`
- ✅ `shoulderpress.jpg` or `shoulderpress.png`
- ❌ NOT `Squats.jpg` (wrong capitalization)
- ❌ NOT `squats_image.jpg` (wrong name)

**Note:** If you use PNG instead of JPG, update the `Contents.json` file in each imageset folder to change `"squats.jpg"` to `"squats.png"`, etc.

---

## 🎥 PROFESSIONAL WORKOUT VIDEOS

### Where to Upload:
Place your professional workout demonstration videos here:

```
iOSdemo/iOSdemo/Resources/ProfessionalVideos/
```

### Required Video Files:
1. `squats_professional.mp4`
2. `pullups_professional.mp4`
3. `shoulderpress_professional.mp4`

### Video Specifications:
- **Format:** MP4 (H.264 codec)
- **Resolution:**
  - Portrait: 1080x1920 (recommended for mobile)
  - Landscape: 1920x1080
- **Duration:** 30-60 seconds per exercise
- **Frame Rate:** 30fps minimum (60fps recommended)
- **Quality:** High definition, well-lit
- **Background:** Neutral/simple (better for pose detection)
- **Content:** Clear demonstration of proper form

### File Naming Rules:
- ✅ `squats_professional.mp4` (exact name required)
- ✅ `pullups_professional.mp4` (exact name required)
- ✅ `shoulderpress_professional.mp4` (exact name required)
- ❌ NOT `Squats_Professional.mp4` (wrong capitalization)
- ❌ NOT `squats.mp4` (missing "_professional")
- ❌ NOT `squats_professional.mov` (wrong format)

---

## 🔧 After Uploading Files

### Step 1: Verify File Locations
Run these commands from the project root to verify files are in the correct locations:

```bash
# Check workout images
ls -la iOSdemo/iOSdemo/Assets.xcassets/WorkoutImages/*/

# Check professional videos
ls -la iOSdemo/iOSdemo/Resources/ProfessionalVideos/
```

### Step 2: Add Files to Xcode Project (Important!)
**On macOS with Xcode:**

1. Open the project:
   ```bash
   cd iOSdemo
   open iOSdemo.xcodeproj
   ```

2. In Xcode, the workout images should automatically appear in Assets.xcassets

3. For videos, you need to add them to the project:
   - Right-click on the project navigator
   - Select "Add Files to iOSdemo..."
   - Navigate to `Resources/ProfessionalVideos/`
   - Select all three `.mp4` files
   - **Important:** Check "Copy items if needed"
   - **Important:** Check the "iOSdemo" target
   - Click "Add"

4. Verify files are added:
   - Select each video file in the project navigator
   - Check the "Target Membership" panel on the right
   - Ensure "iOSdemo" is checked

### Step 3: Build and Test
```bash
# In Xcode
Cmd+B  # Build
Cmd+R  # Run on simulator or device
```

---

## 📝 What Happens If You Don't Upload Files?

### Missing Workout Images:
- The app will show a **placeholder gradient with an SF Symbol icon**
- Text will say "Add Image" on the card
- The app will still function normally

### Missing Professional Videos:
- Partner mode will show a **"Video Not Available"** message
- The app will display: "Add [filename] to Resources"
- Alone mode will still work (uses live camera only)

---

## 🎨 Quick Summary

| Asset Type | Location | File Names | Required? |
|------------|----------|------------|-----------|
| Workout Images | `Assets.xcassets/WorkoutImages/*/` | `squats.jpg`, `pullups.jpg`, `shoulderpress.jpg` | Optional (has fallback) |
| Professional Videos | `Resources/ProfessionalVideos/` | `*_professional.mp4` | Optional (has fallback) |

---

## ✅ Checklist

- [ ] Upload squats.jpg to squats.imageset folder
- [ ] Upload pullups.jpg to pullups.imageset folder
- [ ] Upload shoulderpress.jpg to shoulderpress.imageset folder
- [ ] Upload squats_professional.mp4 to Resources/ProfessionalVideos/
- [ ] Upload pullups_professional.mp4 to Resources/ProfessionalVideos/
- [ ] Upload shoulderpress_professional.mp4 to Resources/ProfessionalVideos/
- [ ] Add video files to Xcode project target
- [ ] Build and test the app

---

## 💡 Tips

1. **Use high-quality images** - They'll be displayed at 200x200 points on screen
2. **Keep videos under 60 seconds** - Shorter loops are better for demonstration
3. **Test on a real device** - Camera features won't work in simulator
4. **Portrait orientation recommended** - Videos should be shot vertically for mobile viewing
5. **Good lighting is crucial** - Helps with both visual quality and pose detection

---

Need help? Check the README.md in the Resources folder for more details!

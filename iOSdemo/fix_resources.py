#!/usr/bin/env python3
"""
Fix resource bundling by adding a proper Resources build phase.
"""
import re

project_path = "iOSdemo.xcodeproj/project.pbxproj"

with open(project_path, 'r') as f:
    content = f.read()

# Step 1: Add file references in PBXFileReference section
file_refs = """		7FRESOURCE1234567890ABC /* squat_hmm_model.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = squat_hmm_model.json; sourceTree = "<group>"; };
		7FRESOURCE1234567890DEF /* error_squat.wav */ = {isa = PBXFileReference; lastKnownFileType = audio.wav; path = error_squat.wav; sourceTree = "<group>"; };
		7FRESOURCE1234567890GHI /* correct_squat.wav */ = {isa = PBXFileReference; lastKnownFileType = audio.wav; path = correct_squat.wav; sourceTree = "<group>"; };
"""

# Find the end of PBXFileReference section and add before it
file_ref_end = content.find("/* End PBXFileReference section */")
if file_ref_end > 0:
    content = content[:file_ref_end] + file_refs + content[file_ref_end:]
    print("✅ Added file references")

# Step 2: Add build files in PBXBuildFile section
build_files = """		7FBUILDFILE1234567890AB /* squat_hmm_model.json in Resources */ = {isa = PBXBuildFile; fileRef = 7FRESOURCE1234567890ABC /* squat_hmm_model.json */; };
		7FBUILDFILE1234567890CD /* error_squat.wav in Resources */ = {isa = PBXBuildFile; fileRef = 7FRESOURCE1234567890DEF /* error_squat.wav */; };
		7FBUILDFILE1234567890EF /* correct_squat.wav in Resources */ = {isa = PBXBuildFile; fileRef = 7FRESOURCE1234567890GHI /* correct_squat.wav */; };
"""

build_file_end = content.find("/* End PBXBuildFile section */")
if build_file_end > 0:
    content = content[:build_file_end] + build_files + content[build_file_end:]
    print("✅ Added build files")

# Step 3: Add a Resources build phase to the iOSdemo target
# Find the target's buildPhases array
target_match = re.search(
    r'(7F40AE1F2DFADF5600949E90 /\* iOSdemo \*/ = \{[^}]*buildPhases = \(\s*)',
    content,
    re.DOTALL
)

if target_match:
    # Add our new Resources phase UUID to the buildPhases array
    insert_pos = target_match.end()
    content = content[:insert_pos] + "\t\t\t\t7FRESOURCEPHASE123456 /* Resources */,\n" + content[insert_pos:]
    print("✅ Added Resources phase to target")

# Step 4: Add the PBXResourcesBuildPhase section before the existing Resources phases
resources_phase = """		7FRESOURCEPHASE123456 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				7FBUILDFILE1234567890AB /* squat_hmm_model.json in Resources */,
				7FBUILDFILE1234567890CD /* error_squat.wav in Resources */,
				7FBUILDFILE1234567890EF /* correct_squat.wav in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""

# Find where to insert the new Resources phase (before the existing ResourcesBuildPhase section)
resources_section = content.find("/* Begin PBXResourcesBuildPhase section */")
if resources_section > 0:
    # Insert after the section header
    insert_pos = content.find("\n", resources_section) + 1
    content = content[:insert_pos] + resources_phase + content[insert_pos:]
    print("✅ Added Resources build phase definition")

# Write the modified content
with open(project_path, 'w') as f:
    f.write(content)

print("\n✅ Project file updated successfully!")
print("\nNow run: xcodebuild -workspace iOSdemo.xcworkspace -scheme iOSdemo -configuration Debug -sdk iphonesimulator clean build")

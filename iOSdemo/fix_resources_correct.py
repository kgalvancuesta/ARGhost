#!/usr/bin/env python3
"""
Properly add resource files to the Xcode project by:
1. Adding PBXFileReference entries
2. Adding PBXBuildFile entries
3. Updating the CopyFiles build phase to include them
"""
import uuid

project_path = "iOSdemo.xcodeproj/project.pbxproj"

with open(project_path, 'r') as f:
    lines = f.readlines()

# Generate UUIDs
json_ref_id = uuid.uuid4().hex[:24].upper()
error_ref_id = uuid.uuid4().hex[:24].upper()
correct_ref_id = uuid.uuid4().hex[:24].upper()
json_build_id = uuid.uuid4().hex[:24].upper()
error_build_id = uuid.uuid4().hex[:24].upper()
correct_build_id = uuid.uuid4().hex[:24].upper()

# Find insertion points
for i, line in enumerate(lines):
    # Add file references before "/* End PBXFileReference section */"
    if "/* End PBXFileReference section */" in line:
        lines.insert(i, f"\t\t{json_ref_id} /* squat_hmm_model.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = squat_hmm_model.json; sourceTree = \"<group>\"; }};\n")
        lines.insert(i+1, f"\t\t{error_ref_id} /* error_squat.wav */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = error_squat.wav; sourceTree = \"<group>\"; }};\n")
        lines.insert(i+2, f"\t\t{correct_ref_id} /* correct_squat.wav */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = correct_squat.wav; sourceTree = \"<group>\"; }};\n")
        print("✅ Added PBXFileReference entries")
        break

# Find and update PBXBuildFile section
for i, line in enumerate(lines):
    if "/* End PBXBuildFile section */" in line:
        lines.insert(i, f"\t\t{json_build_id} /* squat_hmm_model.json in CopyFiles */ = {{isa = PBXBuildFile; fileRef = {json_ref_id} /* squat_hmm_model.json */; }};\n")
        lines.insert(i+1, f"\t\t{error_build_id} /* error_squat.wav in CopyFiles */ = {{isa = PBXBuildFile; fileRef = {error_ref_id} /* error_squat.wav */; }};\n")
        lines.insert(i+2, f"\t\t{correct_build_id} /* correct_squat.wav in CopyFiles */ = {{isa = PBXBuildFile; fileRef = {correct_ref_id} /* correct_squat.wav */; }};\n")
        print("✅ Added PBXBuildFile entries")
        break

# Find and update the CopyFiles phase
for i, line in enumerate(lines):
    if "7F3F93052DFB058C000D378D /* CopyFiles */" in line:
        # Find the files = ( line
        for j in range(i, min(i+10, len(lines))):
            if "files = (" in lines[j]:
                # Insert our files after this line
                lines.insert(j+1, f"\t\t\t\t{json_build_id} /* squat_hmm_model.json in CopyFiles */,\n")
                lines.insert(j+2, f"\t\t\t\t{error_build_id} /* error_squat.wav in CopyFiles */,\n")
                lines.insert(j+3, f"\t\t\t\t{correct_build_id} /* correct_squat.wav in CopyFiles */,\n")
                print("✅ Added files to CopyFiles build phase")
                break
        break

# Write back
with open(project_path, 'w') as f:
    f.writelines(lines)

print("\n✅ Project file updated!")
print(f"\nGenerated IDs:")
print(f"  JSON ref: {json_ref_id}")
print(f"  Error WAV ref: {error_ref_id}")
print(f"  Correct WAV ref: {correct_ref_id}")

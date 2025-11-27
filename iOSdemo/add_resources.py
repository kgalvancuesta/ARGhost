#!/usr/bin/env python3
"""
Add resource files explicitly to the Xcode project.
This is needed because PBXFileSystemSynchronizedRootGroup doesn't always include all file types.
"""
import re
import uuid

# Read the project file
project_path = "iOSdemo.xcodeproj/project.pbxproj"
with open(project_path, 'r') as f:
    content = f.read()

# Generate UUIDs for new entries
squat_json_file_ref = uuid.uuid4().hex[:24].upper()
error_wav_file_ref = uuid.uuid4().hex[:24].upper()
correct_wav_file_ref = uuid.uuid4().hex[:24].upper()
squat_json_build_file = uuid.uuid4().hex[:24].upper()
error_wav_build_file = uuid.uuid4().hex[:24].upper()
correct_wav_build_file = uuid.uuid4().hex[:24].upper()

# Find the PBXFileReference section and add our files
file_ref_section = re.search(r'(/\* Begin PBXFileReference section \*/.*?/\* End PBXFileReference section \*/)', content, re.DOTALL)
if file_ref_section:
    insert_pos = content.rfind('\n', 0, file_ref_section.end())

    new_refs = f"""		{squat_json_file_ref} /* squat_hmm_model.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = squat_hmm_model.json; sourceTree = "<group>"; }};
		{error_wav_file_ref} /* error_squat.wav */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = error_squat.wav; sourceTree = "<group>"; }};
		{correct_wav_file_ref} /* correct_squat.wav */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = correct_squat.wav; sourceTree = "<group>"; }};
"""
    content = content[:insert_pos] + new_refs + content[insert_pos:]

# Find the PBXBuildFile section and add our files to Copy Bundle Resources
build_file_section = re.search(r'(/\* Begin PBXBuildFile section \*/)', content)
if build_file_section:
    insert_pos = build_file_section.end()

    new_build_files = f"""
		{squat_json_build_file} /* squat_hmm_model.json in Resources */ = {{isa = PBXBuildFile; fileRef = {squat_json_file_ref} /* squat_hmm_model.json */; }};
		{error_wav_build_file} /* error_squat.wav in Resources */ = {{isa = PBXBuildFile; fileRef = {error_wav_file_ref} /* error_squat.wav */; }};
		{correct_wav_build_file} /* correct_squat.wav in Resources */ = {{isa = PBXBuildFile; fileRef = {correct_wav_file_ref} /* correct_squat.wav */; }};"""

    content = content[:insert_pos] + new_build_files + content[insert_pos:]

# Find the iOSdemo PBXFileSystemSynchronizedRootGroup and add explicit exceptions
sync_group = re.search(r'(7F40AE222DFADF5600949E90 /\* iOSdemo \*/ = \{[^}]+\})', content, re.DOTALL)
if sync_group:
    group_content = sync_group.group(1)
    # Replace the group to include explicit file references
    # We need to add children array to the synchronized group, or better yet, add files to CopyFiles phase
    pass

# Find the CopyFiles build phase and add our resources
# Looking for: 7F3F93052DFB058C000D378D /* CopyFiles */
copy_files = re.search(r'(7F3F93052DFB058C000D378D /\* CopyFiles \*/ = \{.*?files = \(\s*)(\);)', content, re.DOTALL)
if copy_files:
    insert_pos = copy_files.end(1)

    new_files = f"""				{squat_json_build_file} /* squat_hmm_model.json in Resources */,
				{error_wav_build_file} /* error_squat.wav in Resources */,
				{correct_wav_build_file} /* correct_squat.wav in Resources */,
"""
    content = content[:insert_pos] + new_files + "\t\t\t" + content[insert_pos:]

# Write back
with open(project_path, 'w') as f:
    f.write(content)

print(f"✅ Added resource files to project:")
print(f"   - squat_hmm_model.json ({squat_json_file_ref})")
print(f"   - error_squat.wav ({error_wav_file_ref})")
print(f"   - correct_squat.wav ({correct_wav_file_ref})")

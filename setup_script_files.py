import os
import shutil
import sys

# Avoid cp1252 crashes on non-ASCII media folder names (Windows console)
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(errors="replace")

source_folder = 'slideshow'

IMAGE_EXTENSIONS = ('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff')


def push_code_to_subdirectories(root_directory):
    """
    Pushes slideshow scripts into root and all subdirectories that contain image files.
    Args:
        root_directory (str): The path to the main directory to start scanning.
    """
    for dirpath, dirnames, filenames in os.walk(root_directory):
        if source_folder in dirpath:
            print(f"Ignoring pre-existing source folder '{source_folder}' "
                  f"subdirectories at {dirpath}!")
            continue

        image_files_in_current_dir = [
            filename for filename in filenames
            if filename.lower().endswith(IMAGE_EXTENSIONS)
        ]

        if image_files_in_current_dir:
            destination_folder = os.path.join(dirpath, os.path.basename(source_folder))
            try:
                shutil.copytree(source_folder, destination_folder, dirs_exist_ok=True)
                print(f"Src folder '{source_folder}' merged at: {dirpath}")
            except FileNotFoundError:
                print(f"Error: Source folder '{source_folder}' not found.")
            except Exception as e:
                print(f"An error occurred: {e}")
        else:
            print(f"No images found in directory '{dirpath}'. Skipping!")


if __name__ == '__main__':
    try:
        from setup_script_files_local import root_dirs
    except ImportError:
        # Edit root_dirs to your media library roots before running.
        root_dirs = [
            r'X:\media_root\collection_a',
            r'X:\media_root\collection_b',
        ]
        # Single-creator subtree example:
        # root_dirs = [r'D:\media\creator_name']
        # Multiple drive letters example:
        # root_dirs = [r'F:\media_a', r'E:\media_b', r'D:\media_c']
    for root_dir in root_dirs:
        if not os.path.isdir(root_dir):
            print(f"Root not found, skipping: {root_dir}")
            continue
        push_code_to_subdirectories(root_dir)

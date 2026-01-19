import py_compile
import zipfile
import os
import shutil
import sys
from pathlib import Path

def build_assets(input_py, output_dir):
    """
    Compiles input_py to bytecode and zips it as app_modules.zip in output_dir.
    """
    input_path = Path(input_py).resolve()
    output_path = Path(output_dir).resolve()
    
    if not input_path.exists():
        print(f"Error: Input file {input_path} does not exist")
        sys.exit(1)
        
    output_path.mkdir(parents=True, exist_ok=True)
    
    # 1. Compile to .pyc
    # We rename it to mimic the module name "image_processor'
    pyc_filename = "image_processor.pyc"
    temp_pyc = output_path / pyc_filename
    
    print(f"Compiling {input_path} -> {temp_pyc}...")
    try:
        py_compile.compile(input_path, cfile=str(temp_pyc), doraise=True, optimize=1)
    except Exception as e:
        print(f"Compilation failed: {e}")
        sys.exit(1)
        
    # 2. Create Zip
    zip_filename = output_path / "app_modules.zip"
    print(f"Creating {zip_filename}...")
    
    with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zf:
        # Add the .pyc file at the root of the zip
        zf.write(temp_pyc, arcname=pyc_filename)
        
    # 3. Cleanup temp .pyc
    if temp_pyc.exists():
        temp_pyc.unlink()
        
    print("Success! Created app_modules.zip")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python build_assets.py <input_py_file> <output_dir>")
        sys.exit(1)
        
    build_assets(sys.argv[1], sys.argv[2])

#!/usr/bin/env python3
"""
Planter Pressure - OPTIMIZED Image Processing Module

OPTIMIZATIONS:
1. Explicit memory cleanup after each operation
2. Process images in chunks for large files
3. No unnecessary copies
4. Garbage collection hints
5. Path-only I/O (no Base64)
"""

import os
import sys
import gc
import json
import tempfile
from datetime import datetime
from pathlib import Path

# =============================================================================
# CRITICAL: Add site-packages for embedded Python
# =============================================================================
SITE_PACKAGES = [
    r"C:\Users\adit\AppData\Local\Programs\Python\Python312\Lib\site-packages",
    r"C:\Users\adit\AppData\Local\Programs\Python\Python312\Lib",
]
for p in SITE_PACKAGES:
    if os.path.exists(p) and p not in sys.path:
        sys.path.insert(0, p)
# =============================================================================

try:
    from PIL import Image, ImageFilter, ImageEnhance, ImageDraw, ImageFont
    PIL_AVAILABLE = True
    PIL_ERROR = None
except ImportError as e:
    PIL_AVAILABLE = False
    PIL_ERROR = str(e)


class ImageProcessor:
    """Memory-efficient image processor."""

    SUPPORTED_FORMATS = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.tiff'}

    def __init__(self):
        self._font_cache = {}

    def _get_font(self, size):
        if size in self._font_cache:
            return self._font_cache[size]

        font_paths = [
            "C:\\Windows\\Fonts\\arial.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf",
        ]

        font = None
        for fp in font_paths:
            try:
                font = ImageFont.truetype(fp, size)
                break
            except:
                continue

        if font is None:
            font = ImageFont.load_default()

        # Limit cache size
        if len(self._font_cache) > 10:
            self._font_cache.clear()

        self._font_cache[size] = font
        return font

    def _validate_input(self, path):
        if not path:
            return False, "Empty path"
        if not os.path.exists(path):
            return False, "File not found: {}".format(path)
        if not os.path.isfile(path):
            return False, "Not a file: {}".format(path)

        ext = Path(path).suffix.lower()
        if ext not in self.SUPPORTED_FORMATS:
            return False, "Unsupported format: {}".format(ext)

        return True, ""

    def _generate_output_path(self, input_path, output_dir=None):
        if output_dir is None:
            output_dir = tempfile.gettempdir()

        os.makedirs(output_dir, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        name = Path(input_path).stem
        return os.path.join(output_dir, "processed_{}_{}.png".format(name, ts))

    def process(self, input_path, output_dir=None):
        """
        Process image with explicit memory management.
        Returns dict with status and output path.
        """
        if not PIL_AVAILABLE:
            return {
                "status": "error",
                "error": "Pillow not available: {}".format(PIL_ERROR)
            }

        valid, err = self._validate_input(input_path)
        if not valid:
            return {"status": "error", "error": err}

        img = None
        try:
            # Load image
            img = Image.open(input_path)
            original_size = img.size
            original_mode = img.mode

            # Convert to RGB if needed
            if img.mode in ('RGBA', 'LA', 'P'):
                bg = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'RGBA':
                    bg.paste(img, mask=img.split()[3])
                elif img.mode == 'LA':
                    bg.paste(img, mask=img.split()[1])
                else:
                    bg.paste(img)
                img.close()  # Close original
                img = bg
            elif img.mode != 'RGB':
                new_img = img.convert('RGB')
                img.close()
                img = new_img

            # Apply filters (in-place where possible)
            # Sharpness
            enhancer = ImageEnhance.Sharpness(img)
            new_img = enhancer.enhance(1.5)
            img.close()
            img = new_img

            # Edge enhance
            new_img = img.filter(ImageFilter.EDGE_ENHANCE)
            img.close()
            img = new_img

            # Contrast
            enhancer = ImageEnhance.Contrast(img)
            new_img = enhancer.enhance(1.2)
            img.close()
            img = new_img

            # Smooth
            new_img = img.filter(ImageFilter.SMOOTH)
            img.close()
            img = new_img

            # Add text overlay
            draw = ImageDraw.Draw(img)
            width, height = img.size

            # TITLE size font (10% of image height - doubled from before)
            font_size = max(24, min(300, int(height * 0.10)))
            font = self._get_font(font_size)

            text = "PLANTER PRESSURE DEMO"
            bbox = draw.textbbox((0, 0), text, font=font)
            text_w = bbox[2] - bbox[0]
            text_h = bbox[3] - bbox[1]

            x = (width - text_w) // 2
            y = (height - text_h) // 2

            # Shadow (black, thicker for title)
            shadow_off = max(3, font_size // 20)
            for ox in range(-shadow_off, shadow_off + 1):
                for oy in range(-shadow_off, shadow_off + 1):
                    if ox != 0 or oy != 0:
                        draw.text((x + ox, y + oy), text, font=font, fill=(0, 0, 0))

            # Main text - RED color
            draw.text((x, y), text, font=font, fill=(255, 0, 0))

            del draw  # Release draw object

            # Save output
            output_path = self._generate_output_path(input_path, output_dir)
            img.save(output_path, format='PNG', optimize=True)

            output_size = os.path.getsize(output_path)

            # Close image before returning
            img.close()
            img = None

            # Force garbage collection
            gc.collect()

            return {
                "status": "success",
                "output_image_path": output_path,
                "metadata": {
                    "input_path": input_path,
                    "original_size": list(original_size),
                    "original_mode": original_mode,
                    "output_size_bytes": output_size,
                    "processed_at": datetime.now().isoformat()
                }
            }

        except Exception as e:
            return {
                "status": "error",
                "error": "Processing failed: {}".format(str(e)),
                "error_type": type(e).__name__
            }
        finally:
            # ALWAYS cleanup
            if img is not None:
                try:
                    img.close()
                except:
                    pass
            gc.collect()


# Global instance
_processor = None

def get_processor():
    global _processor
    if _processor is None:
        _processor = ImageProcessor()
    return _processor


def process_image_json(input_json):
    """
    Entry point for C++ engine.

    Input:  {"input_image_path": "C:/path/to/image.png"}
    Output: {"status": "success", "output_image_path": "C:/path/output.png"}
    """
    try:
        data = json.loads(input_json)
    except Exception as e:
        return json.dumps({"status": "error", "error": "Invalid JSON: {}".format(str(e))})

    input_path = data.get("input_image_path")
    if not input_path:
        return json.dumps({"status": "error", "error": "Missing input_image_path"})

    output_dir = data.get("output_dir")

    processor = get_processor()
    result = processor.process(input_path, output_dir)

    return json.dumps(result)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="Input image path")
    parser.add_argument("-o", "--output-dir", help="Output directory")
    args = parser.parse_args()

    result = process_image_json(json.dumps({
        "input_image_path": args.input,
        "output_dir": args.output_dir
    }))
    print(result)
import argparse
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("Missing dependencies, run: pip install pillow numpy")

CACHE_NAME = ".sprite_cache.json"
SUBTEXTURE = re.compile(r"<SubTexture\b[^>]*>")
ATTRIBUTE = r'(\b{}\s*=\s*")(-?\d+(?:\.\d+)?)(")'


def file_hash(path):
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_attribute(tag, name):
    match = re.search(ATTRIBUTE.format(name), tag)
    return float(match.group(2)) if match else None


def write_attribute(tag, name, value):
    return re.sub(ATTRIBUTE.format(name), lambda m: m.group(1) + str(value) + m.group(3), tag, count=1)


def atlas_bounds(xml_text, width, height):
    left, top, right, bottom = width, height, 0, 0
    found = False
    for tag in SUBTEXTURE.findall(xml_text):
        x = read_attribute(tag, "x")
        y = read_attribute(tag, "y")
        w = read_attribute(tag, "width")
        h = read_attribute(tag, "height")
        if None in (x, y, w, h):
            return None
        if re.search(r'\brotated\s*=\s*"true"', tag):
            w, h = h, w
        found = True
        left = min(left, int(x))
        top = min(top, int(y))
        right = max(right, int(x + w))
        bottom = max(bottom, int(y + h))
    if not found:
        return None
    return max(0, left), max(0, top), min(width, right), min(height, bottom)


def shift_atlas(xml_text, dx, dy):
    def replace(match):
        tag = match.group(0)
        tag = write_attribute(tag, "x", int(read_attribute(tag, "x")) - dx)
        return write_attribute(tag, "y", int(read_attribute(tag, "y")) - dy)

    return SUBTEXTURE.sub(replace, xml_text)


def trim_atlas(image, xml_path):
    with open(xml_path, "r", encoding="utf-8-sig") as handle:
        xml_text = handle.read()

    rgba = image.convert("RGBA")
    alpha_box = rgba.getchannel("A").getbbox()
    frame_box = atlas_bounds(xml_text, image.width, image.height)
    if alpha_box is None or frame_box is None:
        return image, None

    box = (
        min(alpha_box[0], frame_box[0]),
        min(alpha_box[1], frame_box[1]),
        max(alpha_box[2], frame_box[2]),
        max(alpha_box[3], frame_box[3]),
    )
    if box == (0, 0, image.width, image.height):
        return image, None

    cropped = image.crop(box)
    return cropped, shift_atlas(xml_text, box[0], box[1])


def to_palette(image):
    rgba = np.asarray(image.convert("RGBA"))
    packed = rgba.view(np.uint32).reshape(-1)
    colors, inverse = np.unique(packed, return_inverse=True)
    if len(colors) > 256:
        return None

    palette_rgba = colors.view(np.uint8).reshape(-1, 4)
    indexed = Image.fromarray(inverse.reshape(rgba.shape[0], rgba.shape[1]).astype(np.uint8), "P")
    indexed.putpalette(palette_rgba[:, :3].flatten().tolist())
    if (palette_rgba[:, 3] < 255).any():
        indexed.info["transparency"] = bytes(palette_rgba[:, 3].tolist())
    return indexed


def quantize(image, colors):
    rgba = image.convert("RGBA")
    return rgba.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)


def psnr(original, candidate):
    a = np.asarray(original.convert("RGBA"), dtype=np.float64)
    b = np.asarray(candidate.convert("RGBA"), dtype=np.float64)
    mse = np.mean((a - b) ** 2)
    if mse == 0:
        return float("inf")
    return 10 * np.log10((255 ** 2) / mse)


def encode(image):
    buffer = io.BytesIO()
    params = {"optimize": True, "compress_level": 9}
    if "transparency" in image.info:
        params["transparency"] = image.info["transparency"]
    image.save(buffer, "PNG", **params)
    return buffer.getvalue()


def candidates(image, options):
    mode = image.mode
    base = image

    if mode in ("I;16", "I", "F") or (mode not in ("RGB", "RGBA", "L", "LA", "P")):
        base = image.convert("RGBA")

    yield base

    if base.mode in ("RGBA", "LA"):
        alpha = base.getchannel("A")
        if alpha.getextrema() == (255, 255):
            yield base.convert("RGB" if base.mode == "RGBA" else "L")

    if base.mode != "P":
        palette = to_palette(base)
        if palette is not None:
            yield palette

    if options.quantize and base.mode != "P":
        lossy = quantize(base, options.colors)
        if options.min_psnr <= 0 or psnr(base, lossy) >= options.min_psnr:
            yield lossy


def run_oxipng(path, level):
    try:
        subprocess.run(["oxipng", "-o", str(level), "--strip", "safe", "-q", path], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        pass


def store_key(path, xml_path, options):
    digest = hashlib.sha1(settings_of(options).encode())
    with open(path, "rb") as handle:
        digest.update(handle.read())
    if options.trim and os.path.exists(xml_path):
        with open(xml_path, "rb") as handle:
            digest.update(handle.read())
    return digest.hexdigest()


def settings_of(options):
    return f"{options.trim}:{options.quantize}:{options.colors}:{options.min_psnr}:{options.oxipng}:{options.oxipng_level}:{options.max_size}"


def restore_from_store(path, xml_path, folder):
    stored_png = os.path.join(folder, "sprite.png")
    if not os.path.exists(stored_png):
        return None
    shutil.copyfile(stored_png, path)
    stored_xml = os.path.join(folder, "atlas.xml")
    if os.path.exists(stored_xml):
        shutil.copyfile(stored_xml, xml_path)
    stored_size = os.path.join(folder, "size.json")
    if os.path.exists(stored_size):
        with open(stored_size, "r", encoding="utf-8") as handle:
            return tuple(json.load(handle))
    return ()


def save_to_store(path, xml_path, folder, has_xml, original_size):
    os.makedirs(folder, exist_ok=True)
    shutil.copyfile(path, os.path.join(folder, "sprite.tmp"))
    if has_xml:
        shutil.copyfile(xml_path, os.path.join(folder, "atlas.xml"))
    if original_size:
        with open(os.path.join(folder, "size.json"), "w", encoding="utf-8") as handle:
            json.dump(list(original_size), handle)
    os.replace(os.path.join(folder, "sprite.tmp"), os.path.join(folder, "sprite.png"))


def optimize(path, options):
    xml_path = os.path.splitext(path)[0] + ".xml"
    if options.store and not options.dry_run:
        key = store_key(path, xml_path, options)
        folder = os.path.join(options.store, key[:2], key)
        before = os.path.getsize(path)
        restored = restore_from_store(path, xml_path, folder)
        if restored is not None:
            return path, before, os.path.getsize(path), True, key, True, restored or None
        result = optimize_file(path, xml_path, options)
        save_to_store(path, xml_path, folder, result[4], result[5])
        return result[0], result[1], result[2], result[3], key, False, result[5]
    result = optimize_file(path, xml_path, options)
    return result[0], result[1], result[2], result[3], None, False, result[5]


def original_size_bytes(path):
    return os.path.getsize(path)


def optimize_file(path, xml_path, options):
    file_size = os.path.getsize(path)
    new_xml = None

    with Image.open(path) as source:
        source.load()
        image = source

        if options.trim and os.path.exists(xml_path):
            image, new_xml = trim_atlas(image, xml_path)

        original_size = None
        if options.max_size > 0 and max(image.size) > options.max_size:
            original_size = image.size
            factor = options.max_size / max(image.size)
            target = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
            mode = "RGBA" if image.mode in ("RGBA", "LA", "P", "PA") else "RGB"
            image = image.convert(mode).resize(target, Image.Resampling.LANCZOS)

        best = None
        for candidate in candidates(image, options):
            data = encode(candidate)
            if best is None or len(data) < len(best):
                best = data

    if best is None:
        return path, original_size_bytes(path), original_size_bytes(path), False, False, None

    if new_xml is None and original_size is None and len(best) >= file_size:
        if options.oxipng and not options.dry_run:
            run_oxipng(path, options.oxipng_level)
        return path, file_size, os.path.getsize(path), False, False, None

    if options.dry_run:
        return path, file_size, len(best), True, new_xml is not None, original_size

    temp_path = path + ".tmp"
    with open(temp_path, "wb") as handle:
        handle.write(best)
    os.replace(temp_path, path)

    if new_xml is not None:
        with open(xml_path, "w", encoding="utf-8", newline="") as handle:
            handle.write(new_xml)

    if options.oxipng:
        run_oxipng(path, options.oxipng_level)

    return path, file_size, os.path.getsize(path), True, new_xml is not None, original_size


def collect(roots, excludes):
    files = []
    for root in roots:
        if os.path.isfile(root) and root.lower().endswith(".png"):
            files.append(root)
            continue
        for folder, _, names in os.walk(root):
            for name in names:
                if not name.lower().endswith(".png"):
                    continue
                path = os.path.join(folder, name)
                relative = path.replace("\\", "/")
                if any(fnmatch.fnmatch(relative, pattern) for pattern in excludes):
                    continue
                files.append(path)
    return sorted(files)


def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_cache(path, cache):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(cache, handle, indent=1, sort_keys=True)


def runtime_path(path):
    relative = os.path.relpath(path).replace("\\", "/")
    if relative.startswith("assets/preload/"):
        return "assets/" + relative[len("assets/preload/"):]
    return relative


def prune_store(store, used_keys):
    removed = 0
    if not os.path.isdir(store):
        return removed
    for prefix in os.listdir(store):
        prefix_path = os.path.join(store, prefix)
        if not os.path.isdir(prefix_path):
            continue
        for key in os.listdir(prefix_path):
            if key not in used_keys:
                shutil.rmtree(os.path.join(prefix_path, key), ignore_errors=True)
                removed += 1
        if not os.listdir(prefix_path):
            os.rmdir(prefix_path)
    return removed


def human(size):
    for unit in ("B", "KB", "MB", "GB"):
        if abs(size) < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def main():
    parser = argparse.ArgumentParser(description="Optimize PNG sprites and Sparrow atlases for Mario Madness")
    parser.add_argument("paths", nargs="*", default=["assets"], help="Folders or PNG files to optimize")
    parser.add_argument("--exclude", action="append", default=[], help="Glob pattern to skip, can be repeated")
    parser.add_argument("--trim", action="store_true", help="Crop unused transparent space from Sparrow atlases and fix their XML")
    parser.add_argument("--quantize", action="store_true", help="Allow lossy palette reduction")
    parser.add_argument("--colors", type=int, default=256, help="Palette size used by --quantize")
    parser.add_argument("--min-psnr", type=float, default=38.0, help="Minimum quality for --quantize, 0 disables the check")
    parser.add_argument("--oxipng", action="store_true", help="Run oxipng after Pillow when it is installed")
    parser.add_argument("--oxipng-level", type=int, default=4, help="oxipng optimization level")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1, help="Parallel workers")
    parser.add_argument("--dry-run", action="store_true", help="Only report what would be saved")
    parser.add_argument("--no-cache", action="store_true", help="Ignore the cache of already optimized files")
    parser.add_argument("--cache", default=CACHE_NAME, help="Cache file path")
    parser.add_argument("--store", help="Folder that keeps optimized results keyed by the original file, used to skip work between builds")
    parser.add_argument("--prune", action="store_true", help="Remove results from --store that were not used in this run")
    parser.add_argument("--max-size", type=int, default=0, help="Downscale textures bigger than this, the game keeps them at their original size on screen")
    parser.add_argument("--scale-manifest", help="JSON file that receives the original size of every downscaled texture")
    options = parser.parse_args()

    if options.oxipng and shutil.which("oxipng") is None:
        print("oxipng was not found, continuing with Pillow only")
        options.oxipng = False

    files = collect(options.paths, options.exclude)
    cache = {} if options.no_cache else load_cache(options.cache)
    settings = settings_of(options)

    pending = []
    for path in files:
        key = path.replace("\\", "/")
        entry = cache.get(key)
        if entry and entry.get("settings") == settings and entry.get("hash") == file_hash(path):
            continue
        pending.append(path)

    print(f"{len(files)} sprites found, {len(pending)} to process")

    total_before = 0
    total_after = 0
    changed = 0
    failed = 0
    reused = 0
    used_keys = set()
    scaled = {}
    if options.scale_manifest and os.path.exists(options.scale_manifest):
        try:
            with open(options.scale_manifest, "r", encoding="utf-8") as handle:
                scaled = json.load(handle)
        except (OSError, ValueError):
            scaled = {}

    with ProcessPoolExecutor(max_workers=max(1, options.jobs)) as pool:
        jobs = {pool.submit(optimize, path, options): path for path in pending}
        for index, job in enumerate(as_completed(jobs), 1):
            path = jobs[job]
            try:
                _, before, after, modified, key, from_store, texture_size = job.result()
            except Exception as error:
                failed += 1
                print(f"[{index}/{len(pending)}] failed {path}: {error}")
                continue

            total_before += before
            total_after += after
            if key is not None:
                used_keys.add(key)
            runtime_id = runtime_path(path)
            if texture_size:
                scaled[runtime_id] = [int(texture_size[0]), int(texture_size[1])]
            else:
                scaled.pop(runtime_id, None)
            if from_store:
                reused += 1
            elif modified:
                changed += 1
                print(f"[{index}/{len(pending)}] {path} {human(before)} -> {human(after)}")

            if not options.dry_run:
                cache[path.replace("\\", "/")] = {"hash": file_hash(path), "settings": settings}

    if not options.dry_run and not options.no_cache:
        save_cache(options.cache, cache)

    if options.scale_manifest and not options.dry_run:
        folder = os.path.dirname(options.scale_manifest)
        if folder:
            os.makedirs(folder, exist_ok=True)
        with open(options.scale_manifest, "w", encoding="utf-8") as handle:
            json.dump(scaled, handle, indent=1, sort_keys=True)
        print(f"{len(scaled)} downscaled textures written to {options.scale_manifest}")

    if options.store and options.prune and not options.dry_run and failed == 0:
        removed = prune_store(options.store, used_keys)
        if removed:
            print(f"Removed {removed} unused results from the store")

    saved = total_before - total_after
    percent = (saved / total_before * 100) if total_before else 0
    print(f"Done: {changed} optimized, {reused} restored from the store, {failed} failed, saved {human(saved)} ({percent:.1f}%)")


if __name__ == "__main__":
    main()

import argparse
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("Missing dependencies, run: pip install pillow numpy pyoxipng")

try:
    import oxipng
except ImportError:
    oxipng = None

VERSION = "6"
CACHE_NAME = ".sprite_cache.json"
SUBTEXTURE = re.compile(r"<SubTexture\b[^>]*>")
NUMBER = r'(\b{}\s*=\s*")(-?\d+(?:\.\d+)?)(")'
GRID_LOAD = re.compile(r"loadGraphic\(\s*Paths\.image\(\s*['\"]([^'\"]+)['\"][^)]*\)\s*,\s*true")
PADDING = 2
MAXRECTS_LIMIT = 160
AUDIO_BITRATES = {3: 112, 4: 128, 5: 160, 6: 192, 7: 224, 8: 256}

Image.MAX_IMAGE_PIXELS = None


def file_hash(path):
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_number(tag, name):
    match = re.search(NUMBER.format(name), tag)
    return float(match.group(2)) if match else None


def write_number(tag, name, value):
    pattern = re.compile(NUMBER.format(name))
    if pattern.search(tag):
        return pattern.sub(lambda m: m.group(1) + str(int(value)) + m.group(3), tag, count=1)
    end = tag.rstrip()
    closing = "/>" if end.endswith("/>") else ">"
    body = end[: -len(closing)].rstrip()
    return f'{body} {name}="{int(value)}"{closing}'


def read_frames(xml_text, width, height):
    frames = []
    for tag in SUBTEXTURE.findall(xml_text):
        if re.search(r'\brotated\s*=\s*"true"', tag):
            return None
        values = {}
        for name in ("x", "y", "width", "height", "frameX", "frameY", "frameWidth", "frameHeight"):
            value = read_number(tag, name)
            if value is not None and value != int(value):
                return None
            values[name] = None if value is None else int(value)
        if None in (values["x"], values["y"], values["width"], values["height"]):
            return None
        if values["width"] <= 0 or values["height"] <= 0:
            return None
        if values["x"] < 0 or values["y"] < 0 or values["x"] + values["width"] > width or values["y"] + values["height"] > height:
            return None
        frames.append((tag, values))
    return frames or None


def atlas_bounds(frames, width, height):
    left, top, right, bottom = width, height, 0, 0
    for _, v in frames:
        left = min(left, v["x"])
        top = min(top, v["y"])
        right = max(right, v["x"] + v["width"])
        bottom = max(bottom, v["y"] + v["height"])
    return left, top, right, bottom


def trim_atlas(pixels, xml_text, frames):
    height, width = pixels.shape[:2]
    alpha = pixels[:, :, 3]
    rows = np.flatnonzero(alpha.any(axis=1))
    cols = np.flatnonzero(alpha.any(axis=0))
    if rows.size == 0:
        return None
    left, top, right, bottom = atlas_bounds(frames, width, height)
    box = (min(cols[0], left), min(rows[0], top), max(cols[-1] + 1, right), max(rows[-1] + 1, bottom))
    if box == (0, 0, width, height):
        return None

    def replace(match):
        tag = match.group(0)
        tag = write_number(tag, "x", read_number(tag, "x") - box[0])
        return write_number(tag, "y", read_number(tag, "y") - box[1])

    return pixels[box[1]:box[3], box[0]:box[2]], SUBTEXTURE.sub(replace, xml_text)


def trim_region(region):
    alpha = region[:, :, 3]
    rows = np.flatnonzero(alpha.any(axis=1))
    if rows.size == 0:
        return 0, 0, 1, 1
    cols = np.flatnonzero(alpha.any(axis=0))
    return int(cols[0]), int(rows[0]), int(cols[-1] + 1), int(rows[-1] + 1)


class Skyline:
    def __init__(self, width):
        self.width = width
        self.nodes = [[0, 0, width]]
        self.height = 0

    def find(self, w, h):
        best = None
        for index in range(len(self.nodes)):
            x = self.nodes[index][0]
            if x + w > self.width:
                break
            y = 0
            remaining = w
            cursor = index
            while remaining > 0:
                node = self.nodes[cursor]
                y = max(y, node[1])
                remaining -= node[2]
                cursor += 1
            score = (y + h, x)
            if best is None or score < best[0]:
                best = (score, index, x, y)
        return best

    def place(self, w, h):
        found = self.find(w, h)
        if found is None:
            return None
        _, index, x, y = found
        self.nodes.insert(index, [x, y + h, w])
        cursor = index + 1
        while cursor < len(self.nodes):
            node = self.nodes[cursor]
            previous = self.nodes[cursor - 1]
            overlap = previous[0] + previous[2] - node[0]
            if overlap <= 0:
                break
            node[0] += overlap
            node[2] -= overlap
            if node[2] <= 0:
                self.nodes.pop(cursor)
            else:
                break
        merged = [self.nodes[0]]
        for node in self.nodes[1:]:
            if node[1] == merged[-1][1]:
                merged[-1][2] += node[2]
            else:
                merged.append(node)
        self.nodes = merged
        self.height = max(self.height, y + h)
        return x, y


def skyline_pack(sizes, order, width, limit):
    skyline = Skyline(width)
    spots = [None] * len(sizes)
    for i in order:
        spot = skyline.place(sizes[i][0] + PADDING, sizes[i][1] + PADDING)
        if spot is None or skyline.height > limit:
            return None
        spots[i] = spot
    return spots


def maxrects_pack(sizes, order, width, limit):
    free = [(0, 0, width, limit)]
    spots = [None] * len(sizes)
    for i in order:
        w = sizes[i][0] + PADDING
        h = sizes[i][1] + PADDING
        best = None
        for fx, fy, fw, fh in free:
            if w <= fw and h <= fh:
                score = (fy + h, min(fw - w, fh - h), fx)
                if best is None or score < best[0]:
                    best = (score, fx, fy)
        if best is None:
            return None
        _, x, y = best
        spots[i] = (x, y)
        split = []
        for rect in free:
            fx, fy, fw, fh = rect
            if x >= fx + fw or x + w <= fx or y >= fy + fh or y + h <= fy:
                split.append(rect)
                continue
            if x > fx:
                split.append((fx, fy, x - fx, fh))
            if x + w < fx + fw:
                split.append((x + w, fy, fx + fw - x - w, fh))
            if y > fy:
                split.append((fx, fy, fw, y - fy))
            if y + h < fy + fh:
                split.append((fx, y + h, fw, fy + fh - y - h))
        split.sort(key=lambda r: -(r[2] * r[3]))
        free = []
        for rect in split:
            contained = False
            for other in free:
                if rect[0] >= other[0] and rect[1] >= other[1] and rect[0] + rect[2] <= other[0] + other[2] and rect[1] + rect[3] <= other[1] + other[3]:
                    contained = True
                    break
            if not contained:
                free.append(rect)
    return spots


def pack(sizes, widths, limit, side_limit):
    orders = [
        sorted(range(len(sizes)), key=lambda i: (-sizes[i][1], -sizes[i][0])),
        sorted(range(len(sizes)), key=lambda i: (-(sizes[i][0] * sizes[i][1]), -sizes[i][1])),
        sorted(range(len(sizes)), key=lambda i: (-max(sizes[i]), -min(sizes[i]))),
    ]
    attempts = []
    for width in widths:
        for order in orders:
            attempts.append((skyline_pack, order, width))
            if len(sizes) <= MAXRECTS_LIMIT:
                attempts.append((maxrects_pack, order, width))
    best = None
    for packer, order, width in attempts:
        spots = packer(sizes, order, width, limit)
        if spots is None:
            continue
        used_width = max(spots[i][0] + sizes[i][0] for i in range(len(sizes)))
        used_height = max(spots[i][1] + sizes[i][1] for i in range(len(sizes)))
        side = max(used_width, used_height)
        score = (max(0, side - side_limit), used_width * used_height)
        if best is None or score < best[0]:
            best = (score, used_width, used_height, spots)
    return best


def repack_atlas(pixels, xml_text, frames, limit, target):
    height, width = pixels.shape[:2]
    unique = {}
    regions = []
    placements = {}
    for tag, v in frames:
        key = (v["x"], v["y"], v["width"], v["height"])
        if key in placements:
            continue
        region = pixels[v["y"]:v["y"] + v["height"], v["x"]:v["x"] + v["width"]]
        left, top, right, bottom = trim_region(region)
        content = region[top:bottom, left:right]
        if not content[:, :, 3].any():
            content = np.zeros((1, 1, 4), dtype=np.uint8)
        digest = hashlib.sha1(content.tobytes() + str(content.shape).encode()).digest()
        if digest not in unique:
            unique[digest] = len(regions)
            regions.append(content)
        placements[key] = (unique[digest], left, top)

    sizes = [(r.shape[1], r.shape[0]) for r in regions]
    area = sum((w + PADDING) * (h + PADDING) for w, h in sizes)
    widest = max(w for w, _ in sizes) + PADDING
    side = max(widest, int(area ** 0.5))
    factors = (0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0)
    widths = {min(limit, max(widest, int(side * f))) for f in factors} | {min(limit, max(widest, width))}
    scale = min(1.0, target / max(width, height)) if target > 0 else 1.0
    side_limit = int(target / scale) if target > 0 else limit
    widths |= {max(widest, min(limit, side_limit))}
    packed = pack(sizes, sorted(widths), limit, side_limit)
    if packed is None:
        return None
    _, new_width, new_height, spots = packed
    if max(new_width, new_height) > side_limit + 1:
        return None
    if new_width * new_height >= width * height * 0.97:
        return None

    atlas = np.zeros((new_height, new_width, 4), dtype=np.uint8)
    for index, region in enumerate(regions):
        x, y = spots[index]
        atlas[y:y + region.shape[0], x:x + region.shape[1]] = region

    def replace(match):
        tag = match.group(0)
        x = int(read_number(tag, "x"))
        y = int(read_number(tag, "y"))
        w = int(read_number(tag, "width"))
        h = int(read_number(tag, "height"))
        index, left, top = placements[(x, y, w, h)]
        region = regions[index]
        spot = spots[index]
        frame_x = read_number(tag, "frameX")
        frame_y = read_number(tag, "frameY")
        frame_w = read_number(tag, "frameWidth")
        frame_h = read_number(tag, "frameHeight")
        if frame_x is None:
            frame_x, frame_y, frame_w, frame_h = 0, 0, w, h
        tag = write_number(tag, "x", spot[0])
        tag = write_number(tag, "y", spot[1])
        tag = write_number(tag, "width", region.shape[1])
        tag = write_number(tag, "height", region.shape[0])
        tag = write_number(tag, "frameX", frame_x - left)
        tag = write_number(tag, "frameY", frame_y - top)
        tag = write_number(tag, "frameWidth", frame_w)
        return write_number(tag, "frameHeight", frame_h)

    new_xml = SUBTEXTURE.sub(replace, xml_text)

    for key, (index, left, top) in placements.items():
        x, y, w, h = key
        region = regions[index]
        spot = spots[index]
        source = pixels[y + top:y + top + region.shape[0], x + left:x + left + region.shape[1]]
        target = atlas[spot[1]:spot[1] + region.shape[0], spot[0]:spot[0] + region.shape[1]]
        if region.shape[:2] == (1, 1) and not region[:, :, 3].any():
            continue
        if source.shape != target.shape or not np.array_equal(source, target):
            return None

    return atlas, new_xml, scale


def minify_xml(text):
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    return re.sub(r">\s+<", "><", text.strip())


def clean_alpha(pixels):
    if pixels.shape[2] == 4:
        hidden = pixels[:, :, 3] == 0
        if hidden.any():
            pixels = pixels.copy()
            pixels[hidden] = 0
    return pixels


def encode_oxipng(pixels, options):
    if pixels.shape[2] == 4 and (pixels[:, :, 3] == 255).all():
        pixels = np.ascontiguousarray(pixels[:, :, :3])
    color = oxipng.ColorType.rgba() if pixels.shape[2] == 4 else oxipng.ColorType.rgb()
    raw = oxipng.RawImage(np.ascontiguousarray(pixels).tobytes(), pixels.shape[1], pixels.shape[0], color_type=color, bit_depth=8)
    small = options.zopfli_limit > 0 and pixels.nbytes <= options.zopfli_limit * 4
    deflate = oxipng.Deflaters.zopfli(options.zopfli_iterations) if small else oxipng.Deflaters.libdeflater(options.compression)
    return raw.create_optimized_png(
        level=options.level,
        deflate=deflate,
        strip=oxipng.StripChunks.safe(),
        fast_evaluation=options.level <= 2,
    )


def encode_pillow(pixels):
    image = Image.fromarray(pixels, "RGBA" if pixels.shape[2] == 4 else "RGB")
    candidates = [image]
    if image.mode == "RGBA" and image.getchannel("A").getextrema() == (255, 255):
        candidates.append(image.convert("RGB"))
    colors = image.getcolors(256)
    if colors is not None:
        candidates.append(image.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE))
    best = None
    for candidate in candidates:
        buffer = io.BytesIO()
        candidate.save(buffer, "PNG", optimize=True, compress_level=9)
        data = buffer.getvalue()
        if best is None or len(data) < len(best):
            best = data
    return best


def encode(pixels, options):
    if oxipng is not None:
        return encode_oxipng(pixels, options)
    return encode_pillow(pixels)


def quantize(pixels, options):
    image = Image.fromarray(pixels, "RGBA")
    method = Image.Quantize.LIBIMAGEQUANT if "libimagequant" in getattr(Image.core, "__dict__", {}) else Image.Quantize.FASTOCTREE
    try:
        lossy = image.quantize(colors=options.colors, method=method, dither=Image.Dither.FLOYDSTEINBERG)
    except (ValueError, OSError):
        lossy = image.quantize(colors=options.colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    candidate = np.asarray(lossy.convert("RGBA"))
    mse = np.mean((pixels.astype(np.float32) - candidate.astype(np.float32)) ** 2)
    score = float("inf") if mse == 0 else 10 * np.log10((255 ** 2) / mse)
    return candidate if score >= options.min_psnr else pixels


def settings_of(options):
    return f"{VERSION}:{options.trim}:{options.repack}:{options.quantize}:{options.colors}:{options.min_psnr}:{options.level}:{options.compression}:{options.zopfli_limit}:{options.zopfli_iterations}:{options.max_size}:{oxipng is not None}"


def store_key(path, xml_path, options):
    digest = hashlib.sha1(settings_of(options).encode())
    with open(path, "rb") as handle:
        digest.update(handle.read())
    if os.path.exists(xml_path):
        with open(xml_path, "rb") as handle:
            digest.update(handle.read())
    return digest.hexdigest()


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


def optimize(path, options, grid):
    xml_path = os.path.splitext(path)[0] + ".xml"
    before = os.path.getsize(path)
    if options.store and not options.dry_run:
        key = store_key(path, xml_path, options)
        folder = os.path.join(options.store, key[:2], key)
        restored = restore_from_store(path, xml_path, folder)
        if restored is not None:
            return path, before, os.path.getsize(path), True, key, True, restored or None, ""
        result = optimize_file(path, xml_path, options, grid)
        save_to_store(path, xml_path, folder, result[4], result[5])
        return result[0], result[1], result[2], result[3], key, False, result[5], result[6]
    result = optimize_file(path, xml_path, options, grid)
    return result[0], result[1], result[2], result[3], None, False, result[5], result[6]


def optimize_file(path, xml_path, options, grid):
    file_size = os.path.getsize(path)
    new_xml = None
    notes = []
    scale = 1.0

    with Image.open(path) as source:
        source.load()
        has_alpha = source.mode in ("RGBA", "LA", "PA") or (source.mode == "P" and "transparency" in source.info)
        pixels = np.asarray(source.convert("RGBA" if has_alpha else "RGB"))

    if pixels.shape[2] == 3 and os.path.exists(xml_path) and (options.trim or options.repack):
        pixels = np.dstack([pixels, np.full(pixels.shape[:2], 255, dtype=np.uint8)])

    xml_text = None
    if os.path.exists(xml_path):
        with open(xml_path, "r", encoding="utf-8-sig") as handle:
            xml_text = handle.read()

    if xml_text is not None and not grid and (options.trim or options.repack):
        frames = read_frames(xml_text, pixels.shape[1], pixels.shape[0])
        if frames:
            result = repack_atlas(pixels, xml_text, frames, options.atlas_limit, options.max_size) if options.repack else None
            if result is not None:
                notes.append(f"repacked {pixels.shape[1]}x{pixels.shape[0]} -> {result[0].shape[1]}x{result[0].shape[0]}")
            elif options.trim:
                result = trim_atlas(pixels, xml_text, frames)
                if result is not None:
                    notes.append(f"trimmed {pixels.shape[1]}x{pixels.shape[0]} -> {result[0].shape[1]}x{result[0].shape[0]}")
            if result is not None:
                pixels, new_xml = result[0], result[1]
                if len(result) > 2:
                    scale = result[2]

    original_size = None
    height, width = pixels.shape[:2]
    factor = scale
    if options.max_size > 0 and max(width, height) * factor > options.max_size:
        factor = options.max_size / max(width, height)
    if factor < 1:
        original_size = (width, height)
        target = (max(1, round(width * factor)), max(1, round(height * factor)))
        image = Image.fromarray(pixels, "RGBA" if pixels.shape[2] == 4 else "RGB")
        if image.mode == "RGBA":
            image = image.convert("RGBa").resize(target, Image.Resampling.LANCZOS).convert("RGBA")
        else:
            image = image.resize(target, Image.Resampling.LANCZOS)
        pixels = np.asarray(image)
        notes.append(f"scaled to {target[0]}x{target[1]}")

    pixels = clean_alpha(pixels)
    if options.quantize and pixels.shape[2] == 4:
        pixels = quantize(pixels, options)

    best = encode(pixels, options)
    changed_layout = new_xml is not None or original_size is not None

    xml_output = None
    if xml_text is not None and SUBTEXTURE.search(xml_text):
        xml_output = minify_xml(new_xml if new_xml is not None else xml_text)
        if new_xml is None and xml_output == xml_text:
            xml_output = None
    elif new_xml is not None:
        xml_output = new_xml

    if not changed_layout and len(best) >= file_size:
        if xml_output is not None and not options.dry_run:
            with open(xml_path, "w", encoding="utf-8", newline="") as handle:
                handle.write(xml_output)
            return path, file_size, file_size, True, True, None, ""
        return path, file_size, file_size, False, False, None, ""

    if options.dry_run:
        return path, file_size, len(best), True, new_xml is not None, original_size, ", ".join(notes)

    temp_path = path + ".tmp"
    with open(temp_path, "wb") as handle:
        handle.write(best)
    os.replace(temp_path, path)

    if xml_output is not None:
        with open(xml_path, "w", encoding="utf-8", newline="") as handle:
            handle.write(xml_output)

    return path, file_size, len(best), True, xml_output is not None, original_size, ", ".join(notes)


def single_store_key(path, kind, settings):
    digest = hashlib.sha1(f"{kind}:{settings}".encode())
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_single(kind, path, options, worker):
    before = os.path.getsize(path)
    settings = kind_settings(kind, options)
    if options.store and not options.dry_run:
        key = single_store_key(path, kind, settings)
        folder = os.path.join(options.store, key[:2], key)
        stored = os.path.join(folder, "output")
        if os.path.exists(stored):
            if os.path.getsize(stored) != before or file_hash(stored) != file_hash(path):
                shutil.copyfile(stored, path)
            return path, before, os.path.getsize(path), True, key, True, None, ""
        result = worker(path, options)
        os.makedirs(folder, exist_ok=True)
        shutil.copyfile(path, os.path.join(folder, "output.tmp"))
        os.replace(os.path.join(folder, "output.tmp"), stored)
        return path, before, result[0], result[1], key, False, None, result[2]
    result = worker(path, options)
    return path, before, result[0], result[1], None, False, None, result[2]


def optimize_json(path, options):
    before = os.path.getsize(path)
    with open(path, "rb") as handle:
        raw = handle.read()
    try:
        text = raw.decode("utf-8-sig")
        end = text.rstrip().rfind("}")
        if end < 0:
            return before, False, ""
        body = text[: end + 1]

        def reject(value):
            raise ValueError(value)

        data = json.loads(body, parse_constant=reject)
    except (UnicodeDecodeError, ValueError):
        return before, False, ""
    output = json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    if json.loads(output.decode("utf-8")) != data or len(output) >= before:
        return before, False, ""
    if not options.dry_run:
        with open(path + ".tmp", "wb") as handle:
            handle.write(output)
        os.replace(path + ".tmp", path)
    return len(output), True, ""


def probe_audio(path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name,channels,sample_rate,bit_rate:format=bit_rate,duration", "-of", "json", path],
        capture_output=True, text=True, check=True,
    )
    data = json.loads(result.stdout)
    stream = (data.get("streams") or [{}])[0]
    fmt = data.get("format") or {}
    bitrate = stream.get("bit_rate") or fmt.get("bit_rate") or "0"
    return {
        "codec": stream.get("codec_name"),
        "channels": int(stream.get("channels") or 0),
        "rate": int(stream.get("sample_rate") or 0),
        "bitrate": int(float(bitrate)) // 1000,
    }


def is_fake_stereo(path):
    process = subprocess.Popen(["ffmpeg", "-v", "quiet", "-i", path, "-map", "0:a:0", "-f", "s16le", "-acodec", "pcm_s16le", "-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    fake = True
    leftover = b""
    try:
        while True:
            chunk = process.stdout.read(1 << 20)
            if not chunk:
                break
            chunk = leftover + chunk
            usable = len(chunk) - len(chunk) % 4
            leftover = chunk[usable:]
            samples = np.frombuffer(chunk[:usable], dtype=np.int16).reshape(-1, 2).astype(np.int32)
            if samples.size and np.abs(samples[:, 0] - samples[:, 1]).max() > 2:
                fake = False
                break
    finally:
        process.stdout.close()
        process.kill()
        process.wait()
    return fake


def optimize_audio(path, options):
    before = os.path.getsize(path)
    info = probe_audio(path)
    if info["codec"] != "vorbis" or info["channels"] == 0:
        return before, False, ""

    mono = options.audio_mono and info["channels"] == 2 and is_fake_stereo(path)
    channels = 1 if mono else info["channels"]
    target = AUDIO_BITRATES.get(options.audio_quality, 192)
    if channels == 1:
        target = int(target * 0.6)
    if not mono and info["bitrate"] and info["bitrate"] <= target * 1.15:
        return before, False, ""

    handle, temp_path = tempfile.mkstemp(suffix=".ogg", dir=os.path.dirname(path))
    os.close(handle)
    try:
        command = ["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:a:0", "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", str(options.audio_quality)]
        if mono:
            command += ["-ac", "1"]
        subprocess.run(command + [temp_path], check=True)
        after = os.path.getsize(temp_path)
        if after >= before * 0.9:
            return before, False, ""
        if options.dry_run:
            return after, True, "mono" if mono else ""
        os.replace(temp_path, path)
        return after, True, "mono" if mono else ""
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


def probe_video(path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height,bit_rate:format=bit_rate", "-of", "json", path],
        capture_output=True, text=True, check=True,
    )
    data = json.loads(result.stdout)
    video = None
    audio = None
    for stream in data.get("streams") or []:
        if stream.get("codec_type") == "video" and video is None:
            video = stream
        elif stream.get("codec_type") == "audio" and audio is None:
            audio = stream
    fmt = data.get("format") or {}
    return video, audio, int(float(fmt.get("bit_rate") or 0)) // 1000


def optimize_video(path, options):
    before = os.path.getsize(path)
    video, audio, total = probe_video(path)
    if video is None:
        return before, False, ""

    width = int(video.get("width") or 0)
    height = int(video.get("height") or 0)
    bitrate = int(float(video.get("bit_rate") or 0)) // 1000 or total
    pixels = max(1, width * height)
    budget = options.video_bitrate * pixels / (1280 * 720)
    too_big = width > options.video_width or height > options.video_height
    if not too_big and bitrate and bitrate <= budget * 1.2:
        return before, False, ""

    handle, temp_path = tempfile.mkstemp(suffix=".mp4", dir=os.path.dirname(path))
    os.close(handle)
    try:
        command = [
            "ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "-1",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", str(options.video_crf), "-pix_fmt", "yuv420p",
            "-maxrate", f"{int(budget * 1.5)}k", "-bufsize", f"{int(budget * 3)}k",
            "-vf", f"scale='min({options.video_width},iw)':'min({options.video_height},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
            "-movflags", "+faststart",
        ]
        audio_rate = int(float(audio.get("bit_rate") or 0)) // 1000 if audio else 0
        if audio is not None and audio.get("codec_name") == "aac" and 0 < audio_rate <= 192:
            command += ["-c:a", "copy"]
        elif audio is not None:
            command += ["-c:a", "aac", "-b:a", "160k"]
        subprocess.run(command + [temp_path], check=True)
        after = os.path.getsize(temp_path)
        if after >= before * 0.9:
            return before, False, ""
        note = f"{width}x{height} {bitrate}k"
        if options.dry_run:
            return after, True, note
        os.replace(temp_path, path)
        return after, True, note
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


def optimize_xml(path, options):
    before = os.path.getsize(path)
    with open(path, "r", encoding="utf-8-sig") as handle:
        text = handle.read()
    if not SUBTEXTURE.search(text):
        return before, False, ""
    output = minify_xml(text)
    size = len(output.encode("utf-8"))
    if size >= before:
        return before, False, ""
    if not options.dry_run:
        with open(path + ".tmp", "w", encoding="utf-8", newline="") as handle:
            handle.write(output)
        os.replace(path + ".tmp", path)
    return size, True, ""


JUNK_PATTERNS = ("*.pdn", "*.psd", "*.fla", "*.xcf", "*.kra", "*.ase", "*.aseprite", "*.sai", "*.clip", "Thumbs.db", ".DS_Store", "desktop.ini", "*.bak", "*.tmp")


def remove_junk(roots, dry_run):
    removed = 0
    size = 0
    for root in roots:
        if not os.path.isdir(root):
            continue
        for folder, _, names in os.walk(root):
            for name in names:
                if any(fnmatch.fnmatch(name, pattern) for pattern in JUNK_PATTERNS):
                    path = os.path.join(folder, name)
                    size += os.path.getsize(path)
                    removed += 1
                    if not dry_run:
                        os.remove(path)
    return removed, size


def kind_settings(kind, options):
    if kind == "xml":
        return f"xml:{VERSION}"
    if kind == "video":
        return f"video:{VERSION}:{options.video_crf}:{options.video_bitrate}:{options.video_width}x{options.video_height}"
    if kind == "audio":
        return f"audio:{VERSION}:{options.audio_quality}:{options.audio_mono}"
    if kind == "json":
        return f"json:{VERSION}"
    return settings_of(options)


def optimize_job(kind, path, options, grid):
    if kind == "xml":
        return run_single(kind, path, options, optimize_xml)
    if kind == "video":
        return run_single(kind, path, options, optimize_video)
    if kind == "audio":
        return run_single(kind, path, options, optimize_audio)
    if kind == "json":
        return run_single(kind, path, options, optimize_json)
    return optimize(path, options, grid)


def collect_extension(roots, excludes, extension):
    files = []
    for root in roots:
        if os.path.isfile(root):
            if root.lower().endswith(extension):
                files.append(root)
            continue
        for folder, _, names in os.walk(root):
            for name in names:
                if not name.lower().endswith(extension):
                    continue
                path = os.path.join(folder, name)
                relative = path.replace("\\", "/")
                if any(fnmatch.fnmatch(relative, pattern) for pattern in excludes):
                    continue
                files.append(path)
    return sorted(files)


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


def grid_images(source_root):
    names = set()
    if not source_root or not os.path.isdir(source_root):
        return names
    for folder, _, files in os.walk(source_root):
        for name in files:
            if not name.endswith(".hx"):
                continue
            with open(os.path.join(folder, name), "r", encoding="utf-8", errors="ignore") as handle:
                for match in GRID_LOAD.finditer(handle.read()):
                    names.add(match.group(1).replace("\\", "/"))
    return names


def is_grid(path, names):
    relative = path.replace("\\", "/")
    stem = os.path.splitext(relative)[0]
    return any(stem.endswith("/images/" + name) for name in names)


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
    parser.add_argument("--trim", action="store_true", help="Crop unused transparent space around Sparrow atlases and fix their XML")
    parser.add_argument("--repack", action="store_true", help="Trim every frame, merge duplicated frames and repack Sparrow atlases")
    parser.add_argument("--atlas-limit", type=int, default=8192, help="Biggest side allowed for a repacked atlas")
    parser.add_argument("--source", default="source", help="Source folder scanned for grid sprite sheets that must keep their layout")
    parser.add_argument("--quantize", action="store_true", help="Allow lossy palette reduction")
    parser.add_argument("--colors", type=int, default=256, help="Palette size used by --quantize")
    parser.add_argument("--min-psnr", type=float, default=38.0, help="Minimum quality for --quantize")
    parser.add_argument("--level", type=int, default=2, help="oxipng optimization level from 0 to 6")
    parser.add_argument("--compression", type=int, default=9, help="libdeflate compression from 1 to 12")
    parser.add_argument("--zopfli-limit", type=int, default=0, help="Use zopfli for textures up to this many bytes of pixels divided by 4, slow but smaller")
    parser.add_argument("--zopfli-iterations", type=int, default=15, help="Zopfli iterations used by --zopfli-limit")
    parser.add_argument("--remove-junk", action="store_true", help="Delete editor and system files that the game never loads")
    parser.add_argument("--report", help="JSON file that receives a summary of the run")
    parser.add_argument("--fast", action="store_true", help="Fastest settings, good for local tests")
    parser.add_argument("--best", action="store_true", help="Smallest files, slower")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1, help="Parallel workers")
    parser.add_argument("--dry-run", action="store_true", help="Only report what would be saved")
    parser.add_argument("--no-cache", action="store_true", help="Ignore the cache of already optimized files")
    parser.add_argument("--cache", default=CACHE_NAME, help="Cache file path")
    parser.add_argument("--store", help="Folder that keeps optimized results keyed by the original file, used to skip work between builds")
    parser.add_argument("--prune", action="store_true", help="Remove results from --store that were not used in this run")
    parser.add_argument("--max-size", type=int, default=0, help="Downscale textures bigger than this, the game keeps them at their original size on screen")
    parser.add_argument("--scale-manifest", help="JSON file that receives the original size of every downscaled texture")
    parser.add_argument("--audio", action="store_true", help="Re-encode Vorbis audio with a high bitrate to a smaller size")
    parser.add_argument("--audio-quality", type=int, default=6, help="Vorbis quality used by --audio, from 3 to 8")
    parser.add_argument("--no-audio-mono", dest="audio_mono", action="store_false", help="Keep stereo files whose channels are identical")
    parser.add_argument("--json", action="store_true", help="Minify JSON data files")
    parser.add_argument("--video", action="store_true", help="Re-encode MP4 videos that are bigger or heavier than needed")
    parser.add_argument("--video-crf", type=int, default=23, help="H.264 quality used by --video, lower is better")
    parser.add_argument("--video-bitrate", type=int, default=2500, help="Video bitrate in kbps that a 1280x720 video may use before it is re-encoded")
    parser.add_argument("--video-width", type=int, default=1280, help="Biggest video width kept by --video")
    parser.add_argument("--video-height", type=int, default=720, help="Biggest video height kept by --video")
    parser.add_argument("--verbose", action="store_true", help="Print every optimized file")
    options = parser.parse_args()

    if options.fast:
        options.level, options.compression = 1, 6
    if options.best:
        options.level, options.compression = 4, 12
        if options.zopfli_limit == 0:
            options.zopfli_limit = 262144

    if oxipng is None:
        print("pyoxipng was not found, using Pillow, run: pip install pyoxipng")

    started = time.time()
    if options.remove_junk:
        junk_count, junk_size = remove_junk(options.paths, options.dry_run)
        if junk_count:
            print(f"Removed {junk_count} junk files ({human(junk_size)})")

    grid = grid_images(options.source)
    cache = {} if options.no_cache else load_cache(options.cache)

    work = [("sprite", path) for path in collect(options.paths, options.exclude)]
    if options.audio:
        if shutil.which("ffmpeg") and shutil.which("ffprobe"):
            work += [("audio", path) for path in collect_extension(options.paths, options.exclude, ".ogg")]
        else:
            print("ffmpeg was not found, skipping audio")
    if options.video:
        if shutil.which("ffmpeg") and shutil.which("ffprobe"):
            work += [("video", path) for path in collect_extension(options.paths, options.exclude, ".mp4")]
        else:
            print("ffmpeg was not found, skipping videos")
    if options.json:
        sprite_xml = {os.path.splitext(path)[0] + ".xml" for kind, path in work if kind == "sprite"}
        work += [("xml", path) for path in collect_extension(options.paths, options.exclude, ".xml") if path not in sprite_xml]
        manifest = os.path.abspath(options.scale_manifest) if options.scale_manifest else None
        work += [("json", path) for path in collect_extension(options.paths, options.exclude, ".json") if os.path.abspath(path) != manifest]

    pending = []
    for kind, path in work:
        entry = cache.get(path.replace("\\", "/"))
        if entry and entry.get("settings") == kind_settings(kind, options) and entry.get("hash") == file_hash(path):
            continue
        pending.append((kind, path))
    pending.sort(key=lambda item: os.path.getsize(item[1]), reverse=True)

    counts = {}
    for kind, _ in work:
        counts[kind] = counts.get(kind, 0) + 1
    summary = ", ".join(f"{count} {kind}" for kind, count in sorted(counts.items()))
    print(f"{summary} found, {len(pending)} to process, {len(grid)} grid sheets kept as they are")

    total_before = 0
    total_after = 0
    changed = 0
    failed = 0
    reused = 0
    repacked = 0
    used_keys = set()
    per_kind = {}
    scaled = {}
    if options.scale_manifest and os.path.exists(options.scale_manifest):
        try:
            with open(options.scale_manifest, "r", encoding="utf-8") as handle:
                scaled = json.load(handle)
        except (OSError, ValueError):
            scaled = {}

    with ProcessPoolExecutor(max_workers=max(1, options.jobs)) as pool:
        jobs = {pool.submit(optimize_job, kind, path, options, kind == "sprite" and is_grid(path, grid)): (kind, path) for kind, path in pending}
        for index, job in enumerate(as_completed(jobs), 1):
            kind, path = jobs[job]
            try:
                _, before, after, modified, key, from_store, texture_size, notes = job.result()
            except Exception as error:
                failed += 1
                print(f"[{index}/{len(pending)}] failed {path}: {error}")
                continue

            total_before += before
            total_after += after
            stats = per_kind.setdefault(kind, [0, 0, 0])
            stats[0] += before
            stats[1] += after
            stats[2] += 1
            if key is not None:
                used_keys.add(key)
            if kind == "sprite":
                runtime_id = runtime_path(path)
                if texture_size:
                    scaled[runtime_id] = [int(texture_size[0]), int(texture_size[1])]
                else:
                    scaled.pop(runtime_id, None)
            if "repacked" in notes:
                repacked += 1
            if from_store:
                reused += 1
            elif modified:
                changed += 1
                if options.verbose or notes:
                    extra = f" ({notes})" if notes else ""
                    print(f"[{index}/{len(pending)}] {path} {human(before)} -> {human(after)}{extra}")

            if not options.dry_run and not options.no_cache:
                cache[path.replace("\\", "/")] = {"hash": file_hash(path), "settings": kind_settings(kind, options)}

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

    for kind, (before, after, count) in sorted(per_kind.items()):
        print(f"  {kind}: {count} files, {human(before)} -> {human(after)}")

    if options.report and not options.dry_run:
        report = {kind: {"files": count, "before": before, "after": after} for kind, (before, after, count) in per_kind.items()}
        report["total"] = {"before": total_before, "after": total_after, "failed": failed, "seconds": round(time.time() - started, 1)}
        with open(options.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1, sort_keys=True)

    saved = total_before - total_after
    percent = (saved / total_before * 100) if total_before else 0
    elapsed = time.time() - started
    print(f"Done in {elapsed:.0f}s: {changed} optimized, {repacked} atlases repacked, {reused} restored from the store, {failed} failed, saved {human(saved)} ({percent:.1f}%)")


if __name__ == "__main__":
    main()

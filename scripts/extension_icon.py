"""Build the extension's transparent speech-bubble mark with Apple's tools.

The containing app keeps its Icon Composer artwork.  The extension instead
needs a mark whose alpha channel describes the bubble and its three dots, so
the host can use it on a toolbar without turning an opaque app tile into a
solid square.  All raster representations are rendered from the same vector
path; this build does not depend on image conversion libraries.
"""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess


ICON_NAME = "ExtensionIcon"
ROOT = Path(__file__).resolve().parents[1]
REPRESENTATIONS = tuple((size, scale) for size in (16, 32, 128, 256, 512)
                        for scale in (1, 2))

# Coordinates use a 1024-point canvas, with the existing brand's wide bubble,
# rounded shoulders, lower-left tail, and three evenly spaced circular dots.
# The dots are transparent holes, not painted circles: a host tinting the
# image must retain them.  The flat fill uses the existing app's cream color.
RENDERER = r'''
#import <Cocoa/Cocoa.h>

static void drawMark(CGContextRef context, size_t pixels) {
    CGContextScaleCTM(context, pixels / 1024.0, pixels / 1024.0);
    CGContextSetShouldAntialias(context, true);
    CGContextSetRGBFillColor(context, 0.970, 0.955, 0.920, 1.0);

    CGMutablePathRef mark = CGPathCreateMutable();
    CGPathMoveToPoint(mark, NULL, 292, 248);
    CGPathAddLineToPoint(mark, NULL, 738, 248);
    CGPathAddCurveToPoint(mark, NULL, 854, 248, 928, 321, 928, 424);
    CGPathAddLineToPoint(mark, NULL, 928, 588);
    CGPathAddCurveToPoint(mark, NULL, 928, 692, 854, 768, 741, 768);
    CGPathAddLineToPoint(mark, NULL, 282, 768);
    CGPathAddCurveToPoint(mark, NULL, 231, 768, 192, 758, 157, 739);
    CGPathAddCurveToPoint(mark, NULL, 137, 752, 118, 766, 90, 774);
    CGPathAddCurveToPoint(mark, NULL, 72, 779, 68, 768, 78, 752);
    CGPathAddCurveToPoint(mark, NULL, 99, 720, 106, 687, 106, 649);
    CGPathAddLineToPoint(mark, NULL, 106, 424);
    CGPathAddCurveToPoint(mark, NULL, 106, 321, 176, 248, 292, 248);
    CGPathCloseSubpath(mark);
    for (int i = 0; i < 3; i++) {
        CGFloat center = 352 + 160 * i;
        CGPathAddEllipseInRect(mark, NULL, CGRectMake(center - 64, 444, 128, 128));
    }
    CGContextAddPath(context, mark);
    CGContextEOFillPath(context);
    CGPathRelease(mark);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        size_t pixels = (size_t)strtoul(argv[1], NULL, 10);
        if (pixels < 16 || pixels > 1024) return 2;
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(NULL, pixels, pixels,
            8, pixels * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (!context) return 3;
        // Use top-left coordinates so the tail matches the source brand art.
        CGContextTranslateCTM(context, 0, pixels);
        CGContextScaleCTM(context, 1, -1);
        drawMark(context, pixels);
        CGImageRef image = CGBitmapContextCreateImage(context);
        if (!image) { CGContextRelease(context); return 3; }
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL written = [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
        CGImageRelease(image);
        CGContextRelease(context);
        return written ? 0 : 4;
    }
}
'''


def prepare(output: Path) -> dict:
    """Write ExtensionIcon.icns/Assets.car and return actool's icon plist keys."""
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    catalog = output / f"{ICON_NAME}.xcassets"
    if catalog.exists():
        shutil.rmtree(catalog)
    icon_set = catalog / f"{ICON_NAME}.appiconset"
    icon_set.mkdir(parents=True)
    catalog_info = {"info": {"version": 1, "author": "xcode"}}
    (catalog / "Contents.json").write_text(json.dumps(catalog_info, indent=2) + "\n")
    renderer_source = output / "render-extension-icon.m"
    renderer = output / "render-extension-icon"
    renderer_source.write_text(RENDERER)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Cocoa", str(renderer_source), "-o", str(renderer)],
                   check=True)
    for pixels in sorted({size * scale for size, scale in REPRESENTATIONS}):
        subprocess.run([str(renderer.resolve()), str(pixels),
                        str((icon_set / f"icon_{pixels}.png").resolve())], check=True)
    images = [{"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x",
               "filename": f"icon_{size * scale}.png"}
              for size, scale in REPRESENTATIONS]
    (icon_set / "Contents.json").write_text(
        json.dumps({"images": images, **catalog_info}, indent=2) + "\n")
    info_path = output / "icon-info.plist"
    subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(output),
                    "--app-icon", ICON_NAME, "--platform", "macosx",
                    "--minimum-deployment-target", "13.0",
                    "--output-partial-info-plist", str(info_path),
                    "--output-format", "human-readable-text"], check=True)
    info = plistlib.loads(info_path.read_bytes())
    if any(info.get(key) != ICON_NAME for key in ("CFBundleIconFile", "CFBundleIconName")):
        raise RuntimeError(f"Unexpected extension icon metadata: {info}")
    if not all((output / name).is_file() for name in (f"{ICON_NAME}.icns", "Assets.car")):
        raise RuntimeError("actool did not produce both extension icon resources")
    return info


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path,
                        default=ROOT / ".subloom/build/extension-icon-assets")
    arguments = parser.parse_args()
    prepare(arguments.output)
    print(arguments.output)

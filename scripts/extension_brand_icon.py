"""Adapt the complete compiled brand artwork to an alpha-based host icon.

Final Cut Pro can tint a workflow-extension icon by its alpha channel.  Its
opaque brand tile otherwise loses the dark bubble's interior detail.  Derive
the extension's alpha from the canonical compiled icon's luminance: the cream
square and three cream dots remain visible, while the dark bubble is a cutout.
No artwork is redrawn and all sizes use the same largest embedded source.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
ICON_NAME = "SubPop"
REPRESENTATIONS = tuple((size, scale) for size in (16, 32, 128, 256, 512)
                        for scale in (1, 2))

RENDERER = r'''
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

static unsigned char *render(CGImageRef image, size_t pixels) {
    unsigned char *data = calloc(pixels * pixels, 4);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, pixels, pixels,
        8, pixels * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { free(data); return NULL; }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, pixels, pixels), image);
    CGContextRelease(context);
    return data;
}

static NSDictionary *sample(const unsigned char *data, size_t pixels,
                             double x, double y) {
    size_t column = MIN(pixels - 1, (size_t)(x * pixels));
    size_t row = MIN(pixels - 1, (size_t)(y * pixels));
    const unsigned char *point = data + (row * pixels + column) * 4;
    return @{ @"x": @(column), @"y": @(row), @"rgba":
        @[@(point[0]), @(point[1]), @(point[2]), @(point[3])], @"alpha": @(point[3]) };
}

static NSDictionary *landmarks(const unsigned char *data, size_t pixels) {
    return @{ @"base": sample(data, pixels, .5, .75),
              @"bubble": sample(data, pixels, .5, .23),
              @"dots": @[sample(data, pixels, .365, .365),
                           sample(data, pixels, .5, .365),
                           sample(data, pixels, .635, .365)],
              @"exterior": sample(data, pixels, .01, .01) };
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5) return 2;
        NSString *sourcePath = [NSString stringWithUTF8String:argv[1]];
        size_t pixels = (size_t)strtoul(argv[2], NULL, 10);
        if (pixels < 16 || pixels > 1024) return 2;
        NSURL *sourceURL = [NSURL fileURLWithPath:sourcePath];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
        if (!source) return 3;
        CGImageRef master = NULL;
        size_t selected = 0;
        for (size_t i = 0; i < CGImageSourceGetCount(source); i++) {
            CGImageRef candidate = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!candidate) continue;
            if (!master || CGImageGetWidth(candidate) * CGImageGetHeight(candidate) >
                           CGImageGetWidth(master) * CGImageGetHeight(master)) {
                if (master) CGImageRelease(master);
                master = candidate;
                selected = i;
            } else CGImageRelease(candidate);
        }
        if (!master) { CFRelease(source); return 3; }
        unsigned char *original = render(master, pixels);
        if (!original) { CGImageRelease(master); CFRelease(source); return 3; }
        unsigned char *converted = calloc(pixels * pixels, 4);
        size_t partialAlphaPixels = 0;
        for (size_t i = 0; i < pixels * pixels; i++) {
            const unsigned char *input = original + i * 4;
            unsigned char *output = converted + i * 4;
            double sourceAlpha = input[3] / 255.0;
            double luminance = sourceAlpha > 0 ?
                (.2126 * input[0] + .7152 * input[1] + .0722 * input[2]) /
                (255.0 * sourceAlpha) : 0;
            double coverage = fmin(1, fmax(0, (luminance - .15) / (.85 - .15)));
            output[0] = 247; output[1] = 244; output[2] = 235;
            output[3] = (unsigned char)lround(255 * sourceAlpha * coverage);
            if (output[3] > 0 && output[3] < 255) partialAlphaPixels++;
        }
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)pixels
            pixelsHigh:(NSInteger)pixels bitsPerSample:8 samplesPerPixel:4
            hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
            bytesPerRow:(NSInteger)pixels * 4 bitsPerPixel:32];
        memcpy(bitmap.bitmapData, converted, pixels * pixels * 4);
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *pngPath = [NSString stringWithUTF8String:argv[3]];
        BOOL written = [png writeToFile:pngPath atomically:YES];
        NSDictionary *report = @{ @"pixels": @(pixels), @"sourceIndex": @(selected),
            @"sourceWidth": @(CGImageGetWidth(master)),
            @"sourceHeight": @(CGImageGetHeight(master)),
            @"sourceLandmarks": landmarks(original, pixels),
            @"landmarks": landmarks(converted, pixels),
            @"partialAlphaPixels": @(partialAlphaPixels) };
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted error:NULL];
        NSString *reportPath = [NSString stringWithUTF8String:argv[4]];
        BOOL reported = [json writeToFile:reportPath atomically:YES];
        // A native composited preview makes the cutout visible on a dark host.
        // It is evidence only, not another artwork or catalog representation.
        for (size_t i = 0; i < pixels * pixels; i++) {
            unsigned char *point = bitmap.bitmapData + i * 4;
            double alpha = point[3] / 255.0;
            for (size_t channel = 0; channel < 3; channel++)
                point[channel] = (unsigned char)lround(point[channel] * alpha + 20 * (1 - alpha));
            point[3] = 255;
        }
        NSData *preview = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *previewPath = [[reportPath stringByDeletingPathExtension]
            stringByAppendingString:@"-on-dark.png"];
        BOOL previewed = [preview writeToFile:previewPath atomically:YES];
        free(converted); free(original); CGImageRelease(master); CFRelease(source);
        return written && reported && previewed ? 0 : 4;
    }
}
'''


def prepare(output: Path, source_icns: Path) -> Path:
    """Write SubPop.icns/Assets.car from the full original icon and return output."""
    output = Path(output).resolve()
    source_icns = Path(source_icns).resolve()
    if not source_icns.is_file():
        raise FileNotFoundError(source_icns)
    # The input is never an output target, including on repeated local builds.
    if source_icns == output / f"{ICON_NAME}.icns":
        raise ValueError("The canonical source icon must be outside the output directory")
    output.mkdir(parents=True, exist_ok=True)
    source_digest = hashlib.sha256(source_icns.read_bytes()).hexdigest()
    catalog = output / f"{ICON_NAME}.xcassets"
    if catalog.exists():
        shutil.rmtree(catalog)
    icon_set = catalog / f"{ICON_NAME}.appiconset"
    icon_set.mkdir(parents=True)
    catalog_info = {"info": {"version": 1, "author": "xcode"}}
    (catalog / "Contents.json").write_text(json.dumps(catalog_info, indent=2) + "\n")
    renderer_source = output / "render-extension-brand-icon.m"
    renderer = output / "render-extension-brand-icon"
    renderer_source.write_text(RENDERER)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                                  text=True).strip()
    subprocess.run(["xcrun", "clang", "-isysroot", sdk, "-fobjc-arc", "-Wall",
                    "-Wextra", "-Werror", "-arch", "arm64", "-mmacosx-version-min=13.0",
                    "-framework", "Cocoa", "-framework", "ImageIO",
                    str(renderer_source), "-o", str(renderer)], check=True)
    reports = []
    for pixels in sorted({size * scale for size, scale in REPRESENTATIONS}):
        report_path = output / f"raster-{pixels}.json"
        subprocess.run([str(renderer), str(source_icns), str(pixels),
                        str(icon_set / f"icon_{pixels}.png"), str(report_path)], check=True)
        reports.append(json.loads(report_path.read_text()))
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
    if source_digest != hashlib.sha256(source_icns.read_bytes()).hexdigest():
        raise RuntimeError("The canonical source icon changed during adaptation")
    report = {"schema": 1, "method": "canonical-luminance-to-alpha",
              "inputIcnsSHA256": source_digest, "artworkRedrawn": False,
              "uniformArtworkSource": True, "minimumLuminance": .15,
              "maximumLuminance": .85, "rasterRepresentations": reports}
    (output / "conversion-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return output


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path,
                        default=ROOT / ".subloom/build/extension-brand-assets")
    parser.add_argument("--source", type=Path,
                        default=ROOT / ".subloom/build/icon-assets/SubPop.icns")
    arguments = parser.parse_args()
    print(prepare(arguments.output, arguments.source))

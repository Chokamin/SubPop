"""Sign a notarized release PKG and its online-update feed (never exports keys)."""
import argparse
import base64
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from sparkle_dependency import SDK, KEY_ACCOUNT, PUBLIC_KEY

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def feed_xml(version, build, size, signature):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not str(build).isdigit() or int(build) < 1:
        raise ValueError('Invalid release version/build')
    if size <= 0 or size > 2 * 1024**3 or len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid signed payload')
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'SubPop 在线更新'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'SubPop {version}'
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = str(build)
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '15.0'
    ET.SubElement(item, f'{{{SPARKLE}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, 'description').text = '自动下载、验证并安装 SubPop。更新时仅重启 SubPop；之后从 FCP 扩展菜单重新打开。模型、词库和历史字幕保持不变。'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/Chokamin/SubPop/releases/download/v{version}/SubPop-{version}-arm64.pkg',
        'length': str(size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature, f'{{{SPARKLE}}}installationType': 'package'})
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def prepare(package, build, output):
    package = Path(package).resolve()
    match = re.fullmatch(r'SubPop-(\d+\.\d+\.\d+)-arm64.pkg', package.name)
    if not match:
        raise ValueError('Expected final release package name')
    result = subprocess.run(['pkgutil', '--check-signature', str(package)], check=True, capture_output=True, text=True, env={**__import__('os').environ,'LC_ALL':'C','LANG':'C'})
    if not re.search(r'^\s*1\. Developer ID Installer: .*\(925BTJVFFZ\)\s*$', result.stdout, re.M):
        raise ValueError('Wrong installer publisher')
    subprocess.run(['xcrun', 'stapler', 'validate', str(package)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'install', str(package)], check=True)
    key = subprocess.check_output([str(SDK/'bin/generate_keys'), '--account', KEY_ACCOUNT, '-p'], text=True).strip()
    if key != PUBLIC_KEY:
        raise ValueError('Signing key does not match the application public key')
    signer = [str(SDK/'bin/sign_update'), '--account', KEY_ACCOUNT]
    signature = subprocess.check_output([*signer, '-p', str(package)], text=True).strip()
    subprocess.run([*signer, '--verify', str(package), signature], check=True)
    output = Path(output)
    output.write_bytes(feed_xml(match[1], build, package.stat().st_size, signature))
    subprocess.run([*signer, str(output)], check=True)
    subprocess.run([*signer, '--verify', str(output)], check=True)
    print(f'Upload {output} alongside the PKG before making this release latest.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('--build', type=int, required=True, help='CFBundleVersion embedded in this exact package')
    parser.add_argument('--output', type=Path, default=Path('dist/appcast.xml'))
    args = parser.parse_args()
    prepare(args.package, args.build, args.output)

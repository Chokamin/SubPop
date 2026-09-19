"""Opt-in Volcengine recorded-file fast ASR; no SDK, retries or persisted secrets.

Protocol: https://www.volcengine.com/docs/6561/1631584
Only audio bytes leave the machine. Vocabulary normalization remains local.
"""
import base64
import hashlib
import http.client
import io
import json
import math
import os
from pathlib import Path
import ssl
import subprocess
import uuid
import wave

from .paths import ROOT

MODEL_ID = 'doubao-cloud'
HOST = 'openspeech.bytedance.com'
ENDPOINT = '/api/v3/auc/bigmodel/recognize/flash'
RESOURCE = 'volc.bigasr.auc_turbo'
RATE = 16000
CHUNK_SAMPLES = 300 * RATE  # <10 MB WAV; comfortably below the API's 100 MB limit.
MAX_RESPONSE = 16 * 1024 * 1024


class CloudError(ValueError):
    """Only fixed, safe messages may reach the worker's persistent log."""


def configured(root=ROOT):
    try:
        path = root / '.subloom/cloud/doubao.json'
        return not path.is_symlink() and path.stat().st_size < 1024 and json.loads(path.read_text()).get('configured') is True
    except (OSError, ValueError, AttributeError):
        return False


def credential():
    # The signed host owns its Keychain item. Never pass the key in argv/env/files.
    executable = os.environ.get('SUBPOP_CONTAINER_EXECUTABLE', '')
    if not executable or not Path(executable).is_file():
        raise CloudError('请先打开应用程序中的 SubPop，再配置豆包云端识别。')
    try:
        result = subprocess.run([executable, '--doubao-key'], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=20, check=False)
        key = result.stdout.decode('ascii').strip() if result.returncode == 0 else ''
    except (OSError, subprocess.SubprocessError, UnicodeError):
        key = ''
    if not key or len(key) > 4096 or any(ord(c) < 33 or ord(c) > 126 for c in key):
        raise CloudError('无法读取豆包 API Key。请在模型设置中重新保存，并允许 SubPop 访问钥匙串。')
    return key


def request_chunk(wav, key):
    body = json.dumps({'user': {'uid': 'subpop'},
                       'audio': {'data': base64.b64encode(wav).decode('ascii')},
                       'request': {'model_name': 'bigmodel', 'show_utterances': True,
                                   'enable_itn': True, 'enable_punc': True,
                                   'enable_ddc': False}}).encode('utf-8')
    headers = {'Content-Type': 'application/json', 'X-Api-Key': key,
               'X-Api-Resource-Id': RESOURCE, 'X-Api-Request-Id': str(uuid.uuid4()),
               'X-Api-Sequence': '-1'}
    import certifi
    # The standalone packaged Python must not depend on a developer's OpenSSL CA path.
    context = ssl.create_default_context(cafile=certifi.where())
    connection = http.client.HTTPSConnection(HOST, timeout=180, context=context)
    try:
        # http.client never follows a redirect or retries a billed POST.
        connection.request('POST', ENDPOINT, body=body, headers=headers)
        response = connection.getresponse()
        code = response.getheader('X-Api-Status-Code', '')
        if response.status in (401, 403) or code in ('45000010', '45000011'):
            raise CloudError('豆包鉴权失败：请检查语音服务 API Key，并开通录音文件极速版权限。')
        if response.status == 429 or code == '55000031':
            raise CloudError('豆包请求受限或服务繁忙，请检查账户额度后稍后重试。')
        if response.status != 200:
            raise CloudError('豆包服务未成功响应。未自动重试，请在火山引擎控制台检查服务状态和用量。')
        if code == '20000003':
            return {'result': {'text': '', 'utterances': []}}
        if code != '20000000':
            raise CloudError('豆包识别失败，请检查服务权限、账户额度及音频要求。未自动重试。')
        raw = response.read(MAX_RESPONSE + 1)
        if len(raw) > MAX_RESPONSE:
            raise CloudError('豆包响应过大，已停止处理。')
        try:
            result = json.loads(raw)
        except (ValueError, UnicodeError):
            raise CloudError('豆包返回了无法解析的识别结果。') from None
        return result
    except CloudError:
        raise
    except (OSError, http.client.HTTPException, ValueError):
        # No server body/header, credential, or exception chain enters persistent logs.
        raise CloudError('豆包连接中断或超时。未自动重试；已提交的音频可能仍会计费，请先检查控制台用量。') from None
    finally:
        connection.close()


def parse_result(value, duration, offset=0):
    """Require measured word timing; never invent alignment from sentence length."""
    from opencc import OpenCC
    convert = OpenCC('t2s').convert
    import re
    def comparable(text):
        return ''.join(c.lower() for c in convert(text) if c.isalnum())
    if not isinstance(value, dict) or not isinstance(value.get('result'), dict):
        raise CloudError('豆包结果结构不完整。')
    result = value['result']
    utterances = result.get('utterances')
    if not isinstance(utterances, list):
        raise CloudError('豆包未返回逐字时间戳，无法生成准确的字幕时间。')
    rows = []
    previous = -1
    for utterance in utterances:
        if not isinstance(utterance, dict) or not isinstance(utterance.get('text'), str):
            raise CloudError('豆包句子数据不完整。')
        words = utterance.get('words')
        if not isinstance(words, list) or (not words and comparable(utterance['text'])):
            raise CloudError('豆包未返回逐字时间戳，无法生成准确的字幕时间。')
        parsed = []
        for word in words:
            if not isinstance(word, dict) or not isinstance(word.get('text'), str):
                raise CloudError('豆包词语数据不完整。')
            start, end = word.get('start_time'), word.get('end_time')
            if (type(start) not in (int, float) or type(end) not in (int, float)
                    or not math.isfinite(start) or not math.isfinite(end)
                    or not 0 <= start <= end <= duration * 1000 + 50 or start < previous):
                raise CloudError('豆包返回的时间戳异常，已停止生成字幕。')
            previous = start
            text = convert(word['text']).strip()
            if not text:
                continue
            if parsed and re.search(r'[A-Za-z0-9]$', parsed[-1]['text']) and re.match(r'[A-Za-z0-9]', text):
                text = ' ' + text
            parsed.append({'text': text, 'start': offset + min(start / 1000, duration),
                           'end': offset + min(end / 1000, duration)})
        if comparable(''.join(w['text'] for w in parsed)) != comparable(utterance['text']):
            raise CloudError('豆包文字与逐字时间戳不一致，无法可靠对齐字幕。')
        if parsed:
            rows.append({'text': convert(utterance['text']), 'words': parsed})
    if isinstance(result.get('text'), str) and comparable(result['text']) != comparable(''.join(r['text'] for r in rows)):
        raise CloudError('豆包返回的字幕内容不完整。')
    return rows


def wav_bytes(samples):
    import numpy as np
    pcm = np.rint(np.clip(samples, -1, 1) * 32767).astype('<i2').tobytes()
    output = io.BytesIO()
    with wave.open(output, 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(pcm)
    return output.getvalue()


def chunk_ranges(samples):
    import numpy as np
    cursor = 0
    while cursor < len(samples):
        end = min(cursor + CHUNK_SAMPLES, len(samples))
        if end < len(samples):
            # Prefer a quiet 100 ms interval in the last five seconds, no overlap/gap.
            candidates = range(max(cursor + RATE, end - 5 * RATE), end - RATE // 10, RATE // 10)
            best = min(candidates, key=lambda i: float(np.mean(samples[i:i + RATE // 10] ** 2)), default=end)
            end = min(end, best + RATE // 20)
        yield cursor, end
        cursor = end


def recognize(pcm, snapshot, *, consent=False, key=None, send=None, emit=None):
    if consent is not True:
        raise CloudError('云端识别需要先确认上传音频及计费。')
    import numpy as np
    if pcm.is_symlink() or not pcm.resolve().is_relative_to((ROOT / '.subloom/verification').resolve()):
        raise CloudError('无效的云端音频输入。')
    if pcm.stat().st_size != snapshot['sampleCount'] * 4 or not snapshot['sampleCount']:
        raise CloudError('音频长度与项目不一致。')
    samples = np.memmap(pcm, dtype='<f4', mode='r')
    key = credential() if key is None else key
    send = request_chunk if send is None else send
    emit = (lambda value: print(json.dumps(value), flush=True)) if emit is None else emit
    rows = []
    for start, end in chunk_ranges(samples):
        chunk = samples[start:end]
        if not np.all(np.isfinite(chunk)):
            raise CloudError('音频包含无效采样。')
        if np.max(np.abs(chunk)) > 1e-7:
            value = send(wav_bytes(chunk), key)
            rows.extend(parse_result(value, len(chunk) / RATE, start / RATE))
        emit({'stage': 'recognize', 'progress': end / len(samples)})
    digest = hashlib.sha256()
    with pcm.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return {'backendVersion': 1, 'snapshot': snapshot, 'pcm_sha256': digest.hexdigest(),
            'device': 'cloud', 'results': rows}

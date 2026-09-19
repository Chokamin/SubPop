"""User-owned private TOS temporary audio, using the official pinned SDK.

Receipts contain only object identifiers, never credentials or signed URLs. A
failed cleanup is retained for the next explicitly authorized cloud job.
"""
import base64
import hashlib
import json
import os
import re
import time
import uuid
from urllib.parse import urlsplit

REGIONS = ('cn-beijing', 'cn-shanghai', 'cn-guangzhou')
PREFIX = 'subpop-temp/'


class StorageError(ValueError):
    pass


def validate(config):
    if not isinstance(config, dict) or config.get('region') not in REGIONS:
        raise StorageError('请选择支持的 TOS 区域：北京、上海或广州。')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{1,61}[a-z0-9]', config.get('bucket', '')):
        raise StorageError('请填写有效的私有 TOS 存储桶名称。')
    for field in ('tosAccessKey', 'tosSecretKey'):
        value = config.get(field)
        if not isinstance(value, str) or not 1 <= len(value) <= 4096 or any(not 33 <= ord(c) <= 126 for c in value):
            raise StorageError('请在云端设置中保存完整的 TOS Access Key 和 Secret Key。')


def client(config, *, cleanup=False):
    import certifi
    import tos
    from tos.log import get_logger
    validate(config)
    get_logger().disabled = True  # SDK diagnostics may include signed requests.
    return tos.TosClientV2(config['tosAccessKey'], config['tosSecretKey'],
                         endpoint=f"https://tos-{config['region']}.volces.com", region=config['region'],
                         max_retry_count=0, follow_redirect_times=0, enable_verify_ssl=True,
                         ca_crt=certifi.where(), connection_time=2 if cleanup else 10,
                         socket_timeout=2 if cleanup else 60, request_timeout=2 if cleanup else 60)


def receipts(root):
    directory = root / '.subloom/cloud/uploads'
    if directory.is_symlink():
        raise StorageError('临时音频清理目录无效。')
    return directory


def pending_count(root):
    return sum(1 for _ in receipts(root).glob('*.json'))


def write_receipt(path, value):
    # New UUID filename, exclusive create for temp file, owner-only permissions.
    temp = path.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as out:
        json.dump(value, out)
        out.flush()
        os.fsync(out.fileno())
    temp.replace(path)


def remove_remote(config, value, factory):
    api = None
    try:
        api = factory(config, cleanup=True)
        version = value.get('versionID')
        if version is None:
            try:
                version = api.head_object(config['bucket'], value['key']).version_id
            except Exception as error:
                if getattr(error, 'status_code', None) == 404:
                    return True
                raise
        api.delete_object(config['bucket'], value['key'], version_id=version, skip_trash=True)
        return True
    except Exception:
        return False
    finally:
        if api is not None:
            try:
                api.close()
            except Exception:
                pass


def cleanup_pending(config, root, factory=client):
    validate(config)
    paths = list(receipts(root).glob('*.json'))
    if len(paths) > 100:
        raise StorageError('待清理的临时音频较多，请先在 TOS 控制台清理 subpop-temp/ 目录。')
    for path in paths:
        try:
            if path.is_symlink() or path.stat().st_size > 2048:
                raise ValueError()
            identifier = str(uuid.UUID(path.stem))
            value = json.loads(path.read_text())
            if value['key'] != PREFIX + identifier + '.wav':
                raise ValueError()
            if value['bucket'] != config['bucket'] or value['region'] != config['region']:
                continue  # Never use new credentials to address an unrelated bucket.
            if value.get('versionID') is not None and not isinstance(value['versionID'], str):
                raise ValueError()
            # A timed-out PUT can still finish server-side; retain its receipt.
            if not value.get('uploaded') and time.time() - float(value['created']) < 120:
                raise ValueError()
            if not remove_remote(config, value, factory):
                raise ValueError()
            path.unlink()
        except (OSError, ValueError, KeyError, TypeError):
            raise StorageError('临时音频尚未清理，已停止新上传。请检查 TOS 删除权限，稍后重试；也可在控制台清理 subpop-temp/ 目录。') from None


class TemporaryAudio:
    def __init__(self, config, wav, *, root, factory=client):
        validate(config)
        self.config, self.wav, self.root, self.factory = config, wav, root, factory
        if not 0 < len(wav) <= 11 * 1024 * 1024:
            raise StorageError('临时音频大小无效。')
        identifier = str(uuid.uuid4())
        self.path = receipts(root) / (identifier + '.json')
        self.value = {'bucket': config['bucket'], 'region': config['region'],
                      'key': PREFIX + identifier + '.wav', 'created': time.time(), 'uploaded': False}

    def __enter__(self):
        import tos
        cleanup_pending(self.config, self.root, self.factory)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        write_receipt(self.path, self.value)
        api = None
        try:
            api = self.factory(self.config)
            result = api.put_object(self.config['bucket'], self.value['key'], content=self.wav,
                                    content_length=len(self.wav), content_type='audio/wav',
                                    content_md5=base64.b64encode(hashlib.md5(self.wav).digest()).decode(),
                                    acl=tos.ACLType.ACL_Private, forbid_overwrite=True)
            self.value.update(uploaded=True, versionID=result.version_id)
            write_receipt(self.path, self.value)
            url = api.pre_signed_url(tos.HttpMethodType.Http_Method_Get, self.config['bucket'],
                                     self.value['key'], expires=3600).signed_url
            parsed = urlsplit(url)
            expected = f"{self.config['bucket']}.tos-{self.config['region']}.volces.com"
            if parsed.scheme != 'https' or parsed.netloc != expected or parsed.path != '/' + self.value['key']:
                raise ValueError()
            return url
        except BaseException as error:
            self.__exit__(None, None, None)
            if isinstance(error, (SystemExit, KeyboardInterrupt)):
                raise
            raise StorageError('TOS 上传或链接生成失败。请检查区域、桶名称、密钥及读写权限。可能残留的临时音频已登记待清理。') from None
        finally:
            if api is not None:
                try:
                    api.close()
                except Exception:
                    pass

    def __exit__(self, *_):
        try:
            removed = remove_remote(self.config, self.value, self.factory)
            if removed and self.value.get('uploaded'):
                self.path.unlink(missing_ok=True)
        except Exception:
            pass  # Durable receipt survives cancellation, permission/network failure.
        return False

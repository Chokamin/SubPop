"""Shared allowlisted model catalog. Availability never triggers a download."""
import json
from pathlib import Path

from .paths import ROOT, CODE_ROOT
CATALOG = json.loads((CODE_ROOT / 'config/models.json').read_text())
DEFAULT_MODEL_ID = CATALOG['defaultModelID']


def model_spec(model_id):
    if not isinstance(model_id, str):
        raise ValueError('Invalid model ID')
    for model in CATALOG['models']:
        if model['id'] == model_id:
            return model
    raise ValueError('Unknown model ID; select an installed SubPop model')


def check_files(spec, root=ROOT):
    if spec.get('engine') == 'doubao':
        raise ValueError('云端模型无需下载，请配置 API Key')
    base = root / '.subloom/models'
    directory = base / spec['directory']
    if directory.is_symlink() or not directory.resolve().is_relative_to(base.resolve()):
        raise ValueError('Linked model directory refused')
    for name, size in spec['files'].items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != size:
            raise ValueError('Model is missing or incomplete: ' + spec['directory'])
    config = json.loads((directory / 'config.json').read_text()) if (directory/'config.json').exists() else {}
    if 'hiddenSize' in spec and (config.get('model_type') != 'qwen3_asr' or
            config.get('thinker_config', {}).get('text_config', {}).get('hidden_size') != spec['hiddenSize']):
        raise ValueError('Model configuration does not match selected model')
    return directory


def resolve_model(model_id, root=ROOT):
    spec = model_spec(model_id)
    if spec.get('engine') == 'doubao':
        from .doubao import configured
        if not configured(root):raise ValueError('请在模型设置中配置语音 API Key 与 TOS')
        return None, None
    return check_files(spec, root), (None if spec.get('engine') else check_files(CATALOG['aligner'], root))


def availability(root=ROOT):
    result = []
    for spec in CATALOG['models']:
        if spec.get('engine') == 'doubao':
            from .doubao import configured
            from .tos_storage import pending_count
            ready = configured(root)
            result.append({'id': spec['id'], 'installed': ready, 'asrInstalled': False, 'hasFiles': False, 'reason': '' if ready else '尚需配置语音 API Key 与 TOS', 'sizeBytes': 0, 'cloud': True, 'cleanupPending': pending_count(root)})
            continue
        try:
            resolve_model(spec['id'], root)
            installed, reason = True, ''
        except (ValueError, OSError):
            installed, reason = False, '模型文件缺失或不完整'
        try:check_files(spec,root);present=True
        except (ValueError,OSError):present=False
        result.append({'id': spec['id'], 'installed': installed, 'asrInstalled':present, 'hasFiles':(root/'.subloom/models'/spec['directory']).exists(), 'reason': reason, 'sizeBytes':sum(spec['files'].values())})
    return result

"""Internal gain automation in explicit planning clock spaces.

Static XML volume retains the ordinary float path. Dynamic gains carry immutable
curves in explicit planning clock spaces until the planner maps them to clock 0.
Fade ramps and canonical keyframe interpolation match isolated FCP 12.3 output
at 48 kHz, including nonzero source trims and independent component volume.
This does not validate every container, retime, or processor in the final mix.
"""
from dataclasses import dataclass, replace
from fractions import Fraction
import math
from numbers import Real
import re


MAX_CURVES = 128
MAX_KEYS = 5000
FADE_TYPES = frozenset(('linear', 'easeIn', 'easeOut', 'easeInOut'))
KEY_CURVES = frozenset(('linear', 'smooth'))


def _number(value):
    if isinstance(value, bool) or not isinstance(value, Real):
        raise ValueError('音量必须是有限数值')
    try:
        value = float(value)
    except (ValueError, TypeError, OverflowError):
        raise ValueError('音量必须是有限数值') from None
    if not math.isfinite(value):
        raise ValueError('音量必须是有限数值')
    return value


def _fraction(value):
    try:
        if isinstance(value, bool):
            raise ValueError
        result = value if isinstance(value, Fraction) else Fraction(str(value))
        if not math.isfinite(float(result)):
            raise ValueError
        return result
    except (ValueError, TypeError, ZeroDivisionError, OverflowError):
        raise ValueError('音量自动化时间无效') from None


def _seconds(value):
    if not isinstance(value, str) or not value.endswith('s'):
        raise ValueError('音量自动化时间无效')
    return _fraction(value[:-1])


def _db(value, suffix=False):
    if not isinstance(value, str) or not re.fullmatch(
            r'-?\d+(?:\.\d+)?dB' if suffix else r'-?\d+(?:\.\d+)?(?:dB)?', value):
        raise ValueError('音量自动化数值无效')
    result = float(value[:-2] if value.endswith('dB') else value)
    if not math.isfinite(result) or not -96 <= result <= 12:
        raise ValueError('音量超出支持范围')
    return result


@dataclass(frozen=True, slots=True)
class Fade:
    duration: Fraction
    kind: str

    def __post_init__(self):
        object.__setattr__(self, 'duration', _fraction(self.duration))
        if self.duration < 0 or not isinstance(self.kind, str) or self.kind not in FADE_TYPES:
            raise ValueError('音频淡化设置无效')


@dataclass(frozen=True, slots=True)
class Keyframe:
    time: Fraction
    db: float
    interp: str = 'linear'
    curve: str = 'smooth'

    def __post_init__(self):
        object.__setattr__(self, 'time', _fraction(self.time))
        object.__setattr__(self, 'db', _number(self.db))
        if (not -96 <= self.db <= 12 or not isinstance(self.interp, str)
                or self.interp != 'linear' or not isinstance(self.curve, str)
                or self.curve not in KEY_CURVES):
            raise ValueError('音量关键帧设置无效')


@dataclass(frozen=True, slots=True)
class Envelope:
    clock: int
    scale: Fraction
    shift: Fraction
    length: Fraction
    base_db: float
    fade_in: Fade | None = None
    fade_out: Fade | None = None
    keyframes: tuple[Keyframe, ...] = ()

    def __post_init__(self):
        if isinstance(self.clock, bool) or not isinstance(self.clock, int) or self.clock < 0:
            raise ValueError('音量自动化时钟无效')
        for name in ('scale', 'shift', 'length'):
            object.__setattr__(self, name, _fraction(getattr(self, name)))
        object.__setattr__(self, 'base_db', _number(self.base_db))
        object.__setattr__(self, 'keyframes', tuple(self.keyframes))
        if self.scale <= 0 or self.length <= 0 or not -96 <= self.base_db <= 12:
            raise ValueError('音量自动化范围无效')
        if any(fade is not None and not isinstance(fade, Fade) for fade in (self.fade_in, self.fade_out)):
            raise ValueError('音频淡化设置无效')
        if sum((fade.duration for fade in (self.fade_in, self.fade_out) if fade is not None), Fraction(0)) > self.length:
            raise ValueError('暂不支持淡入淡出重叠或超出片段范围；请导入整条时间线音频')
        if len(self.keyframes) > MAX_KEYS or any(not isinstance(key, Keyframe) for key in self.keyframes):
            raise ValueError('音量关键帧过多或无效')
        if any(right.time <= left.time for left, right in zip(self.keyframes, self.keyframes[1:])):
            raise ValueError('音量关键帧时间必须递增')


@dataclass(frozen=True, slots=True)
class Gain:
    factor: float
    curves: tuple[Envelope, ...] = ()

    def __post_init__(self):
        object.__setattr__(self, 'factor', _number(self.factor))
        object.__setattr__(self, 'curves', tuple(self.curves))
        if self.factor < 0 or len(self.curves) > MAX_CURVES or any(not isinstance(curve, Envelope) for curve in self.curves):
            raise ValueError('音量自动化曲线过多或无效')
        if sum(len(curve.keyframes) for curve in self.curves) > MAX_KEYS:
            raise ValueError('音量关键帧过多')

    def __mul__(self, other):
        return _gain(self.factor * factor(other), self.curves + curves(other))

    __rmul__ = __mul__

    def __truediv__(self, other):
        if curves(other) or factor(other) <= 0:
            raise ValueError('音量只能除以正的静态系数')
        return _gain(self.factor / factor(other), self.curves)

    def __rtruediv__(self, other):
        if self.curves or self.factor <= 0:
            raise ValueError('音量只能除以正的静态系数')
        return _gain(factor(other) / self.factor, curves(other))


def _gain(value, envelopes=()):
    result = Gain(value, tuple(envelopes))
    return result if result.curves else result.factor


def factor(gain):
    value = gain.factor if isinstance(gain, Gain) else _number(gain)
    if value < 0:
        raise ValueError('音量系数不能为负数')
    return value


def curves(gain):
    if isinstance(gain, Gain):
        return gain.curves
    factor(gain)
    return ()


def volume_gain(node, context=None):
    """Parse one supported volume parameter; bind its age to its owner clock.

    Canonical keyframes use the owner's parameter clock (start + output age),
    dB values, and linear interpolation between the corresponding amplitudes.
    The generic param DTD's default "smooth" does not change volume interpolation.
    """
    if node.tag != 'adjust-volume' or set(node.attrib) - {'amount'}:
        raise ValueError('音量结构无效')
    base_db = _db(node.get('amount', '0dB'), suffix=True)
    base = 10 ** (base_db / 20)
    if not len(node):
        return base
    if len(node) != 1 or node[0].tag != 'param':
        raise ValueError('暂不支持此音量参数结构')
    param = node[0]
    if param.get('name') != 'amount' or set(param.attrib) - {'name', 'value'}:
        raise ValueError('暂不支持此音量参数设置')
    if 'value' in param.attrib and _db(param.get('value')) != base_db:
        raise ValueError('音量参数初始值与片段音量不一致')
    tags = [child.tag for child in param]
    if tags != [name for name in ('fadeIn', 'fadeOut', 'keyframeAnimation') if name in tags]:
        raise ValueError('暂不支持此音量参数结构')
    if not tags:
        return base
    if context is None:
        raise ValueError('音量自动化缺少所属片段时钟')
    try:
        clock = context['clock']
        origin, start, length = (_fraction(context[name]) for name in ('origin', 'start', 'length'))
    except (KeyError, TypeError):
        raise ValueError('音量自动化缺少所属片段时钟') from None
    if length <= 0:
        raise ValueError('音量自动化范围无效')
    fades = {}
    for tag, default_kind in (('fadeIn', 'easeIn'), ('fadeOut', 'easeOut')):
        child = param.find(tag)
        if child is not None:
            if len(child) or set(child.attrib) - {'type', 'duration'}:
                raise ValueError('音频淡化设置无效')
            fades[tag] = Fade(_seconds(child.get('duration')), child.get('type', default_kind))
    animation = param.find('keyframeAnimation')
    keys = []
    if animation is not None:
        if animation.attrib or len(animation) > MAX_KEYS:
            raise ValueError('音量关键帧过多或无效')
        for key in animation:
            if key.tag != 'keyframe' or len(key) or set(key.attrib) - {'time', 'value', 'interp', 'curve'}:
                raise ValueError('音量关键帧结构无效')
            # Explicit linear attributes were ignored by FCP on import and
            # removed on export. Other explicit interpolations are unverified.
            if key.get('interp', 'linear') != 'linear' or key.get('curve', 'linear') != 'linear':
                raise ValueError('暂不支持此音量关键帧插值方式')
            keys.append(Keyframe(_seconds(key.get('time')) - start, _db(key.get('value')),
                                 key.get('interp', 'linear'), key.get('curve', 'smooth')))
    if not keys and not any(fade.duration for fade in fades.values()):
        return base
    envelope = Envelope(clock, Fraction(1), -origin, length, base_db,
                        fades.get('fadeIn'), fades.get('fadeOut'), tuple(keys))
    return _gain(base, (envelope,))


def remap_gain(gain, inner_clock, outer_clock, source_begin, output_begin, speed):
    """Compose localAge=a*innerTime+b with innerTime=speed*outputTime+c."""
    if any(isinstance(clock, bool) or not isinstance(clock, int) or clock < 0
           for clock in (inner_clock, outer_clock)):
        raise ValueError('音量自动化时钟无效')
    if not curves(gain):
        return factor(gain)
    source_begin, output_begin, speed = map(_fraction, (source_begin, output_begin, speed))
    if speed <= 0:
        raise ValueError('音量自动化不支持倒放或停帧时钟')
    mapped = []
    for envelope in curves(gain):
        if envelope.clock == inner_clock:
            envelope = replace(envelope, clock=outer_clock, scale=envelope.scale * speed,
                               shift=envelope.shift + envelope.scale * (source_begin - output_begin * speed))
        mapped.append(envelope)
    return _gain(factor(gain), mapped)


def materialize_gain(gain):
    """Expose only JSON values once every automation curve reaches clock 0."""
    output = []
    for envelope in curves(gain):
        if envelope.clock != 0:
            raise ValueError('音量自动化尚未映射到项目时钟')
        row = dict(clock=0, scale=str(envelope.scale), shift=str(envelope.shift),
                   length=str(envelope.length), baseDB=envelope.base_db)
        for key, fade in (('fadeIn', envelope.fade_in), ('fadeOut', envelope.fade_out)):
            if fade is not None:
                row[key] = dict(duration=str(fade.duration), type=fade.kind)
        row['keyframes'] = [dict(time=str(key.time), db=key.db, interp=key.interp, curve=key.curve)
                            for key in envelope.keyframes]
        output.append(row)
    return factor(gain), output


def _from_json(row):
    if not isinstance(row, dict) or set(row) - {'clock', 'scale', 'shift', 'length', 'baseDB', 'fadeIn', 'fadeOut', 'keyframes'}:
        raise ValueError('音量自动化输出结构无效')
    def fade(key):
        value = row.get(key)
        if value is None:
            return None
        if not isinstance(value, dict) or set(value) != {'duration', 'type'}:
            raise ValueError('音频淡化设置无效')
        return Fade(_fraction(value['duration']), value['type'])
    raw_keys = row.get('keyframes', [])
    if not isinstance(raw_keys, list) or len(raw_keys) > MAX_KEYS:
        raise ValueError('音量关键帧过多或无效')
    keys = []
    for key in raw_keys:
        if not isinstance(key, dict) or set(key) != {'time', 'db', 'interp', 'curve'}:
            raise ValueError('音量关键帧结构无效')
        keys.append(Keyframe(_fraction(key['time']), key['db'], key['interp'], key['curve']))
    try:
        envelope = Envelope(row.get('clock', 0), _fraction(row['scale']), _fraction(row['shift']),
                            _fraction(row['length']), row['baseDB'], fade('fadeIn'), fade('fadeOut'), tuple(keys))
    except KeyError:
        raise ValueError('音量自动化输出结构无效') from None
    if envelope.clock != 0:
        raise ValueError('音量自动化尚未映射到项目时钟')
    return envelope


def _ease(progress, kind):
    # Matched to actual FCP reference PCM, not inferred from generic DTD names.
    import numpy as np
    if kind == 'linear':
        return progress
    if kind == 'easeIn':
        return np.sin(progress * (math.pi / 2))
    if kind == 'easeOut':
        return 1 - np.cos(progress * (math.pi / 2))
    return (1 - np.cos(progress * math.pi)) / 2


def evaluate_envelopes(envelopes, start_sample, count, rate):
    """Evaluate normalized multipliers at the absolute output sample clock."""
    import numpy as np
    if (isinstance(start_sample, bool) or not isinstance(start_sample, int) or start_sample < 0
            or isinstance(count, bool) or not isinstance(count, int) or count < 0
            or isinstance(rate, bool) or not isinstance(rate, int) or rate <= 0):
        raise ValueError('音量自动化采样范围无效')
    if not isinstance(envelopes, (list, tuple)) or len(envelopes) > MAX_CURVES:
        raise ValueError('音量自动化曲线过多或无效')
    parsed = [envelope if isinstance(envelope, Envelope) else _from_json(envelope) for envelope in envelopes]
    if any(envelope.clock != 0 for envelope in parsed) or sum(len(envelope.keyframes) for envelope in parsed) > MAX_KEYS:
        raise ValueError('音量自动化时钟或关键帧无效')
    time = (np.arange(count, dtype=np.float64) + start_sample) / rate
    result = np.ones(count, dtype=np.float64)
    for envelope in parsed:
        age = float(envelope.scale) * time + float(envelope.shift)
        values = np.ones(count, dtype=np.float64)
        if envelope.keyframes:
            keys = envelope.keyframes
            values = np.interp(age, [float(key.time) for key in keys],
                               [10 ** (key.db / 20) for key in keys]) / (10 ** (envelope.base_db / 20))
        for fade, outgoing in ((envelope.fade_in, False), (envelope.fade_out, True)):
            if fade is None or fade.duration == 0:
                continue
            age_from_edge = float(envelope.length) - age if outgoing else age
            progress = np.clip(age_from_edge / float(fade.duration), 0, 1)
            values *= _ease(progress, fade.kind)
        result *= values
    if not np.isfinite(result).all():
        raise ValueError('音量自动化计算得到非有限数值')
    return result

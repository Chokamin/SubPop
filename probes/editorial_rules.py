# Adapted from the user-owned VinciSub subtitle rules; ported as independent text rules (not model training).
"""Subtitle timing, local lexical boundaries and SRT serialization."""

import math
import re
from dataclasses import asdict, dataclass
from .text_units import protected_ranges, display_length


@dataclass(frozen=True)
class Word:
    text: str
    start: float
    end: float


@dataclass(frozen=True)
class Caption:
    start: float
    end: float
    text: str


def validate_captions(rows):
    if not isinstance(rows, list) or not rows or len(rows) > 20000:
        raise ValueError("字幕必须为非空列表，且不超过 20000 条。")
    captions = []
    previous_end = 0
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            raise ValueError(f"第 {index} 条字幕格式错误。")
        try:
            start, end = float(row["start"]), float(row["end"])
            text = row["text"]
        except (KeyError, TypeError, ValueError):
            raise ValueError(f"第 {index} 条字幕缺少有效时间或文本。") from None
        if not all(math.isfinite(t) for t in (start, end)):
            raise ValueError(f"第 {index} 条字幕时间必须为有限数值。")
        start, end = round(start, 3), round(end, 3)
        if start < 0 or end <= start or start < previous_end:
            raise ValueError(f"第 {index} 条字幕时间无效或与上一条重叠。")
        if not isinstance(text, str) or not text.strip() or len(text) > 2000:
            raise ValueError(f"第 {index} 条字幕文本为空或过长。")
        # Prevent embedded blank lines from terminating an SRT cue.
        text = "\n".join(line.strip() for line in text.splitlines() if line.strip())
        if any(ord(c) < 32 and c != "\n" for c in text):
            raise ValueError(f"第 {index} 条字幕包含控制字符。")
        captions.append(Caption(start, end, text))
        previous_end = end
    return captions


def join_words(words):
    result = ""
    for word in words:
        token = word.text.strip()
        if result and token and result[-1].isascii() and result[-1].isalnum() and token[0].isascii() and token[0].isalnum():
            result += " "
        result += token
    return result


def merge_instant_words(words):
    """Merge coincident zero-width units into a neighbour's measured span.

    Aligners can put e.g. 我 at [3.84, 3.84] and 们 at [3.84, 4.16].
    Keep 我们 together at [3.84, 4.16]; never invent a duration for 我.
    """
    result, pending = [], []
    for word in words:
        if not word.text.strip():
            continue
        if not all(math.isfinite(t) for t in (word.start, word.end)) or word.start < 0 or word.end < word.start:
            raise ValueError("识别模型返回了无效时间戳，请重试。")
        if word.end == word.start:
            pending.append(word)
            continue
        if pending:
            if all(abs(w.start - word.start) <= .08 + 1e-9 for w in pending):
                word = Word(join_words(pending + [word]), min(pending[0].start, word.start), word.end)
            elif result and all(-.08 <= w.start-result[-1].end <= .2 + 1e-9
                                and w.start <= word.start for w in pending):
                # An interior instantaneous token can belong to the preceding
                # measured word, just like the already-supported trailing case.
                # Preserve its measured instant; do not assign an invented span.
                previous = result.pop()
                result.append(Word(join_words([previous] + pending), previous.start,
                                   max(previous.end, max(w.end for w in pending))))
            else:
                raise ValueError("模型返回的词语时间戳不完整，无法可靠对齐字幕；这与入点、出点设置无关。")
            pending.clear()
        result.append(word)
    if pending:
        if not result or any(not -.08 <= w.start - result[-1].end <= .2 + 1e-9 for w in pending):
            raise ValueError("模型返回的词语时间戳不完整，无法可靠对齐字幕；这与入点、出点设置无关。")
        previous = result.pop()
        # A trailing word may have a measured instant after a short gap.
        # Preserve that endpoint and the preceding measured span, without
        # assigning an arbitrary duration or dropping the trailing text.
        result.append(Word(join_words([previous] + pending), previous.start,
                           max(previous.end, max(w.end for w in pending))))
    return result


def punctuation_boundary(text, next_text=''):
    # A comma inside a number is not a spoken clause boundary.
    if re.search(r'\d,$', text.rstrip()) and re.match(r'\d', next_text.lstrip()):
        return None
    text = text.rstrip().rstrip('”’」』》〉】〕）)]}' + chr(34) + chr(39))
    if re.search(r'[。！？!?]$', text):
        return 'hard'
    if re.search(r'[，,；;]$', text):
        return 'soft'
    # Decimal numbers are not sentence boundaries.
    if text.endswith('.') and not re.search(r'\d\.$', text):
        return 'hard'
    return None


def aligned_text_words(tokens, text):
    """Attach punctuation and quotes to measured words without changing text."""
    words = []
    cursor = 0
    prefix = ''
    for token in tokens:
        value = token.text.strip()
        if not value:
            continue
        position = text.find(value, cursor)
        if position < 0:
            raise ValueError('对齐词语与字幕文字不一致')
        between = text[cursor:position]
        if any(c.isalnum() for c in between):
            raise ValueError('对齐遗漏字幕文字')
        if words:
            old = words.pop()
            # Opening quotes belong to the next word; closing quotes to the last.
            split = next((i for i,c in enumerate(between) if c in '“‘「『（('), len(between))
            words.append(Word(old.text + between[:split], old.start, old.end))
            prefix = between[split:]
        else:
            prefix = between
        words.append(Word(prefix + value, float(token.start_time), float(token.end_time)))
        cursor = position + len(value)
    suffix = text[cursor:]
    if not words or any(c.isalnum() for c in suffix):
        raise ValueError('对齐遗漏字幕文字')
    old = words.pop()
    words.append(Word(old.text + suffix, old.start, old.end))
    return words


def lexical_words(words, gap, protected_terms=()):
    """Join measured Chinese characters inside dictionary words, not silences."""
    parts, ends, cursor, previous = [], [], 0, ''
    for word in words:
        token = word.text.strip()
        separator = (' ' if previous and token and previous[-1].isascii()
                     and previous[-1].isalnum() and token[0].isascii() and token[0].isalnum() else '')
        parts.extend((separator, token))
        cursor += len(separator) + len(token)
        ends.append(cursor)
        previous = token
    text = ''.join(parts)
    if re.search(r'[\u3400-\u9fff]', text):
        import jieba
        jieba.setLogLevel(40)
        boundaries = {end for _, _, end in jieba.tokenize(text, HMM=False)}
    else:
        boundaries = set(ends)
    for left, right in protected_ranges(text, protected_terms):
        boundaries.difference_update(range(left+1, right))
    result, pending = [], []
    for i, word in enumerate(words):
        pending.append(word)
        if (ends[i] in boundaries or i+1 == len(words)
                or words[i+1].start-word.end >= gap):
            result.append(Word(join_words(pending), pending[0].start, pending[-1].end))
            pending = []
    return result


def make_captions(words, max_chars=20, max_duration=5.0, gap=0.5, protected_terms=()):
    if not 6 <= max_chars <= 60:
        raise ValueError("每条字数需在 6–60 之间。")
    captions, pending = [], []

    def flush():
        if pending:
            captions.append(Caption(pending[0].start, pending[-1].end, join_words(pending)))
            pending.clear()

    last_end = 0.0
    normalized = []
    for word in merge_instant_words(words):
        start = max(last_end, round(word.start, 3))
        end = round(word.end, 3)
        if end <= start:
            raise ValueError("识别时间戳发生倒序，无法可靠生成字幕。")
        normalized.append(Word(word.text, start, end))
        last_end = end
    measured = lexical_words(normalized, gap, protected_terms)
    last_end = 0.0
    for index, word in enumerate(measured):
        if not word.text.strip():
            continue
        if not all(math.isfinite(t) for t in (word.start, word.end)) or word.start < 0 or word.end <= word.start:
            raise ValueError("识别模型返回了无效时间戳，请重试。")
        # Small aligner overlaps are trimmed; never fabricate proportional timings.
        start = max(last_end, round(word.start, 3))
        end = round(word.end, 3)
        if end <= start:
            raise ValueError("识别时间戳发生倒序，无法可靠生成字幕。")
        word = Word(word.text, start, end)
        if pending and start - pending[-1].end >= gap:
            flush()
        elif (pending and start - pending[-1].end >= min(gap, .25)
              and sum(c.isalnum() for c in join_words(pending)) >= 6
              and pending[-1].end - pending[0].start >= 1.0):
            # A measured breath can end a readable phrase even without commas.
            flush()
        if pending and (display_length(join_words(pending + [word])) > max_chars or end - pending[0].start > max_duration):
            boundary = next((n+1 for n in range(len(pending)-1, -1, -1)
                             if punctuation_boundary(pending[n].text,
                                 pending[n+1].text if n+1 < len(pending) else word.text)), None)
            if boundary is None:
                # Near the limit, prefer a real pause with useful text on both
                # sides. Do not manufacture semantic or proportional timings.
                candidates = [n for n in range(1, len(pending))
                              if pending[n].start - pending[n-1].end >= .12
                              and sum(c.isalnum() for c in join_words(pending[:n])) >= 3
                              and sum(c.isalnum() for c in join_words(pending[n:] + [word])) >= 3]
                boundary = max(candidates, key=lambda n: pending[n].start-pending[n-1].end,
                               default=None)
            if boundary:
                rest = pending[boundary:]
                del pending[boundary:]
                flush()
                pending.extend(rest)
            if pending and (display_length(join_words(pending + [word])) > max_chars or end - pending[0].start > max_duration):
                flush()
        pending.append(word)
        last_end = end
        boundary = punctuation_boundary(word.text, measured[index+1].text if index+1 < len(measured) else '')
        if boundary == 'hard':
            flush()
        elif boundary == 'soft':
            text = join_words(pending)
            # Short introductory words can stay with the following clause. Longer
            # spoken clauses break at the comma instead of accumulating commas.
            length = sum(c.isalnum() for c in text)
            if length >= 4 or pending[-1].end - pending[0].start >= 1.0:
                flush()
    flush()
    return validate_captions([asdict(c) for c in captions]) if captions else []


def bridge_brief_gaps(captions, max_gap=.2):
    """Keep text visible across tiny gaps; leave onsets and long pauses intact."""
    result = list(captions)
    for i in range(len(result)-1):
        current, following = result[i:i+2]
        if 0 < following.start-current.end <= max_gap+1e-9:
            result[i] = Caption(current.start, following.start, current.text)
    return result


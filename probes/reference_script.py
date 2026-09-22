"""Conservative, local reference-script assistance on measured speech.

The script is data, never an instruction or a replacement transcript. Only
anchored homophones and equivalent spellings can change; unmatched speech,
omissions, numbers with different values and negations remain untouched.
"""
from collections import Counter, defaultdict
from dataclasses import dataclass
from difflib import SequenceMatcher
import hashlib
import re
import unicodedata

from .editorial_rules import Word
from .vocabulary import _chinese_integer

VERSION = 'reference-v1'
MAX_LENGTH = 20000
_HAN = re.compile(r'^[\u3400-\u9fff]+$')
_TOKENS = re.compile(r'[A-Za-z]+|\d+(?:[.,:/%-]\d+)*|[零〇一二两三四五六七八九十百千]+|[^\W_]', re.UNICODE)
_NEGATION = set('不没无未别非勿否莫甭')
_NUMBERS = {str(i): str(i) for i in range(10000)}
_NUMBERS.update({_chinese_integer(i): str(i) for i in range(10000)})
_NUMBERS.update({'〇': '0', '两': '2'})


def validate(text):
    if not isinstance(text, str):
        raise ValueError('参考脚本必须为文本')
    if len(text.encode('utf-16-le')) // 2 > MAX_LENGTH:
        raise ValueError('参考脚本最多 20000 字')
    if any(unicodedata.category(c) == 'Cc' and c not in '\n\r\t' for c in text):
        raise ValueError('参考脚本不能包含控制字符')
    return text.strip()


def digest(text):
    text = validate(text)
    return hashlib.sha256(text.encode()).hexdigest() if text else ''


@dataclass(frozen=True)
class Token:
    text: str
    key: str
    start: int
    end: int


def tokenize(text):
    tokens = []
    for match in _TOKENS.finditer(text):
        value = match.group()
        # Normalize equivalent integers, without conflating model numbers,
        # decimal points, leading zero identifiers or different spoken values.
        number = _NUMBERS.get(value)
        key = '#' + number if number is not None else unicodedata.normalize('NFKC', value).casefold()
        tokens.append(Token(value, key, match.start(), match.end()))
    return tokens


def _homophones(left, right):
    if not (0 < len(left) == len(right) <= 4 and _HAN.fullmatch(left) and _HAN.fullmatch(right)):
        return False
    if _NEGATION.intersection(left + right) or any(c in '零〇一二两三四五六七八九十百千万亿' for c in left + right):
        return False
    from pypinyin import lazy_pinyin
    return lazy_pinyin(left) == lazy_pinyin(right)


class ReferenceScript:
    def __init__(self, text):
        self.text = validate(text)
        self.tokens = tokenize(self.text)
        self.keys = [t.key for t in self.tokens]
        self.index = defaultdict(list)
        for i in range(len(self.keys) - 2):
            self.index[tuple(self.keys[i:i+3])].append(i)
        self.report = dict(version=VERSION, enabled=bool(self.text), matchedSections=0,
                           correctionCount=0, boundaryCount=0, changes=[])

    def _matches(self, tokens):
        """Retrieve bounded local passages; order/repeated takes may differ."""
        keys = [t.key for t in tokens]
        votes = Counter()
        for i in range(len(keys) - 2):
            locations = self.index.get(tuple(keys[i:i+3]), ())
            # Repeated filler cannot establish a reliable script location.
            if len(locations) > 40:
                continue
            for j in locations:
                votes[j-i] += 1
        candidates = []
        for offset, _ in votes.most_common(8):
            start = max(0, offset - 8)
            end = min(len(self.keys), offset + len(keys) + 8)
            matcher = SequenceMatcher(None, keys, self.keys[start:end], autojunk=False)
            blocks = matcher.get_matching_blocks()
            matched = sum(b.size for b in blocks)
            if matched < 6 or matched / max(1, len(keys)) < .55:
                continue
            ops = [(tag, a, b, start+c, start+d) for tag, a, b, c, d in matcher.get_opcodes()]
            location = tuple((a, c, b-a) for tag, a, b, c, d in ops if tag == 'equal')
            if any(location == old[2] for old in candidates):
                continue
            candidates.append((matched, ops, location))
        candidates.sort(key=lambda c: c[0], reverse=True)
        if not candidates:
            return []
        # Distinct, equally plausible passages must not pick arbitrary wording.
        best = candidates[0]
        best_edits = self._edits(tokens, best[1])
        for candidate in candidates[1:]:
            if candidate[0] < best[0] - 1:
                break
            if self._edits(tokens, candidate[1]) != best_edits:
                return []
        return best[1]

    def _edits(self, tokens, ops):
        edits = []
        for i, (tag, a, b, c, d) in enumerate(ops):
            if tag == 'replace' and i and i+1 < len(ops):
                previous, following = ops[i-1], ops[i+1]
                if previous[0] != 'equal' or following[0] != 'equal':
                    continue
                if previous[2]-previous[1] < 3 or following[2]-following[1] < 3:
                    continue
                left = ''.join(t.text for t in tokens[a:b])
                right = ''.join(t.text for t in self.tokens[c:d])
                if _homophones(left, right):
                    edits.append((tokens[a].start, tokens[b-1].end, right, 'homophone'))
            elif tag == 'equal' and b-a >= 3:
                # Preserve script spelling of Latin names, spaces and equivalent
                # integer notation only within a well-matched local passage.
                j = a
                while j < b:
                    k = j
                    while k < b and (tokens[k].key.startswith('#') or tokens[k].text.isascii()):
                        k += 1
                    if k == j:
                        j += 1
                        continue
                    r, s = c+j-a, c+k-a
                    original = tokens[j:k]
                    replacement = re.sub(r'\s+', ' ', self.text[self.tokens[r].start:self.tokens[s-1].end])
                    # A sentence delimiter must never be swallowed as name spacing.
                    if not re.search(r'[^A-Za-z0-9零〇一二两三四五六七八九十百千.,:/%+\-\s]', replacement):
                        edits.append((original[0].start, original[-1].end, replacement, 'spelling'))
                    j = k
        return edits

    def apply(self, words, *, boundaries=True, protected_terms=()):
        if not self.tokens or not words:
            return words
        text = ''.join(w.text for w in words)
        protected=[m.span() for term in protected_terms if term for m in re.finditer(re.escape(term),text,re.IGNORECASE)]
        tokens = tokenize(text)
        edits, boundary_edits = {}, {}
        # Bounded windows keep long scripts/ASR paragraphs responsive. Context
        # overlaps are deduplicated; no whole-script quadratic alignment.
        for offset in range(0, len(tokens), 96):
            chunk = tokens[max(0, offset-12):offset+108]
            ops = self._matches(chunk)
            if not ops:
                continue
            self.report['matchedSections'] += 1
            for a, b, value, kind in self._edits(chunk, ops):
                if text[a:b] != value:
                    edits[(a, b)] = (value, kind)
            if boundaries:
                for tag, a, b, c, d in ops:
                    if tag != 'equal' or b-a < 6:
                        continue
                    for j in range(a+2, b-2):
                        r = c+j-a
                        gap = self.text[self.tokens[r].end:self.tokens[r+1].start]
                        original_gap = text[chunk[j].end:chunk[j+1].start]
                        if re.search(r'[。！？!?；;，,\n]', gap) and not re.search(r'[。！？!?；;，,\n]', original_gap):
                            boundary_edits[chunk[j].end] = '。' if re.search(r'[。！？!?\n]', gap) else '，'
        spans, cursor = [], 0
        for word in words:
            spans.append((cursor, cursor+len(word.text)))
            cursor += len(word.text)
        groups = []
        accepted_end=-1
        for (a, b), (value, kind) in sorted(edits.items(), key=lambda item:(item[0][0],-item[0][1])):
            if a<accepted_end:continue
            if any(a<right and b>left for left,right in protected):continue
            indices = [i for i, (start, end) in enumerate(spans) if start < b and end > a]
            if not indices:
                continue
            first, last = indices[0], indices[-1]
            if any(words[i+1].start-words[i].end > .5 for i in range(first, last)):
                continue
            # Never delete punctuation from the actual speech inside a spelling.
            if kind == 'spelling' and re.search(r'[。！？!?；;，,\n]', text[a:b]):
                continue
            accepted_end=b
            if groups and first <= groups[-1][1]:
                groups[-1][1] = max(last, groups[-1][1])
                groups[-1][2].append((a, b, value))
            else:
                groups.append([first, last, [(a, b, value)]])
            self.report['correctionCount'] += 1
            if len(self.report['changes']) < 200:
                self.report['changes'].append(dict(before=text[a:b], after=value, kind=kind,
                                                  start=words[first].start, end=words[last].end))
        output = list(words)
        # A script break is usable only at an already measured token boundary.
        for i, (a, b) in enumerate(spans):
            spoken_end = b - len(words[i].text) + len(words[i].text.rstrip())
            if spoken_end in boundary_edits and not any(first <= i <= last for first, last, _ in groups):
                output[i] = Word(words[i].text.rstrip()+boundary_edits[spoken_end], words[i].start, words[i].end)
                self.report['boundaryCount'] += 1
        for first, last, changes in reversed(groups):
            origin = spans[first][0]
            replacement = text[origin:spans[last][1]]
            for a, b, value in reversed(changes):
                replacement = replacement[:a-origin] + value + replacement[b-origin:]
            output[first:last+1] = [Word(replacement, words[first].start, words[last].end)]
        return output


def refine_rows(rows, script, vocabulary=()):
    """Existing edited captions keep exact row boundaries and measured times."""
    reference = ReferenceScript(script)
    output = []
    if not isinstance(rows, list) or not 0 < len(rows) <= 20000:
        raise ValueError('无效的字幕列表')
    total = 0
    for index,row in enumerate(rows):
        if not isinstance(row, dict) or not isinstance(row.get('text'), str) or not 0 < len(row['text']) <= 500:
            raise ValueError('无效的字幕文字')
        total += len(row['text'])
        if total > 200000:
            raise ValueError('当前字幕超过脚本整理上限')
        # No new timestamps: this only rewrites inside an existing cue.
        previous=len(reference.report['changes'])
        changed = reference.apply([Word(row['text'], 0, 1)], boundaries=False,protected_terms=vocabulary)[0].text
        for change in reference.report['changes'][previous:]:
            change.pop('start',None);change.pop('end',None);change['captionIndex']=index
        output.append({**row, 'text': changed})
    return output, reference.report

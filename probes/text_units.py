"""Functional text units that must survive display cleanup and segmentation."""
import re
import unicodedata

# These are written values/identifiers, not sentence punctuation. Keep them
# intact: dropping the dot in 0.1 or the slash in 1/30 changes the meaning.
_NUMBER = re.compile(r'(?<![A-Za-z0-9_.])[+\-−]?\d+(?:[.,]\d+)*(?:[:/\-–]\d+(?:[.,]\d+)*)*(?:\s*(?:[%‰]|(?:kWh|kHz|MHz|GHz|Hz|fps|Mbps|Gbps|GB|MB|TB|KB|mm|cm|km|kg|ms|s|m|g|K|V|W|h)(?![A-Za-z])|毫米|厘米|公里|毫秒|分钟|英寸|千克|公斤|像素|赫兹|秒|米|度|档|元|倍))?')
_IDENTIFIER = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z][A-Za-z0-9]*(?:(?:[-'’][A-Za-z0-9]+)+|(?:\.\d+)+|\+\+|#)")


def protected_ranges(text, terms=()):
    spans = [(m.start(), m.end()) for pattern in (_NUMBER, _IDENTIFIER)
             for m in pattern.finditer(text)]
    for term in terms:
        term = term.strip()
        if not term:
            continue
        pattern = r'\s+'.join(re.escape(part) for part in term.split())
        spans.extend((m.start(), m.end()) for m in re.finditer(pattern, text, re.IGNORECASE))
    return spans


def display_length(text):
    """Approximate full-width characters: ASCII uses half a Chinese character."""
    return sum(.5 if c.isascii() else 1 for c in text if not unicodedata.combining(c))


def clean_generated_text(text):
    protected = {i for a, b in protected_ranges(text) for i in range(a, b)}
    result = []
    for i, char in enumerate(text):
        if not unicodedata.category(char).startswith('P') or i in protected:
            result.append(char)
        elif (i and i+1 < len(text) and text[i-1].isascii() and (text[i-1].isalnum() or text[i-1] in '+#')
              and text[i+1].isascii() and text[i+1].isalnum()):
            # Removing a sentence delimiter must not glue English words together.
            result.append(' ')
    return ''.join(result).strip()

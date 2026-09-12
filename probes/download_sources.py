"""Allowlisted sources; all bytes still use the same pinned upstream SHA-256."""
SOURCES={
    'auto':[('国内镜像 HF-Mirror','https://hf-mirror.com'),('Hugging Face 官方','https://huggingface.co')],
    'official':[('Hugging Face 官方','https://huggingface.co')],
}

def sources(value):
    if not isinstance(value,str) or value not in SOURCES:raise ValueError('Unknown model download source')
    return SOURCES[value]

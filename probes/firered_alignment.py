"""CPU CTC Viterbi alignment; impossible paths fail rather than inventing times."""
import numpy as np


def forced_align(log_probs, tokens, blank=0):
    scores = np.asarray(log_probs)
    tokens = np.asarray(tokens, dtype=np.int64)
    if scores.ndim != 2 or tokens.ndim != 1 or not len(tokens) or not len(scores):
        raise ValueError('FireRed 时间对齐输入为空或形状无效')
    if (tokens == blank).any() or (tokens < 0).any() or (tokens >= scores.shape[1]).any():
        raise ValueError('FireRed 时间对齐包含无效字符')
    if not np.isfinite(scores).all():
        raise ValueError('FireRed 时间对齐分数无效')
    if len(scores) < len(tokens) + int(np.sum(tokens[1:] == tokens[:-1])):
        raise ValueError('FireRed 时间对齐失败：音频帧不足')
    labels = np.full(2 * len(tokens) + 1, blank, dtype=np.int64)
    labels[1::2] = tokens
    skip = np.zeros(len(labels), dtype=bool)
    skip[2:] = (labels[2:] != blank) & (labels[2:] != labels[:-2])
    previous = np.full(len(labels), -np.inf)
    previous[:2] = scores[0, labels[:2]]
    trace = np.zeros((len(scores), len(labels)), dtype=np.uint8)
    for t in range(1, len(scores)):
        options = np.full((3, len(labels)), -np.inf)
        options[0] = previous
        options[1, 1:] = previous[:-1]
        options[2, 2:] = previous[:-2]
        options[2, ~skip] = -np.inf
        trace[t] = np.argmax(options, axis=0)
        previous = np.max(options, axis=0) + scores[t, labels]
    state = len(labels) - 2 + int(previous[-1] > previous[-2])
    if not np.isfinite(previous[state]):
        raise ValueError('FireRed 时间对齐失败：没有完整路径')
    alignment = np.empty(len(scores), dtype=np.int64)
    for t in range(len(scores)-1, -1, -1):
        alignment[t] = labels[state]
        state -= int(trace[t, state])
    return alignment.tolist()

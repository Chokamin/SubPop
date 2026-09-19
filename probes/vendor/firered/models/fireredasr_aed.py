# Copyright 2026 Xiaohongshu. (Author: Kaituo Xu)



import torch
from probes.firered_alignment import forced_align

from .module.conformer_encoder import ConformerEncoder
from .module.ctc import CTC
from .module.transformer_decoder import TransformerDecoder


class FireRedAsrAed(torch.nn.Module):
    @classmethod
    def from_args(cls, args):
        return cls(args)

    def __init__(self, args):
        super().__init__()
        self.sos_id = args.sos_id
        self.eos_id = args.eos_id

        self.encoder = ConformerEncoder(
            args.idim, args.n_layers_enc, args.n_head, args.d_model,
            args.residual_dropout, args.dropout_rate,
            args.kernel_size, args.pe_maxlen)

        self.decoder = TransformerDecoder(
            args.sos_id, args.eos_id, args.pad_id, args.odim,
            args.n_layers_dec, args.n_head, args.d_model,
            args.residual_dropout, args.pe_maxlen)

        self.ctc = CTC(args.odim, args.d_model)

    def transcribe(self, padded_input, input_lengths,
                   beam_size=1, nbest=1, decode_max_len=0,
                   softmax_smoothing=1.0, length_penalty=0.0, eos_penalty=1.0,
                   return_timestamp=False, elm=None, elm_weight=0.0):
        enc_outputs, enc_lengths, enc_mask = self.encoder(padded_input, input_lengths)
        nbest_hyps = self.decoder.batch_beam_search(
            enc_outputs, enc_mask,
            beam_size, nbest, decode_max_len,
            softmax_smoothing, length_penalty, eos_penalty,
            elm, elm_weight)
        if return_timestamp:
            nbest_hyps = self.get_token_timestamp_torchaudio(enc_outputs, enc_lengths, nbest_hyps)
        return nbest_hyps

    def get_token_timestamp_torchaudio(self, enc_outputs, enc_lengths, nbest_hyps):
        ctc_logits = self.ctc(enc_outputs)
        enc_lengths = enc_lengths
        for n in range(enc_outputs.size(0)):
            logits = ctc_logits[n, :enc_lengths[n]].detach().cpu().numpy()
            y = nbest_hyps[n][0]["yseq"]
            y = y[y != 0].cpu().numpy()
            if not len(y):
                nbest_hyps[n][0]["timestamp"] = ([], [])
                continue
            alignment = forced_align(logits, y)
            starts, ends = self.ctc.ctc_alignment_to_timestamp(
                alignment, self.encoder.input_preprocessor.subsampling, blank_id=0)
            if len(starts) != len(y):
                raise ValueError("FireRed 时间对齐不完整，请重试")
            nbest_hyps[n][0]["timestamp"] = (starts, ends)
        return nbest_hyps

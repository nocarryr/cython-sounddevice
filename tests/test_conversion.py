import pytest

import numpy as np

from cysounddevice import types
from _test_conversion import BufferWrapper, build_buffer

def build_signal(fs, length, nchannels, fc=1000):
    t = np.arange(length) / fs
    a = np.sin(2*np.pi*fc*t)
    result = np.zeros((nchannels, length), dtype=a.dtype)
    roll_factor = int(length / nchannels // 2)
    for i in range(nchannels):
        result[i,:] = np.roll(a, i * roll_factor)
    return np.asarray(result, dtype='float32')

def test_converters(sample_rate, block_size, sample_format):
    # if sample_format['is_signed']:
    #     return
    if sample_format['is_24bit']:
        bfr_dtype = np.dtype('float32')
    else:
        bfr_dtype = np.dtype(sample_format['name'])

    for nchannels in [1,2,4,8]:

        print(f'sample_format={sample_format}, nchannels={nchannels}, bfr_dtype={bfr_dtype}')

        bfr = build_buffer(sample_rate, block_size, nchannels, sample_format['name'])

        for fc in [500, 1000, 10000]:
            sig = build_signal(sample_rate, block_size, nchannels)
            sig *= .9
            sig_orig = np.array(sig.tolist(), dtype='float32')

            # bfr.pack_buffer_item(sig)
            # packed = bfr.unpack_buffer_item()
            packed = bfr.pack_and_unpack_item(sig)

            if sample_format['name'] == 'float32':
                assert np.array_equal(sig_orig, packed)
            else:
                tolerance = sample_format['float32_multiplier']
                assert np.abs(sig_orig - packed).max() <= tolerance

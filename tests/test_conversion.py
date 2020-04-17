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
    NCHANNELS_LIST = [1,2,4,8]
    FC_LIST = [500, 1000, 10000]
    NBLOCKS = 8

    sig_array = np.zeros((max(NCHANNELS_LIST), len(FC_LIST), NBLOCKS, block_size), dtype=np.float32)

    for i, fc in enumerate(FC_LIST):
        for j in range(NBLOCKS):
            sig = build_signal(sample_rate, block_size, max(NCHANNELS_LIST), fc)
            sig_array[:,i,j,:] = sig

    nse = np.random.uniform(-.5, .5, sig_array.shape)
    sig_array *= nse
    sig_array *= .9

    ptp = 2 ** sample_format['bit_width']
    tolerance = 1. / (ptp / 2)

    for i, nchannels in enumerate(NCHANNELS_LIST):

        print(f'sample_format={sample_format}, nchannels={nchannels}')

        bfr = build_buffer(sample_rate, block_size, nchannels, sample_format['name'])

        for j, fc in enumerate(FC_LIST):

            sig = sig_array[:nchannels,j]
            sig_orig = np.array(sig.tolist(), dtype='float32')

            packed = bfr.pack_and_unpack_items(sig)

            if sample_format['name'] == 'float32':
                assert np.array_equal(sig_orig, packed)
            else:
                assert np.abs(sig_orig - packed).max() <= tolerance

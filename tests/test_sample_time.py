import time
import pytest

import numpy as np

from cysounddevice.types import SampleTime
# import _test_sample_time

SAMPLE_RATES = [
    22050, 44100, 48000, 88200, 96000,
]

BLOCK_SIZES = [
    256, 512, 1024,
]

# USE_CYTHON = True

@pytest.fixture(params=SAMPLE_RATES)
def sample_rate(request):
    return request.param

@pytest.fixture(params=BLOCK_SIZES)
def block_size(request):
    return request.param

def test_blocks(sample_rate, block_size):
    max_blocks = 256
    # if USE_CYTHON:
    #     _test_sample_time.test_blocks(sample_rate, block_size, max_blocks)
    #     return
    st1 = SampleTime(sample_rate, block_size)
    st2 = st1.copy()

    # Check copy operation
    assert st1 is not st2
    assert st1 == st2


    expected_sample_index = 0
    for cur_blk in range(max_blocks):
        for block_index in range(block_size):
            st1.block = cur_blk
            st1.block_index = block_index
            assert st1.sample_index == expected_sample_index

            if expected_sample_index > 0:
                # Make sure the copy is not altered yet
                assert st1 != st2
                assert st1 > st2
                assert st1 >= st2
                assert st2 < st1
                assert st2 <= st1

            st2.sample_index = expected_sample_index
            assert st2.block == cur_blk
            assert st2.block_index == block_index
            assert st1 == st2
            assert st1 <= st2
            assert st1 >= st2
            assert st2 <= st1
            assert st2 >= st1

            expected_sample_index += 1


def test_time(sample_rate, block_size):
    max_blocks = 256
    # if USE_CYTHON:
    #     _test_sample_time.test_time(sample_rate, block_size, max_blocks)
    #     return
    st1 = SampleTime(sample_rate, block_size)
    st2 = st1.copy()

    oth_sample_times = {}
    for oth_sample_rate in SAMPLE_RATES:
        if oth_sample_rate == sample_rate:
            continue
        oth_st = SampleTime(oth_sample_rate, block_size)
        oth_sample_times[oth_sample_rate] = oth_st


    expected_times = np.arange(block_size * max_blocks) / sample_rate
    expected_times = np.reshape(expected_times, (max_blocks, block_size))

    def check_other_sample_rate(oth_sample_rate, orig_sample_time):
        oth_st = oth_sample_times[oth_sample_rate]
        oth_st.pa_time = orig_sample_time.pa_time
        oth_sample_index = round(orig_sample_time.pa_time * oth_sample_rate)
        assert oth_st.sample_index == oth_sample_index

    expected_sample_index = 0
    for cur_blk in range(max_blocks):
        for block_index in range(block_size):
            st1.block = cur_blk
            st1.block_index = block_index

            assert st1.pa_time == expected_times[cur_blk, block_index]

            st2.pa_time = expected_times[cur_blk, block_index]
            assert st2.block == cur_blk
            assert st2.block_index == block_index
            assert st2.sample_index == expected_sample_index
            assert st1 == st2

            for oth_sample_rate in SAMPLE_RATES:
                if oth_sample_rate == sample_rate:
                    continue
                check_other_sample_rate(oth_sample_rate, st1)

            expected_sample_index += 1

def test_time_offset(sample_rate, block_size):
    max_blocks = 256
    # if USE_CYTHON:
    #     _test_sample_time.test_time_offset(sample_rate, block_size, max_blocks)
    #     return
    st1 = SampleTime(sample_rate, block_size)
    st2 = st1.copy()
    time_offset = time.time()
    st2.time_offset = time_offset


    expected_times = np.arange(block_size * max_blocks) / sample_rate
    expected_times = np.reshape(expected_times, (max_blocks, block_size))
    expected_times_offset = expected_times + time_offset

    expected_sample_index = 0
    for cur_blk in range(max_blocks):
        for block_index in range(block_size):
            st1.block = cur_blk
            st1.block_index = block_index

            assert st1.pa_time == expected_times[cur_blk, block_index]
            assert st1.rel_time == expected_times[cur_blk, block_index]

            st2.pa_time = expected_times_offset[cur_blk, block_index]

            assert st2.block == cur_blk
            assert st2.block_index == block_index
            assert st2.sample_index == expected_sample_index
            assert st2.pa_time == expected_times_offset[cur_blk, block_index]
            assert st2.rel_time == st1.rel_time == expected_times[cur_blk, block_index]
            assert st1 == st2
            assert st1.pa_time < st2.pa_time

            expected_sample_index += 1

def test_math_ops(sample_rate, block_size):
    max_blocks = 128
    # if USE_CYTHON:
    #     _test_sample_time.test_math_ops(sample_rate, block_size, max_blocks)
    #     return
    st1 = SampleTime(sample_rate, block_size)
    st2 = st1.copy()
    time_offset = time.time()
    st2.time_offset = time_offset

    expected_times = np.arange(block_size * max_blocks) / sample_rate
    expected_times = np.reshape(expected_times, (max_blocks, block_size))

    sample_interval = 1 / sample_rate
    block_interval = block_size / sample_rate

    expected_sample_index = 0
    for cur_blk in range(max_blocks):
        for block_index in range(block_size):

            # Set st1 to the current block/block_index
            st1.pa_time = expected_times[cur_blk, block_index]
            assert st1.sample_index == expected_sample_index

            # Set st2 to the same index, but on block 0
            # so we can add from it to st4
            st2.block = 0
            st2.block_index = block_index
            assert st2.rel_time == expected_times[0,block_index]

            #
            st3 = st1 + sample_interval
            assert st3.sample_index == expected_sample_index + 1
            assert st3 > st1

            st3 -= sample_interval
            assert st3.sample_index == expected_sample_index
            assert st3 == st1

            # Add st1 (current block/index) and st2 (block=0, index=block_index)
            # The result should add `block_index * 2` to the total sample_index count
            st4 = st1 + st2
            added_samples = st1.sample_index + st2.sample_index - expected_sample_index
            assert st4.sample_index == expected_sample_index + added_samples

            # Do the same thing, but add by time value
            st5 = st1 + (added_samples * sample_interval)
            assert st5 == st4

            # Subtract by the same amount we added to get st4 (using in-place op).
            # Now we should be back where we started
            st4 -= (added_samples * sample_interval)
            st5 -= st2

            assert st4 == st5 == st1

            expected_sample_index += 1

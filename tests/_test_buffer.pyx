# cython: language_level=3

import time

from cython cimport view
from cpython cimport array
import array
import numpy as np
cimport numpy as np

from cysounddevice.types cimport *
from cysounddevice.types import FLOAT32_DTYPE
from cysounddevice.buffer cimport (
    SampleBuffer,
    BufferItem,
    sample_buffer_create,
    sample_buffer_destroy,
    sample_buffer_write,
    sample_buffer_read,
    sample_buffer_read_sf32,
)

cdef bint check_char_array(float[:,:] arr_view, void *data_ptr, Py_ssize_t length) except *:
    # print('check_char_array')
    # time.sleep(.1)
    cdef Py_ssize_t nchannels = arr_view.shape[0]
    assert length == arr_view.shape[1]
    cdef view.array data_view = view.array(
            shape=(length*nchannels,),
            itemsize=sizeof(float),
            format='f',
            allocate_buffer=False,
        )
    # print('set data_ptr')
    # time.sleep(.1)
    data_view.data = <char *>data_ptr
    cdef Py_ssize_t i, chan_num, chan_ix
    # print('iterating')
    # time.sleep(.1)
    i = 0
    for chan_ix in range(length):
        for chan_num in range(nchannels):
            if arr_view[chan_num,chan_ix] != data_view[i]:
                return False
            i += 1
    #
    # for i in range(length):
    #     if arr_view[i] != data_view[i]:
    #         # print('!=')
    #         # time.sleep(.1)
    #         return False
    # print('==')
    # time.sleep(.1)
    return True

cdef int test_write(SampleBuffer* bfr, const float[:,:] data) except -1:
    cdef Py_ssize_t nchannels = data.shape[0]
    cdef Py_ssize_t block_size = data.shape[1]
    cdef Py_ssize_t i, chan_num, chan_ix
    cdef view.array data_view = view.array(
            shape=(nchannels*block_size,),
            itemsize=sizeof(float),
            format='f',
            allocate_buffer=True,
        )
    i = 0
    for chan_ix in range(block_size):
        for chan_num in range(nchannels):
            data_view[i] = data[chan_num,chan_ix]
            i += 1
    cdef int write_result = sample_buffer_write(bfr, data_view.data, block_size)
    return write_result

cdef SampleTime_s* test_read(SampleBuffer* bfr, float[:,:] data) except *:
    # cdef void *cbfr
    cdef Py_ssize_t block_size = data.shape[1]
    cdef float[:,::1] data_view = data.copy()
    # cdef SampleTime_s* = sample_buffer_read(bfr, cbfr, block_size)
    cdef SampleTime_s* start_time = sample_buffer_read_sf32(bfr, data_view)
    data[...] = data_view
    return start_time

cdef bint _test() except *:
    cdef Py_ssize_t length = 32
    cdef Py_ssize_t nchannels = 2
    cdef Py_ssize_t itemsize = 4
    cdef Py_ssize_t block_size = 512
    cdef Py_ssize_t i, j, k
    cdef bint success = False
    cdef int write_result
    cdef SampleTime s = SampleTime(48000, block_size)
    cdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] sarray = np.zeros((length, block_size), dtype=FLOAT32_DTYPE)

    sarray[...,:] = np.sin(np.arange(block_size))
    for i in range(length):
        sarray[i] = np.roll(sarray[i], i)


    cdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] sarray_write, sarray_read, sarray_temp

    # cdef float[:,::1] sarray_view = sarray
    # cdef float[:,::1] sarray_orig = sarray_view.copy()
    # cdef float[::1] _sarray_view = sarray_view[0,:]
    # for i in range(block_size):
    #     assert _sarray_view[i] == sarray[0][i]

    cdef SampleTime_s* read_start_time
    # cdef void *read_bfr
    # cdef float sarray_read[512]
    # for i in range(block_size):
    #     sarray_read[i] = 0.
    # cdef float[::1] _sarray_read_view = sarray_read


    cdef int write_available = length
    cdef int read_available = 0

    cdef SampleBuffer* bfr = sample_buffer_create(s, length, nchannels, itemsize)
    cdef BufferItem* bfr_item
    print('created')
    try:
        for i in range(length):
            bfr_item = &bfr.items[i]
            assert bfr_item.index == i
            assert bfr_item.itemsize == itemsize
            assert bfr_item.nchannels == nchannels
            assert bfr_item.total_size == itemsize * block_size * nchannels
            assert bfr_item.start_time.block == i

        assert bfr.write_available == write_available
        for i in range(length):
            print('write: {}'.format(i))
            # sarray_ptr = <char *>sarray[i]
            # _sarray_view[:] = sarray_view[i,:]
            sarray_write = np.vstack((sarray[i], sarray[i]))
            sarray_write[1] *= -1
            assert bfr.write_index == i
            # write_result = sample_buffer_write(bfr, &_sarray_view[0], block_size)
            write_result = test_write(bfr, sarray_write)
            assert write_result == 1
            assert bfr.read_index == 0
            if i == length - 1:
                assert bfr.write_index == 0
            else:
                assert bfr.write_index == i + 1
            bfr_item = &bfr.items[i]
            # print('check: {}'.format(i))
            sarray_temp = np.vstack((sarray[i], sarray[i]))
            sarray_temp[1] *= -1
            assert check_char_array(sarray_temp, bfr_item.bfr, block_size)
            write_available -= 1
            read_available += 1
            assert bfr.write_available == write_available
            assert bfr.read_available == read_available
            bfr.current_block += 1
            # time.sleep(.1)
        # time.sleep(.1)
        # print('filled')
        # time.sleep(.5)
        assert bfr.write_available == 0
        assert bfr.read_available == length

        for i in range(length):
            print('read: {}'.format(i))
            assert bfr.read_index == i
            # time.sleep(.1)
            sarray_read = np.vstack((sarray[i], sarray[i]))
            sarray_read[1] *= -1
            # read_start_time = sample_buffer_read_sf32(bfr, _sarray_read_view)
            read_start_time = test_read(bfr, sarray_read)
            assert read_start_time != NULL
            # print('read complete')
            # time.sleep(.1)
            if i == length - 1:
                assert bfr.read_index == 0
            else:
                assert bfr.read_index == i + 1
            write_available += 1
            read_available -= 1
            assert bfr.write_available == write_available
            assert bfr.read_available == read_available
            assert read_start_time.block == i
            bfr_item = &bfr.items[i]
            sarray_temp = np.vstack((sarray[i], sarray[i]))
            sarray_temp[1] *= -1
            assert check_char_array(sarray_temp, bfr_item.bfr, block_size)

            for j in range(block_size):
                assert sarray_read[0,j] == sarray[i,j]
                assert sarray_read[1,j] == sarray[i,j] * -1



        print('complete')
        # time.sleep(.5)

        # print('size: {}'.format(sizeof(float)))
        success = True
    finally:
        print('destroy')
        time.sleep(.1)
        sample_buffer_destroy(bfr)
        bfr = NULL
    return success

def test():
    return _test()

if __name__ == '__main__':
    test()

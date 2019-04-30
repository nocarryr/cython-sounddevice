# cython: language_level=3

cimport cython
from cython cimport view
from libc.stdlib cimport malloc, free
from cpython.mem cimport PyMem_Malloc, PyMem_Free

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.conversion cimport pack_buffer_item, unpack_buffer_item

cdef SampleBuffer* sample_buffer_create(SampleTime_s start_time,
                                        Py_ssize_t length,
                                        Py_ssize_t nchannels,
                                        SampleFormat* sample_format) except *:
    cdef SampleBuffer* bfr = <SampleBuffer*>malloc(sizeof(SampleBuffer))
    cdef Py_ssize_t item_length = start_time.block_size
    cdef Py_ssize_t itemsize = sample_format.bit_width // 8
    cdef Py_ssize_t bfr_length = itemsize * item_length * nchannels
    if bfr == NULL:
        raise MemoryError()
    copy_sample_time_struct(&start_time, &bfr.callback_time)
    bfr.length = length
    bfr.itemsize = itemsize
    bfr.item_length = item_length
    bfr.nchannels = nchannels
    bfr.write_index = 0
    bfr.read_index = 0
    bfr.read_available = 0
    bfr.current_block = start_time.block
    bfr.write_available = length
    bfr.sample_format = sample_format
    bfr.items = <BufferItem *>malloc(sizeof(BufferItem) * length)
    if bfr.items == NULL:
        raise MemoryError()

    cdef Py_ssize_t i
    cdef BufferItem* item
    cdef SampleTime_s _start_time
    copy_sample_time_struct(&start_time, &_start_time)
    for i in range(length):
        item = &bfr.items[i]
        item.length = item_length
        item.index = i
        item.itemsize = itemsize
        item.nchannels = nchannels
        item.total_size = bfr_length
        item.bfr = <char *>malloc(bfr_length)
        if item.bfr == NULL:
            raise MemoryError()
        item.parent_buffer = bfr
        copy_sample_time_struct(&_start_time, &item.start_time)
        _start_time.block += 1

    return bfr

cdef void sample_buffer_destroy(SampleBuffer* bfr) except *:
    cdef Py_ssize_t i
    cdef BufferItem* item

    for i in range(bfr.length):
        item = &bfr.items[i]
        item.parent_buffer = NULL
        free(item.bfr)
        item.bfr = NULL
    item = NULL
    free(bfr.items)
    free(bfr)

cdef void _sample_buffer_write_advance(SampleBuffer* bfr) nogil:
    bfr.write_index += 1
    if bfr.write_index >= bfr.length:
        bfr.write_index = 0
    if bfr.write_available > 0:
        bfr.write_available -= 1
    if bfr.read_available <= bfr.length:
        bfr.read_available += 1

cdef int sample_buffer_write(SampleBuffer* bfr, const void *data, Py_ssize_t length) nogil:
    if bfr.write_available <= 0:
        return 0
    cdef BufferItem* item = &bfr.items[bfr.write_index]
    if length != item.length:
        return 0
    cdef const char *cdata = <char *>data
    copy_char_array(&cdata, &item.bfr, item.total_size)
    item.start_time.block = bfr.current_block
    _sample_buffer_write_advance(bfr)
    return 1

cdef int sample_buffer_write_sf32(SampleBuffer* bfr, float[:,:] data) nogil:
    if bfr.write_available <= 0:
        return 0
    cdef BufferItem* item = &bfr.items[bfr.write_index]
    cdef Py_ssize_t nchannels = data.shape[0]
    cdef Py_ssize_t length = data.shape[1]
    if length != item.length:
        return 0
    if nchannels != item.nchannels:
        return 0
    pack_buffer_item(item, data)
    item.start_time.block = bfr.current_block
    _sample_buffer_write_advance(bfr)
    return 1

cdef int sample_buffer_write_from_callback(SampleBuffer* bfr,
                                           const void *data,
                                           Py_ssize_t length,
                                           PaTime adcTime) nogil:
    if bfr.write_available <= 0:
        return 0
    cdef BufferItem* item = &bfr.items[bfr.write_index]
    if length != item.length:
        return 0
    item.start_time.time_offset = bfr.callback_time.time_offset
    if not SampleTime_set_pa_time(&item.start_time, adcTime, True):
        return 2
    cdef const char *cdata = <char *>data
    copy_char_array(&cdata, &item.bfr, item.total_size)
    _sample_buffer_write_advance(bfr)
    return 1
cdef void _sample_buffer_read_advance(SampleBuffer* bfr) nogil:
    bfr.read_index += 1
    if bfr.read_index >= bfr.length:
        bfr.read_index = 0
    if bfr.read_available > 0:
        bfr.read_available -= 1
    if bfr.write_available <= bfr.length:
        bfr.write_available += 1

cdef SampleTime_s* sample_buffer_read(SampleBuffer* bfr, char *data, Py_ssize_t length) nogil:
    if bfr.read_available <= 0:
        return NULL
    cdef BufferItem* item = &bfr.items[bfr.read_index]
    if length != item.length:
        return NULL
    cdef const char *item_bfr = item.bfr
    copy_char_array(&item_bfr, &data, item.total_size)
    _sample_buffer_read_advance(bfr)
    return &item.start_time

cdef SampleTime_s* sample_buffer_read_from_callback(SampleBuffer* bfr,
                                                    char *data,
                                                    Py_ssize_t length,
                                                    PaTime dacTime) nogil:
    if bfr.read_available <= 0:
        return NULL
    cdef BufferItem* item = &bfr.items[bfr.read_index]
    if length != item.length:
        return NULL
    item.start_time.time_offset = bfr.callback_time.time_offset
    if not SampleTime_set_pa_time(&item.start_time, dacTime, False):
        return NULL
    cdef const char *item_bfr = item.bfr
    copy_char_array(&item_bfr, &data, item.total_size)
    _sample_buffer_read_advance(bfr)
    return &item.start_time

cdef SampleTime_s* sample_buffer_read_sf32(SampleBuffer* bfr, float[:,:] data) nogil:
    if bfr.read_available <= 0:
        return NULL
    cdef Py_ssize_t nchannels = data.shape[0]
    cdef Py_ssize_t length = data.shape[1]
    cdef BufferItem* item = &bfr.items[bfr.read_index]
    if length != item.length:
        return NULL
    if nchannels != item.nchannels:
        return NULL
    unpack_buffer_item(item, data)
    _sample_buffer_read_advance(bfr)
    return &item.start_time

@cython.boundscheck(False)
@cython.wraparound(False)
cdef void copy_char_array(const char **src, char **dest, Py_ssize_t length) nogil:
    cdef const char *src_p = src[0]
    cdef char *dest_p = dest[0]
    cdef Py_ssize_t i

    for i in range(length):
        dest_p[i] = src_p[i]

# cython: language_level=3

cimport cython
from cython cimport view
from libc.stdlib cimport malloc, free
from cpython.mem cimport PyMem_Malloc, PyMem_Free

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *

cdef SampleBuffer* sample_buffer_create(SampleTime start_time,
                                        Py_ssize_t length,
                                        Py_ssize_t nchannels,
                                        Py_ssize_t itemsize) except *:
    """Create a :c:type:`SampleBuffer`

    Allocates memory for :c:type:`BufferItem` members

    Arguments:
        start_time (SampleTime): :c:type:`SampleTime` describing time and block size
        length (Py_ssize_t): Number of :c:type:`BufferItem` members to create
        nchannels (Py_ssize_t): Number of channels (interleaved) in the stream
        itemsize (Py_ssize_t): Size (in bytes) per sample

    Returns:
        SampleBuffer*: A pointer to the :c:type:`SampleBuffer`

    """
    cdef SampleBuffer* bfr = <SampleBuffer*>malloc(sizeof(SampleBuffer))
    cdef Py_ssize_t item_length = start_time.block_size
    cdef Py_ssize_t bfr_length = itemsize * item_length * nchannels
    if bfr == NULL:
        raise MemoryError()
    bfr.length = length
    bfr.itemsize = itemsize
    bfr.item_length = item_length
    bfr.nchannels = nchannels
    bfr.write_index = 0
    bfr.read_index = 0
    bfr.read_available = 0
    bfr.current_block = start_time.block
    bfr.write_available = length
    bfr.items = <BufferItem *>malloc(sizeof(BufferItem) * length)
    if bfr.items == NULL:
        raise MemoryError()

    cdef Py_ssize_t i
    cdef BufferItem* item
    cdef SampleTime _start_time = start_time.copy()

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
        copy_sample_time_struct(&_start_time.data, &item.start_time)
        _start_time.block += 1

    return bfr

cdef void sample_buffer_destroy(SampleBuffer* bfr) except *:
    """Deallocates a :c:type:`SampleBuffer` and all of its members
    """
    cdef Py_ssize_t i
    cdef BufferItem* item

    for i in range(bfr.length):
        item = &bfr.items[i]
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
    """Copy stream data to the :c:type:`SampleBuffer`

    Data is writen to the next available :c:type:`BufferItem`. If none are
    available (the buffer is full), no data is copied.

    Arguments:
        bfr (SampleBuffer*): A pointer to the :c:type:`SampleBuffer`
        data (const void *): A void pointer to the source data buffer
        length (Py_ssize_t): Number of samples (should match the block size of the
            :c:member:`SampleBuffer.start_time`)

    Returns:
        int: 1 on success

    """
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

cdef void _sample_buffer_read_advance(SampleBuffer* bfr) nogil:
    bfr.read_index += 1
    if bfr.read_index >= bfr.length:
        bfr.read_index = 0
    if bfr.read_available > 0:
        bfr.read_available -= 1
    if bfr.write_available <= bfr.length:
        bfr.write_available += 1

cdef SampleTime_s* sample_buffer_read(SampleBuffer* bfr, char *data, Py_ssize_t length) nogil:
    """Copy stream data from a :c:type:`SampleBuffer`

    Arguments:
        bfr (SampleBuffer*): A pointer to the :c:type:`SampleBuffer`
        data (char *): A char pointer to copy data into
        length (Py_ssize_t): Number of samples (should match the block size of the
            :c:member:`SampleBuffer.start_time`)

    Returns:
        SampleTime*: Pointer to the :c:member:`BufferItem.start_time` describing
            the source timing of the data. If no data is available, returns ``NULL``.
    """
    if bfr.read_available <= 0:
        return NULL
    cdef BufferItem* item = &bfr.items[bfr.read_index]
    if length != item.length:
        return NULL
    cdef const char *item_bfr = item.bfr
    copy_char_array(&item_bfr, &data, item.total_size)
    _sample_buffer_read_advance(bfr)
    return &item.start_time

@cython.boundscheck(False)
@cython.wraparound(False)
cdef SampleTime_s* sample_buffer_read_sf32(SampleBuffer* bfr, float[:,:] data) except *:
    """Copy stream data from a :c:type:`SampleBuffer` into a ``float`` array

    Deinterleaves the stream and casts it to 32-bit float. A typed memoryview
    may be used.

    The sample format must be :any:`paFloat32`.

    Arguments:
        bfr (SampleBuffer*): A pointer to the :c:type:`SampleBuffer`
        data: A 2-dimensional array of float32 to copy into. The shape must match
            the block_size and channel layout of the SampleBuffer
            ``(nchannels, block_size)``

    Returns:
        SampleTime*: Pointer to the :c:member:`BufferItem.start_time` describing
            the source timing of the data. If no data is available, returns ``NULL``.
    """
    if bfr.read_available <= 0:
        return NULL
    cdef Py_ssize_t nchannels = data.shape[0]
    cdef Py_ssize_t length = data.shape[1]
    cdef BufferItem* item = &bfr.items[bfr.read_index]
    if length != item.length:
        return NULL
    if nchannels != item.nchannels:
        return NULL
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef void *vptr = <void *>item.bfr
    cdef float[::1] data_view = <float[:length*nchannels]>vptr
    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(length):
        for chan_num in range(nchannels):
            data[chan_num,chan_ix] = data_view[i]
            i += 1
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

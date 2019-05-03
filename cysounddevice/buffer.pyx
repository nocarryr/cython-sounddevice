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


cdef class StreamBuffer:
    """Convenience class wrapping buffer module's functions

    Arguments:
        stream (Stream):

    Attributes:
        nchannels (int): Number of channels
        read_available (int): Number of BufferItems available for reading
        write_available (int): Number of BufferItems available for writing
    """
    def __cinit__(self, Stream stream):
        self.stream = stream
        self.sample_buffer = NULL
        self.nchannels = 0
        self.own_buffer = False
    def __dealloc__(self):
        if self.own_buffer:
            if self.sample_buffer:
                sample_buffer_destroy(self.sample_buffer)
        self.sample_buffer = NULL
    @property
    def read_available(self):
        cdef int result = 0
        cdef SampleBuffer* bfr
        if self.sample_buffer != NULL:
            bfr = self.sample_buffer
            result = bfr.read_available
        return result
    @property
    def write_available(self):
        cdef int result = 0
        cdef SampleBuffer* bfr
        if self.sample_buffer != NULL:
            bfr = self.sample_buffer
            result = bfr.write_available
        return result

    # cpdef _build_buffer(self, Py_ssize_t buffer_len, Py_ssize_t nchannels, Py_ssize_t itemsize):
    #     assert self.sample_buffer == NULL
    #
    #     cdef SampleTime sample_time = SampleTime(self.sample_rate, self.block_size)
    #
    #     self.own_buffer = True
    #     self.nchannels = nchannels
    #
    #     if nchannels > 0:
    #         self.sample_buffer = sample_buffer_create(
    #             sample_time.data, buffer_len, nchannels, itemsize,
    #         )
    #         if not self.sample_buffer:
    #             raise MemoryError()
    cdef void _set_sample_buffer(self, SampleBuffer* bfr) except *:
        if self.sample_buffer:
            if self.own_buffer:
                sample_buffer_destroy(self.sample_buffer)
            self.sample_buffer = NULL

        self.own_buffer = False
        self.sample_buffer = bfr
        self.nchannels = bfr.nchannels

cdef class StreamInputBuffer(StreamBuffer):
    cpdef bint ready(self):
        """Check the SampleBuffer for read availability
        """
        if self.sample_buffer == NULL:
            return False
        cdef SampleBuffer* bfr = self.sample_buffer
        return bfr.read_available > 0

    cpdef SampleTime read_into(self, float[:,:] data):
        """Copy stream data from a :c:type:`SampleBuffer`

        If the stream contains more than one channel, the samples will be deinterleaved
        into shape (nchannels, length).

        Note:
            The data will be converted to float32 and scaled to the range ``-1 to 1``

        Arguments:
            data: A 2-dimensional float array (or memoryview) to copy data into

        Returns:
            SampleTime:  If no data is available, returns ``NULL``.
        """
        cdef SampleTime_s* item_st = self._read_into(data)
        if item_st == NULL:
            return None
        cdef SampleTime sample_time = SampleTime.from_struct(item_st)
        return sample_time

    cdef SampleTime_s* _read_into(self, float[:,:] data) nogil:
        if self.sample_buffer == NULL:
            return NULL
        cdef SampleTime_s* item_st = sample_buffer_read_sf32(self.sample_buffer, data)
        return item_st

    cdef SampleTime_s* _read_ptr(self, char *data) nogil:
        if self.sample_buffer == NULL:
            return NULL
        cdef SampleBuffer* bfr = self.sample_buffer
        return sample_buffer_read(bfr, data, bfr.item_length)

cdef class StreamOutputBuffer(StreamBuffer):
    cpdef bint ready(self):
        """Check the SampleBuffer for write availability
        """
        if self.sample_buffer == NULL:
            return False
        cdef SampleBuffer* bfr = self.sample_buffer
        return bfr.write_available > 0

    cpdef int write_output_sf32(self, float[:,:] data):
        """Copy stream data to the :c:type:`SampleBuffer`

        Note:
            The input data is expected to be float32 in the range ``-1 to 1``.
            It will be scaled and converted to the appropriate type before
            writing to the buffer.

        Arguments:
            data: A 2-dimensional float array (or memoryview) to copy data from

        Returns:
            int: 1 on success
        """
        return self._write_output_sf32(data)

    cdef int _write_output_sf32(self, float[:,:] data) nogil:
        if self.sample_buffer == NULL:
            return 0
        return sample_buffer_write_sf32(self.sample_buffer, data)

    cdef int _write_output(self, const void *data) nogil:
        """Copy stream data to the :c:type:`SampleBuffer`

        Data is writen to the next available :c:type:`BufferItem`. If none are
        available (the buffer is full), no data is copied.

        Arguments:
            data (const void *): A void pointer to the source data buffer

        Returns:
            int: 1 on success
        """
        if self.sample_buffer == NULL:
            return 0
        cdef SampleBuffer* bfr = self.sample_buffer
        return sample_buffer_write(bfr, data, bfr.item_length)

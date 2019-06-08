# cython: language_level=3
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

import numpy as np
cimport numpy as np

from cysounddevice.types cimport *
from cysounddevice cimport buffer
from cysounddevice.buffer cimport SampleBuffer, BufferItem
from cysounddevice cimport conversion


cdef class BufferWrapper:
    cdef readonly SampleTime start_time
    cdef SampleFormat* _sample_format
    cdef SampleBuffer* sample_buffer
    cdef BufferItem* buffer_item
    def __cinit__(self, SampleTime start_time, Py_ssize_t nchannels, str sample_format_str):
        cdef Py_ssize_t length = 1
        self.start_time = start_time
        cdef SampleFormat* sample_format = get_sample_format_by_name(sample_format_str)
        self._sample_format = sample_format
        self.sample_buffer = NULL
        cdef SampleBuffer* bfr = buffer.sample_buffer_create(start_time.data, length, nchannels, sample_format)
        self.sample_buffer = bfr
        cdef BufferItem* item = &bfr.items[0]
        self.buffer_item = item
    def __dealloc__(self):
        self.buffer_item = NULL
        if self.sample_buffer != NULL:
            buffer.sample_buffer_destroy(self.sample_buffer)
            self.sample_buffer = NULL
    @property
    def sample_format(self):
        cdef SampleFormat fmt = self._sample_format[0]
        return fmt

    cpdef pack_buffer_item(self, float[:,:] src):
        cdef BufferItem* item = self.buffer_item
        conversion.pack_buffer_item(item, src)

    cpdef unpack_buffer_item_view(self, float[:,:] dest):
        cdef BufferItem* item = self.buffer_item
        conversion.unpack_buffer_item(item, dest)

    cpdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] unpack_buffer_item(self):
        cdef BufferItem* item = self.buffer_item
        cdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] dest = np.empty(
            (item.nchannels, item.length), dtype='float32',
        )
        self.unpack_buffer_item_view(dest)
        return dest

    cpdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] pack_and_unpack_item(self, float[:,:] src):
        cdef BufferItem* item = self.buffer_item
        cdef np.ndarray[FLOAT32_DTYPE_t, ndim=2] dest = np.empty(
            (item.nchannels, item.length), dtype='float32',
        )
        cdef float[:,:] dest_view = dest
        with nogil:
            conversion.pack_buffer_item(item, src)
            conversion.unpack_buffer_item(item, dest_view)
        return dest


cpdef BufferWrapper build_buffer(SAMPLE_RATE_t sample_rate,
                                 Py_ssize_t block_size,
                                 Py_ssize_t nchannels,
                                 str sample_format_str):
    cdef SampleTime st = SampleTime(0, 0, block_size, sample_rate)
    cdef BufferWrapper bfr = BufferWrapper(st, nchannels, sample_format_str)
    return bfr

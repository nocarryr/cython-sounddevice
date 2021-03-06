# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.streams cimport Stream


cdef struct BufferItem:
    SampleTime_s start_time
    Py_ssize_t index
    Py_ssize_t length
    Py_ssize_t itemsize
    Py_ssize_t nchannels
    Py_ssize_t total_size
    SampleBuffer* parent_buffer
    char *bfr

cdef struct SampleBuffer:
    BufferItem *items
    SampleTime_s callback_time
    Py_ssize_t length
    Py_ssize_t itemsize
    Py_ssize_t item_length
    Py_ssize_t nchannels
    Py_ssize_t write_index
    Py_ssize_t read_index
    BLOCK_t current_block
    int read_available
    int write_available
    SampleFormat* sample_format

cdef SampleBuffer* sample_buffer_create(SampleTime_s start_time,
                                        Py_ssize_t length,
                                        Py_ssize_t nchannels,
                                        SampleFormat* sample_format) except *
cdef void sample_buffer_destroy(SampleBuffer* bfr) except *
cdef int sample_buffer_write(SampleBuffer* bfr, const void *data, Py_ssize_t length) nogil
cdef int sample_buffer_write_sf32(SampleBuffer* bfr, float[:,:] data) nogil
cdef int sample_buffer_write_from_callback(SampleBuffer* bfr,
                                           const void *data,
                                           Py_ssize_t length,
                                           PaTime adcTime) nogil
cdef SampleTime_s* sample_buffer_read(SampleBuffer* bfr, char *data, Py_ssize_t length) nogil
cdef SampleTime_s* sample_buffer_read_from_callback(SampleBuffer* bfr,
                                                    char *data,
                                                    Py_ssize_t length,
                                                    PaTime dacTime) nogil
cdef SampleTime_s* sample_buffer_read_sf32(SampleBuffer* bfr, float[:,:] data) nogil


cdef class StreamBuffer:
    cdef readonly Stream stream
    cdef SampleBuffer* sample_buffer
    cdef readonly Py_ssize_t nchannels
    cdef bint own_buffer

    # cpdef _build_buffers(self, Py_ssize_t buffer_len, Py_ssize_t itemsize)
    cdef void _set_sample_buffer(self, SampleBuffer* bfr) except *
    cdef int check_callback_errors(self) nogil except -1

cdef class StreamInputBuffer(StreamBuffer):
    cpdef bint ready(self)
    cpdef SampleTime read_into(self, float[:,:] data)
    cdef SampleTime_s* _read_into(self, float[:,:] data) nogil
    cdef SampleTime_s* _read_ptr(self, char *data) nogil

cdef class StreamOutputBuffer(StreamBuffer):
    cpdef bint ready(self)
    cpdef int write_output_sf32(self, float[:,:] data)
    cdef int _write_output_sf32(self, float[:,:] data) nogil
    cdef int _write_output(self, const void *data) nogil

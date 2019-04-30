# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *


cdef struct BufferItem:
    SampleTime_s start_time
    Py_ssize_t index
    Py_ssize_t length
    Py_ssize_t itemsize
    Py_ssize_t nchannels
    Py_ssize_t total_size
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
cdef int sample_buffer_write_from_callback(SampleBuffer* bfr,
                                           const void *data,
                                           Py_ssize_t length,
                                           PaTime adcTime) nogil
cdef SampleTime_s* sample_buffer_read(SampleBuffer* bfr, char *data, Py_ssize_t length) nogil
cdef SampleTime_s* sample_buffer_read_from_callback(SampleBuffer* bfr,
                                                    char *data,
                                                    Py_ssize_t length,
                                                    PaTime dacTime) nogil
cdef SampleTime_s* sample_buffer_read_sf32(SampleBuffer* bfr, float[:,:] data) except *

# cython: language_level=3

cimport cython

from libc.stdint cimport *
import numpy as np
cimport numpy as np

from cysounddevice.pawrapper cimport *

ctypedef np.npy_bool BOOL_DTYPE_t
# ctypedef np.int8 INT8_DTYPE_t
# ctypedef np.uint8 UINT8_DTYPE_t
# ctypedef np.int32 INT24_DTYPE_t
# ctypedef np.int32 INT32_DTYPE_t
# ctypedef np.int16 INT16_DTYPE_t
# ctypedef np.float32_t FLOAT32_DTYPE_t
# ctypedef np.int8_t INT8_DTYPE_t
# ctypedef np.uint8_t UINT8_DTYPE_t
# ctypedef np.int32_t INT24_DTYPE_t
# ctypedef np.int32_t INT32_DTYPE_t
# ctypedef np.int16_t INT16_DTYPE_t
# ctypedef np.float32_t FLOAT32_DTYPE_t
ctypedef int8_t INT8_DTYPE_t
ctypedef uint8_t UINT8_DTYPE_t
ctypedef int32_t INT24_DTYPE_t
ctypedef int32_t INT32_DTYPE_t
ctypedef int16_t INT16_DTYPE_t
ctypedef float FLOAT32_DTYPE_t

ctypedef double SAMPLE_RATE_t
ctypedef unsigned int BLOCK_t
ctypedef unsigned long long SAMPLE_INDEX_t



cdef struct SampleFormat:
    PaSampleFormat pa_ident
    Py_ssize_t bit_width
    bint is_signed
    bint is_float
    bint is_24bit
    double min_value
    double max_value
    double ptp_value
    double float32_multiplier
    char* name

ctypedef struct SampleFormats_s:
    SampleFormat sf_float32
    SampleFormat sf_int32
    SampleFormat sf_int24
    SampleFormat sf_int16
    SampleFormat sf_int8
    SampleFormat sf_uint8

cdef SampleFormats_s SampleFormats

cdef dict sample_format_to_dict(SampleFormat* sf)
cdef SampleFormat* get_sample_format_by_name(str name) except *
cdef SampleFormat* get_sample_format(Py_ssize_t bit_width, bint is_signed, bint is_float) except *
cdef SampleFormat* get_sample_format_by_kwargs(dict kwargs) except *
cdef object _get_dtype_for_sample_format(SampleFormat* sf)
cpdef object get_dtype_for_sample_format(str name)

ctypedef enum IOType:
    IOType_Input = 1
    IOType_Output = 2
    IOType_Duplex = 4

cdef struct SampleTime_s:
    PaTime pa_time
    PaTime rel_time
    PaTime time_offset
    SAMPLE_RATE_t sample_rate
    Py_ssize_t block_size
    BLOCK_t block
    Py_ssize_t block_index
    # SAMPLE_INDEX_t sample_index

cdef void copy_sample_time_struct(SampleTime_s* ptr_from, SampleTime_s* ptr_to) except *
cdef SAMPLE_INDEX_t SampleTime_to_sample_index(SampleTime_s* st) nogil
# cdef PaTime SampleTime_get_rel_time(SampleTime_s* st) nogil
cdef PaTime SampleTime_to_rel_time(SampleTime_s* st) nogil
cdef PaTime SampleTime_to_pa_time(SampleTime_s* st) nogil
cdef bint SampleTime_set_sample_index(SampleTime_s* st, SAMPLE_INDEX_t idx, bint allow_misaligned) nogil
cdef void SampleTime_set_block_vars(SampleTime_s* st, BLOCK_t block, Py_ssize_t block_index) nogil
cdef bint SampleTime_set_pa_time(SampleTime_s* st, PaTime t, bint allow_misaligned) nogil
cdef bint SampleTime_set_rel_time(SampleTime_s* st, PaTime t, bint allow_misaligned) nogil

cdef class SampleTime:
    cdef SampleTime_s data

    @staticmethod
    cdef SampleTime from_struct(SampleTime_s* data)

    cpdef SampleTime copy(self)
    cdef void _set_rel_time(self, PaTime value) except *
    cdef void _set_pa_time(self, PaTime value) except *
    cdef void _set_time_offset(self, PaTime value) except *
    cdef void _set_block(self, BLOCK_t value) except *
    cdef void _set_block_index(self, Py_ssize_t value) except *
    cdef SAMPLE_INDEX_t _get_sample_index(self)
    cdef void _set_sample_index(self, SAMPLE_INDEX_t value) except *

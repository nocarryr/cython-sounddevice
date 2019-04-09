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
ctypedef np.int8_t INT8_DTYPE_t
ctypedef np.uint8_t UINT8_DTYPE_t
ctypedef np.int32_t INT24_DTYPE_t
ctypedef np.int32_t INT32_DTYPE_t
ctypedef np.int16_t INT16_DTYPE_t
ctypedef np.float32_t FLOAT32_DTYPE_t



cdef struct SampleFormat:
    PaSampleFormat pa_ident
    Py_ssize_t bit_width
    bint is_signed
    bint is_float
    bint is_24bit
    void* dtype_ptr

ctypedef union SampleFormats_u:
    SampleFormat sf_float32
    SampleFormat sf_int32
    SampleFormat sf_int24
    SampleFormat sf_int16
    SampleFormat sf_int8
    SampleFormat sf_uint8

cdef SampleFormats_u SampleFormats

ctypedef enum IOType:
    IOType_Input = 1
    IOType_Output = 2
    IOType_Duplex = 4

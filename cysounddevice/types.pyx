cimport cython
from libc.math cimport llrint
from cpython.object cimport Py_LT, Py_LE, Py_EQ, Py_NE, Py_GT, Py_GE
import numpy as np
cimport numpy as np
import numbers

FLOAT32_DTYPE = np.float32

# cdef SampleFormats_s SampleFormats

SampleFormats.sf_float32.pa_ident = 1
SampleFormats.sf_float32.bit_width = 32
SampleFormats.sf_float32.is_signed = True
SampleFormats.sf_float32.is_float = True
SampleFormats.sf_float32.is_24bit = False
# SampleFormats.sf_float32.dtype_ptr = <void*>FLOAT32_DTYPE_t

SampleFormats.sf_int32.pa_ident = 2
SampleFormats.sf_int32.bit_width = 32
SampleFormats.sf_int32.is_signed = True
SampleFormats.sf_int32.is_float = False
SampleFormats.sf_int32.is_24bit = False
# SampleFormats.sf_int32.dtype_ptr = <void*>INT32_DTYPE_t

SampleFormats.sf_int24.pa_ident = 4
SampleFormats.sf_int24.bit_width = 24
SampleFormats.sf_int24.is_signed = True
SampleFormats.sf_int24.is_float = False
SampleFormats.sf_int24.is_24bit = True
# SampleFormats.sf_int24.dtype_ptr = <void*>INT24_DTYPE_t

SampleFormats.sf_int16.pa_ident = 8
SampleFormats.sf_int16.bit_width = 16
SampleFormats.sf_int16.is_signed = True
SampleFormats.sf_int16.is_float = False
SampleFormats.sf_int16.is_24bit = False
# SampleFormats.sf_int16.dtype_ptr = <void*>INT16_DTYPE_t

SampleFormats.sf_int8.pa_ident = 16
SampleFormats.sf_int8.bit_width = 8
SampleFormats.sf_int8.is_signed = True
SampleFormats.sf_int8.is_float = False
SampleFormats.sf_int8.is_24bit = False
# SampleFormats.sf_int8.dtype_ptr = <void*>INT8_DTYPE_t

SampleFormats.sf_uint8.pa_ident = 32
SampleFormats.sf_uint8.bit_width = 8
SampleFormats.sf_uint8.is_signed = False
SampleFormats.sf_uint8.is_float = False
SampleFormats.sf_uint8.is_24bit = False
# SampleFormats.sf_uint8.dtype_ptr = <void*>UINT8_DTYPE_t

cdef void copy_sample_time_struct(SampleTime_s* ptr_from, SampleTime_s* ptr_to) except *:
    ptr_to.pa_time = ptr_from.pa_time
    ptr_to.time_offset = ptr_from.time_offset
    ptr_to.sample_rate = ptr_from.sample_rate
    ptr_to.block_size = ptr_from.block_size
    ptr_to.block = ptr_from.block
    ptr_to.block_index = ptr_from.block_index

cdef class SampleTime:
    def __cinit__(self, SAMPLE_RATE_t sample_rate, Py_ssize_t block_size):
        self.data.sample_rate = sample_rate
        self.data.block_size = block_size
        self.data.pa_time = 0
        self.data.time_offset = 0
        self.data.block = 0
        self.data.block_index = 0

    def __init__(self, *args):
        assert self.sample_rate > 0
        assert self.block_size > 0

    @staticmethod
    cdef SampleTime from_struct(SampleTime_s* data):
        cdef SampleTime obj = SampleTime(data.sample_rate, data.block_size)
        copy_sample_time_struct(data, &obj.data)
        return obj

    cpdef SampleTime copy(self):
        cdef SampleTime obj = SampleTime(self.sample_rate, self.block_size)
        obj.time_offset = self.time_offset
        obj.block = self.block
        obj.block_index = self.block_index
        return obj

    @property
    def sample_rate(self):
        return self.data.sample_rate

    @property
    def block_size(self):
        return self.data.block_size

    @property
    def pa_time(self):
        return self.data.pa_time
    @pa_time.setter
    def pa_time(self, value):
        self._set_pa_time(value)
    cdef void _set_pa_time(self, PaTime value) except *:
        if self.data.pa_time == value:
            return
        self.data.pa_time = value
        cdef PaTime t = self.data.pa_time - self.data.time_offset
        cdef SAMPLE_INDEX_t sample_index = llrint(t * self.sample_rate)
        self._set_sample_index(sample_index)

    @property
    def time_offset(self):
        return self.data.time_offset
    @time_offset.setter
    def time_offset(self, value):
        self._set_time_offset(value)
    cdef void _set_time_offset(self, PaTime value) except *:
        self.data.time_offset = value

    @property
    def block(self):
        return self.data.block
    @block.setter
    def block(self, BLOCK_t value):
        self._set_block(value)
    cdef void _set_block(self, BLOCK_t value) except *:
        if value == self.data.block:
            return

        self.data.block = value
        self._update_time_vars()

    @property
    def block_index(self):
        return self.data.block_index
    @block_index.setter
    def block_index(self, value):
        self._set_block_index(value)
    cdef void _set_block_index(self, Py_ssize_t value) except *:
        if value == self.data.block_index:
            return
        self.data.block_index = value
        self._update_time_vars()

    @property
    def sample_index(self):
        return self._get_sample_index()
    @sample_index.setter
    def sample_index(self, SAMPLE_INDEX_t value):
        self._set_sample_index(value)
    cdef SAMPLE_INDEX_t _get_sample_index(self):
        cdef SAMPLE_INDEX_t r = self.data.block * self.data.block_size
        r += self.data.block_index
        return r
    @cython.cdivision(True)
    cdef void _set_sample_index(self, SAMPLE_INDEX_t value) except *:
        if value == self._get_sample_index():
            return
        cdef Py_ssize_t block_size = self.data.block_size
        self.data.block = value // self.data.block_size
        self.data.block_index = value % self.data.block_size
        self._update_time_vars()

    @cython.cdivision(True)
    cdef void _update_time_vars(self) except *:
        cdef SAMPLE_INDEX_t sample_index = self._get_sample_index()
        cdef PaTime t = sample_index / self.data.sample_rate
        t += self.data.time_offset
        self.data.pa_time = t

    def __add__(SampleTime self, other):
        r = self._prepare_op(other)
        if r is None:
            return NotImplemented
        t, t_offset = r
        cdef SampleTime obj = SampleTime(self.sample_rate, self.block_size)

        t += self.pa_time + t_offset
        obj.time_offset = self.time_offset
        obj.pa_time = t
        return obj
    def __sub__(SampleTime self, other):
        r = self._prepare_op(other)
        if r is None:
            return NotImplemented
        t, t_offset = r
        cdef SampleTime obj = SampleTime(self.sample_rate, self.block_size)

        t -= self.pa_time + t_offset
        obj.time_offset = self.time_offset
        obj.pa_time = t
        return obj
    def __iadd__(SampleTime self, other):
        r = self._prepare_op(other)
        if r is None:
            return NotImplemented
        t, t_offset = r

        t += self.pa_time + t_offset
        self.pa_time = t
        return self
    def __isub__(SampleTime self, other):
        r = self._prepare_op(other)
        if r is None:
            return NotImplemented
        t, t_offset = r

        t -= self.pa_time + t_offset
        self.pa_time = t
        return self
    def _prepare_op(self, other):
        cdef PaTime t, t_offset
        t_offset = self.time_offset
        if isinstance(other, SampleTime):
            t = other.pa_time
            t_offset -= other.time_offset
        elif isinstance(other, numbers.Number):
            t = other
        else:
            return None
        return t, t_offset
    def __richcmp__(SampleTime self, other, int op):
        cdef PaTime self_t, oth_t
        if isinstance(other, SampleTime):
            oth_t = other.pa_time
        # elif isinstance(other, numbers.Number):
        #     oth_t = other
        else:
            return NotImplemented
        self_t = self.pa_time
        if op == Py_LT:
            return self_t < oth_t
        elif op == Py_EQ:
            return self_t == oth_t
        elif op == Py_GT:
            return self_t > oth_t
        elif op == Py_LE:
            return self_t <= oth_t
        elif op == Py_NE:
            return self_t != oth_t
        elif op == Py_GE:
            return self_t >= oth_t

    def __repr__(self):
        return '<{self.__class__.__name__}: {self}>'.format(self=self)
    def __str__(self):
        return '({self.block}, {self.block_index})'.format(self=self)

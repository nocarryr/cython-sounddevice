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
SampleFormats.sf_float32.name = b'float32'
# SampleFormats.sf_float32.dtype_ptr = <void*>FLOAT32_DTYPE_t

SampleFormats.sf_int32.pa_ident = 2
SampleFormats.sf_int32.bit_width = 32
SampleFormats.sf_int32.is_signed = True
SampleFormats.sf_int32.is_float = False
SampleFormats.sf_int32.is_24bit = False
SampleFormats.sf_int32.name = b'int32'
# SampleFormats.sf_int32.dtype_ptr = <void*>INT32_DTYPE_t

SampleFormats.sf_int24.pa_ident = 4
SampleFormats.sf_int24.bit_width = 24
SampleFormats.sf_int24.is_signed = True
SampleFormats.sf_int24.is_float = False
SampleFormats.sf_int24.is_24bit = True
SampleFormats.sf_int24.name = b'int24'
# SampleFormats.sf_int24.dtype_ptr = <void*>INT24_DTYPE_t

SampleFormats.sf_int16.pa_ident = 8
SampleFormats.sf_int16.bit_width = 16
SampleFormats.sf_int16.is_signed = True
SampleFormats.sf_int16.is_float = False
SampleFormats.sf_int16.is_24bit = False
SampleFormats.sf_int16.name = b'int16'
# SampleFormats.sf_int16.dtype_ptr = <void*>INT16_DTYPE_t

SampleFormats.sf_int8.pa_ident = 16
SampleFormats.sf_int8.bit_width = 8
SampleFormats.sf_int8.is_signed = True
SampleFormats.sf_int8.is_float = False
SampleFormats.sf_int8.is_24bit = False
SampleFormats.sf_int8.name = b'int8'
# SampleFormats.sf_int8.dtype_ptr = <void*>INT8_DTYPE_t

SampleFormats.sf_uint8.pa_ident = 32
SampleFormats.sf_uint8.bit_width = 8
SampleFormats.sf_uint8.is_signed = False
SampleFormats.sf_uint8.is_float = False
SampleFormats.sf_uint8.is_24bit = False
SampleFormats.sf_uint8.name = b'uint8'
# SampleFormats.sf_uint8.dtype_ptr = <void*>UINT8_DTYPE_t

cdef dict sample_format_to_dict(SampleFormat* sf):
    cdef dict d = {}
    cdef bytes bname = bytes(sf.name)
    cdef str name = bname.decode('UTF-8')
    d['pa_ident'] = sf.pa_ident
    d['bit_width'] = sf.bit_width
    d['is_signed'] = sf.is_signed
    d['is_float'] = sf.is_float
    d['is_24bit'] = sf.is_24bit
    d['name'] = name
    return d

cdef SampleFormat* get_sample_format_by_name(str name) except *:
    cdef SampleFormat* sf
    if 'float32' in name:
        return &SampleFormats.sf_float32
    elif 'int32' in name:
        return &SampleFormats.sf_int32
    elif 'int16' in name:
        return &SampleFormats.sf_int16
    elif 'uint8' in name:
        return &SampleFormats.sf_uint8
    elif 'int8' in name:
        return &SampleFormats.sf_int8
    else:
        raise Exception('Invalid SampleFormat name')

cdef SampleFormat* get_sample_format(Py_ssize_t bit_width, bint is_signed, bint is_float) except *:
    if is_float:
        if bit_width == 32:
            return &SampleFormats.sf_float32
        else:
            raise Exception('Float only supported in 32-bit')
    if not is_signed:
        if bit_width == 8:
            return &SampleFormats.sf_uint8
        else:
            raise Exception('Unsigned only supported in 8-bit')
    if bit_width == 32:
        return &SampleFormats.sf_int32
    elif bit_width == 24:
        return &SampleFormats.sf_int24
    elif bit_width == 16:
        return &SampleFormats.sf_int16
    elif bit_width == 8:
        return &SampleFormats.sf_int8
    else:
        raise Exception('Unsupported format')

cdef SampleFormat* get_sample_format_by_kwargs(dict kwargs) except *:
    cdef Py_ssize_t bit_width = kwargs.get('bit_width', 0)
    cdef bint is_signed = kwargs.get('is_signed', True)
    cdef bint is_float = kwargs.get('is_float', False)

    return get_sample_format(bit_width, is_signed, is_float)

def get_sample_formats():
    d = {}
    d['sf_float32'] = sample_format_to_dict(&SampleFormats.sf_float32)
    d['sf_int32'] = sample_format_to_dict(&SampleFormats.sf_int32)
    d['sf_int24'] = sample_format_to_dict(&SampleFormats.sf_int24)
    d['sf_int16'] = sample_format_to_dict(&SampleFormats.sf_int16)
    d['sf_int8'] = sample_format_to_dict(&SampleFormats.sf_int8)
    d['sf_uint8'] = sample_format_to_dict(&SampleFormats.sf_uint8)
    return d

cdef void copy_sample_time_struct(SampleTime_s* ptr_from, SampleTime_s* ptr_to) except *:
    ptr_to.pa_time = ptr_from.pa_time
    ptr_to.time_offset = ptr_from.time_offset
    ptr_to.sample_rate = ptr_from.sample_rate
    ptr_to.block_size = ptr_from.block_size
    ptr_to.block = ptr_from.block
    ptr_to.block_index = ptr_from.block_index

cdef SAMPLE_INDEX_t SampleTime_to_sample_index(SampleTime_s* st) nogil:
    cdef SAMPLE_INDEX_t r = st.block * st.block_size
    r += st.block_index
    return r

@cython.cdivision(True)
cdef PaTime SampleTime_to_pa_time(SampleTime_s* st) nogil:
    cdef SAMPLE_INDEX_t sidx = SampleTime_to_sample_index(st)
    cdef PaTime t = sidx / st.sample_rate
    t += st.time_offset
    return t

@cython.cdivision(True)
cdef bint SampleTime_set_sample_index(SampleTime_s* st, SAMPLE_INDEX_t idx, bint allow_misaligned) nogil:
    cdef Py_ssize_t block_index = idx % st.block_size
    if not allow_misaligned and block_index != 0:
        return False
    st.block = idx // st.block_size
    st.block_index = block_index
    st.pa_time = SampleTime_to_pa_time(st)
    return True

@cython.cdivision(True)
cdef bint SampleTime_set_pa_time(SampleTime_s* st, PaTime t, bint allow_misaligned) nogil:
    t = t - st.time_offset
    cdef SAMPLE_INDEX_t sample_index = llrint(t * st.sample_rate)
    return SampleTime_set_sample_index(st, sample_index, allow_misaligned)


cdef class SampleTime:
    """Helper class to convert between samples and seconds

    Can be used with arithmetic and comparison operators::

        Fs = 48000
        block_size = 512
        sample_time = SampleTime(Fs, block_size)

        # Set sample_index to 4800 (0.1 seconds)
        # Its block should be `9` and the block_index should be `192`
        sample_time.sample_index = 4800

        print(sample_time)
        # >>> (9, 192)
        print(sample_time.pa_time)
        # >>> 0.1

        # Set it to 0.2 seconds. Now the sample_index should be 9600.
        # block should be 18 and block_index should be 384
        sample_time.pa_time = 0.2

        print(sample_time.sample_index)
        # >>> 9600
        print(sample_time)
        # >>> (18, 384)

        # Subtract in-place by 0.1 (seconds), then the values should match above
        sample_time -= 0.1

        print(sample_time.sample_index)
        # >>> 4800

        # Add 0.1 seconds. This returns a new instance.
        sample_time2 = sample_time + 0.1

        print(sample_time.sample_index)
        # >>> 9600

        # Now add the two together
        sample_time3 = sample_time + sample_time2

        print(sample_time3.pa_time)
        # >>> 0.3
        print(sample_time3.sample_index)
        # >>> 14400

        sample_time < sample_time2 < sample_time3
        # >>> True

    Attributes:
        data (SampleTime_s): A :c:type:`SampleTime_s` struct
        sample_rate (int): The sample rate
        block_size (int): Number of samples per block
        pa_time (float): Time in seconds
        time_offset (float): Time in seconds to offset calculations to/from
            sample counts
        block (int): Number of blocks
        block_index (int): The sample-based index within the current :attr:`block`,
            starting from ``0`` to ``block_size - 1``
        sample_index (int): Overall sample index calculated from :attr:`block`
            and :attr:`block_index` as ``block * block_size + block_index``
    """
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
        cdef SampleTime obj = SampleTime.from_struct(&self.data)
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
        SampleTime_set_pa_time(&self.data, value, True)

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
        self.data.pa_time = SampleTime_to_pa_time(&self.data)

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
        self.data.pa_time = SampleTime_to_pa_time(&self.data)

    @property
    def sample_index(self):
        return self._get_sample_index()
    @sample_index.setter
    def sample_index(self, SAMPLE_INDEX_t value):
        self._set_sample_index(value)
    cdef SAMPLE_INDEX_t _get_sample_index(self):
        return SampleTime_to_sample_index(&self.data)
    @cython.cdivision(True)
    cdef void _set_sample_index(self, SAMPLE_INDEX_t value) except *:
        if value == self._get_sample_index():
            return
        SampleTime_set_sample_index(&self.data, value, True)

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

        t = self.pa_time + t_offset - t
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

        t = self.pa_time + t_offset - t
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

# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True

# TODO: Endian-ness should be checked at compilation time
DEF LITTLE_ENDIAN = True

from cysounddevice.utils cimport raise_withgil, PyExc_ValueError

# -----------------------------------------------------------------------------
# Convert from 2-dimensional float32 array/memoryview into flattened values
# scaled for the SampleBuffer's sample_format, then pack them
# into the BufferItem's char buffer.
# -----------------------------------------------------------------------------

cdef int pack_buffer_item(BufferItem* item, float[:,:] src) nogil except -1:
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    if fmt.pa_ident == paFloat32:
        pack_float32(item, src)
    elif fmt.pa_ident == paInt32:
        pack_sint32(item, src)
    elif fmt.pa_ident == paInt24:
        pack_sint24(item, src)
    elif fmt.pa_ident == paInt16:
        pack_sint16(item, src)
    elif fmt.pa_ident == paInt8:
        pack_sint8(item, src)
    elif fmt.pa_ident == paUInt8:
        pack_uint8(item, src)
    else:
        raise_withgil(PyExc_ValueError, 'Unsupported format')
    return 0

cdef void pack_float32(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef FLOAT32_DTYPE_t *data_view = <FLOAT32_DTYPE_t *>item.bfr
    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            data_view[i] = src[chan_num,chan_ix]
            i += 1

cdef void pack_sint32(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT32_DTYPE_t *data_view = <INT32_DTYPE_t *>item.bfr
    cdef double multiplier = fmt.ptp_value / 2.0
    cdef double value

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            value = src[chan_num,chan_ix] * multiplier
            if value > fmt.max_value:
                value = fmt.max_value
            elif value < fmt.min_value:
                value = fmt.min_value
            data_view[i] = <INT32_DTYPE_t>value
            i += 1


cdef void pack_sint24(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t chan_ix, chan_num, bfr_ix
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef unsigned char *bfr = <unsigned char *>item.bfr
    cdef double multiplier = 2147483648.0  # 2 ** 32 / 2
    cdef double value
    cdef int32_t packed_value

    chan_ix = 0
    chan_num = 0
    bfr_ix = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            value = <double>src[chan_num,chan_ix] * multiplier
            packed_value = <int32_t>value
            IF LITTLE_ENDIAN:
                bfr[bfr_ix+0] = <unsigned char>(packed_value >> 8)
                bfr[bfr_ix+1] = <unsigned char>(packed_value >> 16)
                bfr[bfr_ix+2] = <unsigned char>(packed_value >> 24)
            ELSE:
                bfr[bfr_ix+2] = <unsigned char>(packed_value >> 8)
                bfr[bfr_ix+1] = <unsigned char>(packed_value >> 16)
                bfr[bfr_ix+0] = <unsigned char>(packed_value >> 24)
            bfr_ix += 3

cdef void pack_sint16(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT16_DTYPE_t *data_view = <INT16_DTYPE_t *>item.bfr
    cdef double multiplier = fmt.ptp_value / 2.0
    cdef double value

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            value = src[chan_num,chan_ix] * multiplier
            if value > fmt.max_value:
                value = fmt.max_value
            elif value < fmt.min_value:
                value = fmt.min_value
            data_view[i] = <INT16_DTYPE_t>value
            i += 1

cdef void pack_sint8(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT8_DTYPE_t *data_view = <INT8_DTYPE_t *>item.bfr
    cdef double multiplier = fmt.ptp_value / 2.0
    cdef double value

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            value = src[chan_num,chan_ix] * multiplier
            if value > fmt.max_value:
                value = fmt.max_value
            elif value < fmt.min_value:
                value = fmt.min_value
            data_view[i] = <INT8_DTYPE_t>value
            i += 1

cdef void pack_uint8(BufferItem* item, float[:,:] src) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef UINT8_DTYPE_t *data_view = <UINT8_DTYPE_t *>item.bfr
    cdef double value

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            value = (src[chan_num,chan_ix] + 1.0) / 2.0 * 256

            if value > fmt.max_value:
                value = fmt.max_value
            elif value < fmt.min_value:
                value = fmt.min_value
            data_view[i] = <UINT8_DTYPE_t>value
            i += 1

# -----------------------------------------------------------------------------
# Unpack the BufferItem's char buffer and scale the values to float32,
# placing the results into a 2-dimensional array/memoryview.
# -----------------------------------------------------------------------------

cdef int unpack_buffer_item(BufferItem* item, float[:,:] dest) nogil except -1:
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    if fmt.pa_ident == paFloat32:
        unpack_float32(item, dest)
    elif fmt.pa_ident == paInt32:
        unpack_sint32(item, dest)
    elif fmt.pa_ident == paInt24:
        unpack_sint24(item, dest)
    elif fmt.pa_ident == paInt16:
        unpack_sint16(item, dest)
    elif fmt.pa_ident == paInt8:
        unpack_sint8(item, dest)
    elif fmt.pa_ident == paUInt8:
        unpack_uint8(item, dest)
    else:
        raise_withgil(PyExc_ValueError, 'Unsupported format')
    return 0

cdef void unpack_float32(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef FLOAT32_DTYPE_t *data_view = <FLOAT32_DTYPE_t *>item.bfr

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            dest[chan_num,chan_ix] = data_view[i]
            i += 1

cdef void unpack_sint32(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT32_DTYPE_t *data_view = <INT32_DTYPE_t *>item.bfr

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            dest[chan_num,chan_ix] = <float>data_view[i] * fmt.float32_multiplier
            i += 1

cdef void unpack_sint24(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t bfr_ix, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef unsigned char *bfr = <unsigned char *>item.bfr
    cdef double multiplier = 1 / 2147483648.0  # 2 ** 32 / 2
    cdef int32_t unpacked

    chan_ix = 0
    chan_num = 0
    bfr_ix = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            IF LITTLE_ENDIAN:
                unpacked =  ((<int32_t>bfr[bfr_ix+0]) << 8)
                unpacked |= ((<int32_t>bfr[bfr_ix+1]) << 16)
                unpacked |= ((<int32_t>bfr[bfr_ix+2]) << 24)
            ELSE:
                unpacked =  <int32_t>bfr[bfr_ix+2] << 8
                unpacked |= <int32_t>bfr[bfr_ix+1] << 16
                unpacked |= <int32_t>bfr[bfr_ix+0] << 24
            dest[chan_num,chan_ix] = <float>(<double>unpacked * multiplier)
            bfr_ix += 3

cdef void unpack_sint16(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT16_DTYPE_t *data_view = <INT16_DTYPE_t *>item.bfr

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            dest[chan_num,chan_ix] = <float>data_view[i] * fmt.float32_multiplier
            i += 1

cdef void unpack_sint8(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef INT8_DTYPE_t *data_view = <INT8_DTYPE_t *>item.bfr

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            dest[chan_num,chan_ix] = <float>data_view[i] * fmt.float32_multiplier
            i += 1

cdef void unpack_uint8(BufferItem* item, float[:,:] dest) nogil:
    cdef Py_ssize_t i, chan_ix, chan_num
    cdef SampleFormat* fmt = item.parent_buffer.sample_format
    cdef UINT8_DTYPE_t *data_view = <UINT8_DTYPE_t *>item.bfr
    cdef float value

    chan_ix = 0
    chan_num = 0
    i = 0
    for chan_ix in range(item.length):
        for chan_num in range(item.nchannels):
            # value = <float>data_view[i] / 128.0 - 1.0
            value = <float>data_view[i] / 256
            value = value * 2.0 - 1.0
            # value = <float>data_view[i] - 128
            # value *= fmt.float32_multiplier
            # value = <float>data_view[i] * fmt.float32_multiplier
            # value -= 1.0

            dest[chan_num,chan_ix] = value
            i += 1

# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.buffer cimport BufferItem

cdef int pack_buffer_item(BufferItem* item, float[:,:] src) nogil except -1
cdef void pack_float32(BufferItem* item, float[:,:] src) nogil
cdef void pack_sint32(BufferItem* item, float[:,:] src) nogil
cdef void pack_sint24(BufferItem* item, float[:,:] src) nogil
cdef void pack_sint16(BufferItem* item, float[:,:] src) nogil
cdef void pack_sint8(BufferItem* item, float[:,:] src) nogil
cdef void pack_uint8(BufferItem* item, float[:,:] src) nogil

cdef int unpack_buffer_item(BufferItem* item, float[:,:] dest) nogil except -1
cdef void unpack_float32(BufferItem* item, float[:,:] dest) nogil
cdef void unpack_sint32(BufferItem* item, float[:,:] dest) nogil
cdef void unpack_sint24(BufferItem* item, float[:,:] dest) nogil
cdef void unpack_sint16(BufferItem* item, float[:,:] dest) nogil
cdef void unpack_sint8(BufferItem* item, float[:,:] dest) nogil
cdef void unpack_uint8(BufferItem* item, float[:,:] dest) nogil

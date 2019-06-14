# cython: language_level=3, linetrace=False, profile=False

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.buffer cimport *
from cysounddevice.streams cimport *


cdef int _stream_callback(const void* in_bfr,
                          void* out_bfr,
                          unsigned long frame_count,
                          const PaStreamCallbackTimeInfo* time_info,
                          PaStreamCallbackFlags status_flags,
                          void* user_data) nogil

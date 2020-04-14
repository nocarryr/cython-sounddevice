# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.devices cimport DeviceInfo
from cysounddevice.buffer cimport *
from cysounddevice.stream_callback cimport StreamCallback, CallbackUserData

cdef class Stream:
    cdef readonly DeviceInfo device
    cdef readonly StreamInfo stream_info
    cdef readonly StreamCallback callback_handler
    cdef readonly StreamInputBuffer input_buffer
    cdef readonly StreamOutputBuffer output_buffer
    cdef PaStream* _pa_stream_ptr
    cdef unsigned long _frames_per_buffer
    cdef readonly bint starting

    cdef SampleFormat* _get_sample_format(self)
    cdef CallbackUserData* _get_callback_data(self)
    cpdef check(self)
    cpdef check_active(self)
    cpdef open(self)
    cpdef close(self)
    cdef int check_callback_errors(self) nogil except -1

cdef class StreamInfo:
    cdef SampleFormat* sample_format
    cdef PaStreamParameters _pa_input_params
    cdef PaStreamParameters _pa_output_params
    cdef PaStreamFlags _pa_flags
    cdef Stream stream
    cdef readonly double _sample_rate
    cdef readonly int _input_channels, _output_channels
    cdef readonly PaTime _input_latency, _output_latency
    cdef public bint clip_off, dither_off, never_drop_input, prime_out_buffer

    cdef void _set_sample_format(self, str name, dict kwargs) except *
    cdef PaStreamParameters* get_input_params(self)
    cdef PaStreamParameters* get_output_params(self)
    cdef void _update_from_pa_stream_info(self, const PaStreamInfo* info) except *
    cdef void _update_pa_data(self) except *

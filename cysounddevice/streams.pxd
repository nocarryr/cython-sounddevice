# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.devices cimport DeviceInfo
from cysounddevice.buffer cimport *

cdef struct CallbackUserData:
    int input_channels
    int output_channels
    SampleBuffer* in_buffer
    SampleBuffer* out_buffer

cdef class Stream:
    cdef readonly DeviceInfo device
    cdef readonly StreamInfo stream_info
    cdef readonly StreamCallback callback_handler
    cdef PaStream* _pa_stream_ptr
    cdef unsigned long _frames_per_buffer
    cdef readonly bint active

    cpdef check(self)
    cpdef open(self)
    cpdef close(self)

cdef class StreamInfo:
    cdef SampleFormat sample_format
    cdef PaStreamParameters _pa_input_params
    cdef PaStreamParameters _pa_output_params
    cdef PaStreamFlags _pa_flags
    cdef DeviceInfo device
    cdef public double sample_rate
    cdef public int input_channels, output_channels
    cdef public PaTime suggested_latency
    cdef readonly PaTime input_latency, output_latency
    cdef public bint clip_off, dither_off, never_drop_input, prime_out_buffer

    cdef void _update_pa_data(self) except *

cdef class StreamCallback:
    cdef PaStreamCallbackFlags _pa_flags
    cdef PaStreamCallback* _pa_callback_ptr
    cdef Stream stream
    cdef CallbackUserData* user_data
    cdef readonly SampleTime sample_time
    cdef public bint input_underflow, input_overflow
    cdef public bint output_underflow, output_overflow, priming_output

    cdef void _build_user_data(self, Py_ssize_t buffer_len=*) except *
    cdef void _update_pa_data(self) except *

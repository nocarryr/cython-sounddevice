# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.types cimport *
from cysounddevice.buffer cimport *
from cysounddevice.streams cimport *

cdef enum CallbackErrorStatus:
    CallbackError_none
    CallbackError_flags
    CallbackError_input_aborted
    CallbackError_output_aborted

cdef struct CallbackUserData:
    int input_channels
    int output_channels
    SampleBuffer* in_buffer
    SampleBuffer* out_buffer
    # SampleFormat* sample_format
    PaTime firstInputAdcTime
    PaTime firstOutputDacTime
    PaStreamCallbackFlags last_callback_flags
    CallbackErrorStatus error_status
    bint exit_signal
    bint stream_exit_complete

cdef class StreamCallback:
    cdef PaStreamCallbackFlags _pa_flags
    cdef PaStreamCallback* _pa_callback_ptr
    cdef readonly Stream stream
    cdef CallbackUserData* user_data
    cdef readonly SampleTime sample_time
    cdef public bint input_underflow, input_overflow
    cdef public bint output_underflow, output_overflow, priming_output

    cdef void _build_user_data(self, Py_ssize_t buffer_len=*) except *
    cdef void _free_user_data(self) except *
    cdef void _send_exit_signal(self, float timeout) except *
    cdef void _update_pa_data(self) except *
    cdef int check_callback_errors(self) nogil except -1


cdef int _stream_callback(const void* in_bfr,
                          void* out_bfr,
                          unsigned long frame_count,
                          const PaStreamCallbackTimeInfo* time_info,
                          PaStreamCallbackFlags status_flags,
                          void* user_data) nogil

# cython: language_level=3

cimport cython
from cpython.mem cimport PyMem_Malloc, PyMem_Free

from cysounddevice.pawrapper cimport *
from cysounddevice.utils cimport handle_error
from cysounddevice.devices cimport DeviceInfo
from cysounddevice.types cimport *

# cdef enum CallbackType:
#     CallbackTypeFunction
#     CallbackTypeMethod
#     CallbackTypeFunctionC
#     CallbackTypeMethodC
#
# cdef struct CallbackHandle:
#     PyObject* obj
#     char* method_name
#     void* func_ptr
#     CallbackType type

cdef class Stream:
    def __cinit__(self, DeviceInfo device):
        self.stream_info = StreamInfo(device)
        self.callback_handler = StreamCallback(self)
        self._frames_per_buffer = 512
        self.active = False
    @property
    def frames_per_buffer(self):
        return self._frames_per_buffer
    @frames_per_buffer.setter
    def frames_per_buffer(self, unsigned long value):
        self._frames_per_buffer = value

    cpdef open(self):
        if self.active:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        handle_error(Pa_OpenStream(
            &ptr,
            &self.stream_info._pa_input_params,
            &self.stream_info._pa_output_params,
            self.stream_info.sample_rate,
            self.frames_per_buffer,
            self.stream_info._pa_flags,
            self.callback_handler._pa_callback_ptr,
            <void*>self.callback_handler,
        ))
        self.active = True
        cdef PaStreamInfo* info = Pa_GetStreamInfo(ptr)
        if info == NULL:
            raise Exception('Could not get stream info')
        self.stream_info.sample_rate = info.sampleRate
        self.stream_info.input_latency = info.inputLatency
        self.stream_info.output_latency = info.outputLatency
        cdef PaError err = Pa_StartStream(ptr)
        if err != paStreamIsNotStopped:
            handle_error(err)
    cpdef close(self):
        if not self.active:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        handle_error(Pa_CloseStream(ptr))
    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()
    cdef int stream_callback(self, const void* in_bfr,
                             void* out_bfr,
                             unsigned long frame_count,
                             const PaStreamCallbackTimeInfo* time_info,
                             PaStreamCallbackFlags status_flags) except -1:
        return paContinue

cdef class StreamInfo:
    def __cinit__(self, DeviceInfo device):
        self.device = device
        self.input_channels = device.num_inputs
        self.output_channels = device.num_outputs
        self.sample_rate = device.default_sample_rate
        self.sample_format = &SampleFormats.sf_float32
        self.suggested_latency = device._ptr.defaultHighInputLatency
        self.input_latency = 0
        self.output_latency = 0
        self._pa_params.device = device.index
    def __init__(self, *args):
        self._update_pa_data()
    cdef void _update_pa_data(self) except *:
        self._pa_input_params.device = self.device.index
        self._pa_input_params.channelCount = self.input_channels
        self._pa_input_params.sampleFormat = self.sample_format.pa_ident
        self._pa_input_params.suggestedLatency = self.suggested_latency

        self._pa_output_params.device = self.device.index
        self._pa_output_params.channelCount = self.output_channels
        self._pa_output_params.sampleFormat = self.sample_format.pa_ident
        self._pa_output_params.suggestedLatency = self.suggested_latency

        cdef PaStreamFlags flags = 0

        if self.clip_off:
            flags |= 1
        if self.dither_off:
            flags |= 2
        if self.never_drop_input:
            flags |= 4
        if self.prime_out_buffer:
            flags |= 8
        self._pa_flags = flags


cdef int _stream_callback(const void* in_bfr,
                          void* out_bfr,
                          unsigned long frame_count,
                          const PaStreamCallbackTimeInfo* time_info,
                          PaStreamCallbackFlags status_flags,
                          void* user_data) except -1:
    cdef StreamCallback obj = <StreamCallback>user_data

    return obj.stream_callback(in_bfr, out_bfr, frame_count, time_info, status_flags)


cdef class StreamCallback:
    def __cinit__(self, Stream stream):
        self.stream = stream
        self._pa_callback_ptr = <PaStreamCallback*>_stream_callback
        self.input_underflow = False
        self.input_overflow = False
        self.output_underflow = False
        self.output_overflow = False
        self.priming_output = False
    def __init__(self, *args):
        self._update_pa_data()
    cdef void _update_pa_data(self) except *:
        cdef PaStreamCallbackFlags flags = 0

        if self.input_underflow:
            flags |= 1
        if self.input_overflow:
            flags |= 2
        if self.output_underflow:
            flags |= 4
        if self.output_overflow:
            flags |= 8
        if self.priming_output:
            flags |= 16
    cdef int stream_callback(self, const void* in_bfr,
                             void* out_bfr,
                             unsigned long frame_count,
                             const PaStreamCallbackTimeInfo* time_info,
                             PaStreamCallbackFlags status_flags) except -1:
        return self.stream.stream_callback(in_bfr, out_bfr, frame_count, time_info, status_flags)

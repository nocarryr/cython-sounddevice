# cython: language_level=3

cimport cython
from cython cimport view
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

cdef struct TestData_s:
    Py_ssize_t count

cdef TestData_s TestData

cdef class Stream:
    def __cinit__(self, DeviceInfo device):
        self.device = device
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

    cpdef check(self):
        cdef PaError err = Pa_IsFormatSupported(
            &self.stream_info._pa_input_params,
            &self.stream_info._pa_output_params,
            self.stream_info.sample_rate,
        )
        return err
    cpdef open(self):
        if self.active:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        cdef PaError sample_size = Pa_GetSampleSize(self.stream_info.sample_format.pa_ident)
        print('sample_size={}, should be {} bits'.format(
            sample_size, self.stream_info.sample_format.bit_width,
        ))
        handle_error(Pa_OpenStream(
            &ptr,
            &self.stream_info._pa_input_params,
            &self.stream_info._pa_output_params,
            self.stream_info.sample_rate,
            self.frames_per_buffer,
            self.stream_info._pa_flags,
            self.callback_handler._pa_callback_ptr,
            # &TestData,
            <void*>self.callback_handler,
        ))
        self.active = True
        cdef const PaStreamInfo* info = Pa_GetStreamInfo(ptr)
        if info == NULL:
            raise Exception('Could not get stream info')
        self.stream_info.sample_rate = info.sampleRate
        self.stream_info.input_latency = info.inputLatency
        self.stream_info.output_latency = info.outputLatency
        self._pa_stream_ptr = ptr
        cdef PaError err = Pa_StartStream(ptr)
        if err != paStreamIsNotStopped:
            handle_error(err)
        # print('waiting...')
        # Pa_Sleep(5000)
        # print('stopping...')
        # self.close()
        # self.device.close()
    cpdef close(self):
        if not self.active:
            return
        # cdef PaStream* ptr = self._pa_stream_ptr
        self.active = False
        # handle_error(Pa_StopStream(self._pa_stream_ptr))
        # print('stopped')
        handle_error(Pa_CloseStream(self._pa_stream_ptr))
        print('closed')
    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()
    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cdef int stream_callback(self, const void *in_bfr,
                             void *out_bfr,
                             unsigned long frame_count,
                             const PaStreamCallbackTimeInfo* time_info,
                             PaStreamCallbackFlags status_flags) except -1:
        cdef unsigned long i
        # print('stream_callback: {}'.format(frame_count))
        # cdef unsigned long in_size = frame_count * self.stream_info.input_channels
        cdef unsigned long out_size = frame_count * self.stream_info.output_channels
        cdef char *cbfr = <char *>out_bfr
        cdef float *fbfr = <float *>cbfr
        cdef float value

        # cdef float *out_view = <float *>out_bfr
        # cdef view.array out_arr = view.array(shape=(1, frame_count * out_size), itemsize=sizeof(float), format='f', allocate_buffer=False)
        # out_arr.data = <char *>out_bfr

        for i in range(frame_count):
            # out_view[i] = 0
            value = (i / <float>frame_count * 2) - 1

            # left
            fbfr[0] = value
            fbfr += 1

            # right
            fbfr[0] = 0
            fbfr += 1
        return paContinue

cdef class StreamInfo:
    def __cinit__(self, DeviceInfo device):
        cdef SampleFormat sf
        sf.pa_ident = 1
        sf.bit_width = 32
        sf.is_float = True
        sf.is_signed = True
        sf.is_24bit = False
        self.sample_format = sf
        self.device = device
        self.input_channels = device.num_inputs
        self.output_channels = device.num_outputs
        self.sample_rate = device.default_sample_rate
        # self.sample_format = SampleFormats.sf_float32
        print('sample_format: ident={}, bit_width={}, signed={}, is_float={}'.format(
            self.sample_format.pa_ident, self.sample_format.bit_width,
            self.sample_format.is_signed, self.sample_format.is_float,
        ))
        self.suggested_latency = device._ptr.defaultHighInputLatency
        self.input_latency = 0
        self.output_latency = 0
        self._pa_input_params.device = device.index
        self._pa_output_params.device = device.index
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
                          void* user_data) with gil:
    cdef StreamCallback obj = <StreamCallback>user_data

    return obj.stream_callback(in_bfr, out_bfr, frame_count, time_info, status_flags)
    # print('cb')
    # cdef TestData_s* test_data = <TestData_s*>user_data
    # if test_data.count >= 20:
    #     return paComplete
    # test_data.count = test_data.count + 1
    # return paContinue


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

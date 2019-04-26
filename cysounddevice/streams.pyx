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
    """A stream for audio input and output

    Attributes:
        device (DeviceInfo): The :class:`~cysounddevice.devices.DeviceInfo`
            instance that created the stream
        stream_info (StreamInfo): A :class:`StreamInfo` instance used to
            configure stream parameters
        callback_handler (StreamCallback): A :class:`StreamCallback` instance
            to handle callbacks from PortAudio
        frames_per_buffer (int): Number of samples per callback (block size)
        active (bool): The stream state
    """
    def __cinit__(self, DeviceInfo device, *args, **kwargs):
        self._frames_per_buffer = 512
        self.device = device
        self.stream_info = StreamInfo(self, **kwargs)
        self.callback_handler = StreamCallback(self)
        self.active = False
    def __init__(self, *args, **kwargs):
        keys = ['frames_per_buffer']
        for key in keys:
            if key in kwargs:
                val = kwargs[key]
                setattr(self, key, val)
    @property
    def frames_per_buffer(self):
        return self._frames_per_buffer
    @frames_per_buffer.setter
    def frames_per_buffer(self, unsigned long value):
        if self.active:
            return
        self._frames_per_buffer = value

    cpdef check(self):
        """Check the stream configuration in PortAudio

        Returns:
            PaError: 0 on success, see `PaErrorCode`
        """
        cdef PaError err = Pa_IsFormatSupported(
            &self.stream_info._pa_input_params,
            &self.stream_info._pa_output_params,
            self.stream_info.sample_rate,
        )
        return err
    cpdef open(self):
        """Open the stream and begin audio processing

        Note:
            This method is a no-op if the stream is already active.
        """
        if self.active:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        cdef PaError sample_size = Pa_GetSampleSize(self.stream_info.sample_format.pa_ident)
        print('sample_size={}, should be {} bits'.format(
            sample_size, self.stream_info.sample_format.bit_width,
        ))
        self.callback_handler._build_user_data()
        handle_error(Pa_OpenStream(
            &ptr,
            &self.stream_info._pa_input_params,
            &self.stream_info._pa_output_params,
            self.stream_info.sample_rate,
            self.frames_per_buffer,
            self.stream_info._pa_flags,
            self.callback_handler._pa_callback_ptr,
            # &TestData,
            <void*>self.callback_handler.user_data,
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
        """Close the stream if active
        """
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

cdef class StreamInfo:
    """Configuration parameters for :class:`Stream`

    Attributes:
        sample_format (SampleFormat): The sample format for the stream, see
            `cysounddevice.types.SampleFormats`
        sample_rate (int): Sample rate of the stream
        input_channels (int): Number of channels to receive from the device.
            Use ``0`` for output-only
        output_channels (int): Number of channels to send to the device.
            Use ``0`` for input-only
    """
    def __cinit__(self, Stream stream, *args, **kwargs):
        cdef DeviceInfo device = stream.device
        self.stream = stream
        self._input_channels = device.num_inputs
        self._output_channels = device.num_outputs
        self._sample_rate = device.default_sample_rate
        self.suggested_latency = device._ptr.defaultHighInputLatency
        self.input_latency = 0
        self.output_latency = 0
        self._pa_input_params.device = device.index
        self._pa_output_params.device = device.index
    def __init__(self, *args, **kwargs):
        cdef str sf_name = kwargs.get('sample_format', '')
        self._set_sample_format(sf_name, kwargs)

        keys = ['input_channels', 'output_channels', 'sample_rate']
        for key in keys:
            if key in kwargs:
                val = kwargs[key]
                setattr(self, key, val)
        self._update_pa_data()
    cdef void _set_sample_format(self, str name, dict kwargs) except *:
        cdef SampleFormat* sf
        if len(name):
            sf = get_sample_format_by_name(name)
        else:
            sf = get_sample_format_by_kwargs(kwargs)
        self.sample_format = sf
    @property
    def device(self):
        return self.stream.device
    @property
    def input_channels(self):
        return self._input_channels
    @input_channels.setter
    def input_channels(self, int value):
        if self.stream.active:
            return
        if value == self._input_channels:
            return
        self._input_channels = value
        self._update_pa_data()
    @property
    def output_channels(self):
        return self._output_channels
    @output_channels.setter
    def output_channels(self, int value):
        if self.stream.active:
            return
        if value == self._output_channels:
            return
        self._output_channels = value
        self._update_pa_data()
    @property
    def sample_rate(self):
        return self._sample_rate
    @sample_rate.setter
    def sample_rate(self, double value):
        if self.stream.active:
            return
        if value == self._sample_rate:
            return
        self._sample_rate = value
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


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _stream_callback(const void* in_bfr,
                          void* out_bfr,
                          unsigned long frame_count,
                          const PaStreamCallbackTimeInfo* time_info,
                          PaStreamCallbackFlags status_flags,
                          void* user_data) nogil:
    cdef CallbackUserData* cb_data = <CallbackUserData*>user_data
    cdef SampleTime_s* start_time
    cdef int r
    cdef unsigned long i, bfr_size
    cdef char *in_ptr = <char *>in_bfr
    cdef char *out_ptr = <char *>out_bfr

    if cb_data.input_channels > 0:
        if cb_data.in_buffer.read_available > 0:
            start_time = sample_buffer_read(cb_data.in_buffer, in_ptr, frame_count)
            if start_time == NULL:
                return paAbort
        cb_data.in_buffer.current_block += 1
    if cb_data.output_channels > 0:
        if cb_data.out_buffer.write_available > 0:
            r = sample_buffer_write(cb_data.out_buffer, out_ptr, frame_count)
            if r != 1:
                return paAbort
        cb_data.out_buffer.current_block += 1
    return paContinue


cdef void callback_user_data_destroy(CallbackUserData* user_data) except *:
    if user_data.in_buffer != NULL:
        sample_buffer_destroy(user_data.in_buffer)
    if user_data.out_buffer != NULL:
        sample_buffer_destroy(user_data.out_buffer)

cdef class StreamCallback:
    """Handler for PortAudio callbacks

    Attributes:
        stream (Stream): The :class:`Stream` that created the callback
        sample_time (SampleTime): A :class:`cysounddevice.types.SampleTime`
            instance to track timing from PortAudio
        user_data: Pointer to a :any:`CallbackUserData` structure
    """
    def __cinit__(self, Stream stream):
        self.stream = stream
        self._pa_callback_ptr = <PaStreamCallback*>_stream_callback
        self.input_underflow = False
        self.input_overflow = False
        self.output_underflow = False
        self.output_overflow = False
        self.priming_output = False
        self.user_data = NULL
        self.sample_time = SampleTime(stream.stream_info.sample_rate, stream._frames_per_buffer)
    def __init__(self, *args):
        self._update_pa_data()
    def __dealloc__(self):
        if self.user_data:
            callback_user_data_destroy(self.user_data)
            PyMem_Free(self.user_data)
    cdef void _build_user_data(self, Py_ssize_t buffer_len=32) except *:
        if self.user_data:
            callback_user_data_destroy(self.user_data)
            PyMem_Free(self.user_data)
            self.user_data = NULL
        cdef StreamInfo info = self.stream.stream_info
        cdef int in_chan = info.input_channels
        cdef int out_chan = info.output_channels
        cdef Py_ssize_t itemsize = info.sample_format.bit_width // 8

        cdef CallbackUserData* user_data = <CallbackUserData*>PyMem_Malloc(sizeof(CallbackUserData))
        if not user_data:
            raise MemoryError()

        print('{!r}, bfr_len={}, in={}, out={}, itemsize={}'.format(
            self.sample_time, buffer_len, in_chan, out_chan, itemsize,
        ))
        if in_chan > 0:
            user_data.in_buffer = sample_buffer_create(self.sample_time.data, buffer_len, in_chan, itemsize)
        if out_chan > 0:
            user_data.out_buffer = sample_buffer_create(self.sample_time.data, buffer_len, out_chan, itemsize)
        user_data.input_channels = in_chan
        user_data.output_channels = out_chan
        self.user_data = user_data

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

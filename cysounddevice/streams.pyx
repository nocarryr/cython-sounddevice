# cython: language_level=3

cimport cython
from cython cimport view
from cpython.mem cimport PyMem_Malloc, PyMem_Free

import time
import warnings

from cysounddevice.pawrapper cimport *
from cysounddevice.utils cimport handle_error
from cysounddevice.devices cimport DeviceInfo
from cysounddevice.types cimport *
from cysounddevice.stream_callback cimport _stream_callback

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

class StreamCallbackError(RuntimeWarning):
    def __init__(self, msg):
        self.msg = msg
    def __str__(self):
        return repr(self.msg)

cdef struct TestData_s:
    Py_ssize_t count

cdef TestData_s TestData

cdef class Stream:
    """A stream for audio input and output

    Arguments:
        device (DeviceInfo):

    Keyword Arguments:
        frames_per_buffer (int):

    Attributes:
        device (DeviceInfo): The :class:`~cysounddevice.devices.DeviceInfo`
            instance that created the stream
        stream_info (StreamInfo): A :class:`StreamInfo` instance used to
            configure stream parameters
        input_buffer (StreamInputBuffer):
        output_buffer (StreamOutputBuffer):
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
        self.input_buffer = StreamInputBuffer(self)
        self.output_buffer = StreamOutputBuffer(self)
        self.starting = False
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
        self.stream_info._update_pa_data()
    @property
    def active(self):
        if self.check_active():
            return True
        if self.starting:
            return True
        return False
    @property
    def input_channels(self): return self.stream_info.input_channels
    @input_channels.setter
    def input_channels(self, int value): self.stream_info.input_channels = value

    @property
    def output_channels(self): return self.stream_info.output_channels
    @output_channels.setter
    def output_channels(self, int value): self.stream_info.output_channels = value

    @property
    def sample_rate(self):
        return self.stream_info.sample_rate
    @sample_rate.setter
    def sample_rate(self, double value): self.stream_info.sample_rate = value

    cdef SampleFormat* _get_sample_format(self):
        return self.stream_info.sample_format

    cdef CallbackUserData* _get_callback_data(self):
        if not self.active:
            return NULL
        return self.callback_handler.user_data

    cpdef check(self):
        """Check the stream configuration in PortAudio

        Returns:
            PaError: 0 on success, see `PaErrorCode`
        """
        cdef PaStreamParameters* pa_input_params = self.stream_info.get_input_params()
        cdef PaStreamParameters* pa_output_params = self.stream_info.get_output_params()
        cdef PaError err = Pa_IsFormatSupported(
            pa_input_params,
            pa_output_params,
            self.sample_rate,
        )
        if err != 0:
            handle_error(err)
        return err
    cpdef check_active(self):
        cdef PaError err
        cdef bint active = False

        if self._pa_stream_ptr != NULL:
            err = Pa_IsStreamActive(self._pa_stream_ptr)
            if err == 1:
                active = True
            elif err == 0:
                active = False
            elif err == paBadStreamPtr:
                active = False
                self._pa_stream_ptr = NULL
            else:
                handle_error(err)
        return active
    cpdef open(self):
        """Open the stream and begin audio processing

        Note:
            This method is a no-op if the stream is already active.
        """
        if self.active:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        cdef PaError sample_size = Pa_GetSampleSize(self.stream_info.sample_format.pa_ident)
        cdef PaStreamParameters* pa_input_params = self.stream_info.get_input_params()
        cdef PaStreamParameters* pa_output_params = self.stream_info.get_output_params()

        print('sample_size={}, should be {} bits'.format(
            sample_size, self.stream_info.sample_format.bit_width,
        ))
        self.callback_handler._build_user_data()
        cdef CallbackUserData* user_data = self.callback_handler.user_data
        handle_error(Pa_OpenStream(
            &ptr,
            pa_input_params,
            pa_output_params,
            self.sample_rate,
            self.frames_per_buffer,
            self.stream_info._pa_flags,
            self.callback_handler._pa_callback_ptr,
            # &TestData,
            <void*>user_data,
        ))
        if self.input_channels > 0:
            self.input_buffer._set_sample_buffer(user_data.in_buffer)
        if self.output_channels > 0:
            self.output_buffer._set_sample_buffer(user_data.out_buffer)
        self.starting = True
        cdef const PaStreamInfo* info = Pa_GetStreamInfo(ptr)
        if info == NULL:
            raise Exception('Could not get stream info')
        self.stream_info._update_from_pa_stream_info(info)
        self._pa_stream_ptr = ptr
        cdef PaError err = Pa_StartStream(ptr)
        if err != paStreamIsNotStopped:
            handle_error(err)
        self.starting = False
        # print('waiting...')
        # Pa_Sleep(5000)
        # print('stopping...')
        # self.close()
        # self.device.close()
    cpdef close(self):
        """Close the stream if active
        """
        if self._pa_stream_ptr == NULL:
            return
        cdef PaStream* ptr = self._pa_stream_ptr
        self.starting = False

        self.callback_handler._send_exit_signal(2)
        if not self.check_active():
            Pa_AbortStream(ptr)

        self._pa_stream_ptr = NULL
        # handle_error(Pa_StopStream(self._pa_stream_ptr))
        # print('stopped')
        self.callback_handler._free_user_data()
        print('closed')
    cdef int check_callback_errors(self) nogil except -1:
        self.callback_handler.check_callback_errors()
        return 0
    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()
    def __repr__(self):
        return '<{self.__class__.__name__} object for "{self.device.name}": {self}>'.format(self=self)
    def __str__(self):
        return '{self.stream_info}, block_size={self.frames_per_buffer}'.format(self=self)

cdef class StreamInfo:
    """Configuration parameters for :class:`Stream`

    Arguments:
        stream (Stream):

    Keyword Arguments:
        input_channels (int):
        output_channels (int):

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
        self._input_latency = 0
        self._output_latency = 0
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
    @property
    def suggested_latency(self):
        cdef double result
        cdef double block_size = <double>self.stream.frames_per_buffer * 2
        result = block_size / self._sample_rate
        return result
    @property
    def input_latency(self):
        return self._input_latency
    @input_latency.setter
    def input_latency(self, PaTime value):
        if self.stream.active:
            return
        if value == self._input_latency:
            return
        self._input_latency = value
        print('input_latency={}'.format(value))
    @property
    def output_latency(self):
        return self._output_latency
    @output_latency.setter
    def output_latency(self, PaTime value):
        if self.stream.active:
            return
        if value == self._output_latency:
            return
        self._output_latency = value
        print('output_latency={}'.format(value))

    cdef PaStreamParameters* get_input_params(self):
        if self._input_channels > 0:
            return &self._pa_input_params
        else:
            return NULL
    cdef PaStreamParameters* get_output_params(self):
        if self._output_channels > 0:
            return &self._pa_output_params
        else:
            return NULL

    cdef void _update_from_pa_stream_info(self, const PaStreamInfo* info) except *:
        self._sample_rate = info.sampleRate
        self._input_latency = info.inputLatency
        self._output_latency = info.outputLatency
        print('input_latency={}, output_latency={}'.format(info.inputLatency, info.outputLatency))

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
    def __repr__(self):
        return '<{self.__class__.__name__}: ({self})>'.format(self=self)
    def __str__(self):
        s = '{self.input_channels} ins, {self.output_channels} outs, rs={self.sample_rate}'.format(self=self)
        return s


cdef raise_stream_callback_error(CallbackUserData* user_data):
    cdef PaStreamCallbackFlags cb_flags = user_data.last_callback_flags
    cdef object msg = None
    if user_data.error_status == CallbackError_flags:
        msgs = []
        if cb_flags & 1:
            msgs.append('Input Underflow')
        if cb_flags & 2:
            msgs.append('Input Overflow')
        if cb_flags & 4:
            msgs.append('Output Underflow')
        if cb_flags & 8:
            msgs.append('Output Overflow')
        if not len(msgs):
            return
        msg = ', '.join(msgs)
    elif user_data.error_status == CallbackError_input_aborted:
        msg = 'Input Aborted'
    elif user_data.error_status == CallbackError_output_aborted:
        msg = 'Output Aborted'
    else:
        return
    warnings.warn(StreamCallbackError(msg))

cdef void callback_user_data_destroy(CallbackUserData* user_data) except *:
    if user_data.in_buffer != NULL:
        sample_buffer_destroy(user_data.in_buffer)
        user_data.in_buffer = NULL
    if user_data.out_buffer != NULL:
        sample_buffer_destroy(user_data.out_buffer)
        user_data.out_buffer = NULL

cdef class StreamCallback:
    """Handler for PortAudio callbacks

    Arguments:
        stream (Stream):

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
        self.sample_time = SampleTime(0, 0, stream._frames_per_buffer, stream.sample_rate)
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

        if (self.sample_time.sample_rate != self.stream.sample_rate or
                self.sample_time.block_size != self.stream.frames_per_buffer):
            self.sample_time = SampleTime(0, 0, self.stream.frames_per_buffer, self.stream.sample_rate)

        print('{!r}, bfr_len={}, in={}, out={}, itemsize={}'.format(
            self.sample_time, buffer_len, in_chan, out_chan, itemsize,
        ))
        if in_chan > 0:
            user_data.in_buffer = sample_buffer_create(self.sample_time.data, buffer_len, in_chan, info.sample_format)
        else:
            user_data.in_buffer = NULL
        if out_chan > 0:
            user_data.out_buffer = sample_buffer_create(self.sample_time.data, buffer_len, out_chan, info.sample_format)
        else:
            user_data.out_buffer = NULL
        user_data.input_channels = in_chan
        user_data.output_channels = out_chan
        user_data.last_callback_flags = 0
        user_data.error_status = CallbackError_none
        user_data.exit_signal = False
        user_data.stream_exit_complete = False
        self.user_data = user_data
    cdef void _free_user_data(self) except *:
        cdef CallbackUserData* user_data
        if self.user_data:
            user_data = self.user_data
            self.user_data = NULL
            callback_user_data_destroy(user_data)
            PyMem_Free(user_data)

    cdef void _send_exit_signal(self, float timeout) except *:
        """Sends an exit signal to the callback and waits for it to exit

        Set the `CallbackUserData.exit_signal` flag to True, then wait for the
        `CallbackUserData.stream_exit_complete` flag to be set from the
        PortAudio callback.

        Arguments:
            timeout(float): Time in seconds to wait for the callback to signal
                completion. If timeout <= 0, returns immediately.

        """
        if self.user_data == NULL:
            return
        cdef CallbackUserData* user_data = self.user_data
        user_data.exit_signal = True
        if timeout <= 0:
            return
        if user_data.stream_exit_complete:
            return

        cdef float cur_ts, end_ts
        cur_ts = time.time()
        end_ts = cur_ts + timeout
        while cur_ts <= end_ts:
            if user_data.stream_exit_complete:
                return
            time.sleep(.1)
            cur_ts = time.time()

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

    cdef int check_callback_errors(self) nogil except -1:
        cdef CallbackUserData* user_data
        if self.user_data:
            user_data = self.user_data
            if user_data.error_status != CallbackError_none:
                with gil:
                    raise_stream_callback_error(user_data)
        return 0

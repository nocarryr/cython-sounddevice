# cython: language_level=3

cimport cython
from cpython.mem cimport PyMem_Malloc, PyMem_Free

import time
import warnings

class StreamCallbackError(RuntimeWarning):
    def __init__(self, msg):
        self.msg = msg
    def __str__(self):
        return repr(self.msg)

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

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.profile(False)
@cython.linetrace(False)
cdef int _stream_callback(const void* in_bfr,
                          void* out_bfr,
                          unsigned long frame_count,
                          const PaStreamCallbackTimeInfo* time_info,
                          PaStreamCallbackFlags status_flags,
                          void* user_data) nogil: # pragma: no cover
    cdef CallbackUserData* cb_data = <CallbackUserData*>user_data
    cdef SampleBuffer* samp_bfr
    cdef SampleTime_s* start_time
    cdef PaTime adcTime, dacTime
    cdef int r
    cdef unsigned long i, bfr_size
    cdef char *in_ptr = <char *>in_bfr
    cdef char *out_ptr = <char *>out_bfr
    if cb_data.exit_signal:
        cb_data.stream_exit_complete = True
        return paComplete

    cb_data.error_status = CallbackError_none
    cb_data.last_callback_flags = status_flags
    if status_flags != 0:
        cb_data.error_status = CallbackError_flags

    if cb_data.input_channels > 0:
        samp_bfr = cb_data.in_buffer
        adcTime = time_info.inputBufferAdcTime
        if samp_bfr.current_block == 0:
            cb_data.firstInputAdcTime = adcTime
            samp_bfr.callback_time.time_offset = adcTime
            SampleTime_set_pa_time(&samp_bfr.callback_time, adcTime, True)
        else:
            SampleTime_set_block_vars(&samp_bfr.callback_time, samp_bfr.current_block, 0)
        if samp_bfr.write_available > 0:
            r = sample_buffer_write_from_callback(samp_bfr, in_ptr, frame_count, adcTime)
            if r != 1:
                cb_data.error_status = CallbackError_input_aborted
                cb_data.stream_exit_complete = True
                return paAbort
        samp_bfr.current_block += 1
    if cb_data.output_channels > 0:
        samp_bfr = cb_data.out_buffer
        dacTime = time_info.outputBufferDacTime
        if samp_bfr.current_block == 0:
            cb_data.firstOutputDacTime = dacTime
            samp_bfr.callback_time.time_offset = dacTime
            SampleTime_set_pa_time(&samp_bfr.callback_time, dacTime, True)
        else:
            SampleTime_set_block_vars(&samp_bfr.callback_time, samp_bfr.current_block, 0)
        if samp_bfr.read_available > 0:
            start_time = sample_buffer_read_from_callback(samp_bfr, out_ptr, frame_count, dacTime)
            if start_time == NULL:
                cb_data.error_status = CallbackError_output_aborted
                cb_data.stream_exit_complete = True
                return paAbort
        samp_bfr.current_block += 1
    return paContinue

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

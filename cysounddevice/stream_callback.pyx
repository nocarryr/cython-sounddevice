# cython: language_level=3, linetrace=False, profile=False

cimport cython


@cython.boundscheck(False)
@cython.wraparound(False)
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

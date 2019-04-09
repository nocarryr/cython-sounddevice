
from cysounddevice cimport pawrapper


class PortAudioError(Exception):
    def __init__(self, error_msg, err_code, host_info=None):
        self.error_msg = error_msg
        self.err_code = err_code
        self.host_info = host_info
    def __str__(self):
        return repr(self.error_msg)

cpdef handle_error(PaError err):
    if err == paNoError:
        return
    cdef bytes msg_bytes = Pa_GetErrorText(err)
    cdef str msg_str = msg_bytes.decode('UTF-8')
    raise PortAudioError(msg_str, err)

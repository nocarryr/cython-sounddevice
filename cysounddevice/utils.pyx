
from cysounddevice cimport pawrapper

cdef int raise_withgil(PyObject *error, char *msg) except -1 with gil:
    raise (<object>error)(msg.decode('ascii'))

class PortAudioError(Exception):
    def __init__(self, error_msg, err_code, host_info=None):
        self.error_msg = error_msg
        self.err_code = err_code
        self.host_info = host_info
    def __str__(self):
        return repr(self.error_msg)

cdef int handle_pa_error(PaError err) nogil except -1:
    if err != paNoError:
        raise_pa_error(err)
    return 0

cdef int raise_pa_error(PaError err) except -1 with gil:
    cdef bytes msg_bytes = Pa_GetErrorText(err)
    cdef str msg_str = msg_bytes.decode('UTF-8')
    raise PortAudioError(msg_str, err)

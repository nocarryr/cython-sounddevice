# cython: language_level=3

# from . cimport pawrapper as pa
from cysounddevice.pawrapper cimport *

cpdef handle_error(PaError err)

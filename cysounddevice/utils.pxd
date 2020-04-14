# cython: language_level=3

# from . cimport pawrapper as pa

cdef extern from 'Python.h':
    ctypedef struct PyObject
    PyObject *PyExc_Exception
    PyObject *PyExc_ValueError

from cysounddevice.pawrapper cimport *

cdef int raise_withgil(PyObject *error, char *msg) except -1 with gil

cdef int handle_pa_error(PaError err) nogil except -1

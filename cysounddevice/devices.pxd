# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.streams cimport Stream

cdef class DeviceInfo:
    cdef readonly PaDeviceIndex index
    cdef readonly PaHostApiIndex host_api_index
    cdef readonly HostApiInfo host_api
    cdef readonly str name
    cdef readonly double default_sample_rate
    cdef readonly int num_inputs, num_outputs
    cdef readonly bint active
    cdef readonly Stream stream

    cdef void _get_info(self) except *
    cpdef Stream _open_stream(self, dict kwargs)
    cpdef close(self)

cdef class HostApiInfo:
    cdef readonly PaHostApiIndex index
    cdef readonly Py_ssize_t device_count
    cdef readonly PaDeviceIndex default_input_index, default_output_index
    cdef readonly str name
    cdef dict devices_by_paindex, devices_by_name
    cdef readonly DeviceInfo default_input, default_output

    cpdef DeviceInfo get_device_by_name(self, str name)
    cdef void _get_info(self) except *
    cdef void _add_device(self, DeviceInfo device) except *

cdef class PortAudio:
    cdef char* jack_client_name_ptr
    cdef dict devices_by_paindex, devices_by_name
    cdef dict host_apis_by_paindex, host_apis_by_name
    cdef readonly bint _initialized
    cdef readonly DeviceInfo default_input, default_output

    cpdef open(self)
    cpdef close(self)
    cpdef DeviceInfo get_device_by_name(self, str name)
    cpdef DeviceInfo get_device_by_index(self, PaDeviceIndex i)
    cpdef HostApiInfo get_host_api_by_name(self, str name)
    cdef void _get_info(self) except *

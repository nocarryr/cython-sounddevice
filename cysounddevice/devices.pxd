# cython: language_level=3

from cysounddevice.pawrapper cimport *
from cysounddevice.streams cimport Stream

cdef class DeviceInfo:
    cdef readonly PaDeviceIndex index
    cdef readonly HostApiInfo host_api
    cdef const PaDeviceInfo* _ptr
    cdef readonly bint active
    cdef readonly Stream stream

    cdef void _get_info(self) except *
    cpdef Stream open_stream(self)
    cpdef close(self)

cdef class HostApiInfo:
    cdef readonly PaHostApiIndex index
    cdef const PaHostApiInfo* _ptr
    cdef dict devices_by_paindex, devices_by_name
    cdef readonly DeviceInfo default_input, default_output

    cpdef DeviceInfo get_device_by_name(self, str name)
    cdef void _get_info(self) except *
    cdef void _add_device(self, DeviceInfo device) except *

cdef class PortAudio:
    cdef dict devices_by_paindex, devices_by_name
    cdef dict host_apis_by_paindex, host_apis_by_name
    cdef bint _initialized
    cdef readonly DeviceInfo default_input, default_output

    cpdef open(self)
    cpdef close(self)
    cpdef DeviceInfo get_device_by_name(self, str name)
    cpdef DeviceInfo get_device_by_index(self, PaDeviceIndex i)
    cpdef HostApiInfo get_host_api_by_name(self, str name)
    cdef void _get_info(self) except *

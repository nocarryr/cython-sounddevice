# cython: language_level=3

cimport cython

import atexit

from cysounddevice.pawrapper cimport *
from cysounddevice.utils cimport handle_error

cdef class DeviceInfo:
    """Container for information about particular device

    Attributes:
        index (int): The internal index of the device used by PortAudio
        name (str): The device name
        host_api (HostApiInfo): The :class:`HostApiInfo` instance the device belongs to
        host_api_index (int): Internal index used by PortAudio to identify the
            associated HostApi
        num_inputs (int): Number of input channels
        num_outputs (int): Number of output channels
        default_sample_rate (int): Default sample rate
        active (bool): The device state
    """
    def __cinit__(self, PaDeviceIndex index_):
        self.index = index_
        self._ptr = NULL
        self.active = False
    def __init__(self, *args):
        self._get_info()
    @property
    def host_api_index(self):
        return self._ptr.hostApi
    @property
    def name(self):
        cdef bytes bname = self._ptr.name
        cdef str name = bname.decode('UTF-8')
        return name
    @property
    def num_inputs(self):
        return self._ptr.maxInputChannels
    @property
    def num_outputs(self):
        return self._ptr.maxOutputChannels
    @property
    def default_sample_rate(self):
        return self._ptr.defaultSampleRate
    cdef void _get_info(self) except *:
        self._ptr = Pa_GetDeviceInfo(self.index)
    cpdef Stream _open_stream(self, dict kwargs):
        if self.active:
            return
        self.stream = Stream(self, **kwargs)
        self.active = True
        return self.stream
    def open_stream(self, **kwargs):
        return self._open_stream(kwargs)
    cpdef close(self):
        """Close the device if active
        """
        if not self.active:
            return
        self.active = False
        self.stream.close()
        self.stream = None
    def __repr__(self):
        return '<{self.__class__.__name__}: {self}>'.format(self=self)
    def __str__(self):
        if self._ptr == NULL:
            return 'Unknown Device'
        return '{self.index} {self.name}, {self.host_api} ({self.num_inputs} in, {self.num_outputs} out)'.format(self=self)


cdef class HostApiInfo:
    """Container for information about a particular HostApi

    Attributes:
        index (int): The internal index of the HostApi reported by PortAudio
        name (str): The HostApi name
        device_count (int): Number of devices associated with this HostApi
        default_input (DeviceInfo): If the system default input uses this HostApi,
            the relevant :class:`~DeviceInfo` instance, otherwise ``None``.
        default_input (DeviceInfo): If the system default output uses this HostApi,
            the relevant :class:`~DeviceInfo` instance, otherwise ``None``.
    """
    def __cinit__(self, PaHostApiIndex index_):
        self.index = index_
        self._ptr = NULL
        self.devices_by_paindex = {}
        self.devices_by_name = {}
    def __init__(self, *args):
        self._get_info()
    @property
    def name(self):
        cdef bytes bname = self._ptr.name
        cdef str name = bname.decode('UTF-8')
        return name
    @property
    def device_count(self):
        assert self._ptr.deviceCount >= 0
        cdef Py_ssize_t count = self._ptr.deviceCount
        return count
    cpdef DeviceInfo get_device_by_name(self, str name):
        """Get a device by name
        """
        return self.devices_by_name[name]
    cdef void _get_info(self) except *:
        self._ptr = Pa_GetHostApiInfo(self.index)
    cdef void _add_device(self, DeviceInfo device) except *:
        if device.index in self.devices_by_paindex:
            return
        device.host_api = self
        self.devices_by_paindex[device.index] = device
        self.devices_by_name[device.name] = device
        if device.index == self._ptr.defaultInputDevice:
            self.default_input = device
        elif device.index == self._ptr.defaultOutputDevice:
            self.default_output = device
    def __repr__(self):
        return '<{self.__class__.__name__}: {self}>'.format(self=self)
    def __str__(self):
        if self._ptr == NULL:
            return 'Unknown HostApi'
        return self.name


cdef class PortAudio:
    """Main interface to PortAudio

    Gathers data to populate :class:`~HostApiInfo` and
    :class:`~DeviceInfo` instances.

    Attributes:
        device_count (int): Total number of devices detected
        host_api_count (int): Number of HostApi's detected
        default_input (DeviceInfo): The :class:`~DeviceInfo` instance for the default input
        default_output (DeviceInfo): The :class:`~DeviceInfo` instance for the default output
    """
    def __cinit__(self):
        self.devices_by_paindex = {}
        self.devices_by_name = {}
        self.host_apis_by_paindex = {}
        self.host_apis_by_name = {}
        self._initialized = False
    def __init__(self, *args):
        atexit.register(self.close)
    @property
    def devices(self):
        return list(self.iter_devices())
    cpdef open(self):
        """Initialize the PortAudio library and gather HostApi and Device info

        Note:
            This method is a no-op if called more than once.
        """
        if self._initialized:
            return
        self._initialized = True
        handle_error(Pa_Initialize())
        self._get_info()
    cpdef close(self):
        """Close all streams and terminates the PortAudio library

        Note:
            This method is a no-op if not open.
        """
        if not self._initialized:
            return
        self._initialized = False
        cdef DeviceInfo device
        try:
            for device in self.iter_devices():
                device.close()
        except:
            import traceback
            traceback.print_exc()
        self.host_apis_by_paindex.clear()
        self.host_apis_by_name.clear()
        self.devices_by_name.clear()
        self.devices_by_paindex.clear()
        handle_error(Pa_Terminate())
    def iter_devices(self):
        """Iterate over all devices as :class:`DeviceInfo` instances
        """
        cdef DeviceInfo device
        for device in self.devices_by_paindex.values():
            yield device
    cpdef DeviceInfo get_device_by_name(self, str name):
        """Get a device by name
        """
        return self.devices_by_name[name]
    cpdef DeviceInfo get_device_by_index(self, PaDeviceIndex idx):
        """Get a device by its PortAudio index
        """
        return self.devices_by_paindex[idx]
    cpdef HostApiInfo get_host_api_by_name(self, str name):
        """Get a HostApi by name
        """
        return self.host_apis_by_name[name]
    @property
    def host_api_count(self):
        cdef PaDeviceIndex pacount = Pa_GetHostApiCount()
        assert pacount >= 0
        cdef Py_ssize_t count = pacount
        return count
    @property
    def device_count(self):
        cdef PaDeviceIndex pacount = Pa_GetDeviceCount()
        assert pacount >= 0
        cdef Py_ssize_t count = pacount
        return count
    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void _get_info(self) except *:
        cdef Py_ssize_t device_count = self.device_count
        cdef Py_ssize_t host_api_count = self.host_api_count
        cdef PaDeviceIndex default_ix
        cdef Py_ssize_t i
        cdef HostApiInfo host_api
        cdef DeviceInfo device

        for i in range(host_api_count):
            if i in self.host_apis_by_paindex:
                continue
            host_api = HostApiInfo(i)
            self.host_apis_by_paindex[i] = host_api
            self.host_apis_by_name[host_api.name] = host_api
        for i in range(device_count):
            if i in self.devices_by_paindex:
                continue
            device = DeviceInfo(i)
            self.devices_by_paindex[i] = device
            self.devices_by_name[device.name] = device
            host_api = self.host_apis_by_paindex[device.host_api_index]
            host_api._add_device(device)
        default_ix = Pa_GetDefaultInputDevice()
        self.default_input = self.devices_by_paindex[default_ix]

        default_ix = Pa_GetDefaultOutputDevice()
        self.default_output = self.devices_by_paindex[default_ix]

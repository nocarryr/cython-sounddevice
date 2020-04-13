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
        self.active = False
    def __init__(self, *args):
        self._get_info()
    cdef void _get_info(self) except *:
        cdef const PaDeviceInfo* ptr = Pa_GetDeviceInfo(self.index)
        cdef bytes bname = ptr.name
        cdef str name = bname.decode('UTF-8')
        self.name = name
        self.host_api_index = ptr.hostApi
        self.num_inputs = ptr.maxInputChannels
        self.num_outputs = ptr.maxOutputChannels
        self.default_sample_rate = ptr.defaultSampleRate
    cpdef Stream _open_stream(self, dict kwargs):
        if self.active:
            return
        self.stream = Stream(self, **kwargs)
        self.active = True
        return self.stream
    def open_stream(self, **kwargs):
        return self._open_stream(kwargs)
    def close_stream(self):
        if self.stream is not None:
            self.stream.close()
            self.stream = None
        self.active = False
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
        self.devices_by_paindex = {}
        self.devices_by_name = {}
    def __init__(self, *args):
        self._get_info()
    @property
    def devices(self):
        return list(self.iter_devices())
    cpdef DeviceInfo get_device_by_name(self, str name):
        """Get a device by name
        """
        return self.devices_by_name[name]
    def iter_devices(self):
        """Iterate over all devices as :class:`DeviceInfo` instances
        """
        cdef DeviceInfo device
        cdef PaDeviceIndex ix
        for ix in sorted(self.devices_by_paindex.keys()):
            device = self.devices_by_paindex[ix]
            yield device
    cdef void _get_info(self) except *:
        cdef const PaHostApiInfo* ptr = Pa_GetHostApiInfo(self.index)
        cdef bytes bname = ptr.name
        cdef str name = bname.decode('UTF-8')
        self.name = name
        self.device_count = ptr.deviceCount
        self.default_input_index = ptr.defaultInputDevice
        self.default_output_index = ptr.defaultOutputDevice
    cdef void _add_device(self, DeviceInfo device) except *:
        if device.index in self.devices_by_paindex:
            return
        device.host_api = self
        self.devices_by_paindex[device.index] = device
        self.devices_by_name[device.name] = device
        if device.index == self.default_input_index:
            self.default_input = device
        elif device.index == self.default_output_index:
            self.default_output = device
    def __repr__(self):
        return '<{self.__class__.__name__}: {self}>'.format(self=self)
    def __str__(self):
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
    def host_apis(self):
        return list(self.iter_hostapis())
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
    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()
    def iter_hostapis(self):
        """Iterate over all HostApis as :class:`HostApiInfo` instances
        """
        cdef HostApiInfo host_api
        cdef PaHostApiIndex ix
        for ix in self.host_apis_by_paindex.keys():
            host_api = self.host_apis_by_paindex[ix]
            yield host_api
    def iter_devices(self):
        """Iterate over all devices as :class:`DeviceInfo` instances
        """
        cdef DeviceInfo device
        cdef PaDeviceIndex ix
        for ix in sorted(self.devices_by_paindex.keys()):
            device = self.devices_by_paindex[ix]
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
        if default_ix != paNoDevice:
            self.default_input = self.devices_by_paindex[default_ix]

        default_ix = Pa_GetDefaultOutputDevice()
        if default_ix != paNoDevice:
            self.default_output = self.devices_by_paindex[default_ix]

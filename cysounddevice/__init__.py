from . import types, devices, streams, buffer
PortAudio = devices.PortAudio

def get_include():
    import pkg_resources
    p = pkg_resources.resource_filename('_cysounddevice_data', 'include')
    return p

def get_dll_path():
    import pkg_resources
    p = pkg_resources.resource_filename('_cysounddevice_data', 'lib')
    return p

import sys
import os
from setuptools import setup, find_packages
from Cython.Build import cythonize
from Cython.Build.Dependencies import default_create_extension

try:
    import numpy
except ImportError:
    numpy = None

if numpy is None:
    INCLUDE_PATH = []
else:
    INCLUDE_PATH = [numpy.get_include()]

LIB_PATH = []

def build_pa_lib():
    from tools import build_portaudio
    lib_base = build_portaudio.main()
    INCLUDE_PATH.append(str(lib_base / 'include'))
    LIB_PATH.append(str(lib_base / 'lib'))

RTFD_BUILD = 'READTHEDOCS' in os.environ.keys()
if RTFD_BUILD:
    build_pa_lib()
    print('INCLUDE_PATH: ', INCLUDE_PATH)

USE_CYTHON_TRACE = False
if '--use-cython-trace' in sys.argv:
    USE_CYTHON_TRACE = True
    sys.argv.remove('--use-cython-trace')

COMPILE_TIME_ENV = {'CYSOUNDDEVICE_USE_JACK': 1}

USE_JACK_AUDIO = True
if '--no-jack' in sys.argv:
    USE_JACK_AUDIO = False
    sys.argv.remove('--no-jack')
    COMPILE_TIME_ENV['CYSOUNDDEVICE_USE_JACK'] = 0

def my_create_extension(template, kwds):
    name = kwds['name']
    if RTFD_BUILD:
        kwds['library_dirs'] = LIB_PATH
        kwds['include_dirs'] = INCLUDE_PATH
        kwds['runtime_library_dirs'] = LIB_PATH
        print(kwds)
    if USE_CYTHON_TRACE:
        kwds['define_macros'] = [('CYTHON_TRACE_NOGIL', '1'), ('CYTHON_TRACE', '1')]

    return default_create_extension(template, kwds)

ext_modules = cythonize(
    ['cysounddevice/**/*.pyx'],
    include_path=INCLUDE_PATH,
    annotate=True,
    # gdb_debug=True,
    compiler_directives={
        'linetrace':True,
        'embedsignature':True,
        'binding':True,
    },
    create_extension=my_create_extension,
    compile_time_env=COMPILE_TIME_ENV,
)

setup(
    ext_modules=ext_modules,
)

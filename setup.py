import sys
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

USE_CYTHON_TRACE = False
if '--use-cython-trace' in sys.argv:
    USE_CYTHON_TRACE = True
    sys.argv.remove('--use-cython-trace')

def my_create_extension(template, kwds):
    name = kwds['name']
    if USE_CYTHON_TRACE:
        # avoid using CYTHON_TRACE macro for stream_callback module
        if 'stream_callback' not in name:
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
)

setup(
    ext_modules=ext_modules,
)

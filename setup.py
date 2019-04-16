import sys
from setuptools import setup, find_packages
from Cython.Build import cythonize

try:
    import numpy
except ImportError:
    numpy = None

if numpy is None:
    INCLUDE_PATH = []
else:
    INCLUDE_PATH = [numpy.get_include()]

ext_modules = cythonize(
    ['cysounddevice/**/*.pyx'],
    include_path=INCLUDE_PATH,
    annotate=True,
    # gdb_debug=True,
    compiler_directives={
        'linetrace':True,
        'embedsignature':True,
    },
)

setup(
    packages=find_packages(exclude='test*'),
    ext_modules=ext_modules,
    include_package_data=True,
)

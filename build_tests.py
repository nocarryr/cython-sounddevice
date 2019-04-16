#! /usr/bin/env python
import os
import glob
import shlex
import subprocess
import numpy

ROOT_PATH = os.path.abspath(os.path.dirname(__file__))
TESTS_PATH = os.path.join(ROOT_PATH, 'tests')

INCLUDE_PATH = numpy.get_include()

CYTHONIZE_CMD = 'cythonize -b -i {opts} {pyx_file}'

COMPILER_DIRECTIVES = {
    'linetrace':True,
}

def build_opts():
    opts = []
    # opts.append(f'--option=include_path={INCLUDE_PATH}')
    for key, val in COMPILER_DIRECTIVES.items():
        opts.append(f'--directive={key}={val}')
    return ' '.join(opts)

def do_cythonize(pyx_file, opts=None):
    if opts is None:
        opts = build_opts()
    cmd_str = CYTHONIZE_CMD.format(opts=opts, pyx_file=pyx_file)
    print(cmd_str)
    r = subprocess.check_output(shlex.split(cmd_str))
    if isinstance(r, bytes):
        r = r.decode('UTF-8')
    print(r)

def main():
    pattern = os.path.join(TESTS_PATH, '*.pyx')
    opts = build_opts()
    for fn in glob.glob(pattern):
        do_cythonize(fn, opts)

if __name__ == '__main__':
    main()

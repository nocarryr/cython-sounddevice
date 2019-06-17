#! /usr/bin/env python3

import os
import sys
from pathlib import Path
import tempfile
import subprocess
import shlex
import shutil

EXEC_PREFIX = Path.home() / '.local'
EXEC_PREFIX.mkdir(exist_ok=True)
EXEC_PREFIX = EXEC_PREFIX.resolve()

def run_proc(cmdstr, show_output=False, show_stderr=True):
    if show_stderr:
        stderr = None
    else:
        stderr = subprocess.STDOUT
    p = subprocess.run(
        shlex.split(cmdstr),
        check=True,
        stdout=subprocess.PIPE,
        stderr=stderr,
        # universal_newlines=True,
    )
    if show_output:
        if isinstance(p.stdout, bytes):
            print(p.stdout.decode('UTF-8'))
        else:
            print(p.stdout)
    return p

class Chdir(object):
    def __init__(self, new_path):
        self.prev_path = None
        if not isinstance(new_path, Path):
            new_path = Path(new_path)
        self.new_path = new_path
    def __enter__(self):
        self.prev_path = Path.cwd()
        os.chdir(self.new_path)
        return self
    def __exit__(self, *args):
        os.chdir(self.prev_path)
    def __repr__(self):
        return f'Chdir: {self.prev_path} -> {self.new_path}'
    def __str__(self):
        return str(self.new_path)

class PaSource(object):
    TARBALL_URL = 'http://github.com/nocarryr/portaudio/archive/master.tar.gz'
    def __init__(self):
        self.tempdir = None
        self.base_path = None
        self.src_path = None
    def open(self):
        self.tempdir = tempfile.mkdtemp()
        self.base_path = Path(self.tempdir)
        self.get_tarball()
    def close(self):
        if self.tempdir is not None:
            if os.getcwd() == self.tempdir:
                os.chdir(Path.home())
            shutil.rmtree(self.tempdir)
            self.tempdir = None
    def get_tarball(self):
        with Chdir(self.base_path):
            run_proc(f'wget {self.TARBALL_URL}')
            tarball_fn = self.base_path / 'master.tar.gz'
            run_proc(f'tar -xvzf {tarball_fn}')
            self.src_path = self.base_path / 'portaudio-master'
            assert self.src_path.exists()
    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()

def main():
    src = PaSource()
    with src:
        with Chdir(src.src_path):
            p = run_proc(f'./configure --prefix={EXEC_PREFIX}', show_output=True)
            # print(p.stdout.decode('UTF-8'))
            p = run_proc('make')#, show_output=True)
            # print(p.stdout)
            p = run_proc('make install', show_output=True)
            # print(p.stdout)
            src_incl = src.src_path / 'include'
            dst_incl = EXEC_PREFIX / 'include'
            run_proc(f'ls -al {dst_incl}', show_output=True)
    return EXEC_PREFIX

if __name__ == '__main__':
    main()

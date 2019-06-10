import os
from pathlib import Path
import time
import subprocess
import shlex
import pytest

from cysounddevice import types
from cysounddevice import PortAudio

SAMPLE_RATES_ = (
    22050, 44100, 48000,# 88200, 96000,
    # 96000,
)

BLOCK_SIZES_ = (
    256, 512, 1024, 2048
)

SAMPLE_FORMATS_ = tuple(types.get_sample_formats().values())

@pytest.fixture
def SAMPLE_RATES():
    return SAMPLE_RATES_

@pytest.fixture
def BLOCK_SIZES():
    return BLOCK_SIZES_

@pytest.fixture(params=SAMPLE_RATES_)
def sample_rate(request):
    return request.param

@pytest.fixture(params=BLOCK_SIZES_)
def block_size(request):
    return request.param


@pytest.fixture
def SAMPLE_FORMATS():
    return SAMPLE_FORMATS_

@pytest.fixture(params=SAMPLE_FORMATS_)
def sample_format(request):
    sf = request.param
    # print(SAMPLE_FORMATS_)
    # print(sf)
    if isinstance(sf['name'], bytes):
        sf['name'] = sf['name'].decode('UTF-8')
    return sf

@pytest.fixture(params=[1,2,4,8])
def nchannels(request):
    return request.param

@pytest.fixture(scope='session')
def _worker_id(request):
    if hasattr(request.config, "workerinput"):
        return request.config.workerinput["workerid"]
    elif hasattr(request.config, 'slaveinput'):
        return request.config.slaveinput['slaveid']
    else:
        return "master"

@pytest.fixture
def port_audio(jackd_server, _worker_id):
    pa = PortAudio()
    with pa:
        yield pa
    time.sleep(.1)
    assert not pa._initialized

class JackDServer(object):
    def __init__(self, server_name):
        self.server_name = server_name
        self.proc = None
    def _jack_wait(self, timeout=None, for_quit=False):
        if timeout is None:
            opt_str = '--check'
        else:
            opt_str = f'--wait --timeout {timeout}'
        cmdstr = f'jack_wait --server {self.server_name} {opt_str}'
        try:
            resp = subprocess.check_output(shlex.split(cmdstr))
        except subprocess.CalledProcessError as e:
            if timeout is not None:
                raise
            return False
        if isinstance(resp, bytes):
            resp = resp.decode('UTF-8')
        return 'server is available' in resp
    def is_running(self):
        return self._jack_wait()
    def wait_for_start(self):
        num_waits = 0
        while num_waits < 5:
            try:
                r = self._jack_wait(2)
            except subprocess.CalledProcessError:
                r = False
            if r:
                return True
            num_waits += 1
        return False
    def wait_for_stop(self):
        timeout = 2
        cmdstr = f'jack_wait --server {self.server_name} --quit --timeout {timeout}'
        num_waits = 0
        while num_waits < 5:
            try:
                resp = subprocess.check_output(shlex.split(cmdstr))
            except subprocess.CalledProcessError as e:
                num_waits += 1
                continue
            if isinstance(resp, bytes):
                resp = resp.decode('UTF-8')
            if 'server is gone' in resp:
                return True
        return False
    def start(self):
        if self.is_running():
            if self.proc is not None:
                return
            self.wait_for_stop()
        cmdstr = f'jackd --no-realtime -n{self.server_name} -ddummy -r48000 -p1024'
        self.proc = subprocess.Popen(shlex.split(cmdstr))
        running = self.wait_for_start()
        assert running is True
    def stop(self):
        p = self.proc
        if p is None:
            return
        self.proc = None
        p.terminate()
        p.wait()
        if self.is_running():
            self.wait_for_stop()
    def __enter__(self):
        try:
            self.start()
        except:
            self.stop()
            raise
        return self
    def __exit__(self, *args):
        self.stop()
    def __repr__(self):
        return f'<{self.__class__}: "{self}">'
    def __str__(self):
        return self.server_name

@pytest.fixture
def jackd_server(request, monkeypatch, _worker_id):
    test_mod = request.node.name.split('[')[0]
    test_name = request.node.name.split('[')[1].rstrip(']')
    server_name = f'{test_mod}.{test_name}_{_worker_id}'

    server = JackDServer(server_name)
    with server:
        monkeypatch.setenv('JACK_DEFAULT_SERVER', server_name)
        monkeypatch.setenv('JACK_NO_START_SERVER', '1')
        yield server.server_name

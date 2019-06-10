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

class PaFileLock:
    max_wait = 300
    file_fields = ('ppid', 'pid', 'worker_id')
    def __init__(self, worker_id):
        self.worker_id = worker_id
        self.pid = os.getpid()
        self.ppid = os.getppid()
        self.uid = '\t'.join([str(getattr(self, attr)) for attr in self.file_fields])
    @property
    def pid_file(self):
        base_dir = Path('.').joinpath('pytest-workers-pid')
        base_dir.mkdir(exist_ok=True)
        p = base_dir.joinpath('PaLock.pid')
        return p.resolve()
    def read_file(self):
        p = self.pid_file
        s = p.read_text()
        return s
    def write_file(self):
        p = self.pid_file
        p.write_text(self.uid)
    def check_proc_exists(self, pid):
        cmd_str = f'ps -q {pid} --no-headers'
        try:
            s = subprocess.check_output(shlex.split(cmd_str))
        except subprocess.CalledProcessError as exc:
            if exc.returncode == 1 and not len(exc.output):
                return False
            raise
        return len(s) > 0
    # def _check_dead_proc(self):
    #     dead = False
    #     s = self.read_file()
    #     ppid, pid = [int(v) for v in s.split('\t')[:2]]
    #     if self.check_proc_exists(pid):
    #         return
    #     print('removing dead pid_file')
    #     self.pid_file.unlink()
    def _acquire(self):
        p = self.pid_file
        if p.exists():
            s = self.read_file()
            if s == self.uid:
                return True
            # else:
            #     self._check_dead_proc()
            return False
        else:
            try:
                p.touch(exist_ok=False)
            except FileExistsError:
                return False
            self.write_file()
            return True
    def _release(self):
        p = self.pid_file
        if not p.exists():
            return
        if self.read_file() == self.uid:
            p.unlink()
    def acquire(self):
        start_ts = time.time()
        end_ts = start_ts + self.max_wait
        while True:
            r = self._acquire()
            if r:
                return True
            if time.time() >= end_ts:
                raise Exception('PaFileLock timeout')
            time.sleep(.1)
        return False
    def release(self):
        self._release()
    def __enter__(self):
        r = self.acquire()
        assert r is True
        return self
    def __exit__(self, *args):
        self.release()

@pytest.fixture
def port_audio(_worker_id):
    pa_lock = PaFileLock(_worker_id)
    pa = None
    with pa_lock:
        pa = PortAudio()
        print('openning PortAudio')
        with pa:
            yield pa
            print('closing PortAudio')
        time.sleep(.1)
        assert not pa._initialized

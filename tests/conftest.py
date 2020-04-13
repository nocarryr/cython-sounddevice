import os
import time
from pathlib import Path
from contextlib import contextmanager
import tempfile
import shutil
import pytest

from cysounddevice import types
from cysounddevice import PortAudio

from launch_jackd_servers import Servers


JACK_SERVER_NAME = 'pytest'
os.environ['JACK_DEFAULT_SERVER'] = JACK_SERVER_NAME
os.environ['JACK_NO_START_SERVER'] = '1'

SAMPLE_RATES_ = (
    22050, 44100, 48000,# 88200, 96000,
    # 96000,
)

JACK_SAMPLE_RATES = (
    44100, 48000,
)

BLOCK_SIZES_ = (
    256, 512, 1024, 2048
)

SAMPLE_FORMATS_ = tuple(types.get_sample_formats().values())
for sf in SAMPLE_FORMATS_:
    if isinstance(sf['name'], bytes):
        sf['name'] = sf['name'].decode('UTF-8')

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

@pytest.fixture(params=JACK_SAMPLE_RATES)
def jack_sample_rate(request):
    return request.param

@pytest.fixture
def SAMPLE_FORMATS():
    return SAMPLE_FORMATS_

@pytest.fixture(params=SAMPLE_FORMATS_)
def sample_format(request):
    sf = request.param
    # print(SAMPLE_FORMATS_)
    # print(sf)
    return sf

@pytest.fixture(params=[1,2,4,8])
def nchannels(request):
    return request.param


@pytest.fixture()
def port_audio(jackd_server, worker_id):

    @contextmanager
    def run_pa(sample_rate, block_size):
        with jackd_server(sample_rate, block_size) as server_name:
            pa = PortAudio()
            pa.set_jack_client_name(worker_id)
            with pa:
                yield pa
                print('EXITING PORTAUDIO')
            assert not pa._initialized
            time.sleep(1)
            print('COMPLETE')

    return run_pa

JACKD_SERVERS = None
JACKD_LOG_ROOT = None

@pytest.mark.tryfirst
def pytest_sessionstart(session):
    """Hook to start all jackd servers at the beginning of the test session
    """
    global JACKD_SERVERS, JACKD_LOG_ROOT

    # avoid launching servers for every slave (pytest-xdist)
    workerinput = getattr(session.config, 'workerinput', None)
    if workerinput is None:
        JACKD_LOG_ROOT = Path(tempfile.mkdtemp())
        JACKD_SERVERS = Servers(JACK_SAMPLE_RATES, BLOCK_SIZES_, JACKD_LOG_ROOT)
        JACKD_SERVERS.open()

@pytest.mark.trylast
def pytest_sessionfinish(session, exitstatus):
    """Shut down the jackd servers at the end of the session
    """
    workerinput = getattr(session.config, 'workerinput', None)
    if workerinput is None:
        JACKD_SERVERS.close()
        if exitstatus == 0:
            shutil.rmtree(str(JACKD_LOG_ROOT))


@pytest.fixture()
def jackd_server(request, monkeypatch, tmpdir, worker_id):

    @contextmanager
    def run_server(sample_rate, block_size):
        server_name = f'pytest-{sample_rate}-{block_size}'
        monkeypatch.setenv('JACK_DEFAULT_SERVER', server_name)
        monkeypatch.setenv('JACK_NO_START_SERVER', '1')
        yield server_name

    return run_server

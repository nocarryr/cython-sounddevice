import os
import time
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


@pytest.fixture
def port_audio():
    pa = PortAudio()
    with pa:
        yield pa
        print('EXITING PORTAUDIO')
    assert not pa._initialized
    time.sleep(1)
    print('COMPLETE')

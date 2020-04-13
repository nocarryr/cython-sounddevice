import time
import warnings
import numpy as np

from cysounddevice.types import SampleTime
from cysounddevice.utils import PortAudioError

DURATION = 2

class Generator:
    def __init__(self, stream, play_duration):
        block_size = stream.frames_per_buffer
        start_time = SampleTime(0, 0, block_size, stream.stream_info.sample_rate)
        self.center_freq = 1000.0

        self.stream = stream
        self.start_time = start_time
        self.current_time = start_time.copy()

        end_time = start_time.copy()
        while end_time.pa_time < play_duration:
            end_time.block += 1
        self.end_time = end_time
        self.play_duration = end_time.pa_time
        print('start_time={}, end_time={}'.format(start_time, end_time))

        stream.stream_info.input_channels = 0
        nchannels = stream.stream_info.output_channels
        nblocks = end_time.block + 1
        self.nchannels = nchannels
        self.nblocks = nblocks
        self.complete = False
    def run(self):
        st_info = self.stream.stream_info
        assert not self.stream.active
        assert st_info.output_channels > 0
        assert self.stream.check() == 0

        r = False

        start_ts = time.time()
        end_ts = start_ts + self.play_duration + 2

        with self.stream:
            print('stream opened')
            while not self.complete:
                if not self.stream.active:
                    raise Exception('stream aborted')
                r = self.fill_buffer()
                if self.complete:
                    print('playback complete')
                    break
                if time.time() >= end_ts:
                    print('playback timeout')
                    break
                if not r:
                    time.sleep(.1)
            print('closing stream')
        print('stream closed')

    def fill_buffer(self):
        bfr = self.stream.output_buffer
        if not bfr.ready():
            return False
        data = self.generate()
        r = bfr.write_output_sf32(data)
        if not r:
            return False
        self.current_time.block += 1

        if self.current_time >= self.end_time:
            self.complete = True
            return False
        return True

    def generate(self):
        block_size = self.stream.frames_per_buffer
        fs = self.stream.sample_rate
        data = np.zeros((self.nchannels, block_size), dtype='float32')

        t = np.arange(block_size) / fs
        t += self.current_time.rel_time
        sig = np.sin(2*np.pi*t*self.center_freq)
        for i in range(self.nchannels):
            data[i,:] = sig
        return data


def test_playback(port_audio, sample_rate, sample_format, block_size):
    print(f'fs={sample_rate}, sample_format={sample_format} block_size={block_size}')
    hostapi = port_audio.get_host_api_by_name('JACK Audio Connection Kit')
    device = hostapi.devices[0]
    stream_kw = dict(
        sample_rate=sample_rate,
        block_size=block_size,
        sample_format=sample_format['name'],
        output_channels=2,
    )
    stream = device.open_stream(**stream_kw)
    try:
        stream.check()
    except PortAudioError as exc:
        if exc.error_msg == 'Invalid sample rate':
            warnings.warn(f'Invalid sample rate ({sample_rate})')
            return
    gen = Generator(stream, DURATION)
    gen.run()
    assert gen.complete
    device.close_stream()

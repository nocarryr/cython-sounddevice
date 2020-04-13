import time
import warnings
import numpy as np
from scipy.io import wavfile

from cysounddevice.types import SampleTime
from cysounddevice.utils import PortAudioError

RECORD_DURATION = 3

BLOCK_DATA_DTYPE = np.dtype([
    ('block', np.int),
    ('block_index', np.int),
    ('sample_index', np.int),
    ('pa_time', np.float64),
    ('rel_time', np.float64),
    ('time_offset', np.float64),
])

class Recorder:
    def __init__(self, stream, record_duration):
        block_size = stream.frames_per_buffer
        start_time = SampleTime(0, 0, block_size, stream.sample_rate)

        self.stream = stream
        self.start_time = start_time
        self.current_time = start_time.copy()

        end_time = start_time.copy()
        while end_time.pa_time < record_duration:
            end_time.block += 1
        self.end_time = end_time
        self.record_duration = end_time.pa_time
        print(f'start_time={start_time}, end_time={end_time}')

        stream.stream_info.output_channels = 0
        nchannels = stream.stream_info.input_channels
        nblocks = end_time.block + 1
        data = np.zeros(
            (nchannels, nblocks, block_size), dtype=np.float32,
        )
        self.sample_data = data
        self.block_data = np.zeros(nblocks, dtype=BLOCK_DATA_DTYPE)
        self.complete = False
    # @staticmethod
    # cpdef Recorder from_npz(str filename, SAMPLE_RATE_t sample_rate):
    #     data = np.load(filename)
    #     cdef np.ndarray[FLOAT32_DTYPE_t, ndim=3] sample_data = data['sample_data']
    #     cdef np.ndarray[BLOCK_DATA_DTYPE_t, ndim=1] block_data = data['block_data']

    def record(self):
        st_info = self.stream.stream_info
        assert not self.stream.active
        assert st_info.input_channels > 0
        assert self.stream.check() == 0

        r = False

        start_ts = time.time()
        end_ts = start_ts + self.record_duration + 2
        # times = np.zeros(self.sample_data.shape[1], dtype=np.float64)
        # cdef list times = []
        # i = 0
        # prev_ts = start_ts

        # times.append(time.time())
        with self.stream:
            print('STREAM OPENED')
            while not self.complete:
                if not self.stream.active:
                    raise Exception('stream aborted')
                r = self.gather_samples()
                cur_ts = time.time()
                # if r:
                #     times[i] = cur_ts - prev_ts
                #     times.append(cur_ts - prev_ts)
                #     if i > 0:
                #         times[i] = time.time() - times[-1]
                #         # times.append(time.time() - times[len(times)-1])
                #     else:
                #         times[i] = time.time() - start_ts
                #         # times.append(time.time() - start_ts)
                #     prev_ts = cur_ts
                #     i += 1
                if self.complete:
                    print('record complete')
                    break
                if cur_ts > end_ts:
                    raise Exception('record timeout')
                if not r:
                    # print('sleeping: i={}'.format(i))
                    time.sleep(.1)
        print('STREAM CLOSED')
        # _times = np.array(times)
        # _times = times.copy()
        # print('avg_time={}, max={}, min={}'.format(np.mean(_times), _times.max(), _times.min()))
        # return _times

    def gather_samples(self):
        if self.complete:
            return False
        # cdef CallbackUserData* user_data = self.stream.callback_handler.user_data
        # cdef SampleBuffer* bfr = user_data.in_buffer
        bfr = self.stream.input_buffer
        if not bfr.ready():
            return False
        cur_blk = self.current_time.block
        block_size = self.stream.frames_per_buffer
        assert block_size == self.start_time.block_size
        nchannels = self.stream.input_channels

        # cdef FLOAT32_DTYPE_t[:,:] blk_data = self.data[:,cur_blk]
        data = np.empty((nchannels, block_size), dtype=np.float32)
        # cdef SampleTime read_time

        read_time = bfr.read_into(data)
        assert read_time is not None
        # cdef SampleTime_s* rtime = &read_time.data
        # assert read_time.block == cur_blk
        # self._set_block_data(self.block_data[cur_blk], &read_time.data)
        bd = self.block_data
        bd['block'][cur_blk] = read_time.block
        bd['block_index'][cur_blk] = read_time.block_index
        bd['sample_index'][cur_blk] = read_time.sample_index
        bd['pa_time'][cur_blk] = read_time.pa_time
        bd['rel_time'][cur_blk] = read_time.rel_time
        bd['time_offset'][cur_blk] = read_time.time_offset
        for i in range(nchannels):
            self.sample_data[i,cur_blk,:] = data[i,:]

        # cdef np.ndarray ff
        #
        # for i in range(nchannels):
        #     ff = np.fft.rfft(data[i,:])

        self.current_time.block += 1

        if self.current_time >= self.end_time:
            self.complete = True
            return False
        return True
    # cdef void _set_block_data(self, BLOCK_DATA_DTYPE_t data, SampleTime_s* sample_time) except *:
    #     data.block = sample_time.block
    #     data.block_index = sample_time.block_index
    #     data.pa_time = sample_time.pa_time
    #     data.rel_time = sample_time.rel_time
    #     data.time_offset = sample_time.time_offset
    def save(self, filename):
        np.savez(filename, sample_data=self.sample_data, block_data=self.block_data)
    def to_wav(self, filename):
        recorded_to_wav(filename, self.start_time.sample_rate, self.sample_data)

def recorded_to_wav(filename, sample_rate, sample_data):
    # cdef np.ndarray[FLOAT32_DTYPE_t, ndim=3] all_data = self.sample_data
    nchannels = sample_data.shape[0]
    nsamples = sample_data.shape[1] * sample_data.shape[2]
    data = np.empty((nchannels, nsamples), dtype=np.float32)
    # cdef FLOAT32_DTYPE_t[:] flat_data

    for i in range(nchannels):
        # flat_data = all_data[i,...].reshape(nsamples)
        # data[i,:] = flat_data
        data[i,:] = sample_data[i,...].reshape(nsamples)
    wavfile.write(filename, int(sample_rate), data.T)


def test_record(port_audio, block_size, sample_format, sample_rate):
    # sample_rate = 44100
    # block_size = 512
    hostapi = port_audio.get_host_api_by_name('JACK Audio Connection Kit')
    device = hostapi.devices[0]
    stream_kw = dict(
        sample_rate=sample_rate,
        frames_per_buffer=block_size,
        sample_format=sample_format['name'],
        input_channels=2,
    )
    stream = device.open_stream(**stream_kw)
    try:
        stream.check()
    except PortAudioError as exc:
        if exc.error_msg == 'Invalid sample rate':
            warnings.warn(f'Invalid sample rate ({sample_rate})')
            return
    # assert stream.frames_per_buffer == block_size
    rec = Recorder(stream, RECORD_DURATION)
    rec.record()
    assert rec.complete

    ix = np.flatnonzero(np.greater(rec.block_data['pa_time'], 0))
    block_data = rec.block_data[ix]
    assert block_data.size >= rec.end_time.block - 1

    expected_sample_index = np.arange(rec.block_data.size) * block_size
    expected_sample_index = expected_sample_index[ix]
    _bad_samp_ix = np.flatnonzero(np.not_equal(block_data['sample_index'], expected_sample_index))
    bad_blocks = np.unique(_bad_samp_ix)
    # if bad_blocks.size > 0:
    #     samp_ix_diff = expected_sample_index - block_data['sample_index']
    #     print(samp_ix_diff)
    assert bad_blocks.size == 0

import os
import sys
import time
import argparse
import subprocess
import queue
import shlex
import threading
import signal
import warnings
from pathlib import Path
import tempfile
import typing as tp
from multiprocessing import Process, Pipe
from multiprocessing.connection import Connection
from dataclasses import dataclass


@dataclass()
class Message:
    status: str = 'unknown'

@dataclass()
class ErrorMessage(Message):
    status: str = 'error'
    err: str = ''

@dataclass()
class ReadyMessage(Message):
    status: str = 'ready'
    pid: int = -1

@dataclass()
class StoppedMessage(Message):
    status: str = 'stopped'

@dataclass()
class StopMessage(Message):
    status: str = 'stop'

class ConnectionWrapper(object):
    """Wrapper for :class:`multiprocessing.connection.Connection`
    with an interface similar to :class:`queue.Queue`
    """
    def __init__(self, connection: Connection):
        self.conn = connection
    def get(self, timeout: tp.Optional[float] = None) -> Message:
        if timeout is None:
            return self.recv()
        ready = self.poll(timeout)
        if not ready:
            raise queue.Empty()
        return self.recv()
    def send(self, msg: Message):
        self.conn.send(msg)
    def recv(self) -> Message:
        return self.conn.recv()
    def poll(self, timeout: tp.Optional[float] = None) -> bool:
        return self.conn.poll(timeout)


class LogPair(object):
    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.stdout_path = base_dir / 'stdout.log'
        self.stderr_path = base_dir / 'stderr.log'
        self.stdout = None
        self.stderr = None
    def __enter__(self):
        self.stdout = self.stdout_path.open('w')
        try:
            self.stderr = self.stderr_path.open('w')
        except:
            self.stdout_path.close()
            self.stdout = None
            raise
        return self
    def __exit__(self, *args):
        try:
            self.stdout.close()
        finally:
            self.stderr.close()
        self.stdout = None
        self.stderr = None

class ProcLogger(threading.Thread):
    def __init__(self, proc: subprocess.Popen, log_file: Path):
        super().__init__()
        self.log_file = log_file
        self.proc = proc
        self.running = threading.Event()
        self.stopped = threading.Event()
        self.read_queue = queue.Queue()
        self.daemon = True

    def run(self):
        proc = self.proc
        log_file = self.log_file
        self.running.set()
        with log_file.open('w') as fd:
            while self.running.is_set():
                line = proc.stdout.readline().strip()
                if not line and proc.poll() is not None:
                    break
                self.read_queue.put(line)
                if '\n' not in line:
                    line = f'{line}\n'
                fd.write(line)
        self.stopped.set()

    def stop(self):
        self.running.clear()
        self.stopped.wait()

class JackD(Process):
    """multiprocessing.Process subclass to manage a jackd subprocess
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args)

        self.conn = kwargs['conn']
        if isinstance(self.conn, Connection):
            self.conn = ConnectionWrapper(self.conn)
        self.sample_rate = kwargs['sample_rate']
        self.block_size = kwargs['block_size']
        self.log_root = kwargs['log_root']
        self.server_name = f'pytest-{self.sample_rate}-{self.block_size}'
        self.__id = self.server_name
        self.log_dir = self.log_root / self.server_name
        self._proc = None
        self._log_thread = None
        self.error = None
        self._is_open = False

    @property
    def id(self) -> str:
        return self.__id

    def open_subproc(self):
        if self._is_open:
            return

        assert not self._is_open
        assert self._proc is None
        assert self._log_thread is None
        cmdstr = f'jackd -n{self.server_name} -ddummy -r{self.sample_rate} -p{self.block_size}'
        self._proc = subprocess.Popen(
            shlex.split(cmdstr),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        self._log_thread = ProcLogger(self._proc, self.log_dir)
        self._log_thread.start()
        self._is_open = True

    def _wait_for_startup(self):
        """
        - iterate through jackd stdout
          - if a failure is detected, send an error message to the parent
          - if no input for 1 second, assume everything is good
        """
        q = self._log_thread.read_queue
        while True:
            try:
                line = q.get(timeout=1)
            except queue.Empty:
                return True
            if 'Failed to open' in line:
                self.conn.send(ErrorMessage(msg=line))
                return False
            q.task_done()

    def close_subproc(self):
        if not self._is_open:
            return

        assert self._is_open
        assert self._proc is not None
        self._proc.terminate()
        self._proc = None
        self._log_thread.stop()
        self._log_thread = None
        self._is_open = False

    def run(self):
        """
        - start the jackd process
          - send a ready message with the pid to the parent
        - wait for a "stop" message
          - stop jackd
          - send a response message
        """
        self.open_subproc()
        self._wait_for_startup()
        self.conn.send(ReadyMessage(pid=self._proc.pid))

        while self._is_open:
            try:
                msg = self.conn.recv()
            except EOFError:
                break
            if isinstance(msg, StopMessage):
                break

        self.close_subproc()
        self.conn.send(StoppedMessage())

    def __repr__(self):
        s = super().__repr__()
        return f'{s} - "{self.server_name}"'
    def __str__(self):
        return self.server_name


class Servers(object):
    """Manage multiple :class:`JackD` processes
    """
    def __init__(self, sample_rates: tp.Sequence[int], block_sizes: tp.Sequence[int], log_root: Path):
        self.sample_rates = sample_rates
        self.block_sizes = block_sizes
        self.log_root = log_root
        self._lock = threading.Lock()
        self.servers = {}
        self.connections = {}
        self.server_pids = {}
        self.pids = {}
        self.build_servers()

    @property
    def server_names(self) -> tp.List[str]:
        return list(self.servers.keys())

    def build_servers(self):
        with self._lock:
            assert not len(self.servers)
            assert not len(self.connections)

            for fs in self.sample_rates:
                for bs in self.block_sizes:
                    parent_conn, child_conn = Pipe()
                    server = JackD(conn=child_conn, sample_rate=fs, block_size=bs, log_root=self.log_root)
                    self.servers[server.id] = server
                    self.connections[server.id] = ConnectionWrapper(parent_conn)

    def __iter__(self) -> tp.Iterator[JackD]:
        yield from self.servers.values()

    def __len__(self):
        return len(self.servers)

    def keys(self) -> tp.Iterator[str]:
        yield from self.servers.keys()

    def iter_pairs(self) -> tp.Iterator[tp.Tuple[JackD, Connection]]:
        for server in self:
            key = server.id
            conn = self.connections[key]
            yield server, conn

    def open(self):
        errors = {}
        with self._lock:
            for server, conn in self.iter_pairs():
                print(f'starting {server}')
                server.start()

            waiting = set(self.keys())
            while len(waiting):
                for key in waiting.copy():
                    conn = self.connections[key]
                    try:
                        msg = conn.get(.1)
                    except queue.Empty:
                        continue

                    if isinstance(msg, ReadyMessage):
                        pid = msg.pid
                        if pid != -1:
                            self.server_pids[key] = pid
                        print(f'{key} started (pid={pid})')
                    else:
                        errors[key] = msg
                        warnings.warn(f'{key} not ready -> "{errors[key]}"', RuntimeWarning)
                    waiting.discard(key)

        if len(errors):
            self.close()

    def close(self):
        errors = {}
        with self._lock:
            for server, conn in self.iter_pairs():
                print(f'closing {server}')
                conn.send(StopMessage())

                try:
                    msg = conn.get(5)
                except queue.Empty:
                    errors[server.id] = (server, 'no response')
                    continue

                if isinstance(msg, StoppedMessage):
                    server.join()
                    print(f'{server} closed')
                else:
                    errors[server.id] = (server, msg)

            for key, err in errors.items():
                server, msg = err
                warnings.warn(f'Error when stopping server {server}. response: "{msg}"', RuntimeWarning)
                pid = self.server_pids.get(server.id)
                if pid is not None:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                server.terminate()

            self.servers.clear()
            self.connections.clear()
            self.server_pids.clear()

    def __enter__(self):
        self.open()
        return self
    def __exit__(self, *args):
        self.close()


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    p = argparse.ArgumentParser()
    p.add_argument('--sample-rates', dest='sample_rates', nargs='*', type=int)
    p.add_argument('--block-sizes', dest='block_sizes', nargs='*', type=int)
    p.add_argument('--log-root', dest='log_root')
    args = p.parse_args(argv)
    if args.log_root is None:
        args.log_root = tempfile.mkdtemp()
    args.log_root = Path(args.log_root)

    print(f'log_root={args.log_root}')

    servers = Servers(args.sample_rates, args.block_sizes, args.log_root)
    print(f'server names: {servers.server_names}')

    servers.open()
    i = 0
    try:
        while True:
            time.sleep(1)
            i += 1
            if i > 10:
                servers.close()
                break
    except KeyboardInterrupt:
        servers.close()
    finally:
        servers.kill()

if __name__ == '__main__':
    main()

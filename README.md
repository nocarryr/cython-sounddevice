# cython-sounddevice

## Description
Python bindings for the [PortAudio] library to
interface with audio streams.  This project was inspired by [python-sounddevice](https://github.com/spatialaudio/python-sounddevice/), but uses [Cython] instead of
[CFFI](http://cffi.readthedocs.io/).

This allows for use in other Cython projects needing audio I/O without the
performance penalty of the switching between Python and C/C++ contexts.
All of the necessary classes, functions and data types have shared declarations
for this purpose.

## Links

* Documentation
  * https://cython-sounddevice.readthedocs.io/en/latest/
* Source Code
  * https://github.com/nocarryr/cython-soundevice

## Usage

*TODO*

## Dependencies

* [Cython] >= 0.29.1
* [PortAudio]

## Installation

*TODO*

### Linux

`sudo apt-get install portaudio19-dev`

### Windows

*TODO*

### MacOS

*TODO*

## License

See the [LICENSE](LICENSE) file for license information (GPLv3).

[PortAudio]: http://www.portaudio.com/
[Cython]: https://cython.org/

cysounddevice.types module
==========================

.. automodule:: cysounddevice.types

SampleTime class
----------------

.. autoclass:: cysounddevice.types.SampleTime
    :members:

C-API
-----

.. highlightlang:: c

.. c:type:: SampleFormat

    .. c:member:: PaSampleFormat pa_ident

    .. c:member:: Py_ssize_t bit_width

    .. c:member:: bint is_signed

    .. c:member:: bint is_float

    .. c:member:: bint is_24bit

    .. c:member:: void\* dtype_ptr

.. c:type:: SampleTime_s

    .. c:member:: PaTime pa_time

        Time in seconds

    .. c:member:: PaTime time_offset

        Time offset in seconds

    .. c:member:: SAMPLE_RATE_t sample_rate

        Sample rate

    .. c:member:: Py_ssize_t block_size

        Number of samples per block

    .. c:member:: BLOCK_t block

        Block count

    .. c:member:: Py_ssize_t block_index

        Index within the block

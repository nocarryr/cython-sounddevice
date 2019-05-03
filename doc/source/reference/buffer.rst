cysounddevice.buffer module
===========================

.. automodule:: cysounddevice.buffer

StreamBuffer class
------------------

.. autoclass:: cysounddevice.buffer.StreamBuffer
    :members:
    :member-order: groupwise

StreamInputBuffer class
-----------------------

.. autoclass:: cysounddevice.buffer.StreamInputBuffer
    :members:
    :member-order: groupwise

StreamOutputBuffer class
------------------------

.. autoclass:: cysounddevice.buffer.StreamOutputBuffer
    :members:
    :member-order: groupwise


C-API
-----

.. highlightlang:: c

.. c:type:: SampleBuffer

    A buffering structure with preallocated memory for use in
    :any:`_stream_callback`

    .. c:member:: BufferItem \*items

        Buffer array of :c:type:`BufferItem`

    .. c:member:: Py_ssize_t length

        Number of :c:member:`items` to allocate

    .. c:member:: Py_ssize_t itemsize

        Size in bytes per sample

    .. c:member:: Py_ssize_t item_length

        Number of samples to allocate for each :c:type:`BufferItem` (block size)

    .. c:member:: Py_ssize_t nchannels

        Number of channels

    .. c:member:: Py_ssize_t write_index

        Index of the next item to use for writing

    .. c:member:: Py_ssize_t read_index

        Index of the next item to use for reading

    .. c:member:: BLOCK_t current_block

        The current block of samples

    .. c:member:: int read_available

        Number of items available to read from

    .. c:member:: int write_available

        Number of items available to write to

.. c:type:: BufferItem

    A single item used to store data for :c:type:`SampleBuffer`

    .. c:member:: SampleTime_s start_time

        The time of the first sample in the item's buffer, as reported by PortAudio

    .. c:member:: Py_ssize_t index

        Index of the item within its parent :c:type:`SampleBuffer`

    .. c:member:: Py_ssize_t length

        Number of samples the item contains

    .. c:member:: Py_ssize_t itemsize

        Size in bytes per sample

    .. c:member:: Py_ssize_t nchannels

        Number of channels

    .. c:member:: Py_ssize_t total_size

        The total size in bytes to allocate `` length * itemsize * nchannels ``

    .. c:member:: char \*bfr

        Pointer to the preallocated buffer




.. c:function:: SampleBuffer* sample_buffer_create(SampleTime_s start_time, \
                                                   Py_ssize_t length, \
                                                   Py_ssize_t nchannels, \
                                                   Py_ssize_t itemsize)

    Creates a :c:type:`SampleBuffer` and child items (:c:type:`BufferItem`),
    allocating all required char buffers.

.. c:function:: void sample_buffer_destroy(SampleBuffer* bfr)

    Deallocates the given :c:type:`SampleBuffer` and all of its child items.

.. c:function:: int sample_buffer_write(SampleBuffer* bfr, const void *data, Py_ssize_t length)

    Copy the given data to the next available item in the given :c:type:`SampleBuffer`.
    If no items are available to write (the buffer is full), no data is copied.

    Returns 1 if successful

.. c:function:: SampleTime_s* sample_buffer_read(SampleBuffer* bfr, char *data, Py_ssize_t length)

    Copy data from the next available item into the given buffer.

    Returns:
        A :c:type:`SampleTime_s` pointer to the :c:member:`BufferItem.start_time`
        describing the source timing of the data.
        If no data is available, returns ``NULL``.

.. c:function:: SampleTime_s* sample_buffer_read_sf32(SampleBuffer* bfr, float[:,:] data)

    Copy stream data from a :c:type:`SampleBuffer` into a ``float`` array

    Deinterleaves the stream and casts it to 32-bit float. A typed memoryview
    may be used.

    The sample format must be :any:`paFloat32`.

    Returns:
        A :c:type:`SampleTime_s` pointer to the :c:member:`BufferItem.start_time`
        describing the source timing of the data.
        If no data is available, returns ``NULL``.

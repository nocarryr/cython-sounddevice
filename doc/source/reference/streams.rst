cysounddevice.streams module
============================

.. automodule:: cysounddevice.streams

Stream class
------------

.. autoclass:: cysounddevice.streams.Stream
    :members:

StreamInfo class
----------------

.. autoclass:: cysounddevice.streams.StreamInfo
    :members:

StreamCallback class
--------------------

.. autoclass:: cysounddevice.streams.StreamCallback
    :members:

C-API
-----

.. highlightlang:: c

.. c:type:: CallbackUserData

    Container for data used in :c:func:`_stream_callback`

    .. c:member:: int input_channels

        Number of input channels

    .. c:member:: int output_channels

        Number of output channels

    .. c:member:: SampleBuffer* in_buffer

        Pointer to a :c:type:`SampleBuffer` to write input data to

    .. c:member:: SampleBuffer* out_buffer

        Pointer to a :c:type:`SampleBuffer` to read output data from

.. c:function:: int _stream_callback(const void* in_bfr, \
                                     void* out_bfr, \
                                     unsigned long frame_count, \
                                     const PaStreamCallbackTimeInfo* time_info, \
                                     PaStreamCallbackFlags status_flags, \
                                     void* user_data)

    Callback function that reads and writes input/output data using the
    :c:type:`SampleBuffer` pointers stored in user_data as :c:type:`CallbackUserData`

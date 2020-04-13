# cython: language_level=3
# distutils: libraries = portaudio

ctypedef bint bool
from libc.stdint cimport *

cdef enum PaSampleFormat_enum:
    paFloat32        = 0x00000001
    paInt32          = 0x00000002
    paInt24          = 0x00000004
    paInt16          = 0x00000008
    paInt8           = 0x00000010
    paUInt8          = 0x00000020
    paCustomFormat   = 0x00010000
    paNonInterleaved = 0x80000000

cdef extern from "portaudio.h":
    int Pa_GetVersion()
    const char* Pa_GetVersionText()
    ctypedef int PaError
    ctypedef enum PaErrorCode:
        paNoError = 0
        paNotInitialized = -10000
        paUnanticipatedHostError
        paInvalidChannelCount
        paInvalidSampleRate
        paInvalidDevice
        paInvalidFlag
        paSampleFormatNotSupported
        paBadIODeviceCombination
        paInsufficientMemory
        paBufferTooBig
        paBufferTooSmall
        paNullCallback
        paBadStreamPtr
        paTimedOut
        paInternalError
        paDeviceUnavailable
        paIncompatibleHostApiSpecificStreamInfo
        paStreamIsStopped
        paStreamIsNotStopped
        paInputOverflowed
        paOutputUnderflowed
        paHostApiNotFound
        paInvalidHostApi
        paCanNotReadFromACallbackStream
        paCanNotWriteToACallbackStream
        paCanNotReadFromAnOutputOnlyStream
        paCanNotWriteToAnInputOnlyStream
        paIncompatibleStreamHostApi
        paBadBufferPtr
    const char* Pa_GetErrorText( PaError errorCode )
    PaError Pa_Initialize()
    PaError Pa_Terminate()
    ctypedef int PaDeviceIndex
    #define paNoDevice -1
    #define paUseHostApiSpecificDeviceSpecification -2
    cdef PaDeviceIndex paNoDevice = -1
    ctypedef int PaHostApiIndex
    PaHostApiIndex Pa_GetHostApiCount()
    PaHostApiIndex Pa_GetDefaultHostApi()
    ctypedef enum PaHostApiTypeId:
        paInDevelopment=0
        paDirectSound=1
        paMME=2
        paASIO=3
        paSoundManager=4
        paCoreAudio=5
        paOSS=7
        paALSA=8
        paAL=9
        paBeOS=10
        paWDMKS=11
        paJACK=12
        paWASAPI=13
        paAudioScienceHPI=14
    cdef struct PaHostApiInfo:
        int structVersion
        PaHostApiTypeId type
        const char* name
        int deviceCount
        PaDeviceIndex defaultInputDevice
        PaDeviceIndex defaultOutputDevice
    const PaHostApiInfo* Pa_GetHostApiInfo( PaHostApiIndex hostApi )
    PaHostApiIndex Pa_HostApiTypeIdToHostApiIndex( PaHostApiTypeId type )
    PaDeviceIndex Pa_HostApiDeviceIndexToDeviceIndex( PaHostApiIndex hostApi,
            int hostApiDeviceIndex )
    cdef struct PaHostErrorInfo:
        PaHostApiTypeId hostApiType
        long errorCode
        const char* errorText
    const PaHostErrorInfo* Pa_GetLastHostErrorInfo()
    PaDeviceIndex Pa_GetDeviceCount()
    PaDeviceIndex Pa_GetDefaultInputDevice()
    PaDeviceIndex Pa_GetDefaultOutputDevice()
    ctypedef double PaTime
    ctypedef unsigned long PaSampleFormat
    #define paFloat32        0x00000001
    #define paInt32          0x00000002
    #define paInt24          0x00000004
    #define paInt16          0x00000008
    #define paInt8           0x00000010
    #define paUInt8          0x00000020
    #define paCustomFormat   0x00010000
    #define paNonInterleaved 0x80000000

    cdef struct PaDeviceInfo:
        int structVersion
        const char* name
        PaHostApiIndex hostApi
        int maxInputChannels
        int maxOutputChannels
        PaTime defaultLowInputLatency
        PaTime defaultLowOutputLatency
        PaTime defaultHighInputLatency
        PaTime defaultHighOutputLatency
        double defaultSampleRate

    const PaDeviceInfo* Pa_GetDeviceInfo( PaDeviceIndex device )
    cdef struct PaStreamParameters:
        PaDeviceIndex device
        int channelCount
        PaSampleFormat sampleFormat
        PaTime suggestedLatency
        void* hostApiSpecificStreamInfo
    #define paFormatIsSupported 0
    PaError Pa_IsFormatSupported( const PaStreamParameters* inputParameters,
                                  const PaStreamParameters* outputParameters,
                                  double sampleRate )
    ctypedef void PaStream
    #define paFramesPerBufferUnspecified 0
    ctypedef unsigned long PaStreamFlags
    #define   paNoFlag         0
    #define   paClipOff        0x00000001
    #define   paDitherOff      0x00000002
    #define   paNeverDropInput 0x00000004
    #define   paPrimeOutputBuffersUsingStreamCallback 0x00000008
    #define   paPlatformSpecificFlags 0xFFFF0000
    cdef struct PaStreamCallbackTimeInfo:
        PaTime inputBufferAdcTime
        PaTime currentTime
        PaTime outputBufferDacTime
    ctypedef unsigned long PaStreamCallbackFlags
    #define paInputUnderflow  0x00000001
    #define paInputOverflow   0x00000002
    #define paOutputUnderflow 0x00000004
    #define paOutputOverflow  0x00000008
    #define paPrimingOutput   0x00000010
    ctypedef enum PaStreamCallbackResult:
        paContinue=0
        paComplete=1
        paAbort=2
    ctypedef int PaStreamCallback(
        const void* input, void* output,
        unsigned long frameCount,
        const PaStreamCallbackTimeInfo* timeInfo,
        PaStreamCallbackFlags statusFlags,
        void* userData )
    PaError Pa_OpenStream( PaStream** stream,
                           const PaStreamParameters* inputParameters,
                           const PaStreamParameters* outputParameters,
                           double sampleRate,
                           unsigned long framesPerBuffer,
                           PaStreamFlags streamFlags,
                           PaStreamCallback* streamCallback,
                           void* userData )
    PaError Pa_OpenDefaultStream( PaStream** stream,
                                  int numInputChannels,
                                  int numOutputChannels,
                                  PaSampleFormat sampleFormat,
                                  double sampleRate,
                                  unsigned long framesPerBuffer,
                                  PaStreamCallback* streamCallback,
                                  void* userData )
    PaError Pa_CloseStream( PaStream* stream )
    ctypedef void PaStreamFinishedCallback( void* userData )
    PaError Pa_SetStreamFinishedCallback( PaStream* stream,
        PaStreamFinishedCallback* streamFinishedCallback )
    PaError Pa_StartStream( PaStream* stream )
    PaError Pa_StopStream( PaStream* stream )
    PaError Pa_AbortStream( PaStream* stream )
    PaError Pa_IsStreamStopped( PaStream* stream )
    PaError Pa_IsStreamActive( PaStream* stream )
    cdef struct PaStreamInfo:
        int structVersion
        PaTime inputLatency
        PaTime outputLatency
        double sampleRate
    const PaStreamInfo* Pa_GetStreamInfo( PaStream* stream )
    PaTime Pa_GetStreamTime( PaStream* stream )
    double Pa_GetStreamCpuLoad( PaStream* stream )
    PaError Pa_ReadStream( PaStream* stream,
                           void* buffer,
                           unsigned long frames )
    PaError Pa_WriteStream( PaStream* stream,
                            const void* buffer,
                            unsigned long frames )
    signed long Pa_GetStreamReadAvailable( PaStream* stream )
    signed long Pa_GetStreamWriteAvailable( PaStream* stream )
    PaHostApiTypeId Pa_GetStreamHostApiType( PaStream* stream )
    PaError Pa_GetSampleSize( PaSampleFormat format )
    void Pa_Sleep( long msec )

cdef extern from "pa_jack.h":
    PaError PaJack_SetClientName( const char* name )
    PaError PaJack_GetClientName(const char** clientName)

IF UNAME_SYSNAME == "Darwin":
    cdef extern from "pa_mac_core.h":
        ctypedef int32_t SInt32
        ctypedef struct PaMacCoreStreamInfo:
            unsigned long size
            PaHostApiTypeId hostApiType
            unsigned long version
            unsigned long flags
            const SInt32 * channelMap
            unsigned long channelMapSize
        void PaMacCore_SetupStreamInfo( PaMacCoreStreamInfo *data, unsigned long flags )
        void PaMacCore_SetupChannelMap( PaMacCoreStreamInfo *data, const SInt32 * const channelMap, unsigned long channelMapSize )
        const char *PaMacCore_GetChannelName( int device, int channelIndex, bool input )
        #define paMacCoreChangeDeviceParameters 0x01
        #define paMacCoreFailIfConversionRequired 0x02
        #define paMacCoreConversionQualityMin    0x0100
        #define paMacCoreConversionQualityMedium 0x0200
        #define paMacCoreConversionQualityLow    0x0300
        #define paMacCoreConversionQualityHigh   0x0400
        #define paMacCoreConversionQualityMax    0x0000
        #define paMacCorePlayNice                    0x00
        #define paMacCorePro                         0x01
        #define paMacCoreMinimizeCPUButPlayNice      0x0100
        #define paMacCoreMinimizeCPU                 0x0101
ELIF UNAME_SYSNAME == "Windows":

    cdef extern from "pa_win_waveformat.h":
        ctypedef unsigned long PaWinWaveFormatChannelMask

    cdef extern from "pa_win_wasapi.h":

        ctypedef enum PaWasapiFlags:
            paWinWasapiExclusive                = 1
            paWinWasapiRedirectHostProcessor    = 2
            paWinWasapiUseChannelMask           = 4
            paWinWasapiPolling                  = 8
            paWinWasapiThreadPriority           = 16

        ctypedef void (*PaWasapiHostProcessorCallback) (
            void *inputBuffer,  long inputFrames,
            void *outputBuffer, long outputFrames, void *userData)

        ctypedef enum PaWasapiThreadPriority:
            eThreadPriorityNone = 0
            eThreadPriorityAudio
            eThreadPriorityCapture
            eThreadPriorityDistribution
            eThreadPriorityGames
            eThreadPriorityPlayback
            eThreadPriorityProAudio
            eThreadPriorityWindowManager

        ctypedef enum PaWasapiStreamCategory:
            eAudioCategoryOther           = 0
            eAudioCategoryCommunications  = 3
            eAudioCategoryAlerts          = 4
            eAudioCategorySoundEffects    = 5
            eAudioCategoryGameEffects     = 6
            eAudioCategoryGameMedia       = 7
            eAudioCategoryGameChat        = 8
            eAudioCategorySpeech          = 9
            eAudioCategoryMovie           = 10
            eAudioCategoryMedia           = 11

        ctypedef enum PaWasapiStreamOption:
            eStreamOptionNone        = 0
            eStreamOptionRaw         = 1
            eStreamOptionMatchFormat = 2

        cdef struct PaWasapiStreamInfo:
            unsigned long size
            PaHostApiTypeId hostApiType
            unsigned long version
            unsigned long flags
            PaWinWaveFormatChannelMask channelMask
            PaWasapiHostProcessorCallback hostProcessorOutput
            PaWasapiHostProcessorCallback hostProcessorInput
            PaWasapiThreadPriority threadPriority
            PaWasapiStreamCategory streamCategory
            PaWasapiStreamOption streamOption

    cdef extern from "pa_asio.h":
        #define paAsioUseChannelSelectors 0x01

        cdef struct PaAsioStreamInfo:
            unsigned long size
            PaHostApiTypeId hostApiType
            unsigned long version
            unsigned long flags
            int *channelSelectors

ELIF UNAME_SYSNAME == "Linux":

    cdef extern from "pa_linux_alsa.h":
        cdef struct PaAlsaStreamInfo:
            unsigned long size
            PaHostApiTypeId hostApiType
            unsigned long version

            const char* deviceString
        void PaAlsa_InitializeStreamInfo( PaAlsaStreamInfo* info )
        void PaAlsa_EnableRealtimeScheduling( PaStream* s, int enable )
        PaError PaAlsa_GetStreamInputCard( PaStream* s, int* card )
        PaError PaAlsa_GetStreamOutputCard( PaStream* s, int* card )
        PaError PaAlsa_SetNumPeriods( int numPeriods )
        PaError PaAlsa_SetRetriesBusy( int retries )
        void PaAlsa_SetLibraryPathName( const char* pathName )

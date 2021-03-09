/// WebSockets Shared Process Classes and Definitions
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.ws.core;

{
  *****************************************************************************

   WebSockets Abstract Processing for Client and Server
   - WebSockets Frames Definitions
   - WebSockets Protocols Implementation
   - WebSockets Client and Server Shared Process
   
  *****************************************************************************

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode, // for efficient UTF-8 text process within HTTP
  mormot.core.text,
  mormot.core.data,
  mormot.core.log,
  mormot.core.threads,
  mormot.core.rtti,
  mormot.core.json,
  mormot.core.buffers,
  mormot.core.crypto,
  mormot.core.ecc,
  mormot.core.secure, // IProtocol definition
  mormot.net.sock,
  mormot.net.http;


{ ******************** WebSockets Frames Definitions }

type
  /// Exception raised when processing WebSockets
  EWebSockets = class(ESynException);

  /// defines the interpretation of the WebSockets frame data
  // - match order expected by the WebSockets RFC
  TWebSocketFrameOpCode = (
    focContinuation,
    focText,
    focBinary,
    focReserved3,
    focReserved4,
    focReserved5,
    focReserved6,
    focReserved7,
    focConnectionClose,
    focPing,
    focPong,
    focReservedB,
    focReservedC,
    focReservedD,
    focReservedE,
    focReservedF);

  /// set of WebSockets frame interpretation
  TWebSocketFrameOpCodes = set of TWebSocketFrameOpCode;

  /// define one attribute of a WebSockets frame data
  TWebSocketFramePayload = (
    fopAlreadyCompressed);
  /// define the attributes of a WebSockets frame data

  TWebSocketFramePayloads = set of TWebSocketFramePayload;

  /// stores a WebSockets frame
  // - see @http://tools.ietf.org/html/rfc6455 for reference
  TWebSocketFrame = record
    /// the interpretation of the frame data
    opcode: TWebSocketFrameOpCode;
    /// what is stored in the frame data, i.e. in payload field
    content: TWebSocketFramePayloads;
    /// equals GetTickCount64 shr 10, as used for TWebSocketFrameList timeout
    tix: cardinal;
    /// the frame data itself
    // - is plain UTF-8 for focText kind of frame
    // - is raw binary for focBinary or any other frames
    payload: RawByteString;
  end;

  /// points to a WebSockets frame
  PWebSocketFrame = ^TWebSocketFrame;

  /// a dynamic list of WebSockets frames
  TWebSocketFrameDynArray = array of TWebSocketFrame;


const
  FRAME_OPCODE_FIN = 128;
  FRAME_LEN_MASK = 128;
  FRAME_LEN_2BYTES = 126;
  FRAME_LEN_8BYTES = 127;


/// used to return the text corresponding to a specified WebSockets frame type
function ToText(opcode: TWebSocketFrameOpCode): PShortString; overload;


/// low-level intitialization of a TWebSocketFrame for proper REST content
procedure FrameInit(opcode: TWebSocketFrameOpCode;
  const Content, ContentType: RawByteString; out frame: TWebSocketFrame);

/// compute the SHA-1 signature of the given challenge
procedure ComputeChallenge(const Base64: RawByteString; out Digest: TSha1Digest);



{ ******************** WebSockets Protocols Implementation }

type
  {$M+}
  TWebSocketProcess = class;
  {$M-}

  /// used by TWebSocketProcessSettings for WebSockets process logging settings
  TWebSocketProcessSettingsLogDetails = set of (
    logHeartbeat,
    logTextFrameContent,
    logBinaryFrameContent);

  /// parameters to be used for WebSockets processing
  // - those settings are used by all protocols running on a given
  // TWebSocketServer or a THttpClientWebSockets
  {$ifdef USERECORDWITHMETHODS}
  TWebSocketProcessSettings = record
  {$else}
  TWebSocketProcessSettings = object
  {$endif USERECORDWITHMETHODS}
  public
    /// time in milli seconds between each focPing commands sent to the other end
    // - default is 0, i.e. no automatic ping sending on client side, and
    // 20000, i.e. 20 seconds, on server side
    HeartbeatDelay: cardinal;
    /// maximum period time in milli seconds when ProcessLoop thread will stay
    // idle before checking for the next pending requests
    // - default is 500 ms, but you may put a lower value, if you expects e.g.
    // REST commands or NotifyCallback(wscNonBlockWithoutAnswer) to be processed
    // with a lower delay
    LoopDelay: cardinal;
    /// ms between sending - allow to gather output frames
    // - GetTickCount resolution is around 16ms under Windows, so default 10ms
    // seems fine for a cross-platform similar behavior
    SendDelay: cardinal;
    /// will close the connection after a given number of invalid Heartbeat sent
    // - when a Hearbeat is failed to be transmitted, the class will start
    // counting how many ping/pong did fail: when this property value is
    // reached, it will release and close the connection
    // - default value is 5
    DisconnectAfterInvalidHeartbeatCount: cardinal;
    /// how many milliseconds the callback notification should wait acquiring
    // the connection before failing
    // - defaut is 5000, i.e. 5 seconds
    CallbackAcquireTimeOutMS: cardinal;
    /// how many milliseconds the callback notification should wait for the
    // client to return its answer
    // - defaut is 30000, i.e. 30 seconds
    CallbackAnswerTimeOutMS: cardinal;
    /// callback run when a WebSockets client is just connected
    // - triggerred by TWebSocketProcess.ProcessStart
    OnClientConnected: TNotifyEvent;
    /// callback run when a WebSockets client is just disconnected
    // - triggerred by TWebSocketProcess.ProcessStop
    OnClientDisconnected: TNotifyEvent;
    /// if the WebSockets Client should be upgraded after socket reconnection
    ClientAutoUpgrade: boolean;
    /// by default, contains [] to minimize the logged information
    // - set logHeartbeat if you want the ping/pong frames to be logged
    // - set logTextFrameContent if you want the text frame content to be logged
    // - set logBinaryFrameContent if you want the binary frame content to be logged
    // - used only if WebSocketLog global variable is set to a TSynLog class
    LogDetails: TWebSocketProcessSettingsLogDetails;
    /// TWebSocketProtocol.SetEncryptKey PBKDF2-SHA-3 salt for TProtocolAes
    // - default is some fixed value - you may customize it for a project
    AesSalt: RawUtf8;
    /// TWebSocketProtocol.SetEncryptKey PBKDF2-SHA-3 rounds for TProtocolAes
    // - default is 1024 which takes around 0.5 ms to compute
    // - 0 would use Sha256Weak() derivation function, as mORMot 1.18
    AesRounds: integer;
    /// TWebSocketProtocol.SetEncryptKey AES class for TProtocolAes
    // - default is TAesFast[mCtr]
    AesCipher: TAesAbstractClass;
    /// TWebSocketProtocol.SetEncryptKey AES key size in bits, for TProtocolAes
    // - default is 128 for efficient 'aes-128-ctr' at 2.5GB/s
    // - for mORMot 1.18 compatibility, set for your custom settings:
    // $ AesClass := TAesCfb;
    // $ AesBits := 256;
    // $ AesRounds := 0; // Sha256Weak() deprecated function
    AesBits: integer;
    /// TWebSocketProtocol.SetEncryptKey 'password#xxxxxx.private' ECDHE algo
    // - default is efAesCtr128 as set to TEcdheProtocol.FromPasswordSecureFile
    EcdheCipher: TEcdheEF;
    /// TWebSocketProtocol.SetEncryptKey 'password#xxxxxx.private' ECDHE auth
    // - default is the safest authMutual
    EcdheAuth: TEcdheAuth;
    /// TWebSocketProtocol.SetEncryptKey 'password#xxxxxx.private' password rounds
    // - default is 60000, i.e. DEFAULT_ECCROUNDS
    EcdheRounds: integer;
    /// will set the default values
    procedure SetDefaults;
    /// will set LogDetails to its highest level of verbosity
    // - used only if WebSocketLog global variable is set
    procedure SetFullLog;
  end;

  /// points to parameters to be used for WebSockets process
  // - using a pointer/reference type will allow in-place modification of
  // any TWebSocketProcess.Settings, TWebSocketServer.Settings or
  // THttpClientWebSockets.Settings property
  PWebSocketProcessSettings = ^TWebSocketProcessSettings;

  /// callback event triggered by TWebSocketProtocol for any incoming message
  // - called before TWebSocketProtocol.ProcessIncomingFrame for incoming
  // focText/focBinary frames
  // - should return true if the frame has been handled, or false if the
  // regular processing should take place
  TOnWebSocketProtocolIncomingFrame = function(Sender: TWebSocketProcess;
    var Frame: TWebSocketFrame): boolean of object;

  /// one instance implementing application-level WebSockets protocol
  // - shared by TWebSocketServer and TWebSocketClient classes
  // - once upgraded to WebSockets, a HTTP link could be used e.g. to transmit our
  // proprietary 'synopsejson' or 'synopsebin' application content, as stated
  // by this typical handshake:
  // $ GET /myservice HTTP/1.1
  // $ Host: server.example.com
  // $ Upgrade: websocket
  // $ Connection: Upgrade
  // $ Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==
  // $ Sec-WebSocket-Protocol: synopsejson
  // $ Sec-WebSocket-Version: 13
  // $ Origin: http://example.com
  // $
  // $ HTTP/1.1 101 Switching Protocols
  // $ Upgrade: websocket
  // $ Connection: Upgrade
  // $ Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
  // $ Sec-WebSocket-Protocol: synopsejson
  // - the TWebSocketProtocolJson inherited class will implement
  // $ Sec-WebSocket-Protocol: synopsejson
  // - the TWebSocketProtocolBinary inherited class will implement
  // $ Sec-WebSocket-Protocol: synopsebin
  TWebSocketProtocol = class(TSynPersistent)
  protected
    fName: RawUtf8;
    fUri: RawUtf8;
    fFramesInCount: integer;
    fFramesOutCount: integer;
    fFramesInBytes: QWord;
    fFramesOutBytes: QWord;
    fOnBeforeIncomingFrame: TOnWebSocketProtocolIncomingFrame;
    fRemoteLocalhost: boolean;
    fConnectionFlags: THttpServerRequestFlags;
    fRemoteIP: RawUtf8;
    fUpgradeUri: RawUtf8;
    fLastError: string;
    fEncryption: IProtocol;
    // focText/focBinary or focContinuation/focConnectionClose from ProcessStart/ProcessStop
    procedure ProcessIncomingFrame(Sender: TWebSocketProcess;
      var request: TWebSocketFrame; const info: RawUtf8); virtual; abstract;
    function SendFrames(Owner: TWebSocketProcess;
      var Frames: TWebSocketFrameDynArray; var FramesCount: integer): boolean; virtual;
    procedure AfterGetFrame(var frame: TWebSocketFrame); virtual;
    procedure BeforeSendFrame(var frame: TWebSocketFrame); virtual;
    function FrameData(const frame: TWebSocketFrame; const Head: RawUtf8;
      HeadFound: PRawUtf8 = nil): pointer; virtual;
    function FrameType(const frame: TWebSocketFrame): RawUtf8; virtual;
    function GetRemoteIP: RawUtf8;
    function GetEncrypted: boolean;
      {$ifdef HASINLINE}inline;{$endif}
  public
    /// abstract constructor to initialize the protocol
    // - the protocol should be named, so that the client may be able to request
    // for a given protocol
    // - if aUri is '', any URI would potentially upgrade to this protocol; you can
    // specify an URI to limit the protocol upgrade to a single resource
    constructor Create(const aName, aUri: RawUtf8); reintroduce;
    /// compute a new instance of the WebSockets protocol, with same parameters
    function Clone(const aClientUri: RawUtf8): TWebSocketProtocol; virtual; abstract;
    /// returns Name by default, but could be e.g. 'synopsebin, synopsebinary'
    function GetSubprotocols: RawUtf8; virtual;
    /// specify the recognized sub-protocols, e.g. 'synopsebin, synopsebinary'
    function SetSubprotocol(const aProtocolName: RawUtf8): boolean; virtual;
    /// create the internal Encryption: IProtocol according to the supplied key
    // - any asymmetric algorithm needs to know its side, i.e. client or server
    // - use aKey='password#xxxxxx.private' for efAesCtr128 calling
    // TEcdheProtocol.FromPasswordSecureFile() - FromKeySetCA() should have been
    // called to set the global PKI
    // - use aKey='a=mutual;e=aesctc128;p=34a2;pw=password;ca=..' full
    // TEcdheProtocol.FromKey(aKey) format
    // - or aKey will be derivated using aSettings to call
    // SetEncryptKeyAes - default as 1024 PBKDF2-SHA-3 rounds into aes-128-ctr
    // - you can disable encryption by setting aKey=''
    procedure SetEncryptKey(aServer: boolean; const aKey: RawUtf8;
      aSettings: PWebSocketProcessSettings);
    /// set the fEncryption: IProtocol from TProtocolAes.Create()
    // - if aClass is nil, TAesFast[mCtr] will be used as default
    // - AEAD Cfc,mOfc,mCtc,mGcm modes will be rejected since unsupported
    procedure SetEncryptKeyAes(aCipher: TAesAbstractClass;
      const aKey; aKeySize: cardinal);
    /// set the fEncryption: IProtocol from TEcdheProtocol.Create()
    // - as default, we use efAesCtr128 which is the fastest on x86_64 (2.5GB/s)
    procedure SetEncryptKeyEcdhe(aAuth: TEcdheAuth; aPKI: TEccCertificateChain;
      aPrivate: TEccCertificateSecret; aServer: boolean;
      aEF: TEcdheEF = efAesCtr128; aPrivateOwned: boolean = false);
    /// redirect to Encryption.ProcessHandshake, if defined
    function ProcessHandshake(const ExtIn: TRawUtf8DynArray;
      out ExtOut: RawUtf8; ErrorMsg: PRawUtf8): boolean; virtual;
    /// called e.g. for authentication during the WebSockets handshake
    function ProcessHandshakeUri(const aClientUri: RawUtf8): boolean; virtual;
    /// allow low-level interception before ProcessIncomingFrame is done
    property OnBeforeIncomingFrame: TOnWebSocketProtocolIncomingFrame
      read fOnBeforeIncomingFrame write fOnBeforeIncomingFrame;
    /// access low-level frame encryption
    property Encryption: IProtocol
      read fEncryption;
    /// contains either [hsrSecured, hsrWebsockets] or [hsrWebsockets]
    property ConnectionFlags: THttpServerRequestFlags
      read fConnectionFlags;
    /// if the associated 'Remote-IP' HTTP header value maps the local host
    property RemoteLocalhost: boolean
      read fRemoteLocalhost write fRemoteLocalhost;
  published
    /// the Sec-WebSocket-Protocol application name currently involved
    // - e.g. 'synopsejson', 'synopsebin' or 'synopsebinary'
    property Name: RawUtf8
      read fName write fName;
    /// the optional URI on which this protocol would be enabled
    // - leave to '' if any URI should match
    property URI: RawUtf8
      read fUri;
    /// the associated 'Remote-IP' HTTP header value
    // - returns '' if self=nil or RemoteLocalhost=true
    property RemoteIP: RawUtf8
      read GetRemoteIP write fRemoteIP;
    /// the URI on which this protocol has been upgraded
    property UpgradeUri: RawUtf8
      read fUpgradeUri write fUpgradeUri;
    /// the last error message, during frame processing
    property LastError: string
      read fLastError;
    /// returns TRUE if encryption is enabled during the transmission
    // - is currently only available for TWebSocketProtocolBinary
    property Encrypted: boolean
      read GetEncrypted;
    /// how many frames have been received by this instance
    property FramesInCount: integer
      read fFramesInCount;
    /// how many frames have been sent by this instance
    property FramesOutCount: integer
      read fFramesOutCount;
    /// how many (uncompressed) bytes have been received by this instance
    property FramesInBytes: QWord
      read fFramesInBytes;
    /// how many (uncompressed) bytes have been sent by this instance
    property FramesOutBytes: QWord
      read fFramesOutBytes;
  end;


  /// handle a REST application-level bi-directional WebSockets protocol
  // - will emulate a bi-directional REST process, using THttpServerRequest to
  // store and handle the request parameters: clients would be able to send
  // regular REST requests to the server, but the server could use the same
  // communication channel to push REST requests to the client
  // - a local THttpServerRequest will be used on both client and server sides,
  // to store REST parameters and compute the corresponding WebSockets frames
  TWebSocketProtocolRest = class(TWebSocketProtocol)
  protected
    fSequencing: boolean;
    fSequence: integer;
    procedure ProcessIncomingFrame(Sender: TWebSocketProcess;
       var request: TWebSocketFrame; const info: RawUtf8); override;
    procedure FrameCompress(const Head: RawUtf8; const Values: array of const;
      const Content, ContentType: RawByteString; var frame: TWebSocketFrame);
        virtual; abstract;
    function FrameDecompress(const frame: TWebSocketFrame;
      const Head: RawUtf8; const values: array of PRawByteString;
      var contentType, content: RawByteString): boolean; virtual; abstract;
    /// convert the input information of REST request to a WebSocket frame
    procedure InputToFrame(Ctxt: THttpServerRequestAbstract; aNoAnswer: boolean;
      out request: TWebSocketFrame; out head: RawUtf8); virtual;
    /// convert a WebSocket frame to the input information of a REST request
    function FrameToInput(var request: TWebSocketFrame; out aNoAnswer: boolean;
      Ctxt: THttpServerRequestAbstract): boolean; virtual;
    /// convert a WebSocket frame to the output information of a REST request
    function FrameToOutput(var answer: TWebSocketFrame;
      Ctxt: THttpServerRequestAbstract): cardinal; virtual;
    /// convert the output information of REST request to a WebSocket frame
    procedure OutputToFrame(Ctxt: THttpServerRequestAbstract; Status: cardinal;
      var outhead: RawUtf8; out answer: TWebSocketFrame); virtual;
  end;

  /// used to store the class of a TWebSocketProtocol type
  TWebSocketProtocolClass = class of TWebSocketProtocol;

  /// handle a REST application-level WebSockets protocol using JSON for transmission
  // - could be used e.g. for AJAX or non Delphi remote access
  // - this class will implement then following application-level protocol:
  // $ Sec-WebSocket-Protocol: synopsejson
  TWebSocketProtocolJson = class(TWebSocketProtocolRest)
  protected
    procedure FrameCompress(const Head: RawUtf8; const Values: array of const;
      const Content, ContentType: RawByteString; var frame: TWebSocketFrame); override;
    function FrameDecompress(const frame: TWebSocketFrame; const Head: RawUtf8;
      const values: array of PRawByteString;
      var contentType, content: RawByteString): boolean; override;
    function FrameData(const frame: TWebSocketFrame; const Head: RawUtf8;
      HeadFound: PRawUtf8 = nil): pointer; override;
    function FrameType(const frame: TWebSocketFrame): RawUtf8; override;
  public
    /// initialize the WebSockets JSON protocol
    // - if aUri is '', any URI would potentially upgrade to this protocol; you can
    // specify an URI to limit the protocol upgrade to a single resource
    constructor Create(const aUri: RawUtf8); reintroduce;
    /// compute a new instance of the WebSockets protocol, with same parameters
    function Clone(const aClientUri: RawUtf8): TWebSocketProtocol; override;
  end;

  /// tune the 'synopsebin' protocol
  // - pboCompress will compress all frames payload using SynLZ
  // - pboNoLocalHostCompress won't compress frames on the loopback (127.0.0.1)
  // - pboNoLocalHostEncrypt won't encrypt frames on the loopback (127.0.0.1)
  TWebSocketProtocolBinaryOption = (
    pboSynLzCompress,
    pboNoLocalHostCompress,
    pboNoLocalHostEncrypt);

  /// how TWebSocketProtocolBinary implements the 'synopsebin' protocol
  // - should match on both client and server ends
  TWebSocketProtocolBinaryOptions = set of TWebSocketProtocolBinaryOption;


  /// handle a REST application-level WebSockets protocol using compressed and
  // optionally AES-CTR encrypted binary
  // - this class will implement then following application-level protocol:
  // $ Sec-WebSocket-Protocol: synopsebin
  // or fallback to the previous subprotocol
  // $ Sec-WebSocket-Protocol: synopsebinary
  // - 'synopsebin' will expect requests sequenced as 'r000001','r000002',...
  // headers matching 'a000001','a000002',... instead of 'request'/'answer'
  TWebSocketProtocolBinary = class(TWebSocketProtocolRest)
  protected
    fFramesInBytesSocket: QWord;
    fFramesOutBytesSocket: QWord;
    fOptions: TWebSocketProtocolBinaryOptions;
    procedure FrameCompress(const Head: RawUtf8;
      const Values: array of const; const Content, ContentType: RawByteString;
      var frame: TWebSocketFrame); override;
    function FrameDecompress(const frame: TWebSocketFrame;
      const Head: RawUtf8; const values: array of PRawByteString;
      var contentType, content: RawByteString): boolean; override;
    procedure AfterGetFrame(var frame: TWebSocketFrame); override;
    procedure BeforeSendFrame(var frame: TWebSocketFrame); override;
    function FrameData(const frame: TWebSocketFrame; const Head: RawUtf8;
      HeadFound: PRawUtf8 = nil): pointer; override;
    function FrameType(const frame: TWebSocketFrame): RawUtf8; override;
    function SendFrames(Owner: TWebSocketProcess;
      var Frames: TWebSocketFrameDynArray;
      var FramesCount: integer): boolean; override;
    procedure ProcessIncomingFrame(Sender: TWebSocketProcess;
      var request: TWebSocketFrame; const info: RawUtf8); override;
    function GetFramesInCompression: integer;
    function GetFramesOutCompression: integer;
  public
    /// initialize the WebSockets binary protocol with no encryption
    // - if aUri is '', any URI would potentially upgrade to this protocol; you
    // can specify an URI to limit the protocol upgrade to a single resource
    // - SynLZ compression is enabled by default, for all frames
    constructor Create(const aUri: RawUtf8;
      aOptions: TWebSocketProtocolBinaryOptions = [pboSynLzCompress]);
      reintroduce; overload; virtual;
    /// initialize the WebSockets binary protocol with a symmetric AES key
    // - if aUri is '', any URI would potentially upgrade to this protocol; you
    // can specify an URI to limit the protocol upgrade to a single resource
    // - if aKeySize if 128, 192 or 256, TProtocolAes (i.e. AES-CTR encryption)
    //  will be used to secure the transmission
    // - SynLZ compression is enabled by default, before encryption
    constructor Create(const aUri: RawUtf8; const aKey; aKeySize: cardinal;
      aOptions: TWebSocketProtocolBinaryOptions = [pboSynLzCompress];
      aCipher: TAesAbstractClass = nil);
        reintroduce; overload;
    /// initialize the WebSockets binary protocol from a textual key
    // - if aUri is '', any URI would potentially upgrade to this protocol; you
    // can specify an URI to limit the protocol upgrade to a single resource
    // - will create a TProtocolAes or TEcdheProtocol instance, corresponding to
    // the supplied aKey and aServer values, to secure the transmission using
    // a symmetric or assymetric algorithm
    // - SynLZ compression is enabled by default, unless aCompressed is false
    constructor Create(const aUri: RawUtf8; aServer: boolean;
      const aKey: RawUtf8; aSettings: PWebSocketProcessSettings;
      aOptions: TWebSocketProtocolBinaryOptions = [pboSynLzCompress]);
        reintroduce; overload;
    /// compute a new instance of the WebSockets protocol, with same parameters
    function Clone(const aClientUri: RawUtf8): TWebSocketProtocol; override;
    /// returns Name by default, but could be e.g. 'synopsebin, synopsebinary'
    function GetSubprotocols: RawUtf8; override;
    /// specify the recognized sub-protocols, e.g. 'synopsebin, synopsebinary'
    function SetSubprotocol(const aProtocolName: RawUtf8): boolean; override;
  published
    /// how compression / encryption is implemented during the transmission
    // - is set to [pboSynLzCompress] by default
    property Options: TWebSocketProtocolBinaryOptions
      read fOptions write fOptions;
    /// how many bytes have been received by this instance from the wire
    property FramesInBytesSocket: QWord
      read fFramesInBytesSocket;
    /// how many bytes have been sent by this instance to the wire
    property FramesOutBytesSocket: QWord
      read fFramesOutBytesSocket;
    /// compression ratio of frames received by this instance
    property FramesInCompression: integer
      read GetFramesInCompression;
    /// compression ratio of frames Sent by this instance
    property FramesOutCompression: integer
      read GetFramesOutCompression;
  end;

  /// used to maintain a list of websocket protocols (for the server side)
  TWebSocketProtocolList = class(TSynPersistentLock)
  protected
    fProtocols: array of TWebSocketProtocol;
    // caller should make fSafe.Lock/UnLock
    function FindIndex(const aName, aUri: RawUtf8): integer;
  public
    /// add a protocol to the internal list
    // - returns TRUE on success
    // - if this protocol is already existing for this given name and URI,
    // returns FALSE: it is up to the caller to release aProtocol if needed
    function Add(aProtocol: TWebSocketProtocol): boolean;
    /// add once a protocol to the internal list
    // - if this protocol is already existing for this given name and URI, any
    // previous one will be released - so it may be confusing on a running server
    // - returns TRUE if the protocol was added for the first time, or FALSE
    // if the protocol has been replaced or is invalid (e.g. aProtocol=nil)
    function AddOnce(aProtocol: TWebSocketProtocol): boolean;
    /// erase a protocol from the internal list, specified by its name
    function Remove(const aProtocolName, aUri: RawUtf8): boolean;
    /// finalize the list storage
    destructor Destroy; override;
    /// create a new protocol instance, from the internal list
    function CloneByName(const aProtocolName, aClientUri: RawUtf8): TWebSocketProtocol;
    /// create a new protocol instance, from the internal list
    function CloneByUri(const aClientUri: RawUtf8): TWebSocketProtocol;
    /// how many protocols are stored
    function Count: integer;
  end;

  /// indicates which kind of process did occur in the main WebSockets loop
  TWebSocketProcessOne = (
    wspNone,
    wspPing,
    wspDone,
    wspAnswer,
    wspError,
    wspClosed);

  /// indicates how TWebSocketProcess.NotifyCallback() will work
  TWebSocketProcessNotifyCallback = (
    wscBlockWithAnswer,
    wscBlockWithoutAnswer,
    wscNonBlockWithoutAnswer);

  /// used to manage a thread-safe list of WebSockets frames
  TWebSocketFrameList = class(TSynPersistentLock)
  protected
    fTimeoutSec: PtrInt;
    procedure Delete(i: integer);
  public
    /// low-level access to the WebSocket frames list
    List: TWebSocketFrameDynArray;
    /// current number of WebSocket frames in the list
    Count: integer;
    /// initialize the list
    constructor Create(timeoutsec: integer); reintroduce;
    /// add a WebSocket frame in the list
    // - this method is thread-safe
    procedure Push(const frame: TWebSocketFrame);
    /// add a void WebSocket frame in the list
    // - this method is thread-safe
    procedure PushVoidFrame(opcode: TWebSocketFrameOpCode);
    /// retrieve a WebSocket frame from the list, oldest first
    // - you should specify a frame type to search for, according to the
    // specified WebSockets protocl
    // - this method is thread-safe
    function Pop(protocol: TWebSocketProtocol; const head: RawUtf8;
      out frame: TWebSocketFrame): boolean;
    /// how many 'answer' frames are to be ignored
    // - this method is thread-safe
    function AnswerToIgnore(incr: integer = 0): integer;
  end;



{ ******************** WebSockets Client and Server Shared Process }

  /// the current state of the WebSockets process
  TWebSocketProcessState = (
    wpsCreate,
    wpsRun,
    wpsClose,
    wpsDestroy);

  /// abstract WebSockets process, used on both client or server sides
  // - CanGetFrame/ReceiveBytes/SendBytes abstract methods should be overriden with
  // actual communication, and fState and ProcessStart/ProcessStop should be
  // updated from the actual processing thread (e.g. as in TWebCrtSocketProcess)
  TWebSocketProcess = class(TSynPersistent)
  protected
    fProcessName: RawUtf8;
    fIncoming: TWebSocketFrameList;
    fOutgoing: TWebSocketFrameList;
    fOwnerThread: TSynThread;
    fOwnerConnection: THttpServerConnectionID;
    fState: TWebSocketProcessState;
    fProtocol: TWebSocketProtocol;
    fMaskSentFrames: byte;
    fProcessEnded: boolean;
    fConnectionCloseWasSent: boolean;
    fProcessCount: integer;
    fSettings: PWebSocketProcessSettings;
    fSafeIn, fSafeOut: PSynLocker;
    fInvalidPingSendCount: cardinal;
    fSafePing: PSynLocker;
    fLastSocketTicks: Int64;
    function LastPingDelay: Int64;
    procedure SetLastPingTicks(invalidPing: boolean = false);
    /// callback methods run by ProcessLoop
    procedure ProcessStart; virtual;
    procedure ProcessStop; virtual;
    // called by ProcessLoop - TRUE=continue, FALSE=ended
    // - caller may have checked that some data is pending to read
    function ProcessLoopStepReceive: boolean;
    // called by ProcessLoop - TRUE=continue, FALSE=ended
    // - caller may check that LastPingDelay>fSettings.SendDelay and Socket is writable
    function ProcessLoopStepSend: boolean;
    // blocking process, for one thread handling all WebSocket connection process
    procedure ProcessLoop;
    function ComputeContext(
       out RequestProcess: TOnHttpServerRequest): THttpServerRequestAbstract;
      virtual; abstract;
    procedure HiResDelay(const start: Int64);
    procedure Log(const frame: TWebSocketFrame; const aMethodName: RawUtf8;
      aEvent: TSynLogInfo = sllTrace; DisableRemoteLog: boolean = false); virtual;
    function SendPendingOutgoingFrames: boolean;
  public
    /// initialize the WebSockets process on a given connection
    // - the supplied TWebSocketProtocol will be owned by this instance
    // - other parameters should reflect the client or server expectations
    constructor Create(aProtocol: TWebSocketProtocol;
      aOwnerConnection: THttpServerConnectionID; aOwnerThread: TSynThread;
      aSettings: PWebSocketProcessSettings; const aProcessName: RawUtf8); reintroduce;
    /// finalize the context
    // - if needed, will notify the other end with a focConnectionClose frame
    // - will release the TWebSocketProtocol associated instance
    destructor Destroy; override;
    /// abstract low-level method to retrieve pending input data
    // - should return the number of bytes (<=count) received and written to P
    // - is defined separated to allow multi-thread pooling
    function ReceiveBytes(P: PAnsiChar; count: integer): integer; virtual; abstract;
    /// abstract low-level method to send pending output data
    // - returns false on any error, try on success
    // - is defined separated to allow multi-thread pooling
    function SendBytes(P: pointer; Len: integer): boolean; virtual; abstract;
    /// abstract low-level method to check if there is some pending input data
    // in the input Socket ready for GetFrame/ReceiveBytes
    // - is defined separated to allow multi-thread pooling
    function CanGetFrame(TimeOut: cardinal;
      ErrorWithoutException: PInteger): boolean; virtual; abstract;
    /// blocking process incoming WebSockets framing protocol
    // - CanGetFrame should have been called and returned true before
    // - will call overriden ReceiveBytes() for the actual communication
    function GetFrame(out Frame: TWebSocketFrame;
      ErrorWithoutException: PInteger): boolean;
    /// process outgoing WebSockets framing protocol -> to be overriden
    // - will call overriden SendBytes() for the actual communication
    // - use Outgoing.Push() to send frames asynchronously
    function SendFrame(var Frame: TWebSocketFrame): boolean;
    /// will push a request or notification to the other end of the connection
    // - caller should set the aRequest with the outgoing parameters, and
    // optionally receive a response from the other end
    // - the request may be sent in blocking or non blocking mode
    // - returns the HTTP Status code (e.g. HTTP_SUCCESS=200 for success)
    function NotifyCallback(aRequest: THttpServerRequestAbstract;
      aMode: TWebSocketProcessNotifyCallback): cardinal; virtual;
    /// send a focConnectionClose frame (if not already sent) and set wpsClose
    procedure Shutdown;
    /// returns the current state of the underlying connection
    function State: TWebSocketProcessState;
    /// the associated 'Remote-IP' HTTP header value
    // - returns '' if Protocol=nil or Protocol.RemoteLocalhost=true
    function RemoteIP: RawUtf8;
      {$ifdef HASINLINE}inline;{$endif}
    /// the settings currently used during the WebSockets process
    // - points to the owner instance, e.g. TWebSocketServer.Settings or
    // THttpClientWebSockets.Settings field
    property Settings: PWebSocketProcessSettings
      read fSettings;
    /// direct access to the low-level incoming frame stack
    property Incoming: TWebSocketFrameList
      read fIncoming;
    /// direct access to the low-level outgoing frame stack
    // - call Outgoing.Push() to send frames asynchronously, with optional
    // jumboframe gathering (if supported by the protocol)
    property Outgoing: TWebSocketFrameList
      read fOutgoing;
    /// the associated low-level processing thread
    property OwnerThread: TSynThread
      read fOwnerThread;
    /// the associated low-level WebSocket connection opaque identifier
    property OwnerConnection: THttpServerConnectionID
      read fOwnerConnection;
    /// how many frames are currently processed by this connection
    property ProcessCount: integer
      read fProcessCount;
    /// may be set to TRUE before Destroy to force raw socket disconnection
    property ConnectionCloseWasSent: boolean
      read fConnectionCloseWasSent write fConnectionCloseWasSent;
  published
    /// the Sec-WebSocket-Protocol application protocol currently involved
    // - TWebSocketProtocolJson or TWebSocketProtocolBinary in the mORMot context
    // - could be nil if the connection is in standard HTTP/1.1 mode
    property Protocol: TWebSocketProtocol
      read fProtocol;
    /// the associated process name
    property ProcessName: RawUtf8
      read fProcessName write fProcessName;
    /// how many invalid heartbeat frames have been sent
    // - a non 0 value indicates a connection problem
    property InvalidPingSendCount: cardinal
      read fInvalidPingSendCount;
  end;

  /// TCrtSocket-based WebSockets process, used on both client or server sides
  // - will use the socket in blocking mode, so expects its own processing thread
  TWebCrtSocketProcess = class(TWebSocketProcess)
  protected
    fSocket: TCrtSocket;
  public
    /// initialize the WebSockets process on a given TCrtSocket connection
    // - the supplied TWebSocketProtocol will be owned by this instance
    // - other parameters should reflect the client or server expectations
    constructor Create(aSocket: TCrtSocket; aProtocol: TWebSocketProtocol;
      aOwnerConnection: THttpServerConnectionID; aOwnerThread: TSynThread;
      aSettings: PWebSocketProcessSettings; const aProcessName: RawUtf8);
       reintroduce; virtual;
    /// first step of the low level incoming WebSockets framing protocol over TCrtSocket
    // - in practice, just call fSocket.SockInPending to check for pending data
    function CanGetFrame(TimeOut: cardinal;
      ErrorWithoutException: PInteger): boolean; override;
    /// low level receive incoming WebSockets frame data over TCrtSocket
    // - in practice, just call fSocket.SockInRead to check for pending data
    function ReceiveBytes(P: PAnsiChar; count: integer): integer; override;
    /// low level receive incoming WebSockets frame data over TCrtSocket
    // - in practice, just call fSocket.TrySndLow to send pending data
    function SendBytes(P: pointer; Len: integer): boolean; override;
    /// the associated communication socket
    // - on the server side, is a THttpServerSocket
    // - access to this instance is protected by Safe.Lock/Unlock
    property Socket: TCrtSocket
      read fSocket;
  end;

/// returns the text corresponding to a specified WebSockets sending mode
function ToText(mode: TWebSocketProcessNotifyCallback): PShortString; overload;

/// returns the text corresponding to a specified WebSockets state
function ToText(st: TWebSocketProcessState): PShortString; overload;


var
  /// if set, will log all WebSockets raw information
  // - see also TWebSocketProcessSettings.LogDetails and
  // TWebSocketProcessSettings.SetFullLog to setup even more verbose information,
  // e.g. by setting HttpServerFullWebSocketsLog and HttpClientFullWebSocketsLog
  // global variables to true (as defined in mormot.rest.http.server/client)
  WebSocketLog: TSynLogClass;

  /// number of bytes above which SynLZ compression may be done
  // - when working with TWebSocketProtocolBinary
  // - it is useless to compress smallest frames, which fits in network MTU
  WebSocketsBinarySynLzThreshold: integer = 450;

  /// the allowed maximum size, in MB, of a WebSockets frame
  WebSocketsMaxFrameMB: cardinal = 256;



implementation


{ ******************** WebSockets Frames Definitions }

var
  _TWebSocketFrameOpCode:
    array[TWebSocketFrameOpCode] of PShortString;
  _TWebSocketProcessNotifyCallback:
    array[TWebSocketProcessNotifyCallback] of PShortString;

function ToText(opcode: TWebSocketFrameOpCode): PShortString;
begin
  result := _TWebSocketFrameOpCode[opcode];
end;

function ToText(mode: TWebSocketProcessNotifyCallback): PShortString;
begin
  result := _TWebSocketProcessNotifyCallback[mode];
end;

function ToText(st: TWebSocketProcessState): PShortString;
begin
  result := GetEnumName(TypeInfo(TWebSocketProcessState), ord(st));
end;

procedure ComputeChallenge(const Base64: RawByteString; out Digest: TSha1Digest);
const
  // see https://tools.ietf.org/html/rfc6455
  SALT: string[36] = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
var
  SHA: TSha1;
begin
  SHA.Init;
  SHA.Update(pointer(Base64), length(Base64));
  SHA.Update(@SALT[1], 36);
  SHA.Final(Digest);
end;


{ ******************** WebSockets Protocols Implementation }

{ TWebSocketProtocol }

constructor TWebSocketProtocol.Create(const aName, aUri: RawUtf8);
begin
  fName := aName;
  fUri := aUri;
  fConnectionFlags := [hsrWebsockets];
end;

procedure TWebSocketProtocol.SetEncryptKey(aServer: boolean; const aKey: RawUtf8;
  aSettings: PWebSocketProcessSettings);
var
  key: THash256Rec;
begin
  // always first disable any previous encryption
  fEncryption := nil;
  fConnectionFlags := [hsrWebsockets];
  if (aKey = '') or
     (aSettings = nil) then
    exit;
  // 1. try asymetric ES-256 ephemeral secret key and mutual authentication
  // check human-friendly format 'password#*.private' key file name
  with aSettings^ do
    fEncryption := TEcdheProtocol.FromPasswordSecureFile(
      aKey, aServer, EcdheAuth, EcdheCipher, EcdheRounds);
  if fEncryption = nil then
    // check 'a=mutual;e=aesctc128;p=34a2;pw=password;ca=..' full format
    fEncryption := TEcdheProtocol.FromKey(aKey, aServer);
  if fEncryption <> nil then
    include(fConnectionFlags, hsrSecured)
  else
  begin
    // 2. aKey no 'a=...'/'pw#xx.private' layout -> use symetric TProtocolAes
    if aSettings.AesRounds = 0 then
      // mORMot 1.18 deprecated password derivation
      Sha256Weak(aKey, key.b)
    else
      // new safer password derivation algorithm (rounds=1000 -> 1ms)
      PBKDF2_SHA3(SHA3_256, aKey, aSettings.AesSalt, aSettings.AesRounds,
        @key, SizeOf(key));
    SetEncryptKeyAes(aSettings.AesCipher, key, aSettings.AesBits);
  end;
end;

procedure TWebSocketProtocol.SetEncryptKeyAes(aCipher: TAesAbstractClass;
  const aKey; aKeySize: cardinal);
begin
  fEncryption := nil;
  fConnectionFlags := [hsrWebsockets];
  if aKeySize < 128 then
    exit;
  fEncryption := TProtocolAes.Create(aCipher, aKey, aKeySize);
  include(fConnectionFlags, hsrSecured)
end;

procedure TWebSocketProtocol.SetEncryptKeyEcdhe(aAuth: TEcdheAuth;
  aPKI: TEccCertificateChain; aPrivate: TEccCertificateSecret; aServer: boolean;
  aEF: TEcdheEF; aPrivateOwned: boolean);
begin
  fEncryption := nil;
  fConnectionFlags := [hsrWebsockets];
  fEncryption := ECDHEPROT_CLASS[aServer].Create(
    aAuth, aPKI, aPrivate, aEF, aPrivateOwned);
  include(fConnectionFlags, hsrSecured)
end;

procedure TWebSocketProtocol.AfterGetFrame(var frame: TWebSocketFrame);
begin
  inc(fFramesInCount);
  inc(fFramesInBytes, length(frame.payload) + 2);
end;

procedure TWebSocketProtocol.BeforeSendFrame(var frame: TWebSocketFrame);
begin
  inc(fFramesOutCount);
  inc(fFramesOutBytes, length(frame.payload) + 2);
end;

function TWebSocketProtocol.FrameData(const frame: TWebSocketFrame;
  const Head: RawUtf8; HeadFound: PRawUtf8): pointer;
begin
  result := nil; // no frame type by default
end;

function TWebSocketProtocol.FrameType(const frame: TWebSocketFrame): RawUtf8;
begin
  result := '*'; // no frame URI by default
end;

function TWebSocketProtocol.ProcessHandshake(const ExtIn: TRawUtf8DynArray;
  out ExtOut: RawUtf8; ErrorMsg: PRawUtf8): boolean;
var
  res: TProtocolResult;
  msgin, msgout: RawUtf8;
  synhk: boolean;
  i: integer;
begin
  result := fEncryption = nil;
  if result then
    exit; // nothing to handshake for -> try to continue
  synhk := false;
  if ExtIn <> nil then
  begin
    for i := 0 to length(ExtIn) - 1 do
      if IdemPropNameU(ExtIn[i], 'synhk') then
        synhk := true
      else if synhk and
              IdemPChar(pointer(ExtIn[i]), 'HK=') then
      begin
        msgin := copy(ExtIn[i], 4, maxInt);
        break;
      end;
    if ({%H-}msgin = '') or
       not synhk then
      exit;
  end;
  res := fEncryption.ProcessHandshake(msgin, msgout);
  case res of
    sprSuccess:
      begin
        AddToCsv('synhk; hk=' + msgout, ExtOut{%H-}, '; ');
        result := true;
        exit;
      end;
    sprUnsupported:
      if not synhk then
      begin
        result := true; // try to continue execution
        exit;
      end;
  end;
  WebSocketLog.Add.Log(sllWarning, 'ProcessHandshake=% In=[%]',
    [ToText(res)^, msgin], self);
  if ErrorMsg <> nil then
    ErrorMsg^ := FormatUtf8('%: %', [ErrorMsg^,
      GetCaptionFromEnum(TypeInfo(TProtocolResult), ord(res))]);
end;

function TWebSocketProtocol.ProcessHandshakeUri(const aClientUri: RawUtf8): boolean;
begin
  result := true; // override and return false to return HTTP_UNAUTHORIZED
end;

function TWebSocketProtocol.SendFrames(Owner: TWebSocketProcess;
  var Frames: TWebSocketFrameDynArray; var FramesCount: integer): boolean;
var
  i, n: PtrInt;
begin
  // this default implementation will send all frames one by one
  n := FramesCount;
  if (n > 0) and
     (Owner <> nil) then
  begin
    result := false;
    FramesCount := 0;
    for i := 0 to n - 1 do
      if Owner.SendFrame(Frames[i]) then
        Frames[i].payload := ''
      else
        exit;
  end;
  result := true;
end;

function TWebSocketProtocol.GetEncrypted: boolean;
begin
  result := (self <> nil) and
            (fEncryption <> nil);
end;

function TWebSocketProtocol.GetSubprotocols: RawUtf8;
begin
  result := fName;
end;

function TWebSocketProtocol.SetSubprotocol(const aProtocolName: RawUtf8): boolean;
begin
  result := IdemPropNameU(aProtocolName, fName);
end;

function TWebSocketProtocol.GetRemoteIP: RawUtf8;
begin
  if (self = nil) or
     fRemoteLocalhost then
    result := ''
  else
    result := fRemoteIP;
end;


{ TWebSocketFrameList }

constructor TWebSocketFrameList.Create(timeoutsec: integer);
begin
  inherited Create;
  fTimeoutSec := timeoutsec;
end;

function TWebSocketFrameList.AnswerToIgnore(incr: integer): integer;
begin
  Safe^.Lock;
  if incr <> 0 then
    inc(Safe^.Padding[0].VInteger, incr);
  result := Safe^.Padding[0].VInteger;
  Safe^.UnLock;
end;

function TWebSocketFrameList.Pop(protocol: TWebSocketProtocol;
  const head: RawUtf8; out frame: TWebSocketFrame): boolean;
var
  i: PtrInt;
  tix: cardinal;
  item: PWebSocketFrame;
begin
  result := false;
  if (self = nil) or
     (Count = 0) or
     (head = '') or
     (protocol = nil) then
    exit;
  if fTimeoutSec = 0 then
    tix := 0
  else
    tix := GetTickCount64 shr 10;
  Safe.Lock;
  try
    for i := Count - 1 downto 0 do
    begin
      item := @List[i];
      if protocol.FrameData(item^, head) <> nil then
      begin
        result := true;
        frame := item^;
        Delete(i);
        exit;
      end
      else if (tix > 0) and
              (tix > item^.tix) then
        Delete(i);
    end;
  finally
    Safe.UnLock;
  end;
end;

procedure TWebSocketFrameList.Push(const frame: TWebSocketFrame);
begin
  if self = nil then
    exit;
  Safe.Lock;
  try
    if Count >= length(List) then
      SetLength(List, Count + Count shr 3 + 8);
    List[Count] := frame;
    if fTimeoutSec > 0 then
      List[Count].tix := fTimeoutSec + (GetTickCount64 shr 10);
    inc(Count);
  finally
    Safe.UnLock;
  end;
end;

procedure TWebSocketFrameList.PushVoidFrame(opcode: TWebSocketFrameOpCode);
var
  frame: TWebSocketFrame;
begin
  frame.opcode := opcode;
  frame.content := [];
  Push(frame);
end;

procedure TWebSocketFrameList.Delete(i: integer);
begin
  // slightly faster than a TDynArray which would release the memory
  List[i].payload := '';
  dec(Count);
  if i < Count then
  begin
    MoveFast(List[i + 1], List[i], (Count - i) * sizeof(List[i]));
    pointer(List[Count].payload) := nil;
  end;
end;



{ TWebSocketProtocolRest }

procedure TWebSocketProtocolRest.ProcessIncomingFrame(Sender: TWebSocketProcess;
  var request: TWebSocketFrame; const info: RawUtf8);
var
  Ctxt: THttpServerRequestAbstract;
  onRequest: TOnHttpServerRequest;
  status: cardinal;
  noAnswer: boolean;
  answer: TWebSocketFrame;
  head: RawUtf8;
begin
  if not (request.opcode in [focText, focBinary]) then
    exit; // ignore e.g. from TWebSocketServerResp.ProcessStart/ProcessStop
  if FrameData(request, 'r', @head) <> nil then
  try
    Ctxt := Sender.ComputeContext(onRequest);
    try
      if (Ctxt = nil) or
         not Assigned(onRequest) then
        raise EWebSockets.CreateUtf8('%.ProcessOne: onRequest=nil', [self]);
      if (head = '') or
         not FrameToInput(request, noAnswer, Ctxt) then
        raise EWebSockets.CreateUtf8('%.ProcessOne: invalid frame', [self]);
      request.payload := ''; // release memory ASAP
      if info <> '' then
        Ctxt.AddInHeader(info);
      status := onRequest(Ctxt); // blocking call to compute the answer
      if (Ctxt.OutContentType = NORESPONSE_CONTENT_TYPE) or
         noAnswer then
        exit;
      OutputToFrame(Ctxt, status, head, answer);
      if not Sender.SendFrame(answer) then
        fLastError := Utf8ToString(FormatUtf8('SendFrame error %', [Sender]));
    finally
      Ctxt.Free;
    end;
  except
    on E: Exception do
      FormatString('% [%]', [ClassNameShort(E)^, E.Message], fLastError);
  end
  else if (Sender.fIncoming.AnswerToIgnore > 0) and
          (FrameData(request, 'answer') <> nil) then
  begin
    Sender.fIncoming.AnswerToIgnore(-1);
    Sender.Log(request, 'Ignored answer after NotifyCallback TIMEOUT', sllWarning);
  end
  else
    Sender.fIncoming.Push(request); // e.g. async 'answer'
end;

// by convention, defaults are POST and JSON, to reduce frame size for SOA calls

procedure TWebSocketProtocolRest.InputToFrame(Ctxt: THttpServerRequestAbstract;
  aNoAnswer: boolean; out request: TWebSocketFrame; out head: RawUtf8);
var
  Method, InContentType: RawByteString;
  seq: integer;
begin
  if not IdemPropNameU(Ctxt.Method, 'POST') then
    Method := Ctxt.Method;
  if (Ctxt.InContent <> '') and
     (Ctxt.InContentType <> '') and
     not IdemPropNameU(Ctxt.InContentType, JSON_CONTENT_TYPE) then
    InContentType := Ctxt.InContentType;
  if fSequencing then
  begin
    seq := InterlockedIncrement(fSequence);
    SetLength(head, 7); // safe overlap after 16,777,216 frames
    PAnsiChar(pointer(head))^ := 'r';
    BinToHexDisplay(@seq, PAnsiChar(pointer(head)) + 1, 3);
  end
  else
    head := 'request';
  FrameCompress(head, [{%H-}Method, Ctxt.Url, Ctxt.InHeaders, ord(aNoAnswer)],
    Ctxt.InContent, InContentType{%H-}, request);
  if fSequencing then
    head[1] := 'a'
  else
    head := 'answer';
end;

function TWebSocketProtocolRest.FrameToInput(var request: TWebSocketFrame;
  out aNoAnswer: boolean; Ctxt: THttpServerRequestAbstract): boolean;
var
  URL, Method, InHeaders, NoAnswer, InContentType, InContent: RawByteString;
begin
  result := FrameDecompress(request, 'r',
    [@Method, @URL, @InHeaders, @NoAnswer], InContentType, InContent);
  if result then
  begin
    if (InContentType = '') and
       (InContent <> '') then
      InContentType := JSON_CONTENT_TYPE_VAR;
    if Method = '' then
      Method := 'POST';
    Ctxt.Prepare(URL, Method, InHeaders, InContent, InContentType, fRemoteIP);
    aNoAnswer := NoAnswer = '1';
  end;
end;

procedure TWebSocketProtocolRest.OutputToFrame(Ctxt: THttpServerRequestAbstract;
  Status: cardinal; var outhead: RawUtf8; out answer: TWebSocketFrame);
var
  OutContentType: RawByteString;
begin
  if (Ctxt.OutContent <> '') and
     not IdemPropNameU(Ctxt.OutContentType, JSON_CONTENT_TYPE) then
    OutContentType := Ctxt.OutContentType;
  if NormToUpperAnsi7[outhead[3]] = 'Q' then
    // 'request' -> 'answer'
    outhead := 'answer'
  else
    // 'r000001' -> 'a000001'
    outhead[1] := 'a';
  FrameCompress(outhead, [Status, Ctxt.OutCustomHeaders], Ctxt.OutContent,
    OutContentType{%H-}, answer);
end;

function TWebSocketProtocolRest.FrameToOutput(var answer: TWebSocketFrame;
  Ctxt: THttpServerRequestAbstract): cardinal;
var
  status, outHeaders, outContentType, outContent: RawByteString;
begin
  result := HTTP_NOTFOUND;
  if not FrameDecompress(answer, 'a',
     [@status, @outHeaders], outContentType, outContent) then
    exit;
  result := GetInteger(pointer(status));
  Ctxt.OutCustomHeaders := outHeaders;
  if (outContentType = '') and
     (outContent <> '') then
    Ctxt.OutContentType := JSON_CONTENT_TYPE_VAR
  else
    Ctxt.OutContentType := outContentType;
  Ctxt.OutContent := outContent;
end;


{ TWebSocketProtocolJson }

constructor TWebSocketProtocolJson.Create(const aUri: RawUtf8);
begin
  inherited Create('synopsejson', aUri);
end;

function TWebSocketProtocolJson.Clone(const aClientUri: RawUtf8): TWebSocketProtocol;
begin
  result := TWebSocketProtocolJson.Create(fUri);
end;

procedure TWebSocketProtocolJson.FrameCompress(const Head: RawUtf8;
  const Values: array of const; const Content, ContentType: RawByteString;
  var frame: TWebSocketFrame);
var
  WR: TTextWriter;
  tmp: TTextWriterStackBuffer;
  i: PtrInt;
begin
  frame.opcode := focText;
  frame.content := [];
  WR := TTextWriter.CreateOwnedStream(tmp);
  try
    WR.Add('{');
    WR.AddFieldName(Head);
    WR.Add('[');
    for i := 0 to High(Values) do
    begin
      WR.AddJsonEscape(Values[i]);
      WR.AddComma;
    end;
    WR.Add('"');
    WR.AddString(ContentType);
    WR.Add('"', ',');
    if Content = '' then
      WR.Add('"', '"')
    else if (ContentType = '') or
            IdemPropNameU(ContentType, JSON_CONTENT_TYPE) then
      WR.AddNoJsonEscape(pointer(Content), length(Content))
    else if IdemPChar(pointer(ContentType), 'TEXT/') then
      WR.AddCsvUtf8([Content])
    else
      WR.WrBase64(pointer(Content), length(Content), true);
    WR.Add(']', '}');
    WR.SetText(RawUtf8(frame.payload));
  finally
    WR.Free;
  end;
end;

function TWebSocketProtocolJson.FrameData(const frame: TWebSocketFrame;
  const Head: RawUtf8; HeadFound: PRawUtf8): pointer;
var
  P, txt: PUtf8Char;
  len: integer;
begin
  result := nil;
  if (length(frame.payload) < 10) or
     (frame.opcode <> focText) then
    exit;
  P := pointer(frame.payload);
  if not NextNotSpaceCharIs(P, '{') then
    exit;
  while P^ <> '"' do
  begin
    inc(P);
    if P^ = #0 then
      exit;
  end;
  txt := P + 1;
  P := GotoEndOfJsonString(P); // here P^ should be '"'
  len := length(Head);
  if (P^ <> #0) and
     (P - txt >= len) and
     CompareMem(pointer(Head), txt, len) then
  begin
    result := P + 1;
    if HeadFound <> nil then
      FastSetString(HeadFound^, txt, P - txt);
  end;
end;

function TWebSocketProtocolJson.FrameDecompress(const frame: TWebSocketFrame;
  const Head: RawUtf8; const values: array of PRawByteString;
  var contentType, content: RawByteString): boolean;
var
  i: PtrInt;
  P: PUtf8Char;
  b64: PUtf8Char;
  b64len: integer;

  procedure GetNext(var content: RawByteString);
  var
    txt: PUtf8Char;
    txtlen: integer;
  begin
    txt := GetJsonField(P, P, nil, nil, @txtlen);
    FastSetString(RawUtf8(content), txt, txtlen);
  end;

begin
  result := false;
  P := FrameData(frame, Head);
  if P = nil then
    exit;
  if not NextNotSpaceCharIs(P, ':') or
     not NextNotSpaceCharIs(P, '[') then
    exit;
  for i := 0 to high(values) do
    GetNext(values[i]^);
  GetNext(contentType);
  if P = nil then
    exit;
  if (contentType = '') or
     IdemPropNameU(contentType, JSON_CONTENT_TYPE) then
    GetJsonItemAsRawJson(P, RawJson(content))
  else if IdemPChar(pointer(contentType), 'TEXT/') then
    GetNext(content)
  else
  begin
    b64 := GetJsonField(P, P, nil, nil, @b64len);
    if not Base64MagicCheckAndDecode(b64, b64len, content) then
      exit;
  end;
  result := true;
end;

function TWebSocketProtocolJson.FrameType(const frame: TWebSocketFrame): RawUtf8;
var
  P, txt: PUtf8Char;
begin
  result := '*';
  if (length(frame.payload) < 10) or
     (frame.opcode <> focText) then
    exit;
  P := pointer(frame.payload);
  if not NextNotSpaceCharIs(P, '{') or
     not NextNotSpaceCharIs(P, '"') then
    exit;
  txt := P;
  P := GotoEndOfJsonString(P);
  FastSetString(result, txt, P - txt);
end;


{ TWebSocketProtocolBinary }

constructor TWebSocketProtocolBinary.Create(
  const aUri: RawUtf8; aOptions: TWebSocketProtocolBinaryOptions);
begin
  inherited Create('synopsebin', aUri);
  fOptions := aOptions;
end;

constructor TWebSocketProtocolBinary.Create(const aUri: RawUtf8;
  const aKey; aKeySize: cardinal; aOptions: TWebSocketProtocolBinaryOptions;
  aCipher: TAesAbstractClass);
begin
  Create(aUri, aOptions);
  SetEncryptKeyAes(aCipher, aKey, aKeySize);
end;

constructor TWebSocketProtocolBinary.Create(const aUri: RawUtf8;
  aServer: boolean; const aKey: RawUtf8; aSettings: PWebSocketProcessSettings;
  aOptions: TWebSocketProtocolBinaryOptions);
begin
  Create(aUri, aOptions);
  SetEncryptKey(aServer, aKey, aSettings);
end;

function TWebSocketProtocolBinary.Clone(
  const aClientUri: RawUtf8): TWebSocketProtocol;
begin
  result := TWebSocketProtocolBinary.Create(
    fUri, {dummykey=}self, 0, fOptions);
  TWebSocketProtocolBinary(result).fSequencing := fSequencing;
  if fEncryption <> nil then
    result.fEncryption := fEncryption.Clone;
end;

const
  FRAME_HEAD_SEP = #1;

procedure FrameInit(opcode: TWebSocketFrameOpCode;
  const Content, ContentType: RawByteString; out frame: TWebSocketFrame);
begin
  frame.opcode := opcode;
  if (ContentType <> '') and
     (Content <> '') and
     not IdemPChar(pointer(ContentType), 'TEXT/') and
     IsContentCompressed(pointer(Content), length(Content)) then
    frame.content := [fopAlreadyCompressed]
  else
    frame.content := [];
end;

procedure TWebSocketProtocolBinary.FrameCompress(const Head: RawUtf8;
  const Values: array of const; const Content, ContentType: RawByteString;
  var frame: TWebSocketFrame);
var
  item: TTempUtf8;
  i: PtrInt;
  W: TBufferWriter;
  temp: TTextWriterStackBuffer; // 8KB
begin
  FrameInit(focBinary, Content, ContentType, frame);
  W := TBufferWriter.Create(temp{%H-});
  try
    W.WriteBinary(Head);
    W.Write1(byte(FRAME_HEAD_SEP));
    for i := 0 to high(Values) do
      with Values[i] do
      begin
        VarRecToTempUtf8(Values[i], item);
        W.WriteVar(item);
      end;
    W.Write(ContentType);
    W.WriteBinary(Content);
    frame.payload := W.FlushTo;
  finally
    W.Free;
  end;
end;

function TWebSocketProtocolBinary.FrameData(const frame: TWebSocketFrame;
  const Head: RawUtf8; HeadFound: PRawUtf8): pointer;
var
  len: PtrInt;
  P: PUtf8Char;
begin
  P := pointer(frame.payload);
  len := length(Head);
  if (frame.opcode = focBinary) and
     (length(frame.payload) >= len + 6) and
     CompareMemSmall(pointer(Head), P, len) then
  begin
    result := PosChar(P + len, FRAME_HEAD_SEP);
    if result <> nil then
    begin
      if HeadFound <> nil then
        FastSetString(HeadFound^, P, PAnsiChar(result) - P);
      inc(PByte(result));
    end;
  end
  else
    result := nil;
end;

function TWebSocketProtocolBinary.FrameType(const frame: TWebSocketFrame): RawUtf8;
var
  i: PtrInt;
begin
  if (length(frame.payload) < 10) or
     (frame.opcode <> focBinary) then
    i := 0
  else
    i := PosExChar(FRAME_HEAD_SEP, frame.payload);
  if i = 0 then
    result := '*'
  else
    FastSetString(result, pointer(frame.payload), i - 1);
end;

procedure TWebSocketProtocolBinary.BeforeSendFrame(var frame: TWebSocketFrame);
var
  value: RawByteString;
  threshold: integer;
begin
  inherited BeforeSendFrame(frame);
  if frame.opcode = focBinary then
  begin
    if pboSynLzCompress in fOptions then
    begin
      if (fopAlreadyCompressed in frame.content) or
         (fRemoteLocalhost and
          (pboNoLocalHostCompress in fOptions)) then
        // localhost or compressed -> no SynLZ
        threshold := maxInt
      else
        threshold := WebSocketsBinarySynLzThreshold;
      value := AlgoSynLZ.Compress(
        pointer(frame.payload), length(frame.payload), threshold);
    end
    else
      value := frame.payload;
    if (fEncryption <> nil) and
       not (fRemoteLocalhost and
            (pboNoLocalHostEncrypt in fOptions)) then
      fEncryption.Encrypt(value, frame.payload)
    else
      frame.payload := value;
  end;
  inc(fFramesOutBytesSocket, length(frame.payload) + 2);
end;

procedure TWebSocketProtocolBinary.AfterGetFrame(var frame: TWebSocketFrame);
var
  value: RawByteString;
  res: TProtocolResult;
begin
  inc(fFramesInBytesSocket, length(frame.payload) + 2);
  if frame.opcode = focBinary then
  begin
    if (fEncryption <> nil) and
       not (fRemoteLocalhost and
            (pboNoLocalHostEncrypt in fOptions)) then
    begin
      res := fEncryption.Decrypt(frame.payload, value);
      if res <> sprSuccess then
        raise EWebSockets.CreateUtf8('%.AfterGetFrame: encryption error %',
          [self, ToText(res)^]);
    end
    else
      value := frame.payload;
    if pboSynLzCompress in fOptions then
      AlgoSynLZ.Decompress(pointer(value), length(value), frame.payload)
    else
      frame.payload := value;
  end;
  inherited AfterGetFrame(frame);
end;

function TWebSocketProtocolBinary.FrameDecompress(const frame: TWebSocketFrame;
  const Head: RawUtf8; const values: array of PRawByteString;
  var contentType, content: RawByteString): boolean;
var
  i: PtrInt;
  P: PByte;
begin
  result := false;
  P := FrameData(frame, Head);
  if P = nil then
    exit;
  for i := 0 to high(values) do
    FromVarString(P, values[i]^ ,CP_UTF8);
  FromVarString(P, contentType, CP_UTF8);
  i := length(frame.payload) - (PAnsiChar(P) - pointer(frame.payload));
  if i < 0 then
    exit;
  SetString(content, PAnsiChar(P), i);
  result := true;
end;

function TWebSocketProtocolBinary.SendFrames(Owner: TWebSocketProcess;
  var Frames: TWebSocketFrameDynArray; var FramesCount: integer): boolean;
const
  JUMBO_HEADER: array[0..6] of AnsiChar = 'frames' + FRAME_HEAD_SEP;
var
  jumboFrame: TWebSocketFrame;
  i, len: PtrInt;
  P: PByte;
begin
  if (FramesCount = 0) or
     (Owner = nil) then
  begin
    result := true;
    exit;
  end;
  dec(FramesCount);
  if FramesCount = 0 then
  begin
    result := Owner.SendFrame(Frames[0]);
    exit;
  end;
  jumboFrame.opcode := focBinary;
  jumboFrame.content := [];
  len := sizeof(JUMBO_HEADER) + ToVarUInt32Length(FramesCount);
  for i := 0 to FramesCount do
    if Frames[i].opcode = focBinary then
      inc(len, ToVarUInt32LengthWithData(length(Frames[i].payload)))
    else
      raise EWebSockets.CreateUtf8('%.SendFrames[%]: Unexpected opcode=%',
        [self, i, ord(Frames[i].opcode)]);
  SetString(jumboFrame.payload, nil, len);
  P := pointer(jumboFrame.payload);
  MoveFast(JUMBO_HEADER, P^, SizeOf(JUMBO_HEADER));
  inc(P, SizeOf(JUMBO_HEADER));
  P := ToVarUInt32(FramesCount, P);
  for i := 0 to FramesCount do
  begin
    len := length(Frames[i].payload);
    P := ToVarUInt32(len, P);
    MoveFast(pointer(Frames[i].payload)^, P^, len);
    inc(P, len);
  end;
  FramesCount := 0;
  Frames := nil;
  result := Owner.SendFrame(jumboFrame); // send all frames at once
end;

procedure TWebSocketProtocolBinary.ProcessIncomingFrame(
  Sender: TWebSocketProcess; var request: TWebSocketFrame; const info: RawUtf8);
var
  jumboInfo: RawByteString;
  n, i: integer;
  frame: TWebSocketFrame;
  P: PByte;
begin
  P := FrameData(request, 'frames');
  if P <> nil then
  begin
    n := FromVarUInt32(P);
    for i := 0 to n do
    begin
      if i = 0 then
        jumboInfo := 'Sec-WebSocket-Frame: [0]'
      else if i = n then
        jumboInfo := 'Sec-WebSocket-Frame: [1]'
      else
        jumboInfo := '';
      frame.opcode := focBinary;
      frame.content := [];
      frame.payload := FromVarString(P);
      Sender.Log(frame, FormatUtf8('GetSubFrame(%/%)', [i + 1, n + 1]));
      inherited ProcessIncomingFrame(Sender, frame, jumboInfo);
    end;
  end
  else
    inherited ProcessIncomingFrame(Sender, request, info);
end;

function TWebSocketProtocolBinary.GetFramesInCompression: integer;
begin
  if (self = nil) or
     (fFramesInBytes = 0) then
    result := 100
  else if (fFramesInBytesSocket < fFramesInBytes) or
          not (pboSynLzCompress in fOptions) then
    result := 0
  else
    result := 100 - (fFramesInBytesSocket * 100) div fFramesInBytes;
end;

function TWebSocketProtocolBinary.GetFramesOutCompression: integer;
begin
  if (self = nil) or
     (fFramesOutBytes = 0) then
    result := 100
  else if (fFramesOutBytesSocket <= fFramesOutBytes) or
          not (pboSynLzCompress in fOptions) then
    result := 0
  else
    result := 100 - (fFramesOutBytesSocket * 100) div fFramesOutBytes;
end;

function TWebSocketProtocolBinary.GetSubprotocols: RawUtf8;
begin
  result := 'synopsebin, synopsebinary';
end;

function TWebSocketProtocolBinary.SetSubprotocol(const aProtocolName: RawUtf8): boolean;
begin
  case FindPropName(['synopsebin', 'synopsebinary'], aProtocolName) of
    0:
      fSequencing := true;
    1:
      fSequencing := false;
  else
    begin
      result := false;
      exit;
    end;
  end;
  result := true;
end;


{ TWebSocketProtocolList }

function TWebSocketProtocolList.CloneByName(const aProtocolName,
  aClientUri: RawUtf8): TWebSocketProtocol;
var
  i: PtrInt;
begin
  result := nil;
  if self = nil then
    exit;
  fSafe.Lock;
  try
    for i := 0 to length(fProtocols) - 1 do
      with fProtocols[i] do
        if ((fUri = '') or
            IdemPropNameU(fUri, aClientUri)) and
           SetSubprotocol(aProtocolName) then
        begin
          result := fProtocols[i].Clone(aClientUri);
          result.fName := aProtocolName;
          exit;
        end;
  finally
    fSafe.UnLock;
  end;
end;

function TWebSocketProtocolList.CloneByUri(const aClientUri: RawUtf8): TWebSocketProtocol;
var
  i: PtrInt;
begin
  result := nil;
  if (self = nil) or
     (aClientUri = '') then
    exit;
  fSafe.Lock;
  try
    for i := 0 to length(fProtocols) - 1 do
      if IdemPropNameU(fProtocols[i].fUri, aClientUri) then
      begin
        result := fProtocols[i].Clone(aClientUri);
        exit;
      end;
  finally
    fSafe.UnLock;
  end;
end;

function TWebSocketProtocolList.Count: integer;
begin
  if self = nil then
    result := 0
  else
    result := length(fProtocols);
end;

destructor TWebSocketProtocolList.Destroy;
begin
  ObjArrayClear(fProtocols);
  inherited;
end;

function TWebSocketProtocolList.FindIndex(const aName, aUri: RawUtf8): integer;
begin
  if aName <> '' then
    for result := 0 to high(fProtocols) do
      with fProtocols[result] do
        if IdemPropNameU(fName, aName) and
           ((fUri = '') or
            IdemPropNameU(fUri, aUri)) then
          exit;
  result := -1;
end;

function TWebSocketProtocolList.Add(aProtocol: TWebSocketProtocol): boolean;
var
  i: PtrInt;
begin
  result := false;
  if aProtocol = nil then
    exit;
  fSafe.Lock;
  try
    i := FindIndex(aProtocol.Name, aProtocol.Uri);
    if i < 0 then
    begin
      ObjArrayAdd(fProtocols, aProtocol);
      result := true;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TWebSocketProtocolList.AddOnce(aProtocol: TWebSocketProtocol): boolean;
var
  i: PtrInt;
begin
  result := false;
  if aProtocol = nil then
    exit;
  fSafe.Lock;
  try
    i := FindIndex(aProtocol.Name, aProtocol.Uri);
    if i < 0 then
    begin
      ObjArrayAdd(fProtocols, aProtocol);
      result := true;
    end
    else
    begin
      fProtocols[i].Free;
      fProtocols[i] := aProtocol;
    end;
  finally
    fSafe.UnLock;
  end;
end;

function TWebSocketProtocolList.Remove(const aProtocolName, aUri: RawUtf8): boolean;
var
  i: PtrInt;
begin
  fSafe.Lock;
  try
    i := FindIndex(aProtocolName, aUri);
    if i >= 0 then
    begin
      ObjArrayDelete(fProtocols, i);
      result := true;
    end
    else
      result := false;
  finally
    fSafe.UnLock;
  end;
end;


{ ******************** WebSockets Client and Server Shared Process }

{ TWebSocketProcessSettings }

procedure TWebSocketProcessSettings.SetDefaults;
begin
  HeartbeatDelay := 0;
  LoopDelay := 500;
  SendDelay := 10;
  DisconnectAfterInvalidHeartbeatCount := 5;
  CallbackAcquireTimeOutMS := 5000;
  CallbackAnswerTimeOutMS := 5000;
  LogDetails := [];
  OnClientConnected := nil;
  OnClientDisconnected := nil;
  ClientAutoUpgrade := true;
  AesSalt := 'E750ACCA-2C6F-4B0E-999B-D31C9A14EFAB';
  AesRounds := 1024;
  AesCipher := TAesFast[mCtr];
  AesBits := 128;
  EcdheCipher := efAesCtr128;
  EcdheAuth := authMutual;
  EcdheRounds := DEFAULT_ECCROUNDS;
end;

procedure TWebSocketProcessSettings.SetFullLog;
begin
  LogDetails := [logHeartbeat, logTextFrameContent, logBinaryFrameContent];
end;


{ TWebSocketProcess }

constructor TWebSocketProcess.Create(aProtocol: TWebSocketProtocol;
  aOwnerConnection: THttpServerConnectionID; aOwnerThread: TSynThread;
  aSettings: PWebSocketProcessSettings; const aProcessName: RawUtf8);
begin
  inherited Create;
  fProcessName := aProcessName;
  fProtocol := aProtocol;
  fOwnerConnection := aOwnerConnection;
  fOwnerThread := aOwnerThread;
  fSettings := aSettings;
  fIncoming := TWebSocketFrameList.Create(30 * 60);
  fOutgoing := TWebSocketFrameList.Create(0);
  fSafeIn := NewSynLocker;
  fSafeOut := NewSynLocker;
  fSafePing := NewSynLocker;
end;

procedure TWebSocketProcess.Shutdown;
var
  frame: TWebSocketFrame;
  error: integer;
begin
  if self = nil then
    exit;
  fSafeOut^.Lock;
  try
    if fConnectionCloseWasSent then
      exit;
    fConnectionCloseWasSent := true;
  finally
    fSafeOut^.UnLock;
  end;
  LockedInc32(@fProcessCount);
  try
    if fOutgoing.Count > 0 then
      SendPendingOutgoingFrames;
    fState := wpsClose; // the connection is inactive from now on
    // send and acknowledge a focConnectionClose frame to notify the other end
    frame.opcode := focConnectionClose;
    error := 0;
    if not SendFrame(frame) or
       not CanGetFrame(1000, @error) or
       not GetFrame(frame, @error) then
      WebSocketLog.Add.Log(sllWarning, 'Destroy: no focConnectionClose ACK %',
        [error], self);
  finally
    LockedDec32(@fProcessCount);
  end;
end;

destructor TWebSocketProcess.Destroy;
var
  timeout: Int64;
  log: ISynLog;
begin
  log := WebSocketLog.Enter('Destroy %', [ToText(fState)^], self);
  if fState = wpsCreate then
    fProcessEnded := true
  else if not fConnectionCloseWasSent then
  begin
    if log <> nil then
      log.Log(sllTrace, 'Destroy: send focConnectionClose', self);
    Shutdown;
  end;
  fState := wpsDestroy;
  if (fProcessCount > 0) or
     not fProcessEnded then
  begin
    if log <> nil then
      log.Log(sllDebug, 'Destroy: wait for fProcessCount=%', [fProcessCount], self);
    timeout := GetTickCount64 + 5000;
    repeat
      SleepHiRes(2);
    until ((fProcessCount = 0) and fProcessEnded) or
          (GetTickCount64 > timeout);
    if log <> nil then
      log.Log(sllDebug, 'Destroy: waited fProcessCount=%', [fProcessCount], self);
  end;
  fProtocol.Free;
  fOutgoing.Free;
  fIncoming.Free;
  fSafeIn.DoneAndFreeMem;
  fSafeOut.DoneAndFreeMem;
  fSafePing.DoneAndFreeMem; // to be done lately to avoid GPF in above Destroy
  inherited Destroy;
end;

procedure TWebSocketProcess.ProcessStart;
var
  frame: TWebSocketFrame; // notify e.g. TOnWebSocketProtocolChatIncomingFrame
begin
  if Assigned(fSettings.OnClientConnected) then
  try
    WebSocketLog.Add.Log(sllTrace, 'ProcessStart: OnClientConnected', self);
    fSettings.OnClientConnected(Self);
  except
  end;
  WebSocketLog.Add.Log(sllTrace, 'ProcessStart: callbacks', self);
  frame.opcode := focContinuation;
  if not Assigned(fProtocol.fOnBeforeIncomingFrame) or
     not fProtocol.fOnBeforeIncomingFrame(self, frame) then
    fProtocol.ProcessIncomingFrame(self, frame, ''); // any exception would abort
  WebSocketLog.Add.Log(sllDebug, 'ProcessStart %', [fProtocol], self);
end;

procedure TWebSocketProcess.ProcessStop;
var
  frame: TWebSocketFrame; // notify e.g. TOnWebSocketProtocolChatIncomingFrame
begin
  try
    WebSocketLog.Add.Log(sllTrace, 'ProcessStop: callbacks', self);
    frame.opcode := focConnectionClose;
    if not Assigned(fProtocol.fOnBeforeIncomingFrame) or
       not fProtocol.fOnBeforeIncomingFrame(self, frame) then
      fProtocol.ProcessIncomingFrame(self, frame, '');
    if Assigned(fSettings.OnClientDisconnected) then
    begin
      WebSocketLog.Add.Log(sllTrace, 'ProcessStop: OnClientDisconnected', self);
      fSettings.OnClientDisconnected(Self);
    end;
  except // exceptions are just ignored at shutdown
  end;
  fProcessEnded := true;
  WebSocketLog.Add.Log(sllDebug, 'ProcessStop %', [fProtocol], self);
end;

procedure TWebSocketProcess.SetLastPingTicks(invalidPing: boolean);
var
  tix: Int64;
begin
  tix := GetTickCount64;
  fSafePing.Lock;
  try
    fLastSocketTicks := tix;
    if invalidPing then
    begin
      inc(fInvalidPingSendCount);
      fSafeOut.Lock;
      fConnectionCloseWasSent := true;
      fSafeOut.UnLock;
    end
    else
      fInvalidPingSendCount := 0;
  finally
    fSafePing.UnLock;
  end;
end;

function TWebSocketProcess.LastPingDelay: Int64;
begin
  result := GetTickCount64;
  fSafePing.Lock;
  try
    dec(result, fLastSocketTicks);
  finally
    fSafePing.UnLock;
  end;
end;

function TWebSocketProcess.ProcessLoopStepReceive: boolean;
var
  request: TWebSocketFrame;
  sockerror: integer;
begin
  if fState = wpsRun then
  begin
    LockedInc32(@fProcessCount); // flag currently processing
    try
      if CanGetFrame({timeout=}1, @sockerror) and
         GetFrame(request, @sockerror) then
      begin
        case request.opcode of
          focPing:
            begin
              request.opcode := focPong;
              SendFrame(request);
            end;
          focPong:
            ; // nothing to do
          focText, focBinary:
            if not Assigned(fProtocol.fOnBeforeIncomingFrame) or
               not fProtocol.fOnBeforeIncomingFrame(self, request) then
              fProtocol.ProcessIncomingFrame(self, request, '');
          focConnectionClose:
            begin
              if fState = wpsRun then
              begin
                fState := wpsClose; // will close the connection
                SendFrame(request); // send back the frame as ACK
              end;
            end;
        end;
      end
      else if (fOwnerThread <> nil) and
              fOwnerThread.Terminated then
        fState := wpsClose
      else if sockerror <> 0 then
      begin
        WebSocketLog.Add.Log(sllInfo, 'GetFrame SockInPending error % on %',
          [sockerror, fProtocol], self);
        fState := wpsClose;
      end;
    finally
      LockedDec32(@fProcessCount); // release flag
    end;
  end;
  result := (fState = wpsRun);
end;

function TWebSocketProcess.ProcessLoopStepSend: boolean;
var
  request: TWebSocketFrame;
  elapsed: cardinal;
begin
  if fState = wpsRun then
  begin
    LockedInc32(@fProcessCount); // flag currently processing
    try
      elapsed := LastPingDelay;
      if elapsed > fSettings.SendDelay then
        if (fOutgoing.Count > 0) and
           not SendPendingOutgoingFrames then
          fState := wpsClose
        else if (fSettings.HeartbeatDelay <> 0) and
                (elapsed > fSettings.HeartbeatDelay) then
        begin
          request.opcode := focPing;
          if not SendFrame(request) then
            if (fSettings.DisconnectAfterInvalidHeartbeatCount <> 0) and
               (fInvalidPingSendCount >=
                 fSettings.DisconnectAfterInvalidHeartbeatCount) then
              fState := wpsClose
            else
              SetLastPingTicks(true); // mark invalid, and avoid immediate retry
        end;
    finally
      LockedDec32(@fProcessCount); // release flag
    end;
  end;
  result := (fState = wpsRun);
end;

procedure TWebSocketProcess.ProcessLoop;
begin
  if fProtocol = nil then
    exit;
  try
    ProcessStart; // any exception will close the socket
    try
      SetLastPingTicks;
      fState := wpsRun;
      while (fOwnerThread = nil) or
            not fOwnerThread.Terminated do
        if ProcessLoopStepReceive and
           ProcessLoopStepSend then
          HiResDelay(fLastSocketTicks)
        else
          break; // connection ended
    finally
      ProcessStop;
    end;
  except // don't be optimistic: abort and close connection
    fState := wpsClose;
  end;
end;

procedure TWebSocketProcess.HiResDelay(const start: Int64);
var
  delay: cardinal;
begin
  case GetTickCount64 - start of
    0..50:
      delay := 0; // 10 microsecs on POSIX
    51..200:
      delay := 1;
    201..500:
      delay := 5;
    501..2000:
      delay := 50;
    2001..5000:
      delay := 100;
  else
    delay := 500;
  end;
  if (fSettings.LoopDelay <> 0) and
     (delay > fSettings.LoopDelay) then
    delay := fSettings.LoopDelay;
  SleepHiRes(delay);
end;

function TWebSocketProcess.State: TWebSocketProcessState;
begin
  if self = nil then
    result := wpsCreate
  else
    result := fState;
end;

function TWebSocketProcess.RemoteIP: RawUtf8;
begin
  if (self = nil) or
     (fProtocol = nil) or
     fProtocol.fRemoteLocalhost then
    result := ''
  else
    result := fProtocol.fRemoteIP;
end;

function TWebSocketProcess.NotifyCallback(aRequest: THttpServerRequestAbstract;
  aMode: TWebSocketProcessNotifyCallback): cardinal;
var
  request, answer: TWebSocketFrame;
  i: integer;
  start, max: Int64;
  head: RawUtf8;
begin
  result := HTTP_NOTFOUND;
  if (fProtocol = nil) or
     (aRequest = nil) or
     not fProtocol.InheritsFrom(TWebSocketProtocolRest) then
    exit;
  if WebSocketLog <> nil then
    WebSocketLog.Add.Log(sllTrace, 'NotifyCallback(%,%)',
      [aRequest.Url, _TWebSocketProcessNotifyCallback[aMode]^], self);
  TWebSocketProtocolRest(fProtocol).InputToFrame(aRequest,
    aMode in [wscBlockWithoutAnswer, wscNonBlockWithoutAnswer], request, head);
  case aMode of
    wscNonBlockWithoutAnswer:
      begin
        // add to the internal sending list for asynchronous sending
        fOutgoing.Push(request);
        result := HTTP_SUCCESS;
        exit;
      end;
    wscBlockWithAnswer:
      if fIncoming.AnswerToIgnore > 0 then
      begin
        WebSocketLog.Add.Log(sllDebug,
          'NotifyCallback: Waiting for AnswerToIgnore=%',
          [fIncoming.AnswerToIgnore], self);
        start := GetTickCount64;
        max := start + 30000;
        repeat
          HiResDelay(start);
          if fState in [wpsDestroy, wpsClose] then
          begin
            WebSocketLog.Add.Log(sllError,
              'NotifyCallback on closed connection', self);
            exit;
          end;
          if fIncoming.AnswerToIgnore = 0 then
            break; // it is now safe to send a new 'request'
          if GetTickCount64 < max then
            continue;
          self.Log(request,
            'NotifyCallback AnswerToIgnore TIMEOUT -> abort connection', sllInfo);
          result := HTTP_NOTIMPLEMENTED; // 501 will force recreate connection
          exit;
        until false;
      end;
  end;
  i := InterlockedIncrement(fProcessCount);
  try
    if (i > 2) and
       (WebSocketLog <> nil) then
      WebSocketLog.Add.Log(sllWarning,
        'NotifyCallback with fProcessCount=%', [i], self);
    if not SendFrame(request) then
      exit;
    if aMode = wscBlockWithoutAnswer then
    begin
      result := HTTP_SUCCESS;
      exit;
    end;
    start := GetTickCount64;
    if fSettings.CallbackAnswerTimeOutMS = 0 then
      // never wait for ever
      max := start + 30000
    else if fSettings.CallbackAnswerTimeOutMS < 2000 then
      // 2 seconds minimal wait
      max := start + 2000
    else
      max := start + fSettings.CallbackAnswerTimeOutMS;
    while not fIncoming.Pop(fProtocol, head, answer) do
      if fState in [wpsDestroy, wpsClose] then
      begin
        WebSocketLog.Add.Log(sllError,
          'NotifyCallback on closed connection', self);
        exit;
      end
      else if GetTickCount64 > max then
      begin
        WebSocketLog.Add.Log(sllWarning, 'NotifyCallback TIMEOUT %', [head], self);
        if head = 'answer' then
          fIncoming.AnswerToIgnore(1); // ignore next 'answer'
        exit; // returns HTTP_NOTFOUND
      end
      else
        HiResDelay(start);
  finally
    LockedDec32(@fProcessCount);
  end;
  result := TWebSocketProtocolRest(fProtocol).FrameToOutput(answer, aRequest);
end;

function TWebSocketProcess.SendPendingOutgoingFrames: boolean;
begin
  result := false;
  fOutgoing.Safe.Lock;
  try
    if fProtocol.SendFrames(self, fOutgoing.List, fOutgoing.Count) then
      result := true
    else
      WebSocketLog.Add.Log(sllInfo, 'SendPendingOutgoingFrames: SendFrames failed', self);
  finally
    fOutgoing.Safe.UnLock;
  end;
end;

procedure TWebSocketProcess.Log(const frame: TWebSocketFrame;
  const aMethodName: RawUtf8; aEvent: TSynLogInfo; DisableRemoteLog: boolean);
var
  tmp: TLogEscape;
  log: TSynLog;
  len: integer;
begin
  if WebSocketLog <> nil then
    with WebSocketLog.Family do
      if aEvent in Level then
        if (logHeartbeat in fSettings.LogDetails) or
           not (frame.opcode in [focPing, focPong]) then
        begin
          log := SynLog;
          log.DisableRemoteLog(DisableRemoteLog);
          try
            if (frame.opcode = focText) and
               (logTextFrameContent in fSettings.LogDetails) then
              log.Log(aEvent, '% % % focText %', [aMethodName, fProtocol.GetRemoteIP,
                protocol.FrameType(frame), frame.PayLoad], self)
            else
            begin
              len := length(frame.PayLoad);
              log.Log(aEvent, '% % % % len=%%', [aMethodName, fProtocol.GetRemoteIP,
                protocol.FrameType(frame), _TWebSocketFrameOpCode[frame.opcode]^,
                len, LogEscape(pointer(frame.PayLoad), len, tmp,
                logBinaryFrameContent in fSettings.LogDetails)], self);
            end;
          finally
            log.DisableRemoteLog(false);
          end;
        end;
end;

type
  TFrameHeader = packed record
    first: byte;
    len8: byte;
    len32: cardinal;
    len64: cardinal;
    mask: cardinal; // 0 indicates no payload masking
  end;

procedure ProcessMask(data: pointer; mask: cardinal; len: PtrInt);
var
  i, maskCount: PtrInt;
begin
  maskCount := len shr 2;
  for i := 0 to maskCount - 1 do
    PCardinalArray(data)^[i] := PCardinalArray(data)^[i] xor mask;
  maskCount := maskCount shl 2;
  for i := maskCount to maskCount + (len and 3) - 1 do
  begin
    PByteArray(data)^[i] := PByteArray(data)^[i] xor mask;
    mask := mask shr 8;
  end;
end;

type
  // asynchronous state machine to process incoming frames
  TWebProcessInFrameState = (
    pfsHeader1,
    pfsData1,
    pfsHeaderN,
    pfsDataN,
    pfsDone,
    pfsError);

  TWebProcessInFrame = object
    hdr: TFrameHeader;
    opcode: TWebSocketFrameOpCode;
    masked: boolean;
    st: TWebProcessInFrameState;
    process: TWebSocketProcess;
    outputframe: PWebSocketFrame;
    len: integer;
    data: RawByteString;
    procedure Init(Owner: TWebSocketProcess; output: PWebSocketFrame);
    function GetBytes(P: PAnsiChar; count: integer): boolean;
    function GetHeader: boolean;
    function GetData: boolean;
    function Step(ErrorWithoutException: PInteger): TWebProcessInFrameState;
  end;

function TWebProcessInFrame.GetBytes(P: PAnsiChar; count: integer): boolean;
begin
  // SockInRead() below raise a ENetSock error on failure
  inc(len, process.ReceiveBytes(P + len, count - len));
  result := len = count;
end;

function TWebProcessInFrame.GetHeader: boolean;
begin
  result := false;
  if len < 2 then
  begin
    data := '';
    FillCharFast(hdr, sizeof(hdr), 0);
    if not GetBytes(@hdr, 2) then // first+len8
      exit;
  end;
  opcode := TWebSocketFrameOpCode(hdr.first and 15);
  masked := hdr.len8 and FRAME_LEN_MASK <> 0;
  if masked then
    hdr.len8 := hdr.len8 and 127;
  if hdr.len8 < FRAME_LEN_2BYTES then
    hdr.len32 := hdr.len8
  else if hdr.len8 = FRAME_LEN_2BYTES then
  begin
    if not GetBytes(@hdr, 4) then // first+len8+len32.low
      exit;
    hdr.len32 := swap(word(hdr.len32)); // FPC expects explicit word() cast
  end
  else if hdr.len8 = FRAME_LEN_8BYTES then
  begin
    if not GetBytes(@hdr, 10) then // first+len8+len32+len64.low
      exit;
    if hdr.len32 <> 0 then // size is more than 32 bits (4GB) -> reject
      hdr.len32 := maxInt
    else
      hdr.len32 := bswap32(hdr.len64);
    if hdr.len32 > WebSocketsMaxFrameMB shl 20 then
      raise EWebSockets.CreateUtf8('%.GetFrame: length should be < % MB', [process,
        WebSocketsMaxFrameMB]);
  end;
  if masked then
  begin
    len := 0; // not appended to hdr
    if not GetBytes(@hdr.mask, 4) then
      raise EWebSockets.CreateUtf8('%.GetFrame: truncated mask', [process]);
  end;
  len := 0; // prepare upcoming GetData
  result := true;
end;

function TWebProcessInFrame.GetData: boolean;
begin
  if length(data) <> integer(hdr.len32) then
    SetString(data, nil, hdr.len32);
  result := GetBytes(pointer(data), hdr.len32);
  if result then
  begin
    if hdr.mask <> 0 then
      ProcessMask(pointer(data), hdr.mask, hdr.len32);
    len := 0; // prepare upcoming GetHeader
  end;
end;

function TWebProcessInFrame.Step(ErrorWithoutException: PInteger): TWebProcessInFrameState;
begin
  while true do // process incoming data as much as possible
    case st of
      pfsHeader1:
        if GetHeader then
        begin
          outputframe.opcode := opcode;
          outputframe.content := [];
          st := pfsData1;
        end
        else
          break; // quit when not enough data is available from input
      pfsData1:
        if GetData then
        begin
          outputframe.payload := data;
          if hdr.first and FRAME_OPCODE_FIN = 0 then
            st := pfsHeaderN
          else
            st := pfsDone;
        end
        else
          break;
      pfsHeaderN:
        if GetHeader then
          if (opcode <> focContinuation) and
             (opcode <> outputframe.opcode) then
          begin
            st := pfsError;
            if ErrorWithoutException <> nil then
            begin
              WebSocketLog.Add.Log(sllDebug, 'GetFrame: received %, expected %',
                [_TWebSocketFrameOpCode[opcode]^, _TWebSocketFrameOpCode[outputframe.opcode]^],
                process);
              ErrorWithoutException^ := maxInt;
            end
            else
              raise EWebSockets.CreateUtf8('%.GetFrame: received %, expected %',
                [process, _TWebSocketFrameOpCode[opcode]^,
                _TWebSocketFrameOpCode[outputframe.opcode]^]);
          end
          else
            st := pfsDataN
        else
          break;
      pfsDataN:
        if GetData then
        begin
          outputframe.payload := outputframe.payload + data;
          if hdr.first and FRAME_OPCODE_FIN = 0 then
            st := pfsHeaderN
          else
            st := pfsDone;
        end
        else
          break;
      pfsDone:
        begin
          data := '';
          {$ifdef HASCODEPAGE}
          if opcode = focText then
            SetCodePage(outputframe.payload, CP_UTF8, false); // identify text value as UTF-8
          {$endif HASCODEPAGE}
          if (process.fProtocol <> nil) and
             (outputframe.payload <> '') then
            process.fProtocol.AfterGetFrame(outputframe^);
          process.Log(outputframe^, 'GetFrame');
          process.SetLastPingTicks;
          break;
        end;
    else // e.g. pfsError
      break;
    end;
  result := st;
end;

procedure TWebProcessInFrame.Init(owner: TWebSocketProcess; output: PWebSocketFrame);
begin
  process := owner;
  outputframe := output;
  st := pfsHeader1;
  len := 0;
end;

function TWebSocketProcess.GetFrame(out Frame: TWebSocketFrame;
  ErrorWithoutException: PInteger): boolean;
var
  f: TWebProcessInFrame;
begin
  f.Init(self, @Frame);
  fSafeIn.Lock;
  try
    repeat
      // blocking processing loop to perform all steps
    until f.Step(ErrorWithoutException) in [pfsDone, pfsError];
    result := f.st = pfsDone;
  finally
    fSafeIn.UnLock;
  end;
end;

function TWebSocketProcess.SendFrame(var Frame: TWebSocketFrame): boolean;
var
  hdr: TFrameHeader;
  hdrlen, len: cardinal;
  tmp: TSynTempBuffer;
begin
  fSafeOut.Lock;
  try
    log(Frame, 'SendFrame', sllTrace, true);
    try
      result := true;
      if Frame.opcode = focConnectionClose then
        fConnectionCloseWasSent := true; // to be done once on each end
      if (fProtocol <> nil) and
         (Frame.payload <> '') then
        fProtocol.BeforeSendFrame(Frame);
      len := Length(Frame.payload);
      hdr.first := byte(Frame.opcode) or FRAME_OPCODE_FIN; // single frame
      if len < FRAME_LEN_2BYTES then
      begin
        hdr.len8 := len or fMaskSentFrames;
        hdrlen := 2; // opcode+len8
      end
      else if len < 65536 then
      begin
        hdr.len8 := FRAME_LEN_2BYTES or fMaskSentFrames;
        hdr.len32 := swap(word(len)); // FPC expects explicit word() cast
        hdrlen := 4; // opcode+len8+len32.low
      end
      else
      begin
        hdr.len8 := FRAME_LEN_8BYTES or fMaskSentFrames;
        hdr.len64 := bswap32(len);
        hdr.len32 := 0;
        hdrlen := 10; // opcode+len8+len32+len64.low
      end;
      if fMaskSentFrames <> 0 then
      begin
        hdr.mask := Random32; // https://tools.ietf.org/html/rfc6455#section-10.3
        ProcessMask(pointer(Frame.payload), hdr.mask, len);
        inc(hdrlen, 4);
      end;
      tmp.Init(hdrlen + len); // avoid most memory allocations
      try
        MoveSmall(@hdr, tmp.buf, hdrlen);
        if fMaskSentFrames <> 0 then
          PInteger(PAnsiChar(tmp.buf) + hdrlen - 4)^ := hdr.mask;
        MoveFast(pointer(Frame.payload)^, PAnsiChar(tmp.buf)[hdrlen], len);
        if not SendBytes(tmp.buf, hdrlen + len) then
          result := false;
      finally
        tmp.Done;
      end;
      SetLastPingTicks(not result);
    except
      result := false;
    end;
  finally
    fSafeOut.UnLock;
  end;
end;


{ TWebCrtSocketProcess }

constructor TWebCrtSocketProcess.Create(aSocket: TCrtSocket; aProtocol:
  TWebSocketProtocol; aOwnerConnection: THttpServerConnectionID;
  aOwnerThread: TSynThread; aSettings: PWebSocketProcessSettings;
  const aProcessName: RawUtf8);
begin
  inherited Create(aProtocol, aOwnerConnection, aOwnerThread, aSettings, aProcessName);
  fSocket := aSocket;
end;

function TWebCrtSocketProcess.CanGetFrame(TimeOut: cardinal;
  ErrorWithoutException: PInteger): boolean;
var
  pending: integer;
begin
  if ErrorWithoutException <> nil then
    ErrorWithoutException^ := 0;
  pending := fSocket.SockInPending(TimeOut, {PendingAlsoInSocket=}true);
  if pending < 0 then // socket error
    if ErrorWithoutException <> nil then
    begin
      ErrorWithoutException^ := fSocket.LastLowSocketError;
      result := false;
      exit;
    end
    else
      raise EWebSockets.CreateUtf8('SockInPending() Error % on %:% - from %',
        [fSocket.LastLowSocketError, fSocket.Server, fSocket.Port, fProtocol.fRemoteIP]);
  result := (pending >= 2);
end;

function TWebCrtSocketProcess.ReceiveBytes(P: PAnsiChar; count: integer): integer;
begin
  result := fSocket.SockInRead(P, count, {useonlysockin=}false);
end;

function TWebCrtSocketProcess.SendBytes(P: pointer; Len: integer): boolean;
begin
  result := fSocket.TrySndLow(P, Len);
end;



initialization
  GetEnumNames(TypeInfo(TWebSocketFrameOpCode),
    @_TWebSocketFrameOpCode);
  GetEnumNames(TypeInfo(TWebSocketProcessNotifyCallback),
    @_TWebSocketProcessNotifyCallback);

end.


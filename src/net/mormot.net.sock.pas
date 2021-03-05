/// low-level access to the OperatingSystem Sockets API (e.g. WinSock2)
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.sock;

{
  *****************************************************************************

   Cross-Platform Raw Sockets API Definition
   - Socket Process High-Level Encapsulation
   - TLS / HTTPS Encryption Abstract Layer
   - Efficient Multiple Sockets Polling
   - TCrtSocket Buffered Socket Read/Write Class

   The Low-Level Sockets API, which is complex and inconsistent among OS, is
   not made public and shouldn't be used in end-user code. This unit
   encapsultates all Sockets features into a single set of functions, and
   around the TNetSocket abstract wrapper.

  *****************************************************************************

  Notes:
    Oldest Delphis didn't include WinSock2.pas, so we defined our own.
    Under POSIX, will redirect to the libc or regular FPC units.

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os;


{ ******************** Socket Process High-Level Encapsulation }

const
  cLocalhost = '127.0.0.1';
  cAnyHost = '0.0.0.0';
  cBroadcast = '255.255.255.255';
  c6Localhost = '::1';
  c6AnyHost = '::0';
  c6Broadcast = 'ffff::1';
  cAnyPort = '0';
  cLocalhost32 = $0100007f;

  {$ifdef OSWINDOWS}
  SOCKADDR_SIZE = 28;
  {$else}
  SOCKADDR_SIZE = 110; // able to store UNIX domain socket name
  {$endif OSWINDOWS}

var
  /// global variable containing '127.0.0.1'
  // - defined as var not as const to use reference counting from TNetAddr.IP
  IP4local: RawUtf8;

type
  /// the error codes returned by TNetSocket wrapper
  TNetResult = (
    nrOK,
    nrRetry,
    nrNoSocket,
    nrNotFound,
    nrNotImplemented,
    nrClosed,
    nrFatalError,
    nrUnknownError,
    nrTooManyConnections);

  {$M+}
  /// exception class raised by this unit
  ENetSock = class(Exception)
  public
    /// raise ENetSock if res is not nrOK or nrRetry
    class procedure Check(res: TNetResult; const Context: shortstring);
    /// call NetLastError and raise ENetSock if not nrOK nor nrRetry
    class procedure CheckLastError(const Context: shortstring; ForceRaise: boolean = false;
      AnotherNonFatal: integer = 0);
  end;
  {$M-}

  /// one data state on a given socket
  TNetEvent = (
    neRead,
    neWrite,
    neError,
    neClosed);

  /// the current whole read/write state on a given socket
  TNetEvents = set of TNetEvent;

  /// the available socket protocol layers
  // - by definition, nlUNIX will return nrNotImplemented on Windows
  TNetLayer = (
    nlTCP,
    nlUDP,
    nlUNIX);

  /// the available socket families - mapping AF_INET/AF_INET6/AF_UNIX
  TNetFamily = (
    nfUnknown,
    nfIP4,
    nfIP6,
    nfUNIX);

const
  /// the socket protocol layers over the IP protocol
  nlIP = [nlTCP, nlUDP];

type
  /// internal mapping of an address, in any supported socket layer
  TNetAddr = object
  private
    // opaque wrapper with len: sockaddr_un=110 (POSIX) or sockaddr_in6=28 (Win)
    Addr: array[0..SOCKADDR_SIZE - 1] of byte;
  public
    function SetFrom(const address, addrport: RawUtf8; layer: TNetLayer): TNetResult;
    function Family: TNetFamily;
    function IP(localasvoid: boolean = false): RawUtf8;
    function IPShort(withport: boolean = false): shortstring; overload;
      {$ifdef HASINLINE}inline;{$endif}
    procedure IPShort(out result: shortstring; withport: boolean = false); overload;
    function Port: cardinal;
    function SetPort(p: cardinal): TNetResult;
    function Size: integer;
  end;

  /// pointer to a socket address mapping
  PNetAddr = ^TNetAddr;

  TNetAddrDynArray = array of TNetAddr;

type
  /// end-user code should use this TNetSocket type to hold a socket reference
  // - then methods allow cross-platform access to the connection
  TNetSocket = ^TNetSocketWrap;

  /// convenient object-oriented wrapper around a socket connection
  // - TNetSocket is a pointer to this, so TSocket(@self) is used for the OS API
  TNetSocketWrap = object
  private
    procedure SetOpt(prot, name: integer; value: pointer; valuelen: integer);
  public
    procedure SetupConnection(layer: TNetLayer; sendtimeout, recvtimeout: integer);
    procedure SetSendTimeout(ms: integer);
    procedure SetReceiveTimeout(ms: integer);
    procedure SetKeepAlive(keepalive: boolean);
    procedure SetLinger(linger: integer);
    procedure SetNoDelay(nodelay: boolean);
    function Accept(out clientsocket: TNetSocket; out addr: TNetAddr): TNetResult;
    function GetPeer(out addr: TNetAddr): TNetResult;
    function MakeAsync: TNetResult;
    function Send(Buf: pointer; var len: integer): TNetResult;
    function Recv(Buf: pointer; var len: integer): TNetResult;
    function SendTo(Buf: pointer; len: integer; out addr: TNetAddr): TNetResult;
    function RecvFrom(Buf: pointer; len: integer; out addr: TNetAddr): integer;
    function WaitFor(ms: integer; scope: TNetEvents): TNetEvents;
    function RecvPending(out pending: integer): TNetResult;
    function ShutdownAndClose(rdwr: boolean): TNetResult;
    function Close: TNetResult;
    function Socket: PtrInt;
      {$ifdef HASINLINE}inline;{$endif}
  end;


  /// used by NewSocket() to cache the host names via NewSocketAddressCache global
  // - defined in this unit, but implemented in mormot.net.client.pas
  // - the implementation should be thread-safe
  INewSocketAddressCache = interface
    /// method called by NewSocket() to resolve its address
    function Search(const Host: RawUtf8; out NetAddr: TNetAddr): boolean;
    /// once resolved, NewSocket() will call this method to cache the TNetAddr
    procedure Add(const Host: RawUtf8; const NetAddr: TNetAddr);
    /// called by NewSocket() if connection failed, and force DNS resolution
    procedure Flush(const Host: RawUtf8);
    /// you can call this method to change the default timeout of 10 minutes
    procedure SetTimeOut(aSeconds: integer);
  end;


/// create a new Socket connected or bound to a given ip:port
function NewSocket(const address, port: RawUtf8; layer: TNetLayer;
  dobind: boolean; connecttimeout, sendtimeout, recvtimeout, retry: integer;
  out netsocket: TNetSocket; netaddr: PNetAddr = nil): TNetResult;


var
  /// contains the raw Socket API version, as returned by the Operating System
  SocketApiVersion: RawUtf8;

  /// used by NewSocket() to cache the host names
  // - implemented by mormot.net.client unit using a TSynDictionary
  // - you may call its SetTimeOut or Flush methods to tune the caching
  NewSocketAddressCache: INewSocketAddressCache;

  /// Queue length for completely established sockets waiting to be accepted,
  // a backlog parameter for listen() function. If queue overflows client count,
  // ECONNREFUSED error is returned from connect() call
  // - for Windows default $7fffffff should not be modified. Actual limit is 200
  // - for Unix default is taken from constant (128 as in linux kernel >2.2),
  // but actual value is min(DefaultListenBacklog, /proc/sys/net/core/somaxconn)
  DefaultListenBacklog: integer;

  /// defines if a connection from the loopback should be reported as ''
  // - loopback connection will have no Remote-IP - for the default true
  // - or loopback connection will be explicitly '127.0.0.1' - if equals false
  // - used by both TCrtSock.AcceptRequest and THttpApiServer.Execute servers
  RemoteIPLocalHostAsVoidInServers: boolean = true;


/// returns the trimmed text of a network result
// - e.g. ToText(nrNotFound)='NotFound'
function ToText(res: TNetResult): PShortString; overload;



{ ******************** TLS / HTTPS Encryption Abstract Layer }

type
  /// TLS Options and Information for a given TCrtSocket/INetTLS connection
  // - currently only properly implemented by mormot.lib.openssl11 - SChannel
  // on Windows only recognizes IgnoreCertificateErrors and sets CipherName
  // - typical usage is the following:
  // $ with THttpClientSocket.Create do
  // $ try
  // $   TLS.WithPeerInfo := true;
  // $   TLS.IgnoreCertificateErrors := true;
  // $   TLS.CipherList := 'ECDHE-RSA-AES256-GCM-SHA384';
  // $   OpenBind('synopse.info', '443', {bind=}false, {tls=}true);
  // $   writeln(TLS.PeerInfo);
  // $   writeln(TLS.CipherName);
  // $   writeln(Get('/forum/', 1000), ' len=', ContentLength);
  // $   writeln(Get('/fossil/wiki/Synopse+OpenSource', 1000));
  // $ finally
  // $   Free;
  // $ end;
  TNetTLSContext = record
    /// set if the TLS flag was set to TCrtSocket.OpenBind() method
    Enabled: boolean;
    /// input: let HTTPS be less paranoid about TLS certificates
    IgnoreCertificateErrors: boolean;
    /// input: if PeerInfo field should be retrieved once connected
    WithPeerInfo: boolean;
    /// input: PEM file name containing a certificate to be loaded
    // - (Delphi) warning: encoded as UTF-8 not UnicodeString/TFileName
    CertificateFile: RawUtf8;
    /// input: PEM file name containing a private key to be loaded
    // - (Delphi) warning: encoded as UTF-8 not UnicodeString/TFileName
    PrivateKeyFile: RawUtf8;
    /// input: optional password to load the PrivateKey file
    PrivatePassword: RawUtf8;
    /// input: file containing a specific set of CA certificates chain
    // - e.g. entrust_2048_ca.cer from https://web.entrust.com
    // - (Delphi) warning: encoded as UTF-8 not UnicodeString/TFileName
    CACertificatesFile: RawUtf8;
    /// input: preferred Cipher List
    CipherList: RawUtf8;
    /// output: some information about the connected Peer
    // - stored in the native format of the TLS library, e.g. X509_print()
    PeerInfo: RawUtf8;
    /// output: the cipher description, as used for the current connection
    // - e.g. 'ECDHE-RSA-AES128-GCM-SHA256 TLSv1.2 Kx=ECDH Au=RSA Enc=AESGCM(128) Mac=AEAD'
    CipherName: RawUtf8;
    /// output: low-level details about the last error at TLS level
    LastError: RawUtf8;
  end;

  /// pointer to TLS Options and Information for a given TCrtSocket connection
  PNetTLSContext = ^TNetTLSContext;

  /// abstract definition of the TLS encrypted layer
  // - is implemented e.g. by the SChannel API on Windows, or OpenSSL on POSIX
  // if you include mormot.lib.openssl11 to your project
  INetTLS = interface
    /// this method is called once to attach the underlying socket
    // - should make the proper initial TLS handshake to create a session
    // - should raise an exception on error
    procedure AfterConnection(Socket: TNetSocket; var Context: TNetTLSContext;
      const ServerAddress: RawUtf8);
    /// receive some data from the TLS layer
    function Receive(Buffer: pointer; var Length: integer): TNetResult;
    /// send some data from the TLS layer
    function Send(Buffer: pointer; var Length: integer): TNetResult;
  end;

  /// signature of a factory for a new TLS encrypted layer
  TOnNewNetTLS = function: INetTLS;

var
  /// global factory for a new TLS encrypted layer for TCrtSocket
  // - is set to use the SChannel API on Windows; on other targets, may be nil
  // unless the mormot.lib.openssl11.pas unit is included with your project
  NewNetTLS: TOnNewNetTLS;


{ ******************** Efficient Multiple Sockets Polling }

type
  /// the events monitored by TPollSocketAbstract
  // - we don't make any difference between urgent or normal read/write events
  TPollSocketEvent = (
    pseRead,
    pseWrite,
    pseError,
    pseClosed);

  /// set of events monitored by TPollSocketAbstract
  TPollSocketEvents = set of TPollSocketEvent;

  /// some opaque value (which may be a pointer) associated with a polling event
  TPollSocketTag = type PtrInt;

  /// modifications notified by TPollSocketAbstract.WaitForModified
  TPollSocketResult = record
    /// opaque value as defined by TPollSocketAbstract.Subscribe
    tag: TPollSocketTag;
    /// the events which are notified
    events: TPollSocketEvents;
  end;

  /// all modifications returned by IPollSocket.WaitForModified
  TPollSocketResults = array of TPollSocketResult;

  {$M+}
  /// abstract parent for TPollSocket* and TPollSockets polling
  TPollAbstract = class
  protected
    fCount: integer;
  public
    /// track status modifications on one specified TSocket
    // - you can specify which events are monitored - pseError and pseClosed
    // will always be notified
    // - tag parameter will be returned as TPollSocketResult - you may set
    // here the socket file descriptor value, or a transtyped class instance
    // - similar to epoll's EPOLL_CTL_ADD control interface
    function Subscribe(socket: TNetSocket; events: TPollSocketEvents;
      tag: TPollSocketTag): boolean; virtual; abstract;
    /// how many TSocket instances are currently tracked
    property Count: integer
      read fCount;
  end;
  {$M-}

  /// abstract parent class for efficient socket polling
  // - works like Linux epoll API in level-triggered (LT) mode
  // - implements libevent-like cross-platform features
  // - use PollSocketClass global function to retrieve the best class depending
  // on the running Operating System
  // - actual classes are hidden in the implementation section of this unit,
  // and will use the fastest available API on each Operating System
  TPollSocketAbstract = class(TPollAbstract)
  protected
    fMaxSockets: integer;
  public
    /// class function factory, returning a socket polling instance matching
    // at best the current operating system
    // - return a hidden TPollSocketSelect instance under Windows,
    // TPollSocketEpoll instance under Linux, or TPollSocketPoll on BSD
    // - just a wrapper around PollSocketClass.Create
    class function New: TPollSocketAbstract;
    /// initialize the polling (do nothing by default - but can be overriden)
    constructor Create; virtual;
    /// stop status modifications tracking on one specified TSocket
    // - the socket should have been monitored by a previous call to Subscribe()
    // - on success, returns true and fill tag with the associated opaque value
    // - similar to epoll's EPOLL_CTL_DEL control interface
    function Unsubscribe(socket: TNetSocket): boolean; virtual; abstract;
    /// waits for status modifications of all tracked TSocket
    // - will wait up to timeoutMS milliseconds, 0 meaning immediate return
    // and -1 for infinite blocking
    // - returns -1 on error (e.g. no TSocket currently registered), or
    // the number of modifications stored in results[] (may be 0 if none)
    function WaitForModified(out results: TPollSocketResults;
      timeoutMS: integer): integer; virtual; abstract;
  published
    /// how many TSocket instances could be tracked, at most
    // - depends on the API used
    property MaxSockets: integer
      read fMaxSockets;
  end;

  /// meta-class of TPollSocketAbstract socket polling classes
  // - since TPollSocketAbstract.Create is declared as virtual, could be used
  // to specify the proper polling class to add
  // - see PollSocketClass function and TPollSocketAbstract.New method
  TPollSocketClass = class of TPollSocketAbstract;

  /// implements efficient polling of multiple sockets
  // - will maintain a pool of TPollSocketAbstract instances, to monitor
  // incoming data or outgoing availability for a set of active connections
  // - call Subscribe/Unsubscribe to setup the monitored sockets
  // - call GetOne from any consumming threads to process new events
  TPollSockets = class(TPollAbstract)
  protected
    fPoll: array of TPollSocketAbstract;
    fPollIndex: integer;
    fPending: TPollSocketResults;
    fPendingIndex: PtrInt;
    fGettingOne: integer;
    fTerminated: boolean;
    fPollClass: TPollSocketClass;
    fPollLock: TRTLCriticalSection;
    fPendingLock: TRTLCriticalSection;
  public
    /// initialize the sockets polling
    // - under Linux/POSIX, will set the open files maximum number for the
    // current process to match the system hard limit: if your system has a
    // low "ulimit -H -n" value, you may add the following line in your
    // /etc/limits.conf or /etc/security/limits.conf file:
    // $ * hard nofile 65535
    constructor Create(aPollClass: TPollSocketClass = nil);
    /// finalize the sockets polling, and release all used memory
    destructor Destroy; override;
    /// track modifications on one specified TSocket and tag
    // - the supplied tag value - maybe a PtrInt(aObject) - will be part of
    // GetOne method results
    // - will create as many TPollSocketAbstract instances as needed, depending
    // on the MaxSockets capability of the actual implementation class
    // - this method is thread-safe
    function Subscribe(socket: TNetSocket; events: TPollSocketEvents;
      tag: TPollSocketTag): boolean; override;
    /// stop status modifications tracking on one specified TSocket and tag
    // - the socket should have been monitored by a previous call to Subscribe()
    // - this method is thread-safe
    function Unsubscribe(socket: TNetSocket; tag: TPollSocketTag): boolean; virtual;
    /// retrieve the next pending notification, or let the poll wait for new
    // - if there is no pending notification, will poll and wait up to
    // timeoutMS milliseconds for pending data
    // - returns true and set notif.events/tag with the corresponding notification
    // - returns false if no pending event was handled within the timeoutMS period
    // - this method is thread-safe, and could be called from several threads
    function GetOne(timeoutMS: integer; out notif: TPollSocketResult): boolean; virtual;
    /// retrieve the next pending notification
    // - returns true and set notif.events/tag with the corresponding notification
    // - returns false if no pending event is available
    // - this method is thread-safe, and could be called from several threads
    function GetOneWithinPending(out notif: TPollSocketResult): boolean;
    /// notify any GetOne waiting method to stop its polling loop
    procedure Terminate; virtual;
    /// the actual polling class used to track socket state changes
    property PollClass: TPollSocketClass
      read fPollClass write fPollClass;
    /// set to true by the Terminate method
    property Terminated: boolean
      read fTerminated;
  end;


/// the TPollSocketAbstract class best fitting with the current Operating System
// - as used by TPollSocketAbstract.New method
function PollSocketClass: TPollSocketClass;



{ ********* TCrtSocket Buffered Socket Read/Write Class }

type
  /// meta-class of a TCrtSocket (sub-)type
  TCrtSocketClass = class of TCrtSocket;

  /// identify the incoming data availability in TCrtSocket.SockReceivePending
  TCrtSocketPending = (
    cspSocketError,
    cspNoData,
    cspDataAvailable);

  {$M+}
  /// Fast low-level Socket implementation
  // - direct access to the OS (Windows, Linux) network layer API
  // - use Open constructor to create a client to be connected to a server
  // - use Bind constructor to initialize a server
  // - use SockIn and SockOut (after CreateSock*) to read/readln or write/writeln
  //  as with standard Delphi text files (see SendEmail implementation)
  // - even if you do not use read(SockIn^), you may call CreateSockIn then
  // read the (binary) content via SockInRead/SockInPending methods, which would
  // benefit of the SockIn^ input buffer to maximize reading speed
  // - to write data, CreateSockOut and write(SockOut^) is not mandatory: you
  // rather may use SockSend() overloaded methods, followed by a SockFlush call
  // - in fact, you can decide whatever to use none, one or both SockIn/SockOut
  // - since this class rely on its internal optimized buffering system,
  // TCP_NODELAY is set to disable the Nagle algorithm
  // - our classes are (much) faster than the Indy or Synapse implementation
  TCrtSocket = class
  protected
    fSock: TNetSocket;
    fServer: RawUtf8;
    fPort: RawUtf8;
    fSockIn: PTextFile;
    fSockOut: PTextFile;
    fTimeOut: PtrInt;
    fBytesIn: Int64;
    fBytesOut: Int64;
    fSocketLayer: TNetLayer;
    fSockInEofError: integer;
    fWasBind: boolean;
    // updated by every SockSend() call
    fSndBuf: RawByteString;
    fSndBufLen: integer;
    // set by AcceptRequest() from TVarSin
    fRemoteIP: RawUtf8;
    // updated during UDP connection, accessed via PeerAddress/PeerPort
    fPeerAddr: TNetAddr;
    fSecure: INetTLS;
    procedure SetKeepAlive(aKeepAlive: boolean); virtual;
    procedure SetLinger(aLinger: integer); virtual;
    procedure SetReceiveTimeout(aReceiveTimeout: integer); virtual;
    procedure SetSendTimeout(aSendTimeout: integer); virtual;
    procedure SetTCPNoDelay(aTCPNoDelay: boolean); virtual;
    function GetRawSocket: PtrInt;
  public
    /// direct access to the low-level TLS Options and Information
    // - depending on the actual INetTLS implementation, some fields may not
    // be used nor populated - currently only supported by mormot.lib.openssl11
    TLS: TNetTLSContext;
    /// can be assigned from TSynLog.DoLog class method for low-level logging
    OnLog: TSynLogProc;
    /// common initialization of all constructors
    // - do not call directly, but use Open / Bind constructors instead
    constructor Create(aTimeOut: PtrInt = 10000); reintroduce; virtual;
    /// connect to aServer:aPort
    // - optionaly via TLS (using the SChannel API on Windows, or by including
    // mormot.lib.openssl11 unit to your project) - with custom input options
    // - see also SocketOpen() for a wrapper catching any connection exception
    constructor Open(const aServer, aPort: RawUtf8; aLayer: TNetLayer = nlTCP;
      aTimeOut: cardinal = 10000; aTLS: boolean = false; aTLSContext: PNetTLSContext = nil);
    /// bind to an address
    // - aAddr='1234' - bind to a port on all interfaces, the same as '0.0.0.0:1234'
    // - aAddr='IP:port' - bind to specified interface only, e.g.
    // '1.2.3.4:1234'
    // - aAddr='unix:/path/to/file' - bind to unix domain socket, e.g.
    // 'unix:/run/mormot.sock'
    // - aAddr='' - bind to systemd descriptor on linux - see
    // http://0pointer.de/blog/projects/socket-activation.html
    constructor Bind(const aAddress: RawUtf8; aLayer: TNetLayer = nlTCP;
      aTimeOut: integer = 10000);
    /// low-level internal method called by Open() and Bind() constructors
    // - raise an ENetSock exception on error
    // - optionaly via TLS (using the SChannel API on Windows, or by including
    // mormot.lib.openssl11 unit) - with custom input options in the TLS fields
    procedure OpenBind(const aServer, aPort: RawUtf8; doBind: boolean;
      aTLS: boolean = false; aLayer: TNetLayer = nlTCP;
      aSock: TNetSocket = TNetSocket(-1));
    /// initialize the instance with the supplied accepted socket
    // - is called from a bound TCP Server, just after Accept()
    procedure AcceptRequest(aClientSock: TNetSocket; aClientAddr: PNetAddr);
    /// initialize SockIn for receiving with read[ln](SockIn^,...)
    // - data is buffered, filled as the data is available
    // - read(char) or readln() is indeed very fast
    // - multithread applications would also use this SockIn pseudo-text file
    // - by default, expect CR+LF as line feed (i.e. the HTTP way)
    procedure CreateSockIn(LineBreak: TTextLineBreakStyle = tlbsCRLF;
      InputBufferSize: integer = 1024);
    /// initialize SockOut for sending with write[ln](SockOut^,....)
    // - data is sent (flushed) after each writeln() - it's a compiler feature
    // - use rather SockSend() + SockSendFlush to send headers at once e.g.
    // since writeln(SockOut^,..) flush buffer each time
    procedure CreateSockOut(OutputBufferSize: integer = 1024);
    /// finalize SockIn receiving buffer
    // - you may call this method when you are sure that you don't need the
    // input buffering feature on this connection any more (e.g. after having
    // parsed the HTTP header, then rely on direct socket comunication)
    procedure CloseSockIn;
    /// finalize SockOut receiving buffer
    // - you may call this method when you are sure that you don't need the
    // output buffering feature on this connection any more (e.g. after having
    // parsed the HTTP header, then rely on direct socket comunication)
    procedure CloseSockOut;
    /// close and shutdown the connection (called from Destroy)
    procedure Close;
    /// close the opened socket, and corresponding SockIn/SockOut
    destructor Destroy; override;
    /// read Length bytes from SockIn buffer + Sock if necessary
    // - if SockIn is available, it first gets data from SockIn^.Buffer,
    // then directly receive data from socket if UseOnlySockIn = false
    // - if UseOnlySockIn = true, it will return the data available in SockIn^,
    // and returns the number of bytes
    // - can be used also without SockIn: it will call directly SockRecv()
    // in such case (assuming UseOnlySockin=false)
    function SockInRead(Content: PAnsiChar; Length: integer;
      UseOnlySockIn: boolean = false): integer;
    /// returns the number of bytes in SockIn buffer or pending in Sock
    // - if SockIn is available, it first check from any data in SockIn^.Buffer,
    // then call InputSock to try to receive any pending data if the buffer is void
    // - if aPendingAlsoInSocket is TRUE, returns the bytes available in both the buffer
    // and the socket (sometimes needed, e.g. to process a whole block at once)
    // - will wait up to the specified aTimeOutMS value (in milliseconds) for
    // incoming data - may wait a little less time on Windows due to a select bug
    // - returns -1 in case of a socket error (e.g. broken/closed connection);
    // you can raise a ENetSock exception to propagate the error
    function SockInPending(aTimeOutMS: integer;
      aPendingAlsoInSocket: boolean = false): integer;
    /// checks if the low-level socket handle has been assigned
    // - just a wrapper around PtrInt(fSock)>0
    function SockIsDefined: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// check the connection status of the socket
    function SockConnected: boolean;
    /// simulate writeln() with direct use of Send(Sock, ..) - includes trailing #13#10
    // - useful on multi-treaded environnement (as in THttpServer.Process)
    // - no temp buffer is used
    // - handle RawByteString, ShortString, Char, integer parameters
    // - raise ENetSock exception on socket error
    procedure SockSend(const Values: array of const); overload;
    /// simulate writeln() with a single line - includes trailing #13#10
    procedure SockSend(const Line: RawByteString); overload;
    /// append P^ data into SndBuf (used by SockSend(), e.g.) - no trailing #13#10
    // - call SockSendFlush to send it through the network via SndLow()
    procedure SockSend(P: pointer; Len: integer); overload;
    /// append #13#10 characters
    procedure SockSendCRLF;
    /// flush all pending data to be sent, optionally with some body content
    // - raise ENetSock on error
    procedure SockSendFlush(const aBody: RawByteString = '');
    /// how many bytes could be added by SockSend() in the internal buffer
    function SockSendRemainingSize: integer;
      {$ifdef HASINLINE}inline;{$endif}
    /// fill the Buffer with Length bytes
    // - use TimeOut milliseconds wait for incoming data
    // - bypass the SockIn^ buffers
    // - raise ENetSock exception on socket error
    procedure SockRecv(Buffer: pointer; Length: integer);
    /// check if there are some pending bytes in the input sockets API buffer
    // - returns cspSocketError if the connection is broken or closed
    // - warning: on Windows, may wait a little less than TimeOutMS (select bug)
    function SockReceivePending(TimeOutMS: integer): TCrtSocketPending;
    /// returns the socket input stream as a string
    function SockReceiveString: RawByteString;
    /// fill the Buffer with Length bytes
    // - use TimeOut milliseconds wait for incoming data
    // - bypass the SockIn^ buffers
    // - return false on any fatal socket error, true on success
    // - call Close if the socket is identified as shutdown from the other side
    // - you may optionally set StopBeforeLength = true, then the read bytes count
    // are set in Length, even if not all expected data has been received - in
    // this case, Close method won't be called
    function TrySockRecv(Buffer: pointer; var Length: integer;
      StopBeforeLength: boolean = false): boolean;
    /// call readln(SockIn^,Line) or simulate it with direct use of Recv(Sock, ..)
    // - char are read one by one if needed
    // - use TimeOut milliseconds wait for incoming data
    // - raise ENetSock exception on socket error
    // - by default, will handle #10 or #13#10 as line delimiter (as normal text
    // files), but you can delimit lines using #13 if CROnly is TRUE
    procedure SockRecvLn(out Line: RawUtf8; CROnly: boolean = false); overload;
    /// call readln(SockIn^) or simulate it with direct use of Recv(Sock, ..)
    // - char are read one by one
    // - use TimeOut milliseconds wait for incoming data
    // - raise ENetSock exception on socket error
    // - line content is ignored
    procedure SockRecvLn; overload;
    /// direct send data through network
    // - raise a ENetSock exception on any error
    // - bypass the SockSend() or SockOut^ buffers
    procedure SndLow(P: pointer; Len: integer);
    /// direct send data through network
    // - return false on any error, true on success
    // - bypass the SndBuf or SockOut^ buffers
    function TrySndLow(P: pointer; Len: integer): boolean;
    /// returns the low-level error number
    // - i.e. returns WSAGetLastError
    function LastLowSocketError: integer;
    /// direct send data through network
    // - raise a ENetSock exception on any error
    // - bypass the SndBuf or SockOut^ buffers
    // - raw Data is sent directly to OS: no LF/CRLF is appened to the block
    procedure Write(const Data: RawByteString);
    /// direct accept an new incoming connection on a bound socket
    // - instance should have been setup as a server via a previous Bind() call
    // - returns nil on error or a ResultClass instance on success
    // - if ResultClass is nil, will return a plain TCrtSocket, but you may
    // specify e.g. THttpServerSocket if you expect incoming HTTP requests
    function AcceptIncoming(ResultClass: TCrtSocketClass = nil): TCrtSocket;
    /// remote IP address after AcceptRequest() call over TCP
    // - is either the raw connection IP to the current server socket, or
    // a custom header value set by a local proxy as retrieved by inherited
    // THttpServerSocket.GetRequest, searching the header named in
    // THttpServerGeneric.RemoteIPHeader (e.g. 'X-Real-IP' for nginx)
    property RemoteIP: RawUtf8
      read fRemoteIP write fRemoteIP;
    /// remote IP address of the last packet received (SocketLayer=slUDP only)
    function PeerAddress(LocalAsVoid: boolean = false): RawByteString;
    /// remote IP port of the last packet received (SocketLayer=slUDP only)
    function PeerPort: integer;
    /// set the TCP_NODELAY option for the connection
    // - default true will disable the Nagle buffering algorithm; it should
    // only be set for applications that send frequent small bursts of information
    // without getting an immediate response, where timely delivery of data
    // is required - so it expects buffering before calling Write() or SndLow()
    // - you can set false here to enable the Nagle algorithm, if needed
    // - see http://www.unixguide.net/network/socketfaq/2.16.shtml
    property TCPNoDelay: boolean
      write SetTCPNoDelay;
    /// set the SO_SNDTIMEO option for the connection
    // - i.e. the timeout, in milliseconds, for blocking send calls
    // - see http://msdn.microsoft.com/en-us/library/windows/desktop/ms740476
    property SendTimeout: integer
      write SetSendTimeout;
    /// set the SO_RCVTIMEO option for the connection
    // - i.e. the timeout, in milliseconds, for blocking receive calls
    // - see http://msdn.microsoft.com/en-us/library/windows/desktop/ms740476
    property ReceiveTimeout: integer
      write SetReceiveTimeout;
    /// set the SO_KEEPALIVE option for the connection
    // - 1 (true) will enable keep-alive packets for the connection
    // - see http://msdn.microsoft.com/en-us/library/windows/desktop/ee470551
    property KeepAlive: boolean
      write SetKeepAlive;
    /// set the SO_LINGER option for the connection, to control its shutdown
    // - by default (or Linger<0), Close will return immediately to the caller,
    // and any pending data will be delivered if possible
    // - Linger > 0  represents the time in seconds for the timeout period
    // to be applied at Close; under Linux, will also set SO_REUSEADDR; under
    // Darwin, set SO_NOSIGPIPE
    // - Linger = 0 causes the connection to be aborted and any pending data
    // is immediately discarded at Close
    property Linger: integer
      write SetLinger;
    /// low-level socket handle, initialized after Open() with socket
    property Sock: TNetSocket
      read fSock write fSock;
    /// after CreateSockIn, use Readln(SockIn^,s) to read a line from the opened socket
    property SockIn: PTextFile
      read fSockIn;
    /// after CreateSockOut, use Writeln(SockOut^,s) to send a line to the opened socket
    property SockOut: PTextFile
      read fSockOut;
  published
    /// low-level socket type, initialized after Open() with socket
    property SocketLayer: TNetLayer
      read fSocketLayer;
    /// IP address, initialized after Open() with Server name
    property Server: RawUtf8
      read fServer;
    /// contains Sock, but transtyped as number for log display
    property RawSocket: PtrInt
      read GetRawSocket;
    /// IP port, initialized after Open() with port number
    property Port: RawUtf8
      read fPort;
    /// if higher than 0, read loop will wait for incoming data till
    // TimeOut milliseconds (default value is 10000) - used also in SockSend()
    property TimeOut: PtrInt
      read fTimeOut;
    /// total bytes received
    property BytesIn: Int64
      read fBytesIn write fBytesIn;
    /// total bytes sent
    property BytesOut: Int64
      read fBytesOut write fBytesOut;
  end;
  {$M-}

type
  /// structure used to parse an URI into its components
  // - ready to be supplied e.g. to a THttpRequest sub-class
  // - used e.g. by class function THttpRequest.Get()
  // - will decode standard HTTP/HTTPS urls or Unix sockets URI like
  // 'http://unix:/path/to/socket.sock:/url/path'
  {$ifdef USERECORDWITHMETHODS}
  TUri = record
  {$else}
  TUri = object
  {$endif USERECORDWITHMETHODS}
  public
    /// if the server is accessible via https:// and not plain http://
    Https: boolean;
    /// either nlTCP for HTTP/HTTPS or nlUnix for Unix socket URI
    Layer: TNetLayer;
    /// if the server is accessible via something else than http:// or https://
    // - e.g. 'ws' or 'wss' for ws:// or wss://
    Scheme: RawUtf8;
    /// the server name
    // - e.g. 'www.somewebsite.com' or 'path/to/socket.sock' Unix socket URI
    Server: RawUtf8;
    /// the server port
    // - e.g. '80'
    Port: RawUtf8;
    /// the resource address, including optional parameters
    // - e.g. '/category/name/10?param=1'
    Address: RawUtf8;
    /// fill the members from a supplied URI
    // - recognize e.g. 'http://Server:Port/Address', 'https://Server/Address',
    // 'Server/Address' (as http), or 'http://unix:/Server:/Address'
    // - returns TRUE is at least the Server has been extracted, FALSE on error
    function From(aUri: RawUtf8; const DefaultPort: RawUtf8 = ''): boolean;
    /// compute the whole normalized URI
    // - e.g. 'https://Server:Port/Address' or 'http://unix:/Server:/Address'
    function URI: RawUtf8;
    /// the server port, as integer value
    function PortInt: integer;
    /// compute the root resource Address, without any URI-encoded parameter
    // - e.g. '/category/name/10'
    function Root: RawUtf8;
    /// reset all stored information
    procedure Clear;
  end;


const
  /// the default TCP port used for HTTP = DEFAULT_PORT[false] or
  // HTTPS = DEFAULT_PORT[true]
  DEFAULT_PORT: array[boolean] of RawUtf8 = (
    '80', '443');


/// create a TCrtSocket instance, returning nil on error
// - useful to easily catch any exception, and provide a custom TNetTLSContext
function SocketOpen(const aServer, aPort: RawUtf8;
  aTLS: boolean = false; aTLSContext: PNetTLSContext = nil): TCrtSocket;


implementation

{ ******** System-Specific Raw Sockets API Layer }

{ includes are below inserted just after 'implementation' keyword to allow
  their own private 'uses' clause }

{$ifdef OSWINDOWS}
  {$I mormot.net.sock.windows.inc}
{$endif OSWINDOWS}

{$ifdef OSPOSIX}
  {$I mormot.net.sock.posix.inc}
{$endif OSPOSIX}

const
  // we don't use RTTI to avoid linking mormot.core.rtti.pas
  _NR: array[TNetResult] of string[20] = (
    'OK',
    'Retry',
    'No Socket',
    'Not Found',
    'Not Implemented',
    'Closed',
    'Fatal Error',
    'Unknown Error',
    'Too Many Connections');

function NetLastError(AnotherNonFatal: integer = NO_ERROR;
  Error: PInteger = nil): TNetResult;
var
  err: integer;
begin
  err := sockerrno;
  if Error <> nil then
    Error^ := err;
  if err = NO_ERROR then
    result := nrOK
  else if {$ifdef OSWINDOWS}
          (err <> WSAETIMEDOUT) and
          (err <> WSAEWOULDBLOCK) and
          {$endif OSWINDOWS}
          (err <> WSATRY_AGAIN) and
          (err <> AnotherNonFatal) then
    if err = WSAEMFILE then
      result := nrTooManyConnections
    else
      result := nrFatalError
  else
    result := nrRetry;
end;

function NetLastErrorMsg(AnotherNonFatal: integer = NO_ERROR): shortstring;
var
  nr: TNetResult;
  err: integer;
begin
  nr := NetLastError(AnotherNonFatal, @err);
  str(err, result);
  result := _NR[nr] + ' ' + result;
end;

function NetCheck(res: integer): TNetResult;
  {$ifdef HASINLINE}inline;{$endif}
begin
  if res = NO_ERROR then
    result := nrOK
  else
    result := NetLastError;
end;

procedure IP4Short(ip4addr: PByteArray; var s: shortstring);
begin
  str(ip4addr[0], s);
  AppendShortChar('.', s);
  AppendShortInteger(ip4addr[1], s);
  AppendShortChar('.', s);
  AppendShortInteger(ip4addr[2], s);
  AppendShortChar('.', s);
  AppendShortInteger(ip4addr[3], s);
end;

procedure IP4Text(ip4addr: PByteArray; var result: RawUtf8);
var
  s: shortstring;
begin
  if PCardinal(ip4addr)^ = 0 then
    result := ''
  else if PCardinal(ip4addr)^ = cLocalhost32 then
    result := IP4local
  else
  begin
    IP4Short(ip4addr, s);
    FastSetString(result, @s[1], ord(s[0]));
  end;
end;

function ToText(res: TNetResult): PShortString;
begin
  result := @_NR[res];
end;


{ ENetSock }

class procedure ENetSock.Check(res: TNetResult; const Context: shortstring);
begin
  if (res <> nrOK) and
     (res <> nrRetry) then
    raise CreateFmt('%s: ''%s'' error', [Context, _NR[res]]);
end;

class procedure ENetSock.CheckLastError(const Context: shortstring;
  ForceRaise: boolean; AnotherNonFatal: integer);
var
  res: TNetResult;
begin
  res := NetLastError(AnotherNonFatal);
  if ForceRaise and
     (res in [nrOK, nrRetry]) then
    res := nrUnknownError;
  Check(res, Context);
end;



{ ******** TNetAddr Cross-Platform Wrapper }

{ TNetAddr }

function TNetAddr.Family: TNetFamily;
begin
  case PSockAddr(@Addr)^.sa_family of
    AF_INET:
      result := nfIP4;
    AF_INET6:
      result := nfIP6;
    {$ifdef OSPOSIX}
    AF_UNIX:
      result := nfUNIX;
    {$endif OSPOSIX}
    else
      result := nfUnknown;
  end;
end;

function TNetAddr.IP(localasvoid: boolean): RawUtf8;
var
  tmp: ShortString;
begin
  result := '';
  with PSockAddr(@Addr)^ do
    if sa_family = AF_INET then
      // check most common used values
      if cardinal(sin_addr) = 0 then
        exit
      else if cardinal(sin_addr) = cLocalhost32 then
      begin
        if not localasvoid then
          result := IP4local;
        exit;
      end;
  IPShort(tmp, {withport=}false);
  if not localasvoid or
     (tmp <> c6Localhost) then
    FastSetString(result, @tmp[1], ord(tmp[0]));
end;

function TNetAddr.IPShort(withport: boolean): shortstring;
begin
  IPShort(result, withport);
end;

procedure TNetAddr.IPShort(out result: shortstring; withport: boolean);
var
  host: array[0..NI_MAXHOST] of AnsiChar;
  serv: array[0..NI_MAXSERV] of AnsiChar;
  hostlen, servlen: integer;
begin
  result[0] := #0;
  case PSockAddr(@Addr)^.sa_family of
    AF_INET:
      begin
        IP4Short(@PSockAddr(@Addr)^.sin_addr, result);
        if withport then
        begin
          AppendShortChar(':', result);
          AppendShortInteger(port, result);
        end;
      end;
    AF_INET6:
      begin
        hostlen := NI_MAXHOST;
        servlen := NI_MAXSERV;
        if getnameinfo(@Addr, SizeOf(sockaddr_in6), host{%H-}, hostlen,
             serv{%H-}, servlen, NI_NUMERICHOST + NI_NUMERICSERV) = NO_ERROR then
        begin
          SetString(result, PAnsiChar(@host), mormot.core.base.StrLen(@host));
          if withport then
          begin
            AppendShortChar(':', result);
            AppendShortBuffer(PAnsiChar(@serv), -1, result);
          end;
        end;
      end;
    {$ifdef OSPOSIX}
    AF_UNIX:
      SetString(result, PAnsiChar(@psockaddr_un(@Addr)^.sun_path),
        mormot.core.base.StrLen(@psockaddr_un(@Addr)^.sun_path));
    {$endif OSPOSIX}
  end;
end;

function TNetAddr.Port: cardinal;
begin
  with PSockAddr(@Addr)^ do
    if sa_family in [AF_INET, AF_INET6] then
      result := swap(sin_port)
    else
      result := 0;
end;

function TNetAddr.SetPort(p: cardinal): TNetResult;
begin
  with PSockAddr(@Addr)^ do
    if (sa_family in [AF_INET, AF_INET6]) and
       (p <= 65535) then
    begin
      sin_port := swap(word(p)); // word() is mandatory
      result := nrOk;
    end
    else
      result := nrNotFound;
end;

function TNetAddr.Size: integer;
begin
  case PSockAddr(@Addr)^.sa_family of
    AF_INET:
      result := SizeOf(sockaddr_in);
    AF_INET6:
      result := SizeOf(sockaddr_in6);
  else
    result := SizeOf(Addr);
  end;
end;


{ ******** TNetSocket Cross-Platform Wrapper }

function NewSocket(const address, port: RawUtf8; layer: TNetLayer;
  dobind: boolean; connecttimeout, sendtimeout, recvtimeout, retry: integer;
  out netsocket: TNetSocket; netaddr: PNetAddr): TNetResult;
var
  addr: TNetAddr;
  sock: TSocket;
  fromcache, tobecached: boolean;
  p: cardinal;
begin
  netsocket := nil;
  fromcache := false;
  tobecached := false;
  // resolve the TNetAddr of the address:port layer - maybe from cache
  if (layer in nlIP) and
     (not dobind) and
     Assigned(NewSocketAddressCache) and
     ToCardinal(port, p, 1) then
    if (address = '') or
       (address = cLocalhost) or
       (address = cAnyHost) then // for client: '0.0.0.0'->'127.0.0.1'
      result := addr.SetFrom(cLocalhost, port, layer)
    else if NewSocketAddressCache.Search(address, addr) then
    begin
      fromcache := true;
      result := addr.SetPort(p);
    end
    else
    begin
      tobecached := true;
      result := addr.SetFrom(address, port, layer);
    end
  else
    result := addr.SetFrom(address, port, layer);
  if result <> nrOK then
    exit;
  // create the raw Socket instance
  sock := socket(PSockAddr(@addr)^.sa_family, _ST[layer], _IP[layer]);
  if sock = -1 then
  begin
    result := NetLastError(WSAEADDRNOTAVAIL);
    if fromcache then
      // force call the DNS resolver again, perhaps load-balacing is needed
      NewSocketAddressCache.Flush(address);
    exit;
  end;
  // bind or connect to this Socket
  repeat
    if dobind then
    begin
      // bound Socket should remain open for 5 seconds after a closesocket()
      TNetSocket(sock).SetLinger(5);
      // Server-side binding/listening of the socket to the address:port
      if (bind(sock, @addr, addr.Size)  <> NO_ERROR) or
         ((layer <> nlUDP) and
          (listen(sock, DefaultListenBacklog)  <> NO_ERROR)) then
        result := NetLastError(WSAEADDRNOTAVAIL);
    end
    else
    begin
      // open Client connection
      if connecttimeout > 0 then
      begin
        // set timeouts before connect()
        TNetSocket(sock).SetReceiveTimeout(connecttimeout);
        if recvtimeout = connecttimeout then
          recvtimeout := 0; // call SetReceiveTimeout() once
        TNetSocket(sock).SetSendTimeout(connecttimeout);
        if sendtimeout = connecttimeout then
          sendtimeout := 0; // call SetSendTimeout() once
      end;
      if connect(sock, @addr, addr.Size) <> NO_ERROR then
        result := NetLastError(WSAEADDRNOTAVAIL);
    end;
    if (result = nrOK) or
       (retry <= 0) then
      break;
    dec(retry);
    SleepHiRes(10);
  until false;
  if result <> nrOK then
  begin
    // this address:port seems invalid or already bound
    closesocket(sock);
    if fromcache then
      // ensure the cache won't contain this faulty address any more
      NewSocketAddressCache.Flush(address);
  end
  else
  begin
    // Socket is successfully connected -> setup the connection
    if tobecached then
      // update cache once we are sure the host actually exists
      NewSocketAddressCache.Add(address, addr);
    netsocket := TNetSocket(sock);
    netsocket.SetupConnection(layer, sendtimeout, recvtimeout);
    if netaddr <> nil then
      MoveFast(addr, netaddr^, addr.Size);
  end;
end;


{ TNetSocketWrap }

procedure TNetSocketWrap.SetOpt(prot, name: integer;
  value: pointer; valuelen: integer);
begin
  if @self = nil then
    raise ENetSock.CreateFmt('SetOptions(%d,%d) with no socket', [prot, name]);
  if setsockopt(TSocket(@self), prot, name, value, valuelen)  <> NO_ERROR then
    raise ENetSock.CreateFmt('SetOptions(%d,%d) failed as %s',
      [prot, name, NetLastErrorMsg]);
end;

procedure TNetSocketWrap.SetKeepAlive(keepalive: boolean);
var
  v: integer;
begin
  v := ord(keepalive);
  SetOpt(SOL_SOCKET, SO_KEEPALIVE, @v, SizeOf(v));
end;

procedure TNetSocketWrap.SetNoDelay(nodelay: boolean);
var
  v: integer;
begin
  v := ord(nodelay);
  SetOpt(IPPROTO_TCP, TCP_NODELAY, @v, SizeOf(v));
end;

procedure TNetSocketWrap.SetupConnection(layer: TNetLayer;
  sendtimeout, recvtimeout: integer);
begin
  if @self = nil then
    exit;
  if sendtimeout > 0 then
    SetSendTimeout(sendtimeout);
  if recvtimeout > 0 then
    SetReceiveTimeout(recvtimeout);
  if layer = nlTCP then
  begin
    SetNoDelay(true);   // disable Nagle algorithm (we use our own buffers)
    SetKeepAlive(true); // enabled TCP keepalive
  end;
end;

function TNetSocketWrap.Accept(out clientsocket: TNetSocket;
  out addr: TNetAddr): TNetResult;
var
  len: integer;
  sock: TSocket;
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    len := SizeOf(addr);
    sock := mormot.net.sock.accept(TSocket(@self), @addr, len);
    if sock = -1 then
    begin
      result := NetLastError;
      if result = nrOk then
        result := nrNotImplemented;
    end
    else
    begin
      clientsocket := TNetSocket(sock);
      result := nrOK;
    end;
  end;
end;

function TNetSocketWrap.GetPeer(out addr: TNetAddr): TNetResult;
var
  len: integer;
begin
  FillCharFast(addr, SizeOf(addr), 0);
  if @self = nil then
    result := nrNoSocket
  else
  begin
    len := SizeOf(addr);
    result := NetCheck(getpeername(TSocket(@self), @addr, len));
  end;
end;

function TNetSocketWrap.MakeAsync: TNetResult;
var
  nonblocking: cardinal;
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    nonblocking := 1;
    result := NetCheck(ioctlsocket(TSocket(@self), FIONBIO, @nonblocking));
  end;
end;

function TNetSocketWrap.Send(Buf: pointer; var len: integer): TNetResult;
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    len := mormot.net.sock.send(TSocket(@self), Buf, len, MSG_NOSIGNAL);
    if len < 0 then
      result := NetLastError
    else
      result := nrOK;
  end;
end;

function TNetSocketWrap.Recv(Buf: pointer; var len: integer): TNetResult;
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    len := mormot.net.sock.recv(TSocket(@self), Buf, len, 0);
    if len <= 0 then
      if len = 0 then
        result := nrClosed
      else
        result := NetLastError
    else
      result := nrOK;
  end;
end;

function TNetSocketWrap.SendTo(Buf: pointer; len: integer; out addr: TNetAddr): TNetResult;
begin
  if @self = nil then
    result := nrNoSocket
  else
    result := NetCheck(mormot.net.sock.sendto(TSocket(@self),
      Buf, len, 0, @addr, SizeOf(addr)));
end;

function TNetSocketWrap.RecvFrom(Buf: pointer; len: integer; out addr: TNetAddr): integer;
var
  addrlen: integer;
begin
  if @self = nil then
    result := -1
  else
  begin
    addrlen := SizeOf(addr);
    result := mormot.net.sock.recvfrom(TSocket(@self), Buf, len, 0, @addr, @addrlen);
  end;
end;

function TNetSocketWrap.RecvPending(out pending: integer): TNetResult;
begin
  if @self = nil then
    result := nrNoSocket
  else
    result := NetCheck(ioctlsocket(TSocket(@self), FIONREAD, @pending));
end;

function TNetSocketWrap.ShutdownAndClose(rdwr: boolean): TNetResult;
const
  SHUT_: array[boolean] of integer = (
    SHUT_RD, SHUT_RDWR);
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    {$ifdef OSLINUX}
    // on Linux close() is enough (e.g. nginx doesn't call shutdown)
    if rdwr then
    {$endif OSLINUX}
      shutdown(TSocket(@self), SHUT_[rdwr]);
    result := Close;
  end;
end;

function TNetSocketWrap.Close: TNetResult;
begin
  if @self = nil then
    result := nrNoSocket
  else
  begin
    closesocket(TSocket(@self)); // SO_LINGER usually set to 5 or 10 seconds
    result := nrOk;
  end;
end;

function TNetSocketWrap.Socket: PtrInt;
begin
  result := TSocket(@self);
end;


{ ******************** Efficient Multiple Sockets Polling }

{ TPollSocketAbstract }

class function TPollSocketAbstract.New: TPollSocketAbstract;
begin
  result := PollSocketClass.Create;
end;

constructor TPollSocketAbstract.Create;
begin
  // do nothing by default
end;


{ TPollSockets }

constructor TPollSockets.Create(aPollClass: TPollSocketClass);
begin
  inherited Create;
  InitializeCriticalSection(fPendingLock);
  InitializeCriticalSection(fPollLock);
  if aPollClass = nil then
    fPollClass := PollSocketClass
  else
    fPollClass := aPollClass;
  {$ifdef OSPOSIX}
  SetFileOpenLimit(GetFileOpenLimit(true)); // set soft limit to hard value
  {$endif OSPOSIX}
end;

destructor TPollSockets.Destroy;
var
  p: PtrInt;
  endtix: Int64; // never wait forever
begin
  Terminate;
  endtix := mormot.core.os.GetTickCount64 + 1000;
  while (fGettingOne > 0) and
        (mormot.core.os.GetTickCount64 < endtix) do
    SleepHiRes(1);
  for p := 0 to high(fPoll) do
    fPoll[p].Free;
  DeleteCriticalSection(fPendingLock);
  DeleteCriticalSection(fPollLock);
  inherited Destroy;
end;

function TPollSockets.Subscribe(socket: TNetSocket; events: TPollSocketEvents;
  tag: TPollSocketTag): boolean;
var
  p, n: PtrInt;
  poll: TPollSocketAbstract;
begin
  result := false;
  if (self = nil) or
     (socket = nil) or
     (events = []) then
    exit;
  EnterCriticalSection(fPollLock);
  try
    poll := nil;
    n := length(fPoll);
    for p := 0 to n - 1 do
      if fPoll[p].Count < fPoll[p].MaxSockets then
      begin
        poll := fPoll[p]; // stil some place in this poll instance
        break;
      end;
    if poll = nil then
    begin
      poll := fPollClass.Create;
      SetLength(fPoll, n + 1);
      fPoll[n] := poll;
    end;
    result := poll.Subscribe(socket, events, tag);
    if result then
      inc(fCount);
  finally
    LeaveCriticalSection(fPollLock);
  end;
end;

function TPollSockets.Unsubscribe(socket: TNetSocket; tag: TPollSocketTag): boolean;
var
  p: PtrInt;
begin
  result := false;
  EnterCriticalSection(fPendingLock);
  try
    for p := fPendingIndex to high(fPending) do
      if fPending[p].tag = tag then
        // event to be ignored in future GetOneWithinPending
        byte(fPending[p].events) := 0;
  finally
    LeaveCriticalSection(fPendingLock);
  end;
  EnterCriticalSection(fPollLock);
  try
    for p := 0 to high(fPoll) do
      if fPoll[p].Unsubscribe(socket) then
      begin
        dec(fCount);
        result := true;
        exit;
      end;
  finally
    LeaveCriticalSection(fPollLock);
  end;
end;

function TPollSockets.GetOneWithinPending(out notif: TPollSocketResult): boolean;
var
  last: PtrInt;
begin
  result := false;
  if fTerminated or
     (fPending = nil) then
    exit;
  EnterCriticalSection(fPendingLock);
  try
    last := high(fPending);
    while (fPendingIndex <= last) and
          (fPending <> nil) do
    begin
      // retrieve next notified event
      notif := fPending[fPendingIndex];
      // move forward
      if fPendingIndex < last then
        inc(fPendingIndex)
      else
      begin
        fPending := nil;
        fPendingIndex := 0;
      end;
      // return event (if not set to 0 by Unsubscribe)
      if byte(notif.events) <> 0 then
      begin
        result := true;
        exit;
      end;
    end;
  finally
    LeaveCriticalSection(fPendingLock);
  end;
end;

function TPollSockets.GetOne(timeoutMS: integer; out notif: TPollSocketResult): boolean;

  function PollAndSearchWithinPending(p: PtrInt): boolean;
  begin
    if not fTerminated and
       (fPoll[p].WaitForModified(fPending, {waitms=}0) > 0) then
    begin
      result := GetOneWithinPending(notif);
      if result then
        fPollIndex := p; // next call to continue from fPoll[fPollIndex+1]
    end
    else
      result := false;
  end;

var
  p, n: PtrInt;
  elapsed, start: Int64;
begin
  result := GetOneWithinPending(notif); // some events may be available
  if result or
     (timeoutMS < 0) then
    exit;
  LockedInc32(@fGettingOne);
  try
    byte(notif.events) := 0;
    if fTerminated then
      exit;
    if timeoutMS = 0 then
      start := 0
    else
      start := mormot.core.os.GetTickCount64;
    repeat
      // non-blocking search within all fPoll[] items
      if fCount > 0 then
      begin
        EnterCriticalSection(fPollLock);
        try
          // calls fPoll[].WaitForModified({waitms=}0) to refresh pending state
          n := length(fPoll);
          if n > 0 then
          begin
            for p := fPollIndex + 1 to n - 1 do
              // search from fPollIndex = last found
              if PollAndSearchWithinPending(p) then
                exit;
            for p := 0 to fPollIndex do
              // search from beginning up to fPollIndex
              if PollAndSearchWithinPending(p) then
                exit;
          end;
        finally
          LeaveCriticalSection(fPollLock);
          result := byte(notif.events) <> 0; // exit comes here -> set result
        end;
      end;
      // wait a little for something to happen
      if fTerminated or
         (timeoutMS = 0) then
        exit;
      elapsed := mormot.core.os.GetTickCount64 - start;
      if elapsed > timeoutMS then
        break;
      if elapsed > 300 then
        SleepHiRes(50)
      else if elapsed > 50 then
        SleepHiRes(10)
      else
        SleepHiRes(1);
      result := GetOneWithinPending(notif); // retrieved from another thread?
    until result or fTerminated;
  finally
    LockedDec32(@fGettingOne);
  end;
end;

procedure TPollSockets.Terminate;
begin
  if self <> nil then
    fTerminated := true;
end;


{ ********* TCrtSocket Buffered Socket Read/Write Class }

const
  UNIX_LOW = ord('u') + ord('n') shl 8 + ord('i') shl 16 + ord('x') shl 24;

function StartWith(p, up: PUtf8Char): boolean;
// to avoid linking mormot.core.text for IdemPChar()
var
  c, u: AnsiChar;
begin
  result := false;
  if (p = nil) or
     (up = nil) then
    exit;
  repeat
    u := up^;
    if u = #0 then
      break;
    inc(up);
    c := p^;
    inc(p);
    if c = u  then
      continue;
    if (c >= 'a') and
       (c <= 'z') then
    begin
      dec(c, 32);
      if c <> u then
        exit;
    end
    else
      exit;
  until false;
  result := true;
end;


{ TCrtSocket }

function TCrtSocket.GetRawSocket: PtrInt;
begin
  result := PtrInt(fSock);
end;

procedure TCrtSocket.SetKeepAlive(aKeepAlive: boolean);
begin
  fSock.SetKeepAlive(aKeepAlive);
end;

procedure TCrtSocket.SetLinger(aLinger: integer);
begin
  fSock.SetLinger(aLinger);
end;

procedure TCrtSocket.SetReceiveTimeout(aReceiveTimeout: integer);
begin
  fSock.SetReceiveTimeout(aReceiveTimeout);
end;

procedure TCrtSocket.SetSendTimeout(aSendTimeout: integer);
begin
  fSock.SetSendTimeout(aSendTimeout);
end;

procedure TCrtSocket.SetTCPNoDelay(aTCPNoDelay: boolean);
begin
  fSock.SetNoDelay(aTCPNoDelay);
end;

constructor TCrtSocket.Create(aTimeOut: PtrInt);
begin
  fTimeOut := aTimeOut;
end;

constructor TCrtSocket.Open(const aServer, aPort: RawUtf8;
  aLayer: TNetLayer; aTimeOut: cardinal; aTLS: boolean; aTLSContext: PNetTLSContext);
begin
  Create(aTimeOut); // default read timeout is 10 seconds
  if aTLSContext <> nil then
    TLS := aTLSContext^; // copy the input parameters before OpenBind()
  // OpenBind() raise an exception on error
  {$ifdef OSPOSIX}
  if StartWith(pointer(aServer), 'UNIX:') then
  begin
    // aServer='unix:/path/to/myapp.socket'
    OpenBind(copy(aServer, 6, 200), '', {dobind=}false, aTLS, nlUNIX);
    fServer := aServer; // keep the full server name if reused
  end
  else
  {$endif OSPOSIX}
    OpenBind(aServer, aPort, {dobind=}false, aTLS, aLayer);
end;

function SplitFromRight(const Text: RawUtf8; Sep: AnsiChar;
  var Before, After: RawUtf8): boolean;
var
  i: PtrInt;
begin
  for i := length(Text) - 1 downto 2 do // search Sep from right side
    if Text[i] = Sep then
    begin
      TrimCopy(Text, 1, i - 1, Before);
      TrimCopy(Text, i + 1, maxInt, After);
      result := true;
      exit;
    end;
  result := false;
end;

const
  BINDTXT: array[boolean] of string[4] = (
    'open', 'bind');
  BINDMSG: array[boolean] of string = (
    'is a server available on this address:port?',
    'another process may be currently listening to this port!');

constructor TCrtSocket.Bind(const aAddress: RawUtf8; aLayer: TNetLayer;
  aTimeOut: integer);
var
  s, p: RawUtf8;
  aSock: integer;
begin
  Create(aTimeOut);
  if aAddress = '' then
  begin
    {$ifdef OSLINUX} // try systemd activation
    if not sd.IsAvailable then
      raise ENetSock.Create('Bind('''') but Systemd is not available');
    if sd.listen_fds(0) > 1 then
      raise ENetSock.Create('Bind(''''): Systemd activation failed - too ' +
        'many file descriptors received');
    aSock := SD_LISTEN_FDS_START + 0;
    {$else}
    raise ENetSock.Create('Bind(''''), i.e. Systemd activation, is not allowed on this platform');
    {$endif OSLINUX}
  end
  else
  begin
    aSock := -1; // force OpenBind to create listening socket
    if not SplitFromRight(aAddress, ':', s, p) then
    begin
      s := '0.0.0.0';
      p := aAddress;
    end;
    {$ifdef OSPOSIX}
    if s = 'unix' then
    begin
      // aAddress='unix:/path/to/myapp.socket'
      FpUnlink(pointer(p)); // previous bind may have left the .socket file
      OpenBind(p, '', {dobind=}true, {tls=}false, nlUnix, {%H-}TNetSocket(aSock));
      exit;
    end;
    {$endif OSPOSIX}
  end;
  // next line will raise exception on error
  OpenBind(s{%H-}, p{%H-}, {dobind=}true, {tls=}false, aLayer, {%H-}TNetSocket(aSock));
end;

procedure TCrtSocket.OpenBind(const aServer, aPort: RawUtf8;
  doBind, aTLS: boolean; aLayer: TNetLayer; aSock: TNetSocket);
var
  retry: integer;
  res: TNetResult;
begin
  fSocketLayer := aLayer;
  fWasBind := doBind;
  if {%H-}PtrInt(aSock)<=0 then
  begin
    if (aPort = '') and
       (aLayer <> nlUNIX) then
      fPort := DEFAULT_PORT[aTLS] // default port is 80/443 (HTTP/S)
    else
      fPort := aPort;
    fServer := aServer;
    if doBind then
      // allow small number of retries (e.g. XP or BSD during aggressive tests)
      retry := 10
    else
      retry := {$ifdef OSBSD} 10 {$else} 2 {$endif};
    res := NewSocket(aServer, aPort, aLayer, doBind,
      Timeout, Timeout, Timeout, retry, fSock);
    if res <> nrOK then
      raise ENetSock.CreateFmt('OpenBind(%s:%s,%s) failed as ''%s'': %s',
        [aServer, fPort, BINDTXT[doBind], _NR[res], BINDMSG[doBind]]);
  end
  else
  begin
    fSock := aSock; // ACCEPT mode -> socket is already created by caller
    if TimeOut > 0 then
    begin
      // set timout values for both directions
      ReceiveTimeout := TimeOut;
      SendTimeout := TimeOut;
    end;
  end;
  if aLayer = nlTCP then
    if aTLS and
       not doBind and
       ({%H-}PtrInt(aSock) <= 0) then
    try
      if not Assigned(NewNetTLS) then
        raise ENetSock.Create('TLS is not available - try including ' +
          'mormot.lib.openssl11 and installing OpenSSL 1.1.1');
      fSecure := NewNetTLS;
      if fSecure = nil then
        raise ENetSock.Create('TLS is not available on this system - ' +
          'try installing OpenSSL 1.1.1');
      fSecure.AfterConnection(fSock, TLS, aServer);
      TLS.Enabled := true;
    except
      on E: Exception do
      begin
        fSecure := nil;
        raise ENetSock.CreateFmt('OpenBind(%s:%s,%s): TLS failed [%s %s]',
          [aServer, port, BINDTXT[doBind], ClassNameShort(E)^, E.Message]);
      end;
    end;
  if Assigned(OnLog) then
    OnLog(sllTrace, '%(%:%) sock=% %', [BINDTXT[doBind], fServer, fPort,
      fSock.Socket, TLS.CipherName], self);
end;

procedure TCrtSocket.AcceptRequest(aClientSock: TNetSocket; aClientAddr: PNetAddr);
begin
  {$ifdef OSLINUX}
  // on Linux fd returned from accept() inherits all parent fd options
  // except O_NONBLOCK and O_ASYNC
  fSock := aClientSock;
  {$else}
  // on other OS inheritance is undefined, so call OpenBind to set all fd options
  OpenBind('', '', {bind=}false, {tls=}false, fSocketLayer, aClientSock);
  // assign the ACCEPTed aClientSock to this TCrtSocket instance
  Linger := 5; // should remain open for 5 seconds after a closesocket() call
  {$endif OSLINUX}
  if aClientAddr <> nil then
    fRemoteIP := aClientAddr^.IP(RemoteIPLocalHostAsVoidInServers);
  {$ifdef OSLINUX}
  if Assigned(OnLog) then
    OnLog(sllTrace, 'Accept(%:%) sock=% %',
      [fServer, fPort, fSock.Socket, fRemoteIP], self);
  {$endif OSLINUX}
end;

const
  SOCKMINBUFSIZE = 1024; // big enough for headers (content will be read directly)

type
  PTextRec = ^TTextRec;
  PCrtSocket = ^TCrtSocket;

function OutputSock(var F: TTextRec): integer;
begin
  if F.BufPos = 0 then
    result := 0
  else if PCrtSocket(@F.UserData)^.TrySndLow(F.BufPtr, F.BufPos) then
  begin
    F.BufPos := 0;
    result := 0;
  end
  else
    result := -1; // on socket error -> raise ioresult error
end;

function InputSock(var F: TTextRec): integer;
// SockIn pseudo text file fill its internal buffer only with available data
// -> no unwanted wait time is added
// -> very optimized use for readln() in HTTP stream
var
  size: integer;
  sock: TCrtSocket;
begin
  F.BufEnd := 0;
  F.BufPos := 0;
  sock := PCrtSocket(@F.UserData)^;
  if not sock.SockIsDefined then
  begin
    result := WSAECONNABORTED; // on socket error -> raise ioresult error
    exit; // file closed = no socket -> error
  end;
  result := sock.fSockInEofError;
  if result <> 0 then
    exit; // already reached error below
  size := F.BufSize;
  if sock.SocketLayer = nlUDP then
    size := sock.Sock.RecvFrom(F.BufPtr, size, sock.fPeerAddr)
  else
    // nlTCP/nlUNIX
    if not sock.TrySockRecv(F.BufPtr, size, {StopBeforeLength=}true) then
      size := -1; // fatal socket error
  // TrySockRecv() may return size=0 if no data is pending, but no TCP/IP error
  if size >= 0 then
  begin
    F.BufEnd := size;
    inc(sock.fBytesIn, size);
    result := 0; // no error
  end
  else
  begin
    if not sock.SockIsDefined then // socket broken or closed
      result := WSAECONNABORTED
    else
    begin
      result := -sockerrno; // ioresult = low-level socket error as negative
      if result = 0 then
        result := WSAETIMEDOUT;
    end;
    sock.fSockInEofError := result; // error -> mark end of SockIn
    // result <0 will update ioresult and raise an exception if {$I+}
  end;
end;

function CloseSock(var F: TTextRec): integer;
begin
  if PCrtSocket(@F.UserData)^ <> nil then
    PCrtSocket(@F.UserData)^.Close;
  PCrtSocket(@F.UserData)^ := nil;
  result := 0;
end;

function OpenSock(var F: TTextRec): integer;
begin
  F.BufPos := 0;
  F.BufEnd := 0;
  if F.Mode = fmInput then
  begin
    // ReadLn
    F.InOutFunc := @InputSock;
    F.FlushFunc := nil;
  end
  else
  begin
    // WriteLn
    F.Mode := fmOutput;
    F.InOutFunc := @OutputSock;
    F.FlushFunc := @OutputSock;
  end;
  F.CloseFunc := @CloseSock;
  result := 0;
end;

{$ifdef FPC}
procedure SetLineBreakStyle(var T: Text; Style: TTextLineBreakStyle);
begin
  case Style of
    tlbsCR:
      TextRec(T).LineEnd := #13;
    tlbsLF:
      TextRec(T).LineEnd := #10;
    tlbsCRLF:
      TextRec(T).LineEnd := #13#10;
  end;
end;
{$endif FPC}

procedure TCrtSocket.CreateSockIn(LineBreak: TTextLineBreakStyle;
  InputBufferSize: integer);
begin
  if (Self = nil) or
     (SockIn <> nil) then
    exit; // initialization already occured
  if InputBufferSize < SOCKMINBUFSIZE then
    InputBufferSize := SOCKMINBUFSIZE;
  GetMem(fSockIn, sizeof(TTextRec) + InputBufferSize);
  FillCharFast(SockIn^, sizeof(TTextRec), 0);
  with TTextRec(SockIn^) do
  begin
    PCrtSocket(@UserData)^ := self;
    Mode := fmClosed;
    // ignore internal Buffer[], which is not trailing on latest Delphi and FPC
    BufSize := InputBufferSize;
    BufPtr := pointer(PAnsiChar(SockIn) + sizeof(TTextRec));
    OpenFunc := @OpenSock;
    Handle := {$ifdef FPC}THandle{$endif}(-1);
  end;
  SetLineBreakStyle(SockIn^, LineBreak); // http does break lines with #13#10
  Reset(SockIn^);
end;

procedure TCrtSocket.CreateSockOut(OutputBufferSize: integer);
begin
  if SockOut <> nil then
    exit; // initialization already occured
  if OutputBufferSize < SOCKMINBUFSIZE then
    OutputBufferSize := SOCKMINBUFSIZE;
  GetMem(fSockOut, sizeof(TTextRec) + OutputBufferSize);
  FillCharFast(SockOut^, sizeof(TTextRec), 0);
  with TTextRec(SockOut^) do
  begin
    PCrtSocket(@UserData)^ := self;
    Mode := fmClosed;
    BufSize := OutputBufferSize;
    BufPtr := pointer(PAnsiChar(SockIn) + sizeof(TTextRec)); // ignore Buffer[] (Delphi 2009+)
    OpenFunc := @OpenSock;
    Handle := {$ifdef FPC}THandle{$endif}(-1);
  end;
  SetLineBreakStyle(SockOut^, tlbsCRLF); // force e.g. for Linux platforms
  Rewrite(SockOut^);
end;

procedure TCrtSocket.CloseSockIn;
begin
  if (self <> nil) and
     (fSockIn <> nil) then
  begin
    Freemem(fSockIn);
    fSockIn := nil;
  end;
end;

procedure TCrtSocket.CloseSockOut;
begin
  if (self <> nil) and
     (fSockOut <> nil) then
  begin
    Freemem(fSockOut);
    fSockOut := nil;
  end;
end;

procedure TCrtSocket.Close;
begin
  if self = nil then
    exit;
  fSndBufLen := 0; // always reset (e.g. in case of further Open)
  fSockInEofError := 0;
  ioresult; // reset readln/writeln value
  if SockIn <> nil then
  begin
    PTextRec(SockIn)^.BufPos := 0;  // reset input buffer
    PTextRec(SockIn)^.BufEnd := 0;
  end;
  if SockOut <> nil then
  begin
    PTextRec(SockOut)^.BufPos := 0; // reset output buffer
    PTextRec(SockOut)^.BufEnd := 0;
  end;
  if not SockIsDefined then
    exit; // no opened connection, or Close already executed
  fSecure := nil; // perform the TLS shutdown round and release the TLS context
  {$ifdef OSLINUX}
  if not fWasBind or
     (fPort <> '') then // no explicit shutdown necessary on Linux server side
  {$endif OSLINUX}
    fSock.ShutdownAndClose({rdwr=}fWasBind);
  fSock := TNetSocket(-1);
  // don't reset fServer/fPort/fTls/fWasBind: caller may use them to reconnect
  // (see e.g. THttpClientSocket.Request)
  {$ifdef OSPOSIX}
  if fSocketLayer = nlUnix then
    FpUnlink(pointer(fServer)); // 'unix:/path/to/myapp.socket' -> delete file
  {$endif OSPOSIX}
end;

destructor TCrtSocket.Destroy;
begin
  Close;
  CloseSockIn;
  CloseSockOut;
  inherited Destroy;
end;

function TCrtSocket.SockInRead(Content: PAnsiChar; Length: integer;
  UseOnlySockIn: boolean): integer;
var
  len, res: integer;
// read Length bytes from SockIn^ buffer + Sock if necessary
begin
  // get data from SockIn buffer, if any (faster than ReadChar)
  result := 0;
  if Length <= 0 then
    exit;
  if SockIn <> nil then
    with PTextRec(SockIn)^ do
      repeat
        len := BufEnd - BufPos;
        if len > 0 then
        begin
          if len > Length then
            len := Length;
          MoveFast(BufPtr[BufPos], Content^, len);
          inc(BufPos, len);
          inc(Content, len);
          dec(Length, len);
          inc(result, len);
        end;
        if Length = 0 then
          exit; // we got everything we wanted
        if not UseOnlySockIn then
          break;
        res := InputSock(PTextRec(SockIn)^);
        if res < 0 then
          ENetSock.CheckLastError('SockInRead', {forceraise=}true);
        // loop until Timeout
      until Timeout = 0;
  // direct receiving of the remaining bytes from socket
  if Length > 0 then
  begin
    SockRecv(Content, Length); // raise ENetSock if failed to read Length
    inc(result, Length);
  end;
end;

function TCrtSocket.SockIsDefined: boolean;
begin
  result := (self <> nil) and
            ({%H-}PtrInt(fSock) > 0);
end;

function TCrtSocket.SockInPending(aTimeOutMS: integer;
  aPendingAlsoInSocket: boolean): integer;
var
  backup: PtrInt;
  insocket: integer;
begin
  if SockIn = nil then
    raise ENetSock.Create('SockInPending without SockIn');
  if aTimeOutMS < 0 then
    raise ENetSock.Create('SockInPending(aTimeOutMS<0)');
  with PTextRec(SockIn)^ do
    result := BufEnd - BufPos;
  if result = 0 then
    // no data in SockIn^.Buffer, so try if some pending at socket level
    case SockReceivePending(aTimeOutMS) of
      cspDataAvailable:
        begin
          backup := fTimeOut;
          fTimeOut := 0; // not blocking call to fill SockIn buffer
          try
            // call InputSock() to actually retrieve any pending data
            if InputSock(PTextRec(SockIn)^) = NO_ERROR then
              with PTextRec(SockIn)^ do
                result := BufEnd - BufPos
            else
              result := -1; // indicates broken socket
          finally
            fTimeOut := backup;
          end;
        end;
      cspSocketError:
        result := -1; // indicates broken/closed socket
    end; // cspNoData will leave result=0
  {$ifdef OSWINDOWS}
  // under Unix SockReceivePending use poll(fSocket) and if data available
  // ioctl syscall is redundant
  if aPendingAlsoInSocket then
    // also includes data in socket bigger than TTextRec's buffer
    if (sock.RecvPending(insocket) = nrOK) and
       (insocket > 0) then
      inc(result, insocket);
  {$endif OSWINDOWS}
end;

function TCrtSocket.SockConnected: boolean;
var
  addr: TNetAddr;
begin
  result := SockIsDefined and
            (fSock.GetPeer(addr) = nrOK);
end;

procedure TCrtSocket.SockSend(P: pointer; Len: integer);
var
  cap: integer;
begin
  if Len <= 0 then
    exit;
  cap := Length(fSndBuf);
  if Len + fSndBufLen > cap then
    SetLength(fSndBuf, Len + cap + cap shr 3 + 2048);
  MoveFast(P^, PByteArray(fSndBuf)[fSndBufLen], Len);
  inc(fSndBufLen, Len);
end;

procedure TCrtSocket.SockSendCRLF;
var
  cap: integer;
begin
  cap := Length(fSndBuf);
  if fSndBufLen + 2 > cap then
    SetLength(fSndBuf, cap + cap shr 3 + 2048);
  PWord(@PByteArray(fSndBuf)[fSndBufLen])^ := $0a0d;
  inc(fSndBufLen, 2);
end;

procedure TCrtSocket.SockSend(const Values: array of const);
var
  i: PtrInt;
  tmp: shortstring;
begin
  for i := 0 to high(Values) do
    with Values[i] do
      case VType of
        vtString:
          SockSend(@VString^[1], PByte(VString)^);
        vtAnsiString:
          SockSend(VAnsiString, Length(RawByteString(VAnsiString)));
        {$ifdef HASVARUSTRING}
        vtUnicodeString:
          begin
            Unicode_WideToShort(VUnicodeString, // assume WinAnsi encoding
              length(UnicodeString(VUnicodeString)), 1252, tmp);
            SockSend(@tmp[1], Length(tmp));
          end;
        {$endif HASVARUSTRING}
        vtPChar:
          SockSend(VPChar, StrLen(VPChar));
        vtChar:
          SockSend(@VChar, 1);
        vtWideChar:
          SockSend(@VWideChar, 1); // only ansi part of the character
        vtInteger:
          begin
            Str(VInteger, tmp);
            SockSend(@tmp[1], Length(tmp));
          end;
        vtInt64 {$ifdef FPC}, vtQWord{$endif} :
          begin
            Str(VInt64^, tmp);
            SockSend(@tmp[1], Length(tmp));
          end;
      end;
  SockSendCRLF;
end;

procedure TCrtSocket.SockSend(const Line: RawByteString);
begin
  if Line <> '' then
    SockSend(pointer(Line), Length(Line));
  SockSendCRLF;
end;

function TCrtSocket.SockSendRemainingSize: integer;
begin
  result := Length(fSndBuf) - fSndBufLen;
end;

procedure TCrtSocket.SockSendFlush(const aBody: RawByteString);
var
  body: integer;
begin
  body := Length(aBody);
  if (body > 0) and
     (SockSendRemainingSize >= body) then // around 1800 bytes
  begin
    MoveFast(pointer(aBody)^, PByteArray(fSndBuf)[fSndBufLen], body);
    inc(fSndBufLen, body); // append to buffer as single TCP packet
    body := 0;
  end;
  {$ifdef SYNCRTDEBUGLOW}
  if Assigned(OnLog) then
  begin
    OnLog(sllCustom2, 'SockSend sock=% flush len=% body=% %', [fSock.Socket, fSndBufLen,
      Length(aBody), LogEscapeFull(pointer(fSndBuf), fSndBufLen)], self);
    if body > 0 then
      OnLog(sllCustom2, 'SockSend sock=% body len=% %', [fSock.Socket, body,
        LogEscapeFull(pointer(aBody), body)], self);
  end;
  {$endif SYNCRTDEBUGLOW}
  if fSndBufLen > 0 then
    if TrySndLow(pointer(fSndBuf), fSndBufLen) then
      fSndBufLen := 0
    else
      raise ENetSock.CreateFmt('SockSendFlush(%s) len=%d %s',
        [fServer, fSndBufLen, NetLastErrorMsg]);
  if body > 0 then
    SndLow(pointer(aBody), body); // direct sending of biggest packets
end;

procedure TCrtSocket.SockRecv(Buffer: pointer; Length: integer);
var
  read: integer;
begin
  read := Length;
  if not TrySockRecv(Buffer, read, {StopBeforeLength=}false) or
     (Length <> read) then
    raise ENetSock.CreateFmt('SockRecv(%d) failure (read=%d)', [Length, read]);
end;

function TCrtSocket.SockReceivePending(TimeOutMS: integer): TCrtSocketPending;
var
  events: TNetEvents;
begin
  if SockIsDefined then
    events := fSock.WaitFor(TimeOutMS, [neRead])
  else
    events := [neError];
  if neError in events then
    result := cspSocketError
  else if neRead in events then
    result := cspDataAvailable
  else
    result := cspNoData;
end;

function TCrtSocket.SockReceiveString: RawByteString;
var
  available, resultlen, read: integer;
begin
  result := '';
  if not SockIsDefined then
    exit;
  resultlen := 0;
  repeat
    if fSock.RecvPending(available) <> nrOK then
      exit; // raw socket error
    if available = 0 then // no data in the allowed timeout
      if result = '' then
      begin
        // wait till something
        SleepHiRes(1); // some delay in infinite loop
        continue;
      end
      else
        break; // return what we have
    SetLength(result, resultlen + available); // append to result
    read := available;
    if not TrySockRecv(@PByteArray(result)[resultlen], read,
         {StopBeforeLength=}true) then
    begin
      Close;
      SetLength(result, resultlen);
      exit;
    end;
    inc(resultlen, read);
    if read < available then
      SetLength(result, resultlen); // e.g. Read=0 may happen
    SleepHiRes(0); // 10 microsecs on POSIX
  until false;
end;

function TCrtSocket.TrySockRecv(Buffer: pointer; var Length: integer;
  StopBeforeLength: boolean): boolean;
var
  expected, read: integer;
  now, last, diff: Int64;
  res: TNetResult;
begin
  result := false;
  if SockIsDefined and
     (Buffer <> nil) and
     (Length > 0) then
  begin
    expected := Length;
    Length := 0;
    last := {$ifdef OSWINDOWS}mormot.core.os.GetTickCount64{$else}0{$endif};
    repeat
      read := expected - Length;
      if fSecure <> nil then
        res := fSecure.Receive(Buffer, read)
      else
        res := fSock.Recv(Buffer, read);
      if res <> nrOK then
      begin
        // no more to read, or socket issue?
        {$ifdef SYNCRTDEBUGLOW}
        if Assigned(OnLog) then
          OnLog(sllCustom2, 'TrySockRecv: sock=% Recv=% %',
            [fSock.Socket, read, SocketErrorMessage], self);
        {$endif SYNCRTDEBUGLOW}
        if StopBeforeLength and
           (res = nrRetry) then
          break;
        Close; // connection broken or socket closed gracefully
        exit;
      end
      else
      begin
        inc(fBytesIn, read);
        inc(Length, read);
        if StopBeforeLength or
           (Length = expected) then
          break; // good enough for now
        inc(PByte(Buffer), read);
      end;
      now := mormot.core.os.GetTickCount64;
      if (last = 0) or
         (read > 0) then // check timeout from unfinished read
        last := now
      else
      begin
        diff := now - last;
        if diff >= TimeOut then
        begin
          if Assigned(OnLog) then
            OnLog(sllTrace, 'TrySockRecv: timeout (diff=%>%)',
              [diff, TimeOut], self);
          exit; // identify read timeout as error
        end;
        if diff < 100 then
          SleepHiRes(0)
        else
          SleepHiRes(1);
      end;
    until false;
    result := true;
  end;
end;

procedure TCrtSocket.SockRecvLn(out Line: RawUtf8; CROnly: boolean);

  procedure RecvLn(var Line: RawUtf8);
  var
    P: PAnsiChar;
    LP, L: PtrInt;
    tmp: array[0..1023] of AnsiChar; // avoid ReallocMem() every char
  begin
    P := @tmp;
    Line := '';
    repeat
      SockRecv(P, 1); // this is very slow under Windows -> use SockIn^ instead
      if P^ <> #13 then // at least NCSA 1.3 does send a #10 only -> ignore #13
        if P^ = #10 then
        begin
          if Line = '' then // get line
            FastSetString(Line, @tmp, P - tmp)
          else
          begin
            // append to already read chars
            LP := P - tmp;
            L := Length(Line);
            Setlength(Line, L + LP);
            MoveFast(tmp, PByteArray(Line)[L], LP);
          end;
          exit;
        end
        else if P = @tmp[1023] then
        begin
          // tmp[] buffer full? -> append to already read chars
          L := Length(Line);
          Setlength(Line, L + 1024);
          MoveFast(tmp, PByteArray(Line)[L], 1024);
          P := tmp;
        end
        else
          inc(P);
    until false;
  end;

var
  c: byte;
  L, Error: PtrInt;
begin
  if CROnly then
  begin
    // slower but accurate version expecting #13 as line end
    // SockIn^ expect either #10, either #13#10 -> a dedicated version is needed
    repeat
      SockRecv(@c, 1); // this is slow but works
      if c in [0, 13] then
        exit; // end of line
      L := Length({%H-}Line);
      SetLength(Line, L + 1);
      PByteArray(Line)[L] := c;
    until false;
  end
  else if SockIn <> nil then
  begin
    {$I-}
    readln(SockIn^, Line); // example: HTTP/1.0 200 OK
    Error := ioresult;
    if Error <> 0 then
      raise ENetSock.CreateFmt('SockRecvLn error %d after %d chars',
        [Error, Length(Line)]);
    {$I+}
  end
  else
    RecvLn(Line); // slow under Windows -> use SockIn^ instead
end;

procedure TCrtSocket.SockRecvLn;
var c: AnsiChar;
  Error: integer;
begin
  if SockIn <> nil then
  begin
    {$I-}
    readln(SockIn^);
    Error := ioresult;
    if Error <> 0 then
      raise ENetSock.CreateFmt('SockRecvLn error %d', [Error]);
    {$I+}
  end
  else
    repeat
      SockRecv(@c, 1);
    until c = #10;
end;

procedure TCrtSocket.SndLow(P: pointer; Len: integer);
begin
  if not TrySndLow(P, Len) then
    raise ENetSock.CreateFmt('SndLow(%s) len=%d %s',
      [fServer, Len, NetLastErrorMsg]);
end;

function TCrtSocket.TrySndLow(P: pointer; Len: integer): boolean;
var
  sent: integer;
  now, start: Int64;
  res: TNetResult;
begin
  result := Len = 0;
  if not SockIsDefined or
     (Len <= 0) or
     (P = nil) then
    exit;
  start := {$ifdef OSWINDOWS}mormot.core.os.GetTickCount64{$else}0{$endif};
  repeat
    sent := Len;
    if fSecure <> nil then
      res := fSecure.Send(P, Len)
    else
      res := fSock.Send(P, sent);
    if sent > 0 then
    begin
      inc(fBytesOut, sent);
      dec(Len, sent);
      if Len <= 0 then
        break;
      inc(PByte(P), sent);
    end
    else if (res <> nrOK) and
            (res <> nrRetry) then
      exit; // fatal socket error
    now := mormot.core.os.GetTickCount64;
    if (start = 0) or
       (sent > 0) then
      start := now
    else // measure timeout since nothing written
      if now - start > TimeOut then
        exit; // identify timeout as error
    SleepHiRes(1);
  until false;
  result := true;
end;

function TCrtSocket.LastLowSocketError: integer;
begin
  result := sockerrno;
end;

procedure TCrtSocket.Write(const Data: RawByteString);
begin
  SndLow(pointer(Data), Length(Data));
end;

function TCrtSocket.AcceptIncoming(ResultClass: TCrtSocketClass): TCrtSocket;
var
  client: TNetSocket;
  addr: TNetAddr;
begin
  result := nil;
  if not SockIsDefined then
    exit;
  if fSock.Accept(client, addr) <> nrOK then
    exit;
  if ResultClass = nil then
    ResultClass := TCrtSocket;
  result := ResultClass.Create(Timeout);
  result.AcceptRequest(client, @addr);
  result.CreateSockIn; // use SockIn with 1KB input buffer: 2x faster
end;

function TCrtSocket.PeerAddress(LocalAsVoid: boolean): RawByteString;
begin
  result := fPeerAddr.IP(LocalAsVoid);
end;

function TCrtSocket.PeerPort: integer;
begin
  result := fPeerAddr.Port;
end;


{ TUri }

procedure TUri.Clear;
begin
  Https := false;
  layer := nlTCP;
  Finalize(self);
end;

function TUri.From(aUri: RawUtf8; const DefaultPort: RawUtf8): boolean;
var
  P, S: PAnsiChar;
begin
  Clear;
  result := false;
  aUri := TrimU(aUri);
  if aUri = '' then
    exit;
  P := pointer(aUri);
  S := P;
  while S^ in ['a'..'z', 'A'..'Z', '+', '-', '.', '0'..'9'] do
    inc(S);
  if PInteger(S)^ and $ffffff = ord(':') + ord('/') shl 8 + ord('/') shl 16 then
  begin
    FastSetString(Scheme, P, S - P);
    if StartWith(pointer(P), 'HTTPS') then
      Https := true;
    P := S + 3;
  end;
  S := P;
  if (PInteger(S)^ = UNIX_LOW) and
     (S[4] = ':') then
  begin
    inc(S, 5); // 'http://unix:/path/to/socket.sock:/url/path'
    inc(P, 5);
    layer := nlUNIX;
    while not (S^ in [#0, ':']) do
      inc(S); // Server='path/to/socket.sock'
  end
  else
    while not (S^ in [#0, ':', '/']) do
      inc(S);
  FastSetString(Server, P, S - P);
  if S^ = ':' then
  begin
    inc(S);
    P := S;
    while not (S^ in [#0, '/']) do
      inc(S);
    FastSetString(Port, P, S - P); // Port='' for nlUNIX
  end
  else if DefaultPort <> '' then
    port := DefaultPort
  else
    port := DEFAULT_PORT[Https];
  if S^ <> #0 then // ':' or '/'
    inc(S);
  Address := S;
  if Server <> '' then
    result := true;
end;

function TUri.Uri: RawUtf8;
const
  Prefix: array[boolean] of RawUtf8 = (
    'http://', 'https://');
begin
  if layer = nlUNIX then
    result := 'http://unix:' + Server + ':/' + address
  else if (port = '') or
          (port = '0') or
          (port = DEFAULT_PORT[Https]) then
    result := Prefix[Https] + Server + '/' + address
  else
    result := Prefix[Https] + Server + ':' + port + '/' + address;
end;

function TUri.PortInt: integer;
begin
  result := GetCardinal(pointer(port));
end;

function TUri.Root: RawUtf8;
var
  i: PtrInt;
begin
  i := PosExChar('?', address);
  if i = 0 then
    Root := address
  else
    Root := copy(address, 1, i - 1);
end;

function SocketOpen(const aServer, aPort: RawUtf8; aTLS: boolean;
  aTLSContext: PNetTLSContext): TCrtSocket;
begin
  try
    result := TCrtSocket.Open(aServer, aPort, nlTCP, 10000, aTLS, aTLSContext);
  except
    result := nil;
  end;
end;


initialization
  IP4local := cLocalhost; // use var string with refcount=1 to avoid allocation
  assert(SizeOf(in_addr) = 4);
  assert(SizeOf(in6_addr) = 16);
  assert(SizeOf(sockaddr_in) = 16);
  assert(SizeOf(TNetAddr) = SOCKADDR_SIZE);
  assert(SizeOf(TNetAddr) >=
    {$ifdef OSWINDOWS} SizeOf(sockaddr_in6) {$else} SizeOf(sockaddr_un) {$endif});
  DefaultListenBacklog := SOMAXCONN;
  InitializeUnit; // in mormot.net.sock.windows.inc

finalization
  FinalizeUnit;
  
end.


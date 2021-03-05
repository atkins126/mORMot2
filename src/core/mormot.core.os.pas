/// Framework Core Low-Level Wrappers to the Operating-System API
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.core.os;

{
  *****************************************************************************

  Cross-platform functions shared by all framework units
  - Gather Operating System Information
  - Operating System Specific Types (e.g. TWinRegistry)
  - Unicode, Time, File, Console, Library process
  - Per Class Properties O(1) Lookup via vmtAutoTable Slot (e.g. for RTTI cache)
  - TSynLocker/TSynLocked and Low-Level Threading Features
  - Unix Daemon and Windows Service Support

   Aim of this unit is to centralize most used OS-specific API calls, like a
  SysUtils unit on steroids, to avoid $ifdef/$endif in "uses" clauses.
   In practice, no "Windows", nor "Linux/Posix" reference should be needed in
  regular units, once mormot.core.os is included. :)
   This unit only refers to mormot.core.base so can be used almost stand-alone.

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

uses
  {$ifdef OSWINDOWS}
  Windows, // needed here e.g. for redefinition of standard types
  Messages,
  {$endif OSWINDOWS}
  classes,
  contnrs,
  syncobjs,
  types,
  sysutils,
  mormot.core.base;


{ ****************** Gather Operating System Information }

type
  /// Exception types raised by this mormot.core.os unit
  EOSException = class(Exception);

  /// the recognized operating systems
  // - it will also recognize most Linux distributions
  TOperatingSystem = (
    osUnknown,
    osWindows,
    osLinux,
    osOSX,
    osBSD,
    osPOSIX,
    osArch,
    osAurox,
    osDebian,
    osFedora,
    osGentoo,
    osKnoppix,
    osMint,
    osMandrake,
    osMandriva,
    osNovell,
    osUbuntu,
    osSlackware,
    osSolaris,
    osSuse,
    osSynology,
    osTrustix,
    osClear,
    osUnited,
    osRedHat,
    osLFS,
    osOracle,
    osMageia,
    osCentOS,
    osCloud,
    osXen,
    osAmazon,
    osCoreOS,
    osAlpine,
    osAndroid);

  /// the recognized Windows versions
  // - defined even outside MSWINDOWS to access e.g. from monitoring tools
  TWindowsVersion = (
    wUnknown,
    w2000,
    wXP,
    wXP_64,
    wServer2003,
    wServer2003_R2,
    wVista,
    wVista_64,
    wServer2008,
    wServer2008_64,
    wSeven,
    wSeven_64,
    wServer2008_R2,
    wServer2008_R2_64,
    wEight,
    wEight_64,
    wServer2012,
    wServer2012_64,
    wEightOne,
    wEightOne_64,
    wServer2012R2,
    wServer2012R2_64,
    wTen,
    wTen_64,
    wServer2016,
    wServer2016_64,
    wServer2019_64,
    wServer2022_64);

  /// the running Operating System, encoded as a 32-bit integer
  TOperatingSystemVersion = packed record
    case os: TOperatingSystem of
    osUnknown: (
      b: array[0..2] of byte);
    osWindows: (
      win: TWindowsVersion);
    osLinux: (
      utsrelease: array[0..2] of byte);
  end;

const
  /// the recognized Windows versions, as plain text
  // - defined even outside MSWINDOWS to allow process e.g. from monitoring tools
  WINDOWS_NAME: array[TWindowsVersion] of RawUtf8 = (
    '', '2000', 'XP', 'XP 64bit', 'Server 2003', 'Server 2003 R2',
    'Vista', 'Vista 64bit', 'Server 2008', 'Server 2008 64bit',
    '7', '7 64bit', 'Server 2008 R2', 'Server 2008 R2 64bit',
    '8', '8 64bit', 'Server 2012', 'Server 2012 64bit',
    '8.1', '8.1 64bit', 'Server 2012 R2', 'Server 2012 R2 64bit',
    '10', '10 64bit', 'Server 2016', 'Server 2016 64bit',
    'Server 2019 64bit', 'Server 2022 64bit');

  /// the recognized Windows versions which are 32-bit
  WINDOWS_32 = [
     w2000, wXP, wServer2003, wServer2003_R2, wVista, wServer2008,
     wSeven, wServer2008_R2, wEight, wServer2012, wEightOne, wServer2012R2,
     wTen, wServer2016];

  /// translate one operating system (and distribution) into a its common name
  OS_NAME: array[TOperatingSystem] of RawUtf8 = (
    'Unknown', 'Windows', 'Linux', 'OSX', 'BSD', 'POSIX',
    'Arch', 'Aurox', 'Debian', 'Fedora', 'Gentoo', 'Knoppix', 'Mint', 'Mandrake',
    'Mandriva', 'Novell', 'Ubuntu', 'Slackware', 'Solaris', 'Suse', 'Synology',
    'Trustix', 'Clear', 'United', 'RedHat', 'LFS', 'Oracle', 'Mageia', 'CentOS',
    'Cloud', 'Xen', 'Amazon', 'CoreOS', 'Alpine', 'Android');

  /// translate one operating system (and distribution) into a single character
  // - may be used internally e.g. for a HTTP User-Agent header, as with
  // TFileVersion.UserAgent
  OS_INITIAL: array[TOperatingSystem] of AnsiChar = (
    '?', 'W', 'L', 'X', 'B', 'P', 'A', 'a', 'D', 'F', 'G', 'K', 'M', 'm',
    'n', 'N', 'U', 'S', 's', 'u', 'Y', 'T', 'C', 't', 'R', 'l', 'O', 'G',
    'c', 'd', 'x', 'Z', 'r', 'p', 'J'); // for Android: J=JVM

  /// the operating systems items which actually have a Linux kernel
  OS_LINUX = [
    osLinux, osArch .. osAndroid];

  /// the compiler family used
  COMP_TEXT = {$ifdef FPC}'Fpc'{$else}'Delphi'{$endif};

  /// the target Operating System used for compilation, as short text
  OS_TEXT =
    {$ifdef OSWINDOWS}
      'Win';
    {$else} {$ifdef OSDARWIN}
      'OSX';
    {$else}{$ifdef OSBSD}
      'BSD';
    {$else} {$ifdef OSANDROID}
      'Android';
    {$else} {$ifdef OSLINUX}
      'Linux';
    {$else}
       'Posix';
    {$endif OSLINUX}
    {$endif OSANDROID}
    {$endif OSBSD}
    {$endif OSDARWIN}
    {$endif OSWINDOWS}

  /// the CPU architecture used for compilation
  CPU_ARCH_TEXT =
    {$ifdef CPUX86}
      'x86'
    {$else} {$ifdef CPUX64}
      'x64'
    {$else} {$ifdef CPUARM3264}
      'arm' +
    {$else} {$ifdef CPUPOWERPC}
      'ppc' +
    {$else} {$ifdef CPUSPARC}
      'sparc' +
    {$endif CPUSPARC}
    {$endif CPUPOWERPC}
    {$endif CPUARM3264}
    {$ifdef CPU32}
      '32'
    {$else}
      '64'
    {$endif CPU32}
    {$endif CPUX64}
    {$endif CPUX86};

var
  /// the target Operating System used for compilation, as TOperatingSystem
  // - a specific Linux distribution may be detected instead of plain osLinux
  OS_KIND: TOperatingSystem =
    {$ifdef OSWINDOWS}
      osWindows
    {$else} {$ifdef OSDARWIN}
      osOSX
    {$else} {$ifdef OSBSD}
      osBSD
    {$else} {$ifdef OSANDROID}
      osAndroid
    {$else} {$ifdef OSLINUX}
      osLinux
    {$else}
      osPOSIX
    {$endif OSLINUX}
    {$endif OSANDROID}
    {$endif OSBSD}
    {$endif OSDARWIN}
    {$endif OSWINDOWS};

  /// the current Operating System version, as retrieved for the current process
  // - contains e.g. 'Windows Seven 64 SP1 (6.1.7601)' or
  // 'Ubuntu 16.04.5 LTS - Linux 3.13.0 110 generic#157 Ubuntu SMP Mon Feb 20 11:55:25 UTC 2017'
  OSVersionText: RawUtf8;
  /// some addition system information as text, e.g. 'Wine 1.1.5'
  // - also always appended to OSVersionText high-level description
  // - use if PosEx('Wine', OSVersionInfoEx) > 0 then to check for Wine presence
  OSVersionInfoEx: RawUtf8;
  /// the current Operating System version, as retrieved for the current process
  // and computed by ToTextOS(OSVersionInt32)
  // - returns e.g. 'Windows Vista' or 'Ubuntu 5.4.0'
  OSVersionShort: RawUtf8;

  /// some textual information about the current CPU
  CpuInfoText: RawUtf8;
  /// some textual information about the current computer hardware, from BIOS
  BiosInfoText: RawUtf8;

  /// the running Operating System
  OSVersion32: TOperatingSystemVersion;
  /// the running Operating System, encoded as a 32-bit integer
  OSVersionInt32: integer absolute OSVersion32;

/// convert an Operating System type into its text representation
// - returns e.g. 'Windows Vista' or 'Ubuntu'
function ToText(const osv: TOperatingSystemVersion): RawUtf8; overload;

/// convert a 32-bit Operating System type into its full text representation
// including the kernel revision (not the distribution version) on POSIX systems
// - returns e.g. 'Windows Vista' or 'Ubuntu 5.4.0'
function ToTextOS(osint32: integer): RawUtf8;


const
  /// contains the Delphi/FPC Compiler Version as text
  // - e.g. 'Delphi 10.3 Rio', 'Delphi 2010' or 'Free Pascal 3.3.1'
  COMPILER_VERSION: RawUtf8 =
  {$ifdef FPC}
    'Free Pascal'
    {$ifdef VER2_6_4} + ' 2.6.4'{$endif}
    {$ifdef VER3_0}   + ' 3.0'  {$ifdef VER3_0_4} + '.4' {$else}
    {$ifdef VER3_0_2} + '.2'    {$endif} {$endif} {$endif}
    {$ifdef VER3_1}   + ' 3.1'  {$ifdef VER3_1_1} + '.1' {$endif} {$endif}
    {$ifdef VER3_2}   + ' 3.2'  {$endif}
    {$ifdef VER3_3}   + ' 3.3'  {$ifdef VER3_3_1} + '.1' {$endif} {$endif}
    {$ifdef VER3_4}   + ' 3.4'  {$endif}
  {$else}
    'Delphi'
    {$ifdef CONDITIONALEXPRESSIONS}  // Delphi 6 or newer
      {$if     defined(VER140)} + ' 6'
      {$elseif defined(VER150)} + ' 7'
      {$elseif defined(VER160)} + ' 8'
      {$elseif defined(VER170)} + ' 2005'
      {$elseif defined(VER185)} + ' 2007'
      {$elseif defined(VER180)} + ' 2006'
      {$elseif defined(VER200)} + ' 2009'
      {$elseif defined(VER210)} + ' 2010'
      {$elseif defined(VER220)} + ' XE'
      {$elseif defined(VER230)} + ' XE2'
      {$elseif defined(VER240)} + ' XE3'
      {$elseif defined(VER250)} + ' XE4'
      {$elseif defined(VER260)} + ' XE5'
      {$elseif defined(VER265)} + ' AppMethod 1'
      {$elseif defined(VER270)} + ' XE6'
      {$elseif defined(VER280)} + ' XE7'
      {$elseif defined(VER290)} + ' XE8'
      {$elseif defined(VER300)} + ' 10 Seattle'
      {$elseif defined(VER310)} + ' 10.1 Berlin'
      {$elseif defined(VER320)} + ' 10.2 Tokyo'
      {$elseif defined(VER330)} + ' 10.3 Rio'
      {$elseif defined(VER340)} + ' 10.4 Sydney'
      {$elseif defined(VER350)} + ' 10.5 Next'
      {$ifend}
    {$endif CONDITIONALEXPRESSIONS}
  {$endif FPC}
  {$ifdef CPU64} + ' 64 bit' {$else} + ' 32 bit' {$endif};

{$ifndef PUREMORMOT2}
/// deprecated function: use COMPILER_VERSION constant instead
function GetDelphiCompilerVersion: RawUtf8; deprecated;
{$endif PUREMORMOT2}

{$ifdef OSWINDOWS}

{$ifdef UNICODE}

const
  /// a global constant to be appended for Windows Ansi or wide API names
  _AW = 'W';

{$else}

const
  /// a global constant to be appended for Windows Ansi or wide API names
  _AW = 'A';

type
  /// low-level API structure, not defined in old Delphi versions
  TOSVersionInfoEx = record
    dwOSVersionInfoSize: DWORD;
    dwMajorVersion: DWORD;
    dwMinorVersion: DWORD;
    dwBuildNumber: DWORD;
    dwPlatformId: DWORD;
    szCSDVersion: array[0..127] of char;
    wServicePackMajor: WORD;
    wServicePackMinor: WORD;
    wSuiteMask: WORD;
    wProductType: BYTE;
    wReserved: BYTE;
  end;

{$endif UNICODE}

var
  /// is set to TRUE if the current process is a 32-bit image running under WOW64
  // - WOW64 is the x86 emulator that allows 32-bit Windows-based applications
  // to run seamlessly on 64-bit Windows
  // - equals always FALSE if the current executable is a 64-bit image
  IsWow64: boolean;
  /// the current System information, as retrieved for the current process
  // - under a WOW64 process, it will use the GetNativeSystemInfo() new API
  // to retrieve the real top-most system information
  // - note that the lpMinimumApplicationAddress field is replaced by a
  // more optimistic/realistic value ($100000 instead of default $10000)
  // - under BSD/Linux, only contain dwPageSize and dwNumberOfProcessors fields
  SystemInfo: TSystemInfo;
  /// low-level Operating System information, as retrieved for the current process
  OSVersionInfo: TOSVersionInfoEx;
  /// the current Windows edition, as retrieved for the current process
  OSVersion: TWindowsVersion;

{$else OSWINDOWS}

var
  /// emulate only some used fields of Windows' TSystemInfo
  SystemInfo: record
    // retrieved from libc's getpagesize() - is expected to not be 0
    dwPageSize: cardinal;
    // retrieved from HW_NCPU (BSD) or /proc/cpuinfo (Linux)
    dwNumberOfProcessors: cardinal;
    // meaningful system information, as returned by fpuname()
    uts: record
      sysname, release, version: RawUtf8;
    end;
    /// Linux Distribution release name, retrieved from /etc/*-release
    release: RawUtf8;
  end;
  
{$endif OSWINDOWS}

{$M+} // to have existing RTTI for published properties

type
  /// used to retrieve version information from any EXE
  // - under Linux, all version numbers are set to 0 by default, unless
  // you define the FPCUSEVERSIONINFO conditional and information is
  // extracted from executable resources
  // - you should not have to use this class directly, but via the
  // Executable global variable
  TFileVersion = class
  protected
    fDetailed: string;
    fFileName: TFileName;
    fBuildDateTime: TDateTime;
    fVersionInfo, fUserAgent: RawUtf8;
    /// change the version (not to be used in most cases)
    procedure SetVersion(aMajor, aMinor, aRelease, aBuild: integer);
  public
    /// executable major version number
    Major: integer;
    /// executable minor version number
    Minor: integer;
    /// executable release version number
    Release: integer;
    /// executable release build number
    Build: integer;
    /// build year of this exe file
    BuildYear: word;
    /// version info of the exe file as '3.1'
    // - return "string" type, i.e. UnicodeString for Delphi 2009+
    Main: string;
    /// associated CompanyName string version resource
    CompanyName: RawUtf8;
    /// associated FileDescription string version resource
    FileDescription: RawUtf8;
    /// associated FileVersion string version resource
    FileVersion: RawUtf8;
    /// associated InternalName string version resource
    InternalName: RawUtf8;
    /// associated LegalCopyright string version resource
    LegalCopyright: RawUtf8;
    /// associated OriginalFileName string version resource
    OriginalFilename: RawUtf8;
    /// associated ProductName string version resource
    ProductName: RawUtf8;
    /// associated ProductVersion string version resource
    ProductVersion: RawUtf8;
    /// associated Comments string version resource
    Comments: RawUtf8;
    /// associated Language Translation string version resource
    LanguageInfo: RawUtf8;
    /// retrieve application version from exe file name
    // - DefaultVersion32 is used if no information Version was included into
    // the executable resources (on compilation time)
    // - you should not have to use this constructor, but rather access the
    // Executable global variable
    constructor Create(const aFileName: TFileName; aMajor: integer = 0;
      aMinor: integer = 0; aRelease: integer = 0; aBuild: integer = 0);
    /// retrieve the version as a 32-bit integer with Major.Minor.Release
    // - following Major shl 16+Minor shl 8+Release bit pattern
    function Version32: integer;
    /// build date and time of this exe file, as plain text
    function BuildDateTimeString: string;
    /// version info of the exe file as '3.1.0.123' or ''
    // - this method returns '' if Detailed is '0.0.0.0'
    function DetailedOrVoid: string;
    /// returns the version information of this exe file as text
    // - includes FileName (without path), Detailed and BuildDateTime properties
    // - e.g. 'myprogram.exe 3.1.0.123 (2016-06-14 19:07:55)'
    function VersionInfo: RawUtf8;
    /// returns a ready-to-use User-Agent header with exe name, version and OS
    // - e.g. 'myprogram/3.1.0.123W32' for myprogram running on Win32
    // - here OS_INITIAL[] character is used to identify the OS, with '32'
    // appended on Win32 only (e.g. 'myprogram/3.1.0.2W', is for Win64)
    function UserAgent: RawUtf8;
    /// returns the version information of a specified exe file as text
    // - includes FileName (without path), Detailed and BuildDateTime properties
    // - e.g. 'myprogram.exe 3.1.0.123 2016-06-14 19:07:55'
    class function GetVersionInfo(const aFileName: TFileName): RawUtf8;
  published
    /// version info of the exe file as '3.1.0.123'
    // - return "string" type, i.e. UnicodeString for Delphi 2009+
    // - under Linux, always return '0.0.0.0' if no custom version number
    // has been defined
    // - consider using DetailedOrVoid method if '0.0.0.0' is not expected
    property Detailed: string
      read fDetailed write fDetailed;
    /// build date and time of this exe file
    property BuildDateTime: TDateTime
      read fBuildDateTime write fBuildDateTime;
  end;

{$M-}

type
  /// stores some global information about the current executable and computer
  TExecutable = record
    /// the main executable name, without any path nor extension
    // - e.g. 'Test' for 'c:\pathto\Test.exe'
    ProgramName: RawUtf8;
    /// the main executable details, as used e.g. by TSynLog
    // - e.g. 'C:\Dev\lib\SQLite3\exe\TestSQL3.exe 1.2.3.123 (2011-03-29 11:09:06)'
    ProgramFullSpec: RawUtf8;
    /// the main executable file name (including full path)
    // - same as paramstr(0)
    ProgramFileName: TFileName;
    /// the main executable full path (excluding .exe file name)
    // - same as ExtractFilePath(paramstr(0))
    ProgramFilePath: TFileName;
    /// the full path of the running executable or library
    // - for an executable, same as paramstr(0)
    // - for a library, will contain the whole .dll file name
    InstanceFileName: TFileName;
    /// the current executable version
    Version: TFileVersion;
    /// the current computer host name
    Host: RawUtf8;
    /// the current computer user name
    User: RawUtf8;
    /// some hash representation of this information
    // - the very same executable on the very same computer run by the very
    // same user will always have the same Hash value
    // - is computed from the crc32c of this TExecutable fields: c0 from
    // Version32, CpuFeatures and Host, c1 from User, c2 from ProgramFullSpec
    // and c3 from InstanceFileName
    // - may be used as an entropy seed, or to identify a process execution
    Hash: THash128Rec;
  end;

var
  /// global information about the current executable and computer
  // - this structure is initialized in this unit's initialization block below
  // - you can call SetExecutableVersion() with a custom version, if needed
  Executable: TExecutable;

  {$ifndef PUREMORMOT2}
  /// deprecated global: use Executable variable instead
  ExeVersion: TExecutable absolute Executable;
  {$endif PUREMORMOT2}

/// initialize Executable global variable, supplying a custom version number
// - by default, the version numbers will be retrieved at startup from the
// executable itself (if it was included at build time)
// - but you can use this function to set any custom version numbers
procedure SetExecutableVersion(aMajor,aMinor,aRelease,aBuild: integer); overload;

/// initialize Executable global variable, supplying the version as text
// - e.g. SetExecutableVersion('7.1.2.512');
procedure SetExecutableVersion(const aVersionText: RawUtf8); overload;

/// return a function/method location according to the supplied code address
// - returns the address as hexadecimal by default, e.g. '004cb765'
// - if mormot.core.log.pas is defined in the project, will redirect to
// TDebugFile.FindLocationShort() method using .map/.dbg/.mab information, and
// return filename, symbol name and line number (if any) as plain text, e.g.
// '4cb765 ../src/core/mormot.core.base.pas statuscodeissuccess (11183)' on FPC
var
  GetExecutableLocation: function(aAddress: pointer): shortstring;


type
  /// identify an operating system folder
  TSystemPath = (
    spCommonData,
    spUserData,
    spCommonDocuments,
    spUserDocuments,
    spTempFolder,
    spLog);

/// returns an operating system folder
// - will return the full path of a given kind of private or shared folder,
// depending on the underlying operating system
// - will use SHGetFolderPath and the corresponding CSIDL constant under Windows
// - under POSIX, will return $TMP/$TMPDIR folder for spTempFolder, ~/.cache/appname
// for spUserData, /var/log for spLog, or the $HOME folder
// - returned folder name contains the trailing path delimiter (\ or /)
function GetSystemPath(kind: TSystemPath): TFileName;



{ ****************** Operating System Specific Types (e.g. TWinRegistry) }

{$ifdef OSWINDOWS}

type
  TThreadID = DWORD;
  TMessage = Messages.TMessage;
  HWND = Windows.HWND;
  LARGE_INTEGER = Windows.LARGE_INTEGER;
  BOOL = Windows.BOOL;

  /// the known Windows Registry Root key used by TWinRegistry.Open
  TWinRegistryRoot = (
    wrClasses,
    wrCurrentUser,
    wrLocalMachine,
    wrUsers);

  /// direct access to the Windows Registry
  // - could be used as alternative to TRegistry, which doesn't behave the same on
  // all Delphi versions, and is enhanced on FPC (e.g. which supports REG_MULTI_SZ)
  // - is also Unicode ready for text, using UTF-8 conversion on all compilers
  TWinRegistry = object
  public
    /// the opened HKEY handle
    key: HKEY;
    /// start low-level read access to a Windows Registry node
    // - on success (returned true), ReadClose() should be called
    function ReadOpen(root: TWinRegistryRoot; const keyname: RawUtf8;
      closefirst: boolean = false): boolean;
    /// finalize low-level read access to the Windows Registry after ReadOpen()
    procedure Close;
    /// low-level read a UTF-8 string from the Windows Registry after ReadOpen()
    // - in respect to Delphi's TRegistry, will properly handle REG_MULTI_SZ
    // (return the first value of the multi-list)
    // - we don't use string here since it would induce a dependency to
    // mormot.core.unicode
    function ReadString(const entry: SynUnicode; andtrim: boolean = true): RawUtf8;
    /// low-level read a Windows Registry content after ReadOpen()
    // - works with any kind of key, but was designed for REG_BINARY
    function ReadData(const entry: SynUnicode): RawByteString;
    /// low-level read a Windows Registry 32-bit REG_DWORD value after ReadOpen()
    function ReadDword(const entry: SynUnicode): cardinal;
    /// low-level read a Windows Registry 64-bit REG_QWORD value after ReadOpen()
    function ReadQword(const entry: SynUnicode): QWord;
    /// low-level read a Windows Registry content as binary buffer after ReadOpen()
    // - just a wrapper around RegQueryValueExW() API call
    function ReadBuffer(const entry: SynUnicode; Data: pointer; DataLen: DWORD): boolean;
    /// low-level enumeration of all sub-entries names of a Windows Registry key
    function ReadEnumEntries: TRawUtf8DynArray;
  end;

  /// TSynWindowsPrivileges enumeration synchronized with WinAPI
  // - see https://docs.microsoft.com/en-us/windows/desktop/secauthz/privilege-constants
  TWinSystemPrivilege = (
    wspCreateToken,
    wspAssignPrimaryToken,
    wspLockMemory,
    wspIncreaseQuota,
    wspUnsolicitedInput,
    wspMachineAccount,
    wspTCP,
    wspSecurity,
    wspTakeOwnership,
    wspLoadDriver,
    wspSystemProfile,
    wspSystemTime,
    wspProfSingleProcess,
    wspIncBasePriority,
    wspCreatePageFile,
    wspCreatePermanent,
    wspBackup,
    wspRestore,
    wspShutdown,
    wspDebug,
    wspAudit,
    wspSystemEnvironment,
    wspChangeNotify,
    wspRemoteShutdown,
    wspUndock,
    wspSyncAgent,
    wspEnableDelegation,
    wspManageVolume,
    wspImpersonate,
    wspCreateGlobal,
    wspTrustedCredmanAccess,
    wspRelabel,
    wspIncWorkingSet,
    wspTimeZone,
    wspCreateSymbolicLink);

  /// TSynWindowsPrivileges set synchronized with WinAPI
  TWinSystemPrivileges = set of TWinSystemPrivilege;

  /// TSynWindowsPrivileges enumeration synchronized with WinAPI
  // - define the execution context, i.e. if the token is used for current
  // process or the current thread
  TPrivilegeTokenType = (
    pttProcess,
    pttThread);

  /// object dedicated to management of available privileges on Windows platform
  // - not all available privileges are active for process
  // - for usage of more advanced WinAPI, explicit enabling of privilege is
  // sometimes needed
  TSynWindowsPrivileges = object
  private
    fAvailable: TWinSystemPrivileges;
    fEnabled: TWinSystemPrivileges;
    fDefEnabled: TWinSystemPrivileges;
    function SetPrivilege(
      aPrivilege: TWinSystemPrivilege; aEnablePrivilege: boolean): boolean;
    procedure LoadPrivileges;
  public
    /// handle to privileges token
    Token: THandle;
    /// initialize the object dedicated to management of available privileges
    // - aTokenPrivilege can be used for current process or current thread
    procedure Init(aTokenPrivilege: TPrivilegeTokenType = pttProcess);
    /// finalize the object and relese Token handle
    // - aRestoreInitiallyEnabled parameter can be used to restore initially
    // state of enabled privileges
    procedure Done(aRestoreInitiallyEnabled: boolean = true);
    /// enable privilege
    // - if aPrivilege is already enabled return true, if operation is not
    // possible (required privilege doesn't exist or API error) return false
    function Enable(aPrivilege: TWinSystemPrivilege): boolean;
    /// disable privilege
    // - if aPrivilege is already disabled return true, if operation is not
    // possible (required privilege doesn't exist or API error) return false
    function Disable(aPrivilege: TWinSystemPrivilege): boolean;
    /// set of available privileges for current process/thread
    property Available: TWinSystemPrivileges
      read fAvailable;
    /// set of enabled privileges for current process/thread
    property Enabled: TWinSystemPrivileges
      read fEnabled;
  end;

  /// which information was returned by GetProcessInfo() overloaded functions
  TWinProcessAvailableInfos = set of (
    wpaiPID,
    wpaiBasic,
    wpaiPEB,
    wpaiCommandLine,
    wpaiImagePath);

  /// information returned by GetProcessInfo() overloaded functions
  TWinProcessInfo = record
    AvailableInfo: TWinProcessAvailableInfos;
    PID: cardinal;
    ParentPID: cardinal;
    SessionID: cardinal;
    PEBBaseAddress: Pointer;
    AffinityMask: cardinal;
    BasePriority: integer;
    ExitStatus: integer;
    BeingDebugged: byte;
    ImagePath: SynUnicode;
    CommandLine: SynUnicode;
  end;

  PWinProcessInfo = ^TWinProcessInfo;
  TWinProcessInfoDynArray = array of TWinProcessInfo;


/// retrieve low-level process information, from the Windows API
procedure GetProcessInfo(aPid: cardinal;
  out aInfo: TWinProcessInfo); overload;

/// retrieve low-level process(es) information, from the Windows API
procedure GetProcessInfo(const aPidList: TCardinalDynArray;
  out aInfo: TWinProcessInfoDynArray); overload;


type
  HCRYPTPROV = pointer;
  HCRYPTKEY = pointer;
  HCRYPTHASH = pointer;

  /// direct access to the Windows CryptoApi
  TWinCryptoApi = object
  private
    /// if the presence of this API has been tested
    Tested: boolean;
    /// if this API has been loaded
    Handle: THandle;
    /// used when inlining Available method
    procedure Resolve;
  public
    /// acquire a handle to a particular key container within a
    // particular cryptographic service provider (CSP)
    AcquireContextA: function(var phProv: HCRYPTPROV; pszContainer: PAnsiChar;
      pszProvider: PAnsiChar; dwProvType: DWORD; dwFlags: DWORD): BOOL; stdcall;
    /// releases the handle of a cryptographic service provider (CSP) and a
    // key container
    ReleaseContext: function(hProv: HCRYPTPROV; dwFlags: PtrUInt): BOOL; stdcall;
    /// transfers a cryptographic key from a key BLOB into a cryptographic
    // service provider (CSP)
    ImportKey: function(hProv: HCRYPTPROV; pbData: pointer; dwDataLen: DWORD;
      hPubKey: HCRYPTKEY; dwFlags: DWORD; var phKey: HCRYPTKEY): BOOL; stdcall;
    /// customizes various aspects of a session key's operations
    SetKeyParam: function(hKey: HCRYPTKEY; dwParam: DWORD; pbData: pointer;
      dwFlags: DWORD): BOOL; stdcall;
    /// releases the handle referenced by the hKey parameter
    DestroyKey: function(hKey: HCRYPTKEY): BOOL; stdcall;
    /// encrypt the data designated by the key held by the CSP module
    // referenced by the hKey parameter
    Encrypt: function(hKey: HCRYPTKEY; hHash: HCRYPTHASH; Final: BOOL;
      dwFlags: DWORD; pbData: pointer; var pdwDataLen: DWORD; dwBufLen: DWORD): BOOL; stdcall;
    /// decrypts data previously encrypted by using the CryptEncrypt function
    Decrypt: function(hKey: HCRYPTKEY; hHash: HCRYPTHASH; Final: BOOL;
      dwFlags: DWORD; pbData: pointer; var pdwDataLen: DWORD): BOOL; stdcall;
    /// fills a buffer with cryptographically random bytes
    // - since Windows Vista with Service Pack 1 (SP1), an AES counter-mode
    // based PRNG specified in NIST Special Publication 800-90 is used
    GenRandom: function(hProv: HCRYPTPROV; dwLen: DWORD; pbBuffer: Pointer): BOOL; stdcall;
    /// try to load the CryptoApi on this system
    function Available: boolean;
      {$ifdef HASINLINE}inline;{$endif}
  end;

const
  NO_ERROR = Windows.NO_ERROR;
  ERROR_ACCESS_DENIED = Windows.ERROR_ACCESS_DENIED;
  ERROR_INVALID_PARAMETER = Windows.ERROR_INVALID_PARAMETER;
  INVALID_HANDLE_VALUE = Windows.INVALID_HANDLE_VALUE;
  
  PROV_RSA_AES = 24;
  CRYPT_NEWKEYSET = 8;
  PLAINTEXTKEYBLOB = 8;
  CUR_BLOB_VERSION = 2;
  KP_IV = 1;
  KP_MODE = 4;
  CALG_AES_128 = $660E;
  CALG_AES_192 = $660F;
  CALG_AES_256 = $6610;
  CRYPT_MODE_CBC = 1;
  CRYPT_MODE_ECB = 2;
  CRYPT_MODE_OFB = 3;
  CRYPT_MODE_CFB = 4;
  CRYPT_MODE_CTS = 5;
  HCRYPTPROV_NOTTESTED = HCRYPTPROV(-1);
  NTE_BAD_KEYSET = HRESULT($80090016);
  PROV_RSA_FULL = 1;
  CRYPT_VERIFYCONTEXT = DWORD($F0000000);

var
  CryptoApi: TWinCryptoApi;

/// protect some data for the current user, using Windows DPAPI
// - the application can specify a secret salt text, which should reflect the
// current execution context, to ensure nobody could decrypt the data without
// knowing this application-specific AppSecret value
// - will use CryptProtectData DPAPI function call under Windows
// - see https://msdn.microsoft.com/en-us/library/ms995355
// - this function is Windows-only, could be slow, and you don't know which
// algorithm is really used on your system, so using our mormot.core.crypto.pas
// CryptDataForCurrentUser() is probably a better (and cross-platform) alternative
// - also note that DPAPI has been closely reverse engineered - see e.g.
// https://www.passcape.com/index.php?section=docsys&cmd=details&id=28
function CryptDataForCurrentUserDPAPI(const Data, AppSecret: RawByteString;
  Encrypt: boolean): RawByteString;

/// this global procedure should be called from each thread needing to use OLE
// - it is called e.g. by TOleDBConnection.Create when an OleDb connection
// is instantiated for a new thread
// - every call of CoInit shall be followed by a call to CoUninit
// - implementation will maintain some global counting, to call the CoInitialize
// API only once per thread
// - only made public for user convenience, e.g. when using custom COM objects
procedure CoInit;

/// this global procedure should be called at thread termination
// - it is called e.g. by TOleDBConnection.Destroy, when thread associated
// to an OleDb connection is terminated
// - every call of CoInit shall be followed by a call to CoUninit
// - only made public for user convenience, e.g. when using custom COM objects
procedure CoUninit;

/// retrieves the current executable module handle, i.e.  its memory load address
// - redefined in mormot.core.os to avoid dependency to Windows
function GetModuleHandle(lpModuleName: PChar): HMODULE;

/// post a message to the Windows message queue
// - redefined in mormot.core.os to avoid dependency to Windows
function PostMessage(hWnd: HWND; Msg:UINT; wParam: WPARAM; lParam: LPARAM): BOOL;

/// retrieves the current stack trace
// - only available since Windows XP
// - FramesToSkip + FramesToCapture should be <= 62
function RtlCaptureStackBackTrace(FramesToSkip, FramesToCapture: cardinal;
  BackTrace, BackTraceHash: pointer): byte; stdcall;

/// compatibility function, wrapping Win32 API available since XP
function IsDebuggerPresent: BOOL; stdcall;

/// retrieves the current thread ID
// - redefined in mormot.core.os to avoid dependency to Windows
function GetCurrentThreadId: DWORD; stdcall;

/// retrieves the current process ID
// - redefined in mormot.core.os to avoid dependency to Windows
function GetCurrentProcessId: DWORD; stdcall;

/// redefined in mormot.core.os to avoid dependency to Windows
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD; stdcall;

/// redefined in mormot.core.os to avoid dependency to Windows
function GetEnvironmentStringsW: PWideChar; stdcall;

/// redefined in mormot.core.os to avoid dependency to Windows
function FreeEnvironmentStringsW(EnvBlock: PWideChar): BOOL; stdcall;

/// expand any embedded environment variables, i.e %windir%
function ExpandEnvVars(const aStr: string): string;

/// try to enter a Critical Section (Lock)
// - redefined in mormot.core.os to avoid dependency to Windows
// - under Delphi/Windows, directly call the homonymous Win32 API
function TryEnterCriticalSection(var cs: TRTLCriticalSection): integer; stdcall;

/// enter a Critical Section (Lock)
// - redefined in mormot.core.os to avoid dependency to Windows
// - under Delphi/Windows, directly call the homonymous Win32 API
procedure EnterCriticalSection(var cs: TRTLCriticalSection); stdcall;

/// leave a Critical Section (UnLock)
// - redefined in mormot.core.os to avoid dependency to Windows
// - under Delphi/Windows, directly call the homonymous Win32 API
procedure LeaveCriticalSection(var cs: TRTLCriticalSection); stdcall;

/// initialize IOCP instance
// - redefined in mormot.core.os to avoid dependency to Windows
function CreateIoCompletionPort(FileHandle, ExistingCompletionPort: THandle;
  CompletionKey: pointer; NumberOfConcurrentThreads: DWORD): THandle; stdcall;

/// retrieve IOCP instance status
// - redefined in mormot.core.os to avoid dependency to Windows
function GetQueuedCompletionStatus(CompletionPort: THandle;
  var lpNumberOfBytesTransferred: DWORD; var lpCompletionKey: PtrUInt;
  var lpOverlapped: pointer; dwMilliseconds: DWORD): BOOL; stdcall;

/// trigger a IOCP instance
// - redefined in mormot.core.os to avoid dependency to Windows
function PostQueuedCompletionStatus(CompletionPort: THandle;
  NumberOfBytesTransferred: DWORD; dwCompletionKey: pointer;
  lpOverlapped: POverlapped): BOOL; stdcall;

/// finalize a Windows resource (e.g. IOCP instance)
// - redefined in mormot.core.os to avoid dependency to Windows
function CloseHandle(hObject: THandle): BOOL; stdcall;

/// redefined here to avoid warning to include "Windows" in uses clause
// - why did Delphi define this slow RTL function as inlined in SysUtils.pas?
function FileCreate(const aFileName: TFileName): THandle;

/// redefined here to avoid warning to include "Windows" in uses clause
// - why did Delphi define this slow RTL function as inlined in SysUtils.pas?
procedure FileClose(F: THandle); stdcall;

/// redefined here to avoid warning to include "Windows" in uses clause
// - why did Delphi define this slow RTL function as inlined in SysUtils.pas?
function DeleteFile(const aFileName: TFileName): boolean;

/// redefined here to avoid warning to include "Windows" in uses clause
// - why did Delphi define this slow RTL function as inlined in SysUtils.pas?
function RenameFile(const OldName, NewName: TFileName): boolean;

{$else}

/// returns how many files could be opened at once on this POSIX system
// - hard=true is for the maximum allowed limit, false for the current process
// - returns -1 if the getrlimit() API call failed
function GetFileOpenLimit(hard: boolean = false): integer;

/// changes how many files could be opened at once on this POSIX system
// - hard=true is for the maximum allowed limit (requires root priviledges),
// false for the current process
// - returns the new value set (may not match the expected max value on error)
// - returns -1 if the getrlimit().setrlimit() API calls failed
// - for instance, to set the limit of the current process to its highest value:
// ! SetFileOpenLimit(GetFileOpenLimit(true));
function SetFileOpenLimit(max: integer; hard: boolean = false): integer;

type
  /// Low-level access to the ICU library installed on this system
  // - "International Components for Unicode" (ICU) is an open-source set of
  // libraries for Unicode support, internationalization and globalization
  // - used by Unicode_CompareString, Unicode_AnsiToWide, Unicode_WideToAnsi,
  // Unicode_InPlaceUpper and Unicode_InPlaceLower function from this unit
  TIcuLibrary = packed object
  protected
    icu, icudata, icui18n: pointer;
    Loaded: boolean;
    procedure DoLoad(const LibName: TFileName = ''; const Version: string = '');
    procedure Done;
  public
    /// Initialize an ICU text converter for a given encoding
    ucnv_open: function (converterName: PAnsiChar; var err: SizeInt): pointer; cdecl;
    /// finalize the ICU text converter for a given encoding
    ucnv_close: procedure (converter: pointer); cdecl;
    /// customize the ICU text converter substitute char
    ucnv_setSubstChars: procedure (converter: pointer;
      subChars: PAnsiChar; len: byte; var err: SizeInt); cdecl;
    /// enable the ICU text converter fallback
    ucnv_setFallback: procedure (cnv: pointer; usesFallback: LongBool); cdecl;
    /// ICU text conversion from UTF-16 to a given encoding
    ucnv_fromUChars: function (cnv: pointer; dest: PAnsiChar; destCapacity: cardinal;
      src: PWideChar; srcLength: cardinal; var err: SizeInt): cardinal; cdecl;
    /// ICU text conversion from a given encoding to UTF-16
    ucnv_toUChars: function (cnv: pointer; dest: PWideChar; destCapacity: cardinal;
      src: PAnsiChar; srcLength: cardinal; var err: SizeInt): cardinal; cdecl;
    /// ICU UTF-16 text conversion to uppercase
    u_strToUpper: function (dest: PWideChar; destCapacity: cardinal;
      src: PWideChar; srcLength: cardinal; locale: PAnsiChar;
      var err: SizeInt): cardinal; cdecl;
    /// ICU UTF-16 text conversion to lowercase
    u_strToLower: function (dest: PWideChar; destCapacity: cardinal;
      src: PWideChar; srcLength: cardinal; locale: PAnsiChar;
      var err: SizeInt): cardinal; cdecl;
    /// ICU UTF-16 text comparison
    u_strCompare: function (s1: PWideChar; length1: cardinal;
      s2: PWideChar; length2: cardinal; codePointOrder: LongBool): cardinal; cdecl;
    /// ICU UTF-16 text comparison with options, e.g. for case-insensitive
    u_strCaseCompare: function (s1: PWideChar; length1: cardinal;
      s2: PWideChar; length2: cardinal; options: cardinal;
      var err: SizeInt): cardinal; cdecl;
    /// get the ICU data folder
    u_getDataDirectory: function: PAnsiChar; cdecl;
    /// set the ICU data folder
    u_setDataDirectory: procedure(directory: PAnsiChar); cdecl;
    /// initialize the ICU library
    u_init: procedure(var status: SizeInt); cdecl;
    /// try to initialize a specific version of the ICU library
    // - first finalize any existing loaded instance
    // - returns true if was successfully loaded and setup
    function ForceLoad(const LibName: TFileName; const Version: string): boolean;
    /// returns TRUE if a ICU library is available on this system
    // - will thread-safely load and initialize it if necessary
    function IsAvailable: boolean; inline;
    /// Initialize an ICU text converter for a given codepage
    // - returns nil if ICU is not available on this system
    // - wrapper around ucnv_open/ucnv_setSubstChars/ucnv_setFallback calls
    // - caller should make ucnv_close() once done with the returned instance
    function ucnv(codepage: cardinal): pointer;
  end;

var
  /// low-level late-binding access to any installed ICU library
  // - typical use is to check icu.IsAvailable then the proper icu.*() functions
  // - this unit will make icu.Done in its finalization section
  icu: TIcuLibrary;


{$ifdef OSLINUX} { the systemd API is Linux-specific }

const
  /// The first passed file descriptor is fd 3
  SD_LISTEN_FDS_START = 3;

  /// low-level libcurl library file name, depending on the running OS
  LIBSYSTEMD_PATH = 'libsystemd.so.0';

  ENV_INVOCATION_ID: PAnsiChar = 'INVOCATION_ID';

type
  /// low-level systemd parameter to sd.journal_sendv() function
  TIoVec = record
    iov_base: pointer;
    iov_len: PtrUInt;
  end;

  /// implements late-binding of the systemd library
  // - about systemd: see https://www.freedesktop.org/wiki/Software/systemd
  // and http://0pointer.de/blog/projects/socket-activation.html - to get headers
  // on debian: `sudo apt install libsystemd-dev && cd /usr/include/systemd`
  TSystemD = packed object
  private
    systemd: pointer;
    tested: boolean;
    procedure DoLoad;
  public
    /// returns how many file descriptors have been passed to process
    // - if result=1 then socket for accepting connection is LISTEN_FDS_START
    listen_fds: function(unset_environment: integer): integer; cdecl;
    /// returns 1 if the file descriptor is an AF_UNIX socket of the specified type and path
    is_socket_unix: function(fd, typr, listening: integer;
      var path: TFileName; pathLength: PtrUInt): integer; cdecl;
    /// systemd: submit simple, plain text log entries to the system journal
    // - priority value can be obtained using integer(LOG_TO_SYSLOG[logLevel])
    journal_print: function(priority: integer; args: array of const): integer; cdecl;
    /// systemd: submit array of iov structures instead of the format string to the system journal.
    //  - each structure should reference one field of the entry to submit.
    //  - the second argument specifies the number of structures in the array.
    journal_sendv: function(var iov: TIoVec; n: integer): integer; cdecl;
    /// sends notification to systemd
    // - see https://www.freedesktop.org/software/systemd/man/notify.html
    // status notification sample: sd.notify(0, 'READY=1');
    // watchdog notification: sd.notify(0, 'WATCHDOG=1');
    notify: function(unset_environment: integer; state: PUtf8Char): integer; cdecl;
    /// check whether the service manager expects watchdog keep-alive
    // notifications from a service
    // - if result > 0 then usec contains the notification interval (app should
    // notify every usec/2)
    watchdog_enabled: function(unset_environment: integer; usec: Puint64): integer; cdecl;
    /// returns true in case the current process was started by systemd
    // - For systemd v232+
    function ProcessIsStartedBySystemd: boolean;
    /// returns TRUE if a systemd library is available
    // - will thread-safely load and initialize it if necessary
    function IsAvailable: boolean; inline;
    /// release the systemd library
    procedure Done;
  end;

var
  /// low-level late-binding of the systemd library
  // - typical use is to check sd.IsAvailable then the proper sd.*() functions
  // - this unit will make sd.Done in its finalization section
  sd: TSystemD;

{$endif OSLINUX}

{$endif OSWINDOWS}


{ ****************** Unicode, Time, File, Console, Library process }

{$ifdef OSWINDOWS}

type
  /// redefined as our own mormot.core.os type to avoid dependency to Windows
  // - warning: do use this type directly, but rather TSynSystemTime as
  // defined in mormot.core.datetime which is really cross-platform, and has
  // consistent field order (FPC POSIX/Windows fields do not match!)
  TSystemTime = Windows.TSystemTime;

{$ifdef ISDELPHI}

  /// redefined as our own mormot.core.os type to avoid dependency to Windows
  TRTLCriticalSection = Windows.TRTLCriticalSection;

  /// defined as in FPC RTL, to avoid dependency to Windows.pas unit
  TLibHandle = THandle;

{$endif ISDELPHI}

/// returns the current UTC time as TSystemTime
// - under Delphi/Windows, directly call the homonymous Win32 API
// - redefined in mormot.core.os to avoid dependency to Windows
// - you should call directly FPC's version otherwise
// - warning: do not call this function directly, but use TSynSystemTime as
// defined in mormot.core.datetime which is really cross-platform
procedure GetLocalTime(out result: TSystemTime); stdcall;

{$endif OSWINDOWS}

/// raw cross-platform library loading function
// - alternative to LoadLibrary() Windows API and FPC RTL
// - consider inheriting TSynLibrary if you want to map a set of API functions
function LibraryOpen(const LibraryName: TFileName): TLibHandle;

/// raw cross-platform library unloading function
// - alternative to FreeLibrary() Windows API and FPC RTL
procedure LibraryClose(Lib: TLibHandle);

/// raw cross-platform library resolution function, as defined in FPC RTL
// - alternative to GetProcAddr() Windows API and FPC RTL
function LibraryResolve(Lib: TLibHandle; ProcName: PAnsiChar): pointer;
  {$ifdef OSWINDOWS} stdcall; {$endif}


const
  /// redefined here to avoid dependency to Windows or SyncObjs
  INFINITE = cardinal(-1);

/// initialize a Critical Section (for Lock/UnLock)
// - redefined in mormot.core.os to avoid dependency to Windows
// - under Delphi/Windows, directly call the homonymous Win32 API
procedure InitializeCriticalSection(var cs : TRTLCriticalSection);
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// finalize a Critical Section (for Lock/UnLock)
// - redefined in mormot.core.os to avoid dependency to Windows
// - under Delphi/Windows, directly call the homonymous Win32 API
procedure DeleteCriticalSection(var cs : TRTLCriticalSection);
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// returns TRUE if the supplied mutex has been initialized
// - will check if the supplied mutex is void (i.e. all filled with 0 bytes)
function IsInitializedCriticalSection(var cs: TRTLCriticalSection): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// on need initialization of a mutex, then enter the lock
// - if the supplied mutex has been initialized, do nothing
// - if the supplied mutex is void (i.e. all filled with 0), initialize it
procedure InitializeCriticalSectionIfNeededAndEnter(var cs: TRTLCriticalSection);
  {$ifdef HASINLINE}inline;{$endif}

/// on need finalization of a mutex
// - if the supplied mutex has been initialized, delete it
// - if the supplied mutex is void (i.e. all filled with 0), do nothing
procedure DeleteCriticalSectionIfNeeded(var cs: TRTLCriticalSection);

/// returns the current UTC time as TSystemTime
// - under Linux/POSIX, calls clock_gettime(CLOCK_REALTIME_COARSE) if available
// - under Windows, directly call the homonymous Win32 API
// - warning: do not call this function directly, but use TSynSystemTime as
// defined in mormot.core.datetime which is really cross-platform
procedure GetSystemTime(out result: TSystemTime);
  {$ifdef OSWINDOWS} stdcall; {$endif}

/// compatibility function, wrapping Win32 API file truncate at current position
procedure SetEndOfFile(F: THandle);
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// compatibility function, wrapping Win32 API file flush to disk
procedure FlushFileBuffers(F: THandle);
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// compatibility function, wrapping Win32 API last error code
function GetLastError: integer;
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// compatibility function, wrapping Win32 API last error code
procedure SetLastError(error: integer);
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// returns a given error code as plain text
// - calls FormatMessageW on Windows, or StrError() on POSIX
function GetErrorText(error: integer): RawUtf8;

/// retrieve the text corresponding to an error message for a given Windows module
// - use RTL SysErrorMessage() as fallback
function SysErrorMessagePerModule(Code: cardinal; ModuleName: PChar): string;

/// raise an Exception from the last system error
procedure RaiseLastModuleError(ModuleName: PChar; ModuleException: ExceptClass);

/// compatibility function, wrapping Win32 API function
// - returns the current main Window handle on Windows, or 0 on POSIX/Linux
function GetDesktopWindow: PtrInt;
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// compatibility function, wrapping GetACP() Win32 API function
// - returns the curent system code page (default WinAnsi)
function Unicode_CodePage: integer;

/// compatibility function, wrapping CompareStringW() Win32 API text comparison
// - returns 1 if PW1>PW2, 2 if PW1=PW2, 3 if PW1<PW2 - so substract 2 to have
// -1,0,1 as regular StrCompW/StrICompW comparison function result
// - will compute StrLen(PW1/PW2) if L1 or L2 < 0
// - on POSIX, use the ICU library, or fallback to FPC RTL widestringmanager
// with a temporary variable - you would need to include cwstring unit
// - in practice, is seldom called, unless our proprietary WIN32CASE collation
// is used in mormot.db.raw.sqlite3
// - consider Utf8ILCompReference() from mormot.core.unicode.pas for an
// operating-system-independent Unicode 10.0 comparison function
function Unicode_CompareString(
  PW1, PW2: PWideChar; L1, L2: PtrInt; IgnoreCase: boolean): integer;

/// compatibility function, wrapping MultiByteToWideChar() Win32 API call
// - returns the number of WideChar written into W^ destination buffer
// - on POSIX, use the ICU library, or fallback to FPC RTL widestringmanager
// with a temporary variable - you would need to include cwstring unit
// - raw function called by TSynAnsiConvert.AnsiBufferToUnicode from
// mormot.core.unicode unit
function Unicode_AnsiToWide(
  A: PAnsiChar; W: PWideChar; LA, LW, CodePage: PtrInt): integer;

/// compatibility function, wrapping WideCharToMultiByte() Win32 API call
// - returns the number of AnsiChar written into A^ destination buffer
// - on POSIX, use the ICU library, or fallback to FPC RTL widestringmanager
// with a temporary variable - you would need to include cwstring unit
// - raw function called by TSynAnsiConvert.UnicodeBufferToAnsi from
// mormot.core.unicode unit
function Unicode_WideToAnsi(
  W: PWideChar; A: PAnsiChar; LW, LA, CodePage: PtrInt): integer;

/// conversion of some UTF-16 buffer into a temporary Ansi shortstring
// - used when mormot.core.unicode is an overkill, e.g. TCrtSocket.SockSend()
procedure Unicode_WideToShort(
  W: PWideChar; LW, CodePage: PtrInt; var res: shortstring);

/// compatibility function, wrapping Win32 API CharUpperBuffW()
// - on POSIX, use the ICU library, or fallback to 'a'..'z' conversion only
// - raw function called by UpperCaseUnicode() from mormot.core.unicode unit
function Unicode_InPlaceUpper(W: PWideChar; WLen: integer): integer;
  {$ifdef OSWINDOWS} stdcall; {$endif}

/// compatibility function, wrapping Win32 API CharLowerBuffW()
// - on POSIX, use the ICU library, or fallback to 'A'..'Z' conversion only
// - raw function called by LowerCaseUnicode() from mormot.core.unicode unit
function Unicode_InPlaceLower(W: PWideChar; WLen: integer): integer;
  {$ifdef OSWINDOWS} stdcall; {$endif}

/// returns a system-wide current monotonic timestamp as milliseconds
// - will use the corresponding native API function under Vista+, or will be
// redirected to a custom wrapper function for older Windows versions (XP)
// to avoid the 32-bit overflow/wrapping issue of GetTickCount
// - warning: FPC's SysUtils.GetTickCount64 or TThread.GetTickCount64 don't
// handle properly 49 days wrapping under XP -> always use this safe version
// - on POSIX, will call (via vDSO) the very fast CLOCK_MONOTONIC_COARSE if
// available, or the low-level mach_absolute_time() monotonic Darwin API
// - warning: FPC's SysUtils.GetTickCount64 may call fpgettimeofday() e.g.
// on Darwin, which is not monotonic -> always use this safe version
// - do not expect exact millisecond resolution - it may rather be within the
// 10-16 ms range, especially under Windows
{$ifdef OSWINDOWS}
var
  GetTickCount64: function: Int64; stdcall;
{$else}
function GetTickCount64: Int64;
{$endif OSWINDOWS}

/// returns the current UTC time
// - will convert from clock_gettime(CLOCK_REALTIME_COARSE) if available
function NowUtc: TDateTime;

/// returns the current UTC date/time as a second-based c-encoded time
// - i.e. current number of seconds elapsed since Unix epoch 1/1/1970
// - faster than NowUtc or GetTickCount64, on Windows or Unix platforms
// (will use e.g. fast clock_gettime(CLOCK_REALTIME_COARSE) under Linux,
// or GetSystemTimeAsFileTime under Windows)
// - returns a 64-bit unsigned value, so is "Year2038bug" free
function UnixTimeUtc: Int64;

/// returns the current UTC date/time as a millisecond-based c-encoded time
// - i.e. current number of milliseconds elapsed since Unix epoch 1/1/1970
// - faster and more accurate than NowUtc or GetTickCount64, on Windows or Unix
// - will use e.g. fast clock_gettime(CLOCK_REALTIME_COARSE) under Linux,
// or GetSystemTimeAsFileTime/GetSystemTimePreciseAsFileTime under Windows - the
// later being more accurate, but slightly slower than the former, so you may
// consider using UnixMSTimeUtcFast on Windows if its 10-16ms accuracy is enough
function UnixMSTimeUtc: Int64;

/// returns the current UTC date/time as a millisecond-based c-encoded time
// - under Linux/POSIX, is the very same than UnixMSTimeUtc (inlined call)
// - under Windows 8+, will call GetSystemTimeAsFileTime instead of
// GetSystemTimePreciseAsFileTime, which has higher precision, but is slower
// - prefer it under Windows, if a dozen of ms resolution is enough for your task
function UnixMSTimeUtcFast: Int64;
  {$ifdef OSPOSIX} inline; {$endif}

{$ifndef NOEXCEPTIONINTERCEPT}

type
  /// calling context when intercepting exceptions
  // - used e.g. for TSynLogExceptionToStr or RawExceptionIntercept() handlers
  TSynLogExceptionContext = object
    /// the raised exception class
    EClass: ExceptClass;
    /// the Delphi Exception instance
    // - may be nil for external/OS exceptions
    EInstance: Exception;
    /// the OS-level exception code
    // - could be $0EEDFAE0 of $0EEDFADE for Delphi-generated exceptions
    ECode: DWord;
    /// the address where the exception occured
    EAddr: PtrUInt;
    /// the optional stack trace
    EStack: PPtrUInt;
    /// = FPC's RaiseProc() FrameCount if EStack is Frame: PCodePointer
    EStackCount: integer;
    /// timestamp of this exception, as number of seconds since UNIX Epoch (TUnixTime)
    // - UnixTimeUtc is faster than NowUtc or GetSystemTime
    // - use UnixTimeToDateTime() to convert it into a regular TDateTime
    ETimestamp: Int64;
    /// the logging level corresponding to this exception
    // - may be either sllException or sllExceptionOS
    ELevel: TSynLogInfo;
    /// retrieve some extended information about a given Exception
    // - on Windows, recognize most DotNet CLR Exception Names
    function AdditionalInfo(out ExceptionNames: TPUtf8CharDynArray): cardinal;
  end;

  /// the global function signature expected by RawExceptionIntercept()
  // - assigned e.g. to SynLogException() in mormot.core.log.pas
  TOnRawLogException = procedure(const Ctxt: TSynLogExceptionContext);

/// setup Exception interception for the whole process
// - call RawExceptionIntercept(nil) to disable custom exception handling
procedure RawExceptionIntercept(const Handler: TOnRawLogException);

{$endif NOEXCEPTIONINTERCEPT}

/// returns a high-resolution system-wide monotonic timestamp as microseconds
// - under Linux/POSIX, has true microseconds resolution, calling e.g.
// CLOCK_MONOTONIC on Linux/BSD
// - under Windows, calls QueryPerformanceCounter / QueryPerformanceFrequency
procedure QueryPerformanceMicroSeconds(out Value: Int64);

/// cross-platform check if the supplied THandle is not invalid
function ValidHandle(Handle: THandle): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// get a file date and time, from its name
// - returns 0 if file doesn't exist
// - under Windows, will use GetFileAttributesEx fast API
function FileAgeToDateTime(const FileName: TFileName): TDateTime;

/// low-level conversion of a TDateTime into a Windows File 32-bit TimeStamp
function DateTimeToWindowsFileTime(DateTime: TDateTime): integer;

/// get the date and time of one file into a Windows File 32-bit TimeStamp
// - this cross-system function is used e.g. by mormot.core.zip which expects
// Windows TimeStamps in its headers
function FileAgeToWindowsTime(const FileName: TFileName): integer;

/// copy the date of one file to another
function FileSetDateFrom(const Dest: TFileName; SourceHandle: THandle): boolean;

/// copy the date of one file from a Windows File 32-bit TimeStamp
// - this cross-system function is used e.g. by mormot.core.zip which expects
// Windows TimeStamps in its headers
function FileSetDateFromWindowsTime(const Dest: TFileName; WinTime: integer): boolean;

/// reduce the visibility of a given file by setting its read/write attributes
// - on POSIX, change attributes for the the owner, and reset group/world flags
// - if Secret=false, will have normal file attributes, with read/write access
// - if Secret=true, will have read-only attributes (and hidden on Windows -
// under POSIX, there is no "hidden" file attribute, but you should define a
// FileName starting by '.')
procedure FileSetAttributes(const FileName: TFileName; Secret: boolean);

/// get a file size, from its name
// - returns 0 if file doesn't exist
// - under Windows, will use GetFileAttributesEx fast API
function FileSize(const FileName: TFileName): Int64; overload;

/// get a file size, from its handle
// - returns 0 if file doesn't exist
function FileSize(F: THandle): Int64; overload;

/// FileSeek() overloaded function, working with huge files
// - Delphi FileSeek() is buggy -> use this function to safe access files > 2 GB
// (thanks to sanyin for the report)
function FileSeek64(Handle: THandle; const Offset: Int64;
  Origin: cardinal): Int64;

/// get low-level file information, in a cross-platform way
// - returns true on success
// - here file write/creation time are given as TUnixMSTime values, for better
// cross-platform process - note that FileCreateDateTime may not be supported
// by most Linux file systems, so the oldest timestamp available is returned
// as failover on such systems (probably the latest file metadata writing)
function FileInfoByHandle(aFileHandle: THandle; out FileId, FileSize,
  LastWriteAccess, FileCreateDateTime: Int64): boolean;

/// copy one file to another, similar to the Windows API
function CopyFile(const Source, Target: TFileName;
  FailIfExists: boolean): boolean;

/// conversion of Windows OEM charset into a UTF-16 encoded string
function OemToUnicode(const oem: RawByteString): SynUnicode;

/// conversion of Windows OEM charset into a file name
// - as used e.g. by mormot.core.zip for non UTF-8 file names
function OemToFileName(const oem: RawByteString): TFileName;

/// prompt the user for an error message
// - in practice, text encoding is expected to be plain ASCII 
// - on Windows, will call MessageBoxA()
// - on POSIX, will use Writeln(StdErr)
procedure DisplayFatalError(const title, msg: RawUtf8);

const
  /// operating-system dependent Line Feed characters
  {$ifdef OSWINDOWS}
  CRLF = #13#10;
  {$else}
  CRLF = #10;
  {$endif OSWINDOWS}

  /// operating-system dependent wildchar to match all files in a folder
  {$ifdef OSWINDOWS}
  FILES_ALL = '*.*';
  {$else}
  FILES_ALL = '*';
  {$endif OSWINDOWS}

/// get a file date and time, from a FindFirst/FindNext search
// - the returned timestamp is in local time, not UTC
// - this method would use the F.Timestamp field available since Delphi XE2
function SearchRecToDateTime(const F: TSearchRec): TDateTime;
  {$ifdef HASINLINE}inline;{$endif}

/// check if a FindFirst/FindNext found instance is actually a file
function SearchRecValidFile(const F: TSearchRec): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// check if a FindFirst/FindNext found instance is actually a folder
function SearchRecValidFolder(const F: TSearchRec): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// overloaded function optimized for one pass file reading
// - will use e.g. the FILE_FLAG_SEQUENTIAL_SCAN flag under Windows, as stated
// by http://blogs.msdn.com/b/oldnewthing/archive/2012/01/20/10258690.aspx
// - note: under XP, we observed ERROR_NO_SYSTEM_RESOURCES problems when calling
// FileRead() for chunks bigger than 32MB on files opened with this flag,
// so it would use regular FileOpen() on this deprecated OS
// - on POSIX, calls fpOpen(pointer(FileName),O_RDONLY) with no fpFlock() call
// - is used e.g. by StringFromFile() or HashFile() functions
function FileOpenSequentialRead(const FileName: string): integer;
  {$ifdef FPC}inline;{$endif}

/// returns a TFileStream optimized for one pass file reading
// - will use FileOpenSequentialRead(), i.e. FILE_FLAG_SEQUENTIAL_SCAN on Windows
// - on POSIX, calls fpOpen(pointer(FileName),O_RDONLY) with no fpFlock() call
// - is used e.g. by TRestOrmServerFullMemory and TAlgoCompress
function FileStreamSequentialRead(const FileName: string): THandleStream;

/// read a File content into a string
// - content can be binary or text
// - returns '' if file was not found or any read error occured
// - wil use GetFileSize() API by default, unless HasNoSize is defined,
// and read will be done using a buffer (required e.g. for char files under Linux)
// - uses RawByteString for byte storage, whatever the codepage is
function StringFromFile(const FileName: TFileName;
  HasNoSize: boolean = false): RawByteString;

/// create a File from a string content
// - uses RawByteString for byte storage, whatever the codepage is
function FileFromString(const Content: RawByteString; const FileName: TFileName;
  FlushOnDisk: boolean = false; FileDate: TDateTime = 0): boolean;

/// compute an unique temporary file name
// - following 'exename_123.tmp' pattern, in the system temporary folder
function TemporaryFileName: TFileName;

/// delete the content of a specified directory
// - only one level of file is deleted within the folder: no recursive deletion
// is processed by this function (for safety)
// - if DeleteOnlyFilesNotDirectory is TRUE, it won't remove the folder itself,
// but just the files found in it
function DirectoryDelete(const Directory: TFileName;
  const Mask: TFileName = FILES_ALL; DeleteOnlyFilesNotDirectory: boolean = false;
  DeletedCount: PInteger = nil): boolean;

/// delete the files older than a given age in a specified directory
// - for instance, to delete all files older than one day:
// ! DirectoryDeleteOlderFiles(FolderName, 1);
// - only one level of file is deleted within the folder: no recursive deletion
// is processed by this function, unless Recursive is TRUE
// - if Recursive=true, caller should set TotalSize^=0 to have an accurate value
function DirectoryDeleteOlderFiles(const Directory: TFileName;
  TimePeriod: TDateTime; const Mask: TFileName = FILES_ALL;
  Recursive: boolean = false; TotalSize: PInt64 = nil): boolean;

/// check if the directory is writable for the current user
// - try to write a small file with a random name
function IsDirectoryWritable(const Directory: TFileName): boolean;

type
  /// text file layout, as recognized by TMemoryMap.TextFileKind
  TTextFileKind = (
    isUnicode,
    isUtf8,
    isAnsi);

  /// cross-platform memory mapping of a file content
  TMemoryMap = object
  protected
    fBuf: PAnsiChar;
    fBufSize: PtrUInt;
    fFile: THandle;
    {$ifdef OSWINDOWS}
    fMap: THandle;
    {$endif OSWINDOWS}
    fFileSize: Int64;
    fFileLocal, fLoadedNotMapped: boolean;
    function DoMap(aCustomOffset: Int64): boolean;
    procedure DoUnMap;
  public
    /// map the corresponding file handle
    // - if aCustomSize and aCustomOffset are specified, the corresponding
    // map view if created (by default, will map whole file)
    function Map(aFile: THandle; aCustomSize: PtrUInt = 0;
      aCustomOffset: Int64 = 0; aFileOwned: boolean = false): boolean; overload;
    /// map the file specified by its name
    // - file will be closed when UnMap will be called
    function Map(const aFileName: TFileName): boolean; overload;
    /// set a fixed buffer for the content
    // - emulated a memory-mapping from an existing buffer
    procedure Map(aBuffer: pointer; aBufferSize: PtrUInt); overload;
    /// recognize the BOM of a text file - returns isAnsi if no BOM is available
    function TextFileKind: TTextFileKind;
    /// unmap the file
    procedure UnMap;
    /// retrieve the memory buffer mapped to the file content
    property Buffer: PAnsiChar
      read fBuf;
    /// retrieve the buffer size
    property Size: PtrUInt
      read fBufSize;
    /// retrieve the mapped file size
    property FileSize: Int64
      read fFileSize;
    /// access to the low-level associated File handle (if any)
    property FileHandle: THandle
      read fFile;
  end;

  /// a TStream created from a file content, using fast memory mapping
  TSynMemoryStreamMapped = class(TSynMemoryStream)
  protected
    fMap: TMemoryMap;
    fFileStream: TFileStream;
    fFileName: TFileName;
  public
    /// create a TStream from a file content using fast memory mapping
    // - if aCustomSize and aCustomOffset are specified, the corresponding
    // map view if created (by default, will map whole file)
    constructor Create(const aFileName: TFileName;
      aCustomSize: PtrUInt = 0; aCustomOffset: Int64 = 0); overload;
    /// create a TStream from a file content using fast memory mapping
    // - if aCustomSize and aCustomOffset are specified, the corresponding
    // map view if created (by default, will map whole file)
    constructor Create(aFile: THandle;
      aCustomSize: PtrUInt = 0; aCustomOffset: Int64 = 0); overload;
    /// release any internal mapped file instance
    destructor Destroy; override;
    /// the file name, if created from such Create(aFileName) constructor
    property FileName: TFileName
      read fFileName;
  end;

  /// low-level access to a resource bound to the executable
  // - so that Windows is not required in your unit uses clause
  TExecutableResource = object
  private
    HResInfo: THandle;
    HGlobal: THandle;
  public
    /// the resource memory pointer, after successful Open()
    Buffer: pointer;
    /// the resource memory size in bytes, after successful Open()
    Size: PtrInt;
    /// locate and lock a resource
    // - use the current executable if Instance is left to its 0 default value
    // - returns TRUE if the resource has been found, and Buffer/Size are set
    function Open(const ResourceName: string; ResType: PChar;
      Instance: THandle = 0): boolean;
    /// unlock and finalize a resource
    procedure Close;
  end;


type
  /// store CPU and RAM usage for a given process
  // - as used by TSystemUse class
  TSystemUseData = packed record
    /// when the data has been sampled
    Timestamp: TDateTime;
    /// percent of current Kernel-space CPU usage for this process
    Kernel: single;
    /// percent of current User-space CPU usage for this process
    User: single;
    /// how many KB of working memory are used by this process
    WorkKB: cardinal;
    /// how many KB of virtual memory are used by this process
    VirtualKB: cardinal;
  end;

  /// store CPU and RAM usage history for a given process
  // - as returned by TSystemUse.History
  TSystemUseDataDynArray = array of TSystemUseData;

  /// low-level structure used to compute process memory and CPU usage
  TProcessInfo = object
  private
    {$ifdef OSWINDOWS}
    fSysPrevIdle, fSysPrevKernel, fSysPrevUser,
    fDiffIdle, fDiffKernel, fDiffUser, fDiffTotal: Int64;
    {$endif OSWINDOWS}
  public
    /// initialize the system/process resource tracking
    function Init: boolean;
    /// to be called before PerSystem() or PerProcess() iteration
    function Start: boolean;
    /// percent of current Idle/Kernel/User CPU usage for all processes
    function PerSystem(out Idle, Kernel, User: single): boolean;
    /// retrieve CPU and RAM usage for a given process
    function PerProcess(PID: cardinal; Now: PDateTime;
      out Data: TSystemUseData; var PrevKernel, PrevUser: Int64): boolean;
  end;

  /// hold low-level information about current memory usage
  // - as filled by GetMemoryInfo()
  TMemoryInfo = record
    memtotal, memfree, filetotal, filefree,
    vmtotal, vmfree, allocreserved, allocused: QWord;
    percent: integer;
  end;

  /// stores information about a disk partition
  TDiskPartition = packed record
    /// the name of this partition
    // - is the Volume name under Windows, or the Device name under POSIX
    name: RawUtf8;
    /// where this partition has been mounted
    // - e.g. 'C:' or '/home'
    // - you can use GetDiskInfo(mounted) to retrieve current space information
    mounted: TFileName;
    /// total size (in bytes) of this partition
    size: QWord;
  end;

  /// stores information about several disk partitions
  TDiskPartitions = array of TDiskPartition;


{$ifdef CPUARM}
var
  /// internal wrapper address for ReserveExecutableMemory()
  // - set to @TInterfacedObjectFake.ArmFakeStub by mormot.core.interfaces.pas
  ArmFakeStubAddr: pointer;
{$endif CPUARM}


/// cross-platform reserve some executable memory
// - using PAGE_EXECUTE_READWRITE flags on Windows, and PROT_READ or PROT_WRITE
// or PROT_EXEC on POSIX
// - this function maintain an internal set of 64KB memory pages for efficiency
// - memory blocks can not be released (don't try to use fremeem on them) and
// will be returned to the system at process finalization
function ReserveExecutableMemory(size: cardinal): pointer;

/// to be called after ReserveExecutableMemory() when you want to actually write
// the memory blocks
// - affect the mapping flags of the first memory page (4KB) of the Reserved
// buffer, so its size should be < 4KB
// - do nothing on Windows and Linux, but may be needed on OpenBSD
procedure ReserveExecutableMemoryPageAccess(Reserved: pointer; Exec: boolean);

/// return the PIDs of all running processes
// - under Windows, is a wrapper around EnumProcesses() PsAPI call
// - on Linux, will enumerate /proc/* pseudo-files
function EnumAllProcesses(out Count: cardinal): TCardinalDynArray;

/// return the process name of a given PID
// - under Windows, is a wrapper around QueryFullProcessImageNameW/GetModuleFileNameEx
// PsAPI call
// - on Linux, will query /proc/[pid]/exe or /proc/[pid]/cmdline pseudo-file
function EnumProcessName(PID: cardinal): RawUtf8;

/// return the system-wide time usage information
// - under Windows, is a wrapper around GetSystemTimes() kernel API call
function RetrieveSystemTimes(out IdleTime, KernelTime, UserTime: Int64): boolean;

/// return the time and memory usage information about a given process
// - under Windows, is a wrapper around GetProcessTimes/GetProcessMemoryInfo
function RetrieveProcessInfo(PID: cardinal; out KernelTime, UserTime: Int64;
  out WorkKB, VirtualKB: cardinal): boolean;

/// retrieve low-level information about current memory usage
// - as used by TSynMonitorMemory
// - under BSD, only memtotal/memfree/percent are properly returned
// - allocreserved and allocused are set only if withalloc is TRUE
function GetMemoryInfo(out info: TMemoryInfo; withalloc: boolean): boolean;

/// retrieve low-level information about a given disk partition
// - as used by TSynMonitorDisk and GetDiskPartitionsText()
// - only under Windows the Quotas are applied separately to aAvailableBytes
// in respect to global aFreeBytes
function GetDiskInfo(var aDriveFolderOrFile: TFileName;
  out aAvailableBytes, aFreeBytes, aTotalBytes: QWord
  {$ifdef OSWINDOWS}; aVolumeName: PSynUnicode = nil{$endif}): boolean;

/// retrieve low-level information about all mounted disk partitions of the system
// - returned partitions array is sorted by "mounted" ascending order
function GetDiskPartitions: TDiskPartitions;

type
  /// available console colors
  TConsoleColor = (
    ccBlack,
    ccBlue,
    ccGreen,
    ccCyan,
    ccRed,
    ccMagenta,
    ccBrown,
    ccLightGray,
    ccDarkGray,
    ccLightBlue,
    ccLightGreen,
    ccLightCyan,
    ccLightRed,
    ccLightMagenta,
    ccYellow,
    ccWhite);

{$ifdef OSPOSIX}
var
  stdoutIsTTY: boolean;
{$endif OSPOSIX}

/// similar to Windows AllocConsole API call, to be truly cross-platform
// - do nothing on Linux/POSIX
procedure AllocConsole;
  {$ifdef OSWINDOWS} stdcall; {$else} inline; {$endif}

/// change the console text writing color
// - you should call this procedure to initialize StdOut global variable, if
// you manually initialized the Windows console, e.g. via the following code:
// ! AllocConsole;
// ! TextColor(ccLightGray); // initialize internal console context
procedure TextColor(Color: TConsoleColor);

/// write some text to the console using a given color
procedure ConsoleWrite(const Text: RawUtf8; Color: TConsoleColor = ccLightGray;
  NoLineFeed: boolean = false; NoColor: boolean = false); overload;

/// change the console text background color
procedure TextBackground(Color: TConsoleColor);

/// will wait for the ENTER key to be pressed, processing Synchronize() pending
// notifications, and the internal Windows Message loop (on this OS)
// - to be used e.g. for proper work of console applications with interface-based
// service implemented as optExecInMainThread
procedure ConsoleWaitForEnterKey;

/// read all available content from stdin
// - could be used to retrieve some file piped to the command line
// - the content is not converted, so will follow the encoding used for storage
function ConsoleReadBody: RawByteString;

{$ifdef OSWINDOWS}

/// low-level access to the keyboard state of a given key
function ConsoleKeyPressed(ExpectedKey: Word): boolean;

{$endif OSWINDOWS}

/// direct conversion of a UTF-8 encoded string into a console OEM-encoded string
// - under Windows, will use the CP_OEMCP encoding
// - under Linux, will expect the console to be defined with UTF-8 encoding
function Utf8ToConsole(const S: RawUtf8): RawByteString;

var
  /// low-level handle used for console writing
  // - may be overriden when console is redirected
  // - is initialized when TextColor() is called
  StdOut: THandle;


type
  /// encapsulate cross-platform loading of library files
  // - this generic class can be used for any external library (.dll/.so)
  TSynLibrary = class
  protected
    fHandle: TLibHandle;
    fLibraryPath: TFileName;
  public
    /// cross-platform resolution of a function entry in this library
    // - if RaiseExceptionOnFailure is set, missing entry will call FreeLib then raise it
    function Resolve(ProcName: PAnsiChar; Entry: PPointer;
      RaiseExceptionOnFailure: ExceptionClass = nil): boolean;
    /// cross-platform call to FreeLibrary() + set fHandle := 0
    // - as called by Destroy, but you can use it directly to reload the library
    procedure FreeLib;
    /// same as SafeLoadLibrary() but setting fLibraryPath and cwd on Windows
    function TryLoadLibrary(const aLibrary: array of TFileName;
      aRaiseExceptionOnFailure: ExceptionClass): boolean; virtual;
    /// release associated memory and linked library
    destructor Destroy; override;
    /// the associated library handle
    property Handle: TLibHandle
      read fHandle write fHandle;
    /// the loaded library path
    property LibraryPath: TFileName
      read fLibraryPath;
  end;


{ *************** Per Class Properties O(1) Lookup via vmtAutoTable Slot }

/// self-modifying code - change some memory buffer in the code segment
// - if Backup is not nil, it should point to a Size array of bytes, ready
// to contain the overridden code buffer, for further hook disabling
procedure PatchCode(Old, New: pointer; Size: PtrInt; Backup: pointer = nil;
  LeaveUnprotected: boolean = false);

/// self-modifying code - change one PtrUInt in the code segment
procedure PatchCodePtrUInt(Code: PPtrUInt; Value: PtrUInt;
  LeaveUnprotected: boolean = false);

{$ifdef CPUX64}
/// low-level x86_64 asm routine patch and redirection
procedure RedirectCode(Func, RedirectFunc: Pointer);
{$endif CPUX64}

/// search for a given class stored in an object vmtAutoTable Slot
// - up to 15 properties could be registered per class
// - quickly returns the PropertiesClass instance for this class on success
// - returns nil if no Properties was registered for this class; caller should
// call ClassPropertiesAdd() to initialize
function ClassPropertiesGet(ObjectClass: TClass): pointer;
  {$ifdef HASINLINE}inline;{$endif}

/// try to register a given Properties instance for a given class
// - returns associated PropertiesInstance otherwise, which may not be the supplied
// PropertiesInstance, if it has been registered by another thread in between -
// it will free the supplied PropertiesInstance in this case, and return the existing
function ClassPropertiesAdd(ObjectClass: TClass; PropertiesInstance: TObject;
  FreeExistingPropertiesInstance: boolean = true): TObject;



{ **************** TSynLocker/TSynLocked and Low-Level Threading Features }

  { TODO : introduce light read/write lockers }

type
  /// allow to add cross-platform locking methods to any class instance
  // - typical use is to define a Safe: TSynLocker property, call Safe.Init
  // and Safe.Done in constructor/destructor methods, and use Safe.Lock/UnLock
  // methods in a try ... finally section
  // - in respect to the TCriticalSection class, fix a potential CPU cache line
  // conflict which may degrade the multi-threading performance, as reported by
  // @http://www.delphitools.info/2011/11/30/fixing-tcriticalsection
  // - internal padding is used to safely store up to 7 values protected
  // from concurrent access with a mutex, so that SizeOf(TSynLocker)>128
  // - for object-level locking, see TSynPersistentLock which owns one such
  // instance, or call low-level fSafe := NewSynLocker in your constructor,
  // then fSafe^.DoneAndFreemem in your destructor
  TSynLocker = object
  protected
    fSection: TRTLCriticalSection;
    fSectionPadding: PtrInt; // paranoid to avoid FUTEX_WAKE_PRIVATE=EAGAIN
    fLocked, fInitialized: boolean;
    function GetVariant(Index: integer): Variant;
    procedure SetVariant(Index: integer; const Value: Variant);
    function GetInt64(Index: integer): Int64;
    procedure SetInt64(Index: integer; const Value: Int64);
    function GetBool(Index: integer): boolean;
    procedure SetBool(Index: integer; const Value: boolean);
    function GetUnlockedInt64(Index: integer): Int64;
    procedure SetUnlockedInt64(Index: integer; const Value: Int64);
    function GetPointer(Index: integer): Pointer;
    procedure SetPointer(Index: integer; const Value: Pointer);
    function GetUtf8(Index: integer): RawUtf8;
    procedure SetUtf8(Index: integer; const Value: RawUtf8);
  public
    /// internal padding data, also used to store up to 7 variant values
    // - this memory buffer will ensure no CPU cache line mixup occurs
    // - you should not use this field directly, but rather the Locked[],
    // LockedInt64[], LockedUtf8[] or LockedPointer[] methods
    // - if you want to access those array values, ensure you protect them
    // using a Safe.Lock; try ... Padding[n] ... finally Safe.Unlock structure,
    // and maintain the PaddingUsedCount field accurately
    Padding: array[0..6] of TVarData;
    /// number of values stored in the internal Padding[] array
    // - equals 0 if no value is actually stored, or a 1..7 number otherwise
    // - you should not have to use this field, but for optimized low-level
    // direct access to Padding[] values, within a Lock/UnLock safe block
    PaddingUsedCount: integer;
    /// initialize the mutex
    // - calling this method is mandatory (e.g. in the class constructor owning
    // the TSynLocker instance), otherwise you may encounter unexpected
    // behavior, like access violations or memory leaks
    procedure Init;
    /// finalize the mutex
    // - calling this method is mandatory (e.g. in the class destructor owning
    // the TSynLocker instance), otherwise you may encounter unexpected
    // behavior, like access violations or memory leaks
    procedure Done;
    /// finalize the mutex, and call FreeMem() on the pointer of this instance
    // - should have been initiazed with a NewSynLocker call
    procedure DoneAndFreeMem;
    /// lock the instance for exclusive access
    // - this method is re-entrant from the same thread (you can nest Lock/UnLock
    // calls in the same thread), but would block any other Lock attempt in
    // another thread
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! Safe.Lock;
    // ! try
    // !   ...
    // ! finally
    // !   Safe.Unlock;
    // ! end;
    procedure Lock; {$ifdef FPC} inline; {$endif}
    /// will try to acquire the mutex
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! if Safe.TryLock then
    // !   try
    // !     ...
    // !   finally
    // !     Safe.Unlock;
    // !   end;
    function TryLock: boolean; {$ifdef FPC} inline; {$endif}
    /// will try to acquire the mutex for a given time
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! if Safe.TryLockMS(100) then
    // !   try
    // !     ...
    // !   finally
    // !     Safe.Unlock;
    // !   end;
    function TryLockMS(retryms: integer): boolean;
    /// release the instance for exclusive access
    // - each Lock/TryLock should have its exact UnLock opposite, so a
    // try..finally block is mandatory for safe code
    procedure UnLock; {$ifdef FPC} inline; {$endif}
    /// will enter the mutex until the IUnknown reference is released
    // - could be used as such under Delphi:
    // !begin
    // !  ... // unsafe code
    // !  Safe.ProtectMethod;
    // !  ... // thread-safe code
    // !end; // local hidden IUnknown will release the lock for the method
    // - warning: under FPC, you should assign its result to a local variable -
    // see bug http://bugs.freepascal.org/view.php?id=26602
    // !var LockFPC: IUnknown;
    // !begin
    // !  ... // unsafe code
    // !  LockFPC := Safe.ProtectMethod;
    // !  ... // thread-safe code
    // !end; // LockFPC will release the lock for the method
    // or
    // !begin
    // !  ... // unsafe code
    // !  with Safe.ProtectMethod do
    // !  begin
    // !    ... // thread-safe code
    // !  end; // local hidden IUnknown will release the lock for the method
    // !end;
    function ProtectMethod: IUnknown;
    /// returns true if the mutex is currently locked by another thread
    property IsLocked: boolean
      read fLocked;
    /// returns true if the Init method has been called for this mutex
    // - is only relevant if the whole object has been previously filled with 0,
    // i.e. as part of a class or as global variable, but won't be accurate
    // when allocated on stack
    property IsInitialized: boolean
      read fInitialized;
    /// safe locked access to a Variant value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // LockedBool, LockedInt64, LockedPointer and LockedUtf8 array properties
    // - returns null if the Index is out of range
    property Locked[Index: integer]: Variant
      read GetVariant write SetVariant;
    /// safe locked access to a Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUtf8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns nil if the Index is out of range, or does not store a Int64
    property LockedInt64[Index: integer]: Int64
      read GetInt64 write SetInt64;
    /// safe locked access to a boolean value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked, LockedInt64, LockedPointer and LockedUtf8 array properties
    // - value will be stored internally as a varboolean variant
    // - returns nil if the Index is out of range, or does not store a boolean
    property LockedBool[Index: integer]: boolean
      read GetBool write SetBool;
    /// safe locked access to a pointer/TObject value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked, LockedBool, LockedInt64 and LockedUtf8 array properties
    // - pointers will be stored internally as a varUnknown variant
    // - returns nil if the Index is out of range, or does not store a pointer
    property LockedPointer[Index: integer]: Pointer
      read GetPointer write SetPointer;
    /// safe locked access to an UTF-8 string value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedPointer array properties
    // - UTF-8 string will be stored internally as a varString variant
    // - returns '' if the Index is out of range, or does not store a string
    property LockedUtf8[Index: integer]: RawUtf8
      read GetUtf8 write SetUtf8;
    /// safe locked in-place increment to an Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUtf8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns the newly stored value
    // - if the internal value is not defined yet, would use 0 as default value
    function LockedInt64Increment(Index: integer; const Increment: Int64): Int64;
    /// safe locked in-place exchange of a Variant value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUtf8 array properties
    // - returns the previous stored value, or null if the Index is out of range
    function LockedExchange(Index: integer; const Value: variant): variant;
    /// safe locked in-place exchange of a pointer/TObject value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUtf8 array properties
    // - pointers will be stored internally as a varUnknown variant
    // - returns the previous stored value, nil if the Index is out of range,
    // or does not store a pointer
    function LockedPointerExchange(Index: integer; Value: pointer): pointer;
    /// unsafe access to a Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUtf8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns nil if the Index is out of range, or does not store a Int64
    // - you should rather call LockedInt64[] property, or use this property
    // with a Lock; try ... finally UnLock block
    property UnlockedInt64[Index: integer]: Int64
      read GetUnlockedInt64 write SetUnlockedInt64;
  end;

  /// a pointer to a TSynLocker mutex instance
  // - see also NewSynLocker and TSynLocker.DoneAndFreemem functions
  PSynLocker = ^TSynLocker;

  /// raw class used by TAutoLocker.ProtectMethod and TSynLocker.ProtectMethod
  // - defined here for use by TAutoLocker in mormot.core.data.pas
  TAutoLock = class(TInterfacedObject)
  protected
    fLock: PSynLocker;
  public
    constructor Create(aLock: PSynLocker);
    destructor Destroy; override;
  end;


/// initialize a TSynLocker instance from heap
// - call DoneandFreeMem to release the associated memory and OS mutex
// - is used e.g. in TSynPersistentLock to reduce class instance size
function NewSynLocker: PSynLocker;

type
  {$M+}

  /// a lighter alternative to TSynPersistentLock
  // - can be used as base class when custom JSON persistence is not needed
  TSynLocked = class
  protected
    fSafe: PSynLocker; // TSynLocker would increase inherited fields offset
  public
    /// initialize the instance, and its associated lock
    // - is defined as virtual, just like TSynPersistent
    constructor Create; virtual;
    /// finalize the instance, and its associated lock
    destructor Destroy; override;
    /// access to the associated instance critical section
    // - call Safe.Lock/UnLock to protect multi-thread access on this storage
    property Safe: PSynLocker
      read fSafe;
  end;

  {$M-}

  /// meta-class definition of the TSynLocked hierarchy
  TSynLockedClass = class of TSynLocked;

{$ifdef OSPOSIX}

var
  /// could be set to TRUE to force SleepHiRes(0) to call the sched_yield API
  // - in practice, it has been reported as buggy under POSIX systems
  // - even Linus Torvald himself raged against its usage - see e.g.
  // https://www.realworldtech.com/forum/?threadid=189711&curpostid=189752
  // - you may tempt the devil and try it by yourself
  SleepHiRes0Yield: boolean = false;

{$endif OSPOSIX}

/// similar to Windows sleep() API call, to be truly cross-platform
// - using millisecond resolution
// - SleepHiRes(0) calls ThreadSwitch on Windows, but POSIX version will
// wait 10 microsecond unless SleepHiRes0Yield is forced to true (bad idea)
// - in respect to RTL's Sleep() function, it will return on ESysEINTR if was
// interrupted by any OS signal
// - warning: wait typically the next system timer interrupt on Windows, which
// is every 16ms by default; as a consequence, never rely on the ms supplied
// value to guess the elapsed time, but call GetTickCount64
procedure SleepHiRes(ms: cardinal);

/// low-level naming of a thread
// - under Linux/FPC, calls pthread_setname_np API which truncates to 16 chars
procedure RawSetThreadName(ThreadID: TThreadID; const Name: RawUtf8);

/// name the current thread so that it would be easily identified in the IDE debugger
// - could then be retrieved by CurrentThreadName/GetCurrentThreadName
// - just a wrapper around SetThreadName(GetCurrentThreadId, ...)
procedure SetCurrentThreadName(const Format: RawUtf8; const Args: array of const); overload;

/// name the current thread so that it would be easily identified in the IDE debugger
// - could also be retrieved by CurrentThreadName/GetCurrentThreadName
// - just a wrapper around SetThreadName(GetCurrentThreadId, ...)
procedure SetCurrentThreadName(const Name: RawUtf8); overload;

var
  /// name a thread so that it would be easily identified in the IDE debugger
  // - default implementation does nothing, unless mormot.core.log is included
  // - you can force this function to do nothing by setting the NOSETTHREADNAME
  // conditional, if you have issues with this feature when debugging your app
  // - most meaningless patterns (like 'TSql') are trimmed to reduce the
  // resulting length - which is convenient e.g. with POSIX truncation to 16 chars
  // - you can retrieve the name later on using CurrentThreadName
  // - this method will register TSynLog.LogThreadName(), so threads calling it
  // should also call TSynLogFamily.OnThreadEnded/TSynLog.NotifyThreadEnded
  SetThreadName: procedure(ThreadID: TThreadID; const Format: RawUtf8;
    const Args: array of const);

threadvar
  /// low-level access to the thread name, as set by SetThreadName()
  // - since threadvar can't contain managed strings, it is limited to 31 chars,
  // which is enough since POSIX truncates to 16 chars and SetThreadName does
  // trim meaningless patterns
  CurrentThreadName: TShort31;

/// retrieve the thread name, as set by SetThreadName()
// - if possible, direct CurrentThreadName threadvar access is slightly faster
// - will return the CurrentThreadName value, truncated to 31 chars
function GetCurrentThreadName: RawUtf8;
  {$ifdef HASINLINE}inline;{$endif}

/// enter a process-wide giant lock for thread-safe shared process
// - shall be protected as such:
// ! GlobalLock;
// ! try
// !   .... do something thread-safe but as short as possible
// ! finally
// !  GlobalUnLock;
// ! end;
// - you should better not use such a giant-lock, but an instance-dedicated
// critical section or TSynLocker - these functions are just here to be
// convenient, for non time-critical process (e.g. singleton initialization)
procedure GlobalLock;

/// release the giant lock for thread-safe shared process
// - you should better not use such a giant-lock, but an instance-dedicated
// critical section or TSynLocker - these functions are just here to be
// convenient, for non time-critical process (e.g. singleton initialization)
procedure GlobalUnLock;


{ ****************** Unix Daemon and Windows Service Support }

{$ifdef OSWINDOWS}

{ *** some minimal Windows API definitions, replacing WinSvc.pas missing for FPC }

const
  SERVICE_QUERY_CONFIG         = $0001;
  SERVICE_CHANGE_CONFIG        = $0002;
  SERVICE_QUERY_STATUS         = $0004;
  SERVICE_ENUMERATE_DEPENDENTS = $0008;
  SERVICE_START                = $0010;
  SERVICE_STOP                 = $0020;
  SERVICE_PAUSE_CONTINUE       = $0040;
  SERVICE_INTERROGATE          = $0080;
  SERVICE_USER_DEFINED_CONTROL = $0100;
  SERVICE_ALL_ACCESS           = STANDARD_RIGHTS_REQUIRED or
                                 SERVICE_QUERY_CONFIG or
                                 SERVICE_CHANGE_CONFIG or
                                 SERVICE_QUERY_STATUS or
                                 SERVICE_ENUMERATE_DEPENDENTS or
                                 SERVICE_START or
                                 SERVICE_STOP or
                                 SERVICE_PAUSE_CONTINUE or
                                 SERVICE_INTERROGATE or
                                 SERVICE_USER_DEFINED_CONTROL;

  SC_MANAGER_CONNECT            = $0001;
  SC_MANAGER_CREATE_SERVICE     = $0002;
  SC_MANAGER_ENUMERATE_SERVICE  = $0004;
  SC_MANAGER_LOCK               = $0008;
  SC_MANAGER_QUERY_LOCK_STATUS  = $0010;
  SC_MANAGER_MODIFY_BOOT_CONFIG = $0020;
  SC_MANAGER_ALL_ACCESS         = STANDARD_RIGHTS_REQUIRED or
                                  SC_MANAGER_CONNECT or
                                  SC_MANAGER_CREATE_SERVICE or
                                  SC_MANAGER_ENUMERATE_SERVICE or
                                  SC_MANAGER_LOCK or
                                  SC_MANAGER_QUERY_LOCK_STATUS or
                                  SC_MANAGER_MODIFY_BOOT_CONFIG;

  SERVICE_CONFIG_DESCRIPTION    = $0001;

  SERVICE_WIN32_OWN_PROCESS     = $00000010;
  SERVICE_WIN32_SHARE_PROCESS   = $00000020;
  SERVICE_INTERACTIVE_PROCESS   = $00000100;

  SERVICE_BOOT_START            = $00000000;
  SERVICE_SYSTEM_START          = $00000001;
  SERVICE_AUTO_START            = $00000002;
  SERVICE_DEMAND_START          = $00000003;
  SERVICE_DISABLED              = $00000004;
  SERVICE_ERROR_IGNORE          = $00000000;
  SERVICE_ERROR_NORMAL          = $00000001;
  SERVICE_ERROR_SEVERE          = $00000002;
  SERVICE_ERROR_CRITICAL        = $00000003;

  SERVICE_CONTROL_STOP          = $00000001;
  SERVICE_CONTROL_PAUSE         = $00000002;
  SERVICE_CONTROL_CONTINUE      = $00000003;
  SERVICE_CONTROL_INTERROGATE   = $00000004;
  SERVICE_CONTROL_SHUTDOWN      = $00000005;
  SERVICE_STOPPED               = $00000001;
  SERVICE_START_PENDING         = $00000002;
  SERVICE_STOP_PENDING          = $00000003;
  SERVICE_RUNNING               = $00000004;
  SERVICE_CONTINUE_PENDING      = $00000005;
  SERVICE_PAUSE_PENDING         = $00000006;
  SERVICE_PAUSED                = $00000007;

type
  PServiceStatus = ^TServiceStatus;
  TServiceStatus = object
  public
    dwServiceType: cardinal;
    dwCurrentState: cardinal;
    dwControlsAccepted: cardinal;
    dwWin32ExitCode: cardinal;
    dwServiceSpecificExitCode: cardinal;
    dwCheckPoint: cardinal;
    dwWaitHint: cardinal;
  end;

  PServiceStatusProcess = ^TServiceStatusProcess;
  TServiceStatusProcess = object(TServiceStatus)
  public
    dwProcessId: cardinal;
    dwServiceFlags: cardinal;
  end;

  SC_HANDLE = THandle;
  SERVICE_STATUS_HANDLE = cardinal;
  TServiceTableEntry = record
    lpServiceName: PChar;
    lpServiceProc: procedure(ArgCount: cardinal; Args: PPChar); stdcall;
  end;
  PServiceTableEntry = ^TServiceTableEntry;

  {$Z4}
  SC_STATUS_TYPE = (SC_STATUS_PROCESS_INFO);
  {$Z1}

function OpenSCManager(lpMachineName, lpDatabaseName: PChar;
  dwDesiredAccess: cardinal): SC_HANDLE; stdcall; external advapi32
  name 'OpenSCManager' + _AW;
function ChangeServiceConfig2(hService: SC_HANDLE; dwsInfoLevel: cardinal;
  lpInfo: Pointer): BOOL; stdcall; external advapi32 name 'ChangeServiceConfig2W';
function StartService(hService: SC_HANDLE; dwNumServiceArgs: cardinal;
  lpServiceArgVectors: Pointer): BOOL; stdcall; external advapi32
  name 'StartService' + _AW;
function CreateService(hSCManager: SC_HANDLE; lpServiceName, lpDisplayName: PChar;
  dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: cardinal;
  lpBinaryPathName, lpLoadOrderGroup: PChar; lpdwTagId: LPDWORD; lpDependencies,
  lpServiceStartName, lpPassword: PChar): SC_HANDLE; stdcall; external advapi32
  name 'CreateService' + _AW;
function OpenService(hSCManager: SC_HANDLE; lpServiceName: PChar;
  dwDesiredAccess: cardinal): SC_HANDLE; stdcall; external advapi32
  name 'OpenService' + _AW;
function DeleteService(hService: SC_HANDLE): BOOL; stdcall; external advapi32;
function CloseServiceHandle(hSCObject: SC_HANDLE): BOOL; stdcall; external advapi32;
function QueryServiceStatus(hService: SC_HANDLE;
  var lpServiceStatus: TServiceStatus): BOOL; stdcall; external advapi32;
function QueryServiceStatusEx(hService: SC_HANDLE;
  InfoLevel: SC_STATUS_TYPE; lpBuffer: Pointer; cbBufSize: cardinal;
  var pcbBytesNeeded: cardinal): BOOL; stdcall; external advapi32;
function ControlService(hService: SC_HANDLE; dwControl: cardinal;
  var lpServiceStatus: TServiceStatus): BOOL; stdcall; external advapi32;
function SetServiceStatus(hServiceStatus: SERVICE_STATUS_HANDLE;
  var lpServiceStatus: TServiceStatus): BOOL; stdcall; external advapi32;
function RegisterServiceCtrlHandler(lpServiceName: PChar;
  lpHandlerProc: TFarProc): SERVICE_STATUS_HANDLE; stdcall; external advapi32
  name 'RegisterServiceCtrlHandler' + _AW;
function StartServiceCtrlDispatcher(
  lpServiceStartTable: PServiceTableEntry): BOOL; stdcall; external advapi32
  name 'StartServiceCtrlDispatcher' + _AW;


{ *** high level classes to define and manage Windows Services }

var
  /// can be assigned from TSynLog.DoLog class method for
  // TServiceController/TService logging
  // - default is nil, i.e. disabling logging, since it may interfere with the
  // logging process of the Windows Service itself
  WindowsServiceLog: TSynLogProc;

type
  /// all possible states of the service
  TServiceState = (
    ssNotInstalled,
    ssStopped,
    ssStarting,
    ssStopping,
    ssRunning,
    ssResuming,
    ssPausing,
    ssPaused,
    ssErrorRetrievingState);

  /// TServiceControler class is intended to create a new Windows Service instance
  // or to maintain (that is start, stop, pause, resume...) an existing Service
  // - to provide the service itself, use the TService class
  TServiceController = class
  protected
    fSCHandle: THandle;
    fHandle: THandle;
    fStatus: TServiceStatus;
    fName: RawUtf8;
  protected
    function GetStatus: TServiceStatus;
    function GetState: TServiceState;
  public
    /// create a new Windows Service and control it and/or its configuration
    // - TargetComputer - set it to empty string if local computer is the target.
    // - DatabaseName - set it to empty string if the default database is supposed
    // ('ServicesActive').
    // - Name - name of a service.
    // - DisplayName - display name of a service.
    // - Path - a path to binary (executable) of the service created.
    // - OrderGroup - an order group name (unnecessary)
    // - Dependencies - string containing a list with names of services, which must
    // start before (every name should be separated with #0, entire
    // list should be separated with #0#0. Or, an empty string can be
    // passed if there is no dependancy).
    // - Username - login name. For service type SERVICE_WIN32_OWN_PROCESS, the
    // account name in the form of "DomainName\Username"; If the account
    // belongs to the built-in domain, ".\Username" can be specified;
    // Services of type SERVICE_WIN32_SHARE_PROCESS are not allowed to
    // specify an account other than LocalSystem. If '' is specified, the
    // service will be logged on as the 'LocalSystem' account, in which
    // case, the Password parameter must be empty too.
    // - Password - a password for login name. If the service type is
    // SERVICE_KERNEL_DRIVER or SERVICE_FILE_SYSTEM_DRIVER,
    // this parameter is ignored.
    // - DesiredAccess - a combination of following flags:
    // SERVICE_ALL_ACCESS (default value), SERVICE_CHANGE_CONFIG,
    // SERVICE_ENUMERATE_DEPENDENTS, SERVICE_INTERROGATE, SERVICE_PAUSE_CONTINUE,
    // SERVICE_QUERY_CONFIG, SERVICE_QUERY_STATUS, SERVICE_START, SERVICE_STOP,
    // SERVICE_USER_DEFINED_CONTROL
    // - ServiceType - a set of following flags:
    // SERVICE_WIN32_OWN_PROCESS (default value, which specifies a Win32 service
    // that runs in its own process), SERVICE_WIN32_SHARE_PROCESS,
    // SERVICE_KERNEL_DRIVER, SERVICE_FILE_SYSTEM_DRIVER,
    // SERVICE_INTERACTIVE_PROCESS (default value, which enables a Win32 service
    // process to interact with the desktop)
    // - StartType - one of following values:
    // SERVICE_BOOT_START, SERVICE_SYSTEM_START,
    // SERVICE_AUTO_START (which specifies a device driver or service started by
    // the service control manager automatically during system startup),
    // SERVICE_DEMAND_START (default value, which specifies a service started by
    // a service control manager when a process calls the StartService function,
    // that is the TServiceController.Start method), SERVICE_DISABLED
    // - ErrorControl - one of following:
    // SERVICE_ERROR_IGNORE, SERVICE_ERROR_NORMAL (default value, by which
    // the startup program logs the error and displays a message but continues
    // the startup operation), SERVICE_ERROR_SEVERE,
    // SERVICE_ERROR_CRITICAL
    constructor CreateNewService(
      const TargetComputer, DatabaseName, Name, DisplayName, Path: string;
      const OrderGroup: string = ''; const Dependencies: string = '';
      const Username: string = ''; const Password: string = '';
      DesiredAccess: cardinal = SERVICE_ALL_ACCESS;
      ServiceType: cardinal = SERVICE_WIN32_OWN_PROCESS or SERVICE_INTERACTIVE_PROCESS;
      StartType: cardinal = SERVICE_DEMAND_START;
      ErrorControl: cardinal = SERVICE_ERROR_NORMAL);
    /// wrapper around CreateNewService() to install the current executable as service
    class function Install(const Name, DisplayName, Description: string;
      AutoStart: boolean; ExeName: TFileName = '';
      Dependencies: string = ''): TServiceState;
    /// open an existing service, in order to control it or its configuration
    // from your application
    // - TargetComputer - set it to empty string if local computer is the target.
    // - DatabaseName - set it to empty string if the default database is supposed
    // ('ServicesActive').
    // - Name - name of a service.
    // - DesiredAccess - a combination of following flags:
    // SERVICE_ALL_ACCESS, SERVICE_CHANGE_CONFIG, SERVICE_ENUMERATE_DEPENDENTS,
    // SERVICE_INTERROGATE, SERVICE_PAUSE_CONTINUE, SERVICE_QUERY_CONFIG,
    // SERVICE_QUERY_STATUS, SERVICE_START, SERVICE_STOP, SERVICE_USER_DEFINED_CONTROL
    constructor CreateOpenService(
      const TargetComputer, DataBaseName, Name: string;
      DesiredAccess: cardinal = SERVICE_ALL_ACCESS);
    /// release memory and handles
    destructor Destroy; override;
    /// Handle of SC manager
    property SCHandle: THandle
      read fSCHandle;
    /// Handle of service opened or created
    // - its value is 0 if something failed in any Create*() method
    property Handle: THandle
      read fHandle;
    /// Retrieve the Current status of the service
    property Status: TServiceStatus
      read GetStatus;
    /// Retrieve the Current state of the service
    property State: TServiceState
      read GetState;
    /// Requests the service to stop
    function Stop: boolean;
    /// Requests the service to pause
    function Pause: boolean;
    /// Requests the paused service to resume
    function Resume: boolean;
    /// Requests the service to update immediately its current status information
    // to the service control manager
    function Refresh: boolean;
    /// Request the service to shutdown
    // - this function always return false
    function Shutdown: boolean;
    /// Removes service from the system, i.e. close the Service
    function Delete: boolean;
    /// starts the execution of a service with some specified arguments
    // - this version expect PChar pointers, either AnsiString (for FPC and old
    //  Delphi compiler), either UnicodeString (till Delphi 2009)
    function Start(const Args: array of PChar): boolean;
    /// try to define the description text of this service
    procedure SetDescription(const Description: string);
    /// this class method will check the command line parameters, and will let
    //  control the service according to it
    // - MyServiceSetup.exe /install will install the service
    // - MyServiceSetup.exe /start   will start the service
    // - MyServiceSetup.exe /stop    will stop the service
    // - MyServiceSetup.exe /uninstall will uninstall the service
    // - so that you can write in the main block of your .dpr:
    // !CheckParameters('MyService.exe',HTTPSERVICENAME,HTTPSERVICEDISPLAYNAME);
    // - if ExeFileName='', it will install the current executable
    // - optional Description and Dependencies text may be specified
    class procedure CheckParameters(const ExeFileName: TFileName;
      const ServiceName, DisplayName, Description: string;
      const Dependencies: string = '');
  end;

  {$M+}
  TService = class;
  {$M-}

  /// callback procedure for Windows Service Controller
  TServiceControlHandler = procedure(CtrlCode: cardinal); stdcall;

  /// event triggered for Control handler
  TServiceControlEvent = procedure(Sender: TService; Code: cardinal) of object;

  /// event triggered to implement the Service functionality
  TServiceEvent = procedure(Sender: TService) of object;

  /// let an executable implement a Windows Service
  TService = class
  protected
    fSName: string;
    fDName: string;
    fStartType: cardinal;
    fServiceType: cardinal;
    fData: cardinal;
    fControlHandler: TServiceControlHandler;
    fOnControl: TServiceControlEvent;
    fOnInterrogate: TServiceEvent;
    fOnPause: TServiceEvent;
    fOnShutdown: TServiceEvent;
    fOnStart: TServiceEvent;
    fOnExecute: TServiceEvent;
    fOnResume: TServiceEvent;
    fOnStop: TServiceEvent;
    fStatusRec: TServiceStatus;
    fArgsList: array of string;
    fStatusHandle: THandle;
    function GetArgCount: Integer;
    function GetArgs(Idx: Integer): string;
    function GetInstalled: boolean;
    procedure SetStatus(const Value: TServiceStatus);
    procedure CtrlHandle(Code: cardinal);
    function GetControlHandler: TServiceControlHandler;
    procedure SetControlHandler(const Value: TServiceControlHandler);
  public
    /// this method is the main service entrance, from the OS point of view
    // - it will call OnControl/OnStop/OnPause/OnResume/OnShutdown events
    // - and report the service status to the system (via ReportStatus method)
    procedure DoCtrlHandle(Code: cardinal); virtual;
    /// Creates the service
    // - the service is added to the internal registered services
    // - main application must call the global ServicesRun procedure to actually
    // start the services
    // - caller must free the TService instance when it's no longer used
    constructor Create(const aServiceName, aDisplayName: string); reintroduce; virtual;
    /// Reports new status to the system
    function ReportStatus(dwState, dwExitCode, dwWait: cardinal): BOOL;
    /// Installs the service in the database
    // - return true on success
    // - create a local TServiceController with the current executable file,
    // with the supplied command line parameters
    function Install(const Params: string = ''): boolean;
    /// Removes the service from database
    //  - uses a local TServiceController with the current Service Name
    procedure Remove;
    /// Starts the service
    //  - uses a local TServiceController with the current Service Name
    procedure Start;
    /// Stops the service
    // - uses a local TServiceController with the current Service Name
    procedure Stop;
    /// this is the main method, in which the Service should implement its run
    procedure Execute; virtual;

    /// Number of arguments passed to the service by the service controler
    property ArgCount: Integer
      read GetArgCount;
    /// List of arguments passed to the service by the service controler
    property Args[Idx: Integer]: string
      read GetArgs;
    /// Any data You wish to associate with the service object
    property Data: cardinal
      read FData write FData;
    /// Whether service is installed in DataBase
    // - uses a local TServiceController to check if the current Service Name exists
    property Installed: boolean
      read GetInstalled;
    /// Current service status
    // - To report new status to the system, assign another
    // value to this record, or use ReportStatus method (preferred)
    property Status: TServiceStatus
      read fStatusRec write SetStatus;
    /// Callback handler for Windows Service Controller
    // - if handler is not set, then auto generated handler calls DoCtrlHandle
    // (note that this auto-generated stubb is... not working yet - so you should
    // either set your own procedure to this property, or use TServiceSingle)
    // - a typical control handler may be defined as such:
    // ! var MyGlobalService: TService;
    // !
    // ! procedure MyServiceControlHandler(Opcode: LongWord); stdcall;
    // ! begin
    // !   if MyGlobalService<>nil then
    // !     MyGlobalService.DoCtrlHandle(Opcode);
    // ! end;
    // !
    // ! ...
    // ! MyGlobalService := TService.Create(...
    // ! MyGlobalService.ControlHandler := MyServiceControlHandler;
    property ControlHandler: TServiceControlHandler
      read GetControlHandler write SetControlHandler;
    /// Start event is executed before the main service thread (i.e. in the Execute method)
    property OnStart: TServiceEvent
      read fOnStart write fOnStart;
    /// custom Execute event
    // - launched in the main service thread (i.e. in the Execute method)
    property OnExecute: TServiceEvent
      read fOnExecute write fOnExecute;
    /// custom event triggered when a Control Code is received from Windows
    property OnControl: TServiceControlEvent
      read fOnControl write fOnControl;
    /// custom event triggered when the service is stopped
    property OnStop: TServiceEvent
      read fOnStop write fOnStop;
    /// custom event triggered when the service is paused
    property OnPause: TServiceEvent
      read fOnPause write fOnPause;
    /// custom event triggered when the service is resumed
    property OnResume: TServiceEvent
      read fOnResume write fOnResume;
    /// custom event triggered when the service receive an Interrogate
    property OnInterrogate: TServiceEvent
      read fOnInterrogate write fOnInterrogate;
    /// custom event triggered when the service is shut down
    property OnShutdown: TServiceEvent
      read fOnShutdown write fOnShutdown;
  published
    /// Name of the service. Must be unique
    property ServiceName: string
      read fSName;
    /// Display name of the service
    property DisplayName: string
      read fDName write fDName;
    /// Type of service
    property ServiceType: cardinal
      read fServiceType write fServiceType;
    /// Type of start of service
    property StartType: cardinal
      read fStartType write fStartType;
  end;

  /// inherit from this class if your application has a single Windows Service
  // - note that the TService jumper does not work well - so use this instead
  TServiceSingle = class(TService)
  public
    /// will set a global function as service controller
    constructor Create(const aServiceName, aDisplayName: string); override;
    /// will release the global service controller
    destructor Destroy; override;
  end;


var
  /// the main TService instance running in the current executable
  ServiceSingle: TServiceSingle = nil;

/// launch the registered Service execution
// - ServiceSingle provided by this aplication is sent to the operating system
// - returns TRUE on success
// - returns FALSE on error (to get extended information, call GetLastError)
function ServiceSingleRun: boolean;

/// convert the Control Code retrieved from Windows into a service state
// enumeration item
function CurrentStateToServiceState(CurrentState: cardinal): TServiceState;

/// return the ready to be displayed text of a TServiceState value
function ServiceStateText(State: TServiceState): string;

function ToText(st: TServiceState): PShortString; overload;

/// return service PID
function GetServicePid(const aServiceName: string): cardinal;

/// kill Windows process
function KillProcess(pid: cardinal; waitseconds: integer = 30): boolean;

{$else}

/// low-level function able to properly run or fork the current process
// then execute the start/stop methods of a TSynDaemon / TDDDDaemon instance
// - fork will create a local /run/[ProgramName]-[ProgramPathHash].pid file name
// - onLog can be assigned from TSynLog.DoLog for proper logging
procedure RunUntilSigTerminated(daemon: TObject; dofork: boolean;
  const start, stop: TThreadMethod; const onlog: TSynLogProc = nil;
  const servicename: string = '');

/// kill a process previously created by RunUntilSigTerminated(dofork=true)
// - will lookup a local /run/[ProgramName]-[ProgramPathHash].pid file name to
// retrieve the actual PID to be killed, then send a SIGTERM, and wait
// waitseconds for the .pid file to disapear
// - returns true on success, false on error (e.g. no valid .pid file or
// the file didn't disappear, which may mean that the daemon is broken)
function RunUntilSigTerminatedForKill(waitseconds: integer = 30): boolean;

/// local .pid file name as created by RunUntilSigTerminated(dofork=true)
function RunUntilSigTerminatedPidFile: TFileName;

var
  /// once SynDaemonIntercept has been called, this global variable
  // contains the SIGQUIT / SIGTERM / SIGINT received signal
  SynDaemonTerminated: integer;

/// enable low-level interception of executable stop signals
// - any SIGQUIT / SIGTERM / SIGINT signal will set appropriately the global
// SynDaemonTerminated variable, with an optional logged entry to log
// - as called e.g. by RunUntilSigTerminated()
// - you can call this method several times with no issue
// - onLog can be assigned from TSynLog.DoLog for proper logging
procedure SynDaemonIntercept(const onlog: TSynLogProc = nil);

{$endif OSWINDOWS}

type
  /// command line patterns recognized by ParseCommandArgs()
  TParseCommand = (
    pcHasRedirection,
    pcHasSubCommand,
    pcHasParenthesis,
    pcHasJobControl,
    pcHasWildcard,
    pcHasShellVariable,
    pcUnbalancedSingleQuote,
    pcUnbalancedDoubleQuote,
    pcTooManyArguments,
    pcInvalidCommand,
    pcHasEndingBackSlash);
  TParseCommands = set of TParseCommand;
  PParseCommands = ^TParseCommands;

  /// used to store references of arguments recognized by ParseCommandArgs()
  TParseCommandsArgs = array[0..31] of PAnsiChar;
  PParseCommandsArgs = ^TParseCommandsArgs;

const
  /// identifies some bash-specific processing
  PARSECOMMAND_BASH =
    [pcHasRedirection .. pcHasShellVariable];

  /// identifies obvious invalid content
  PARSECOMMAND_ERROR =
    [pcUnbalancedSingleQuote .. pcHasEndingBackSlash];

/// low-level parsing of a RunCommand() execution command
// - parse and fills argv^[0..argc^-1] with corresponding arguments, after
// un-escaping and un-quoting if applicable, using temp^ to store the content
// - if argv=nil, do only the parsing, not the argument extraction - could be
// used for fast validation of the command line syntax
// - you can force arguments OS flavor using the posix parameter - note that
// Windows parsing is not consistent by itself (e.g. double quoting or
// escaping depends on the actual executable called) so returned flags
// should be considered as indicative only with posix=false
function ParseCommandArgs(const cmd: RawUtf8; argv: PParseCommandsArgs = nil;
  argc: PInteger = nil; temp: PRawUtf8 = nil;
  posix: boolean = {$ifdef OSWINDOWS} false {$else} true {$endif}): TParseCommands;

/// like SysUtils.ExecuteProcess, but allowing not to wait for the process to finish
// - optional env value follows 'n1=v1'#0'n2=v2'#0'n3=v3'#0#0 Windows layout
function RunProcess(const path, arg1: TFileName; waitfor: boolean;
  const arg2: TFileName = ''; const arg3: TFileName = '';
  const arg4: TFileName = ''; const arg5: TFileName = '';
  const env: TFileName = ''; envaddexisting: boolean = false): integer;

/// like fpSystem, but cross-platform
// - under POSIX, calls bash only if needed, after ParseCommandArgs() analysis
// - under Windows (especially Windows 10), creating a process can be dead slow
// https://randomascii.wordpress.com/2019/04/21/on2-in-createprocess
function RunCommand(const cmd: TFileName; waitfor: boolean;
  const env: TFileName = ''; envaddexisting: boolean = false;
  parsed: PParseCommands = nil): integer;




implementation

// those include files hold all OS-specific functions
// note: the *.inc files start with their own "uses" clause, so both $include
// should remain here, just after the "implementation" clause

{$ifdef OSPOSIX}
  {$include mormot.core.os.posix.inc}
{$endif OSPOSIX}

{$ifdef OSWINDOWS}
  {$include mormot.core.os.windows.inc}
{$endif OSWINDOWS}


{ ****************** Gather Operating System Information }

function ToText(const osv: TOperatingSystemVersion): RawUtf8;
begin
  if osv.os = osWindows then
    result := 'Windows ' + WINDOWS_NAME[osv.win]
  else
    result := OS_NAME[osv.os];
end;

function ToTextOS(osint32: integer): RawUtf8;
var
  osv: TOperatingSystemVersion absolute osint32;
begin
  result := ToText(osv);
  if (osv.os >= osLinux) and
     (osv.utsrelease[2] <> 0) then
    // include the kernel number to the distribution name, e.g. 'Ubuntu 5.4.0'
    result := RawUtf8(Format('%s %d.%d.%d', [result, osv.utsrelease[2],
      osv.utsrelease[1], osv.utsrelease[0]]));
end;


{ *************** Per Class Properties O(1) Lookup via vmtAutoTable Slot }

var
  AutoSlotsLock: TRTLCriticalSection;

procedure PatchCodePtrUInt(Code: PPtrUInt; Value: PtrUInt; LeaveUnprotected: boolean);
begin
  PatchCode(Code, @Value, SizeOf(Code^), nil, LeaveUnprotected);
end;

{$ifdef CPUX64}
procedure RedirectCode(Func, RedirectFunc: Pointer);
var
  NewJump: packed record
    Code: byte;        // $e9 = jmp {relative}
    Distance: integer; // relative jump is 32-bit even on CPU64
  end;
begin
  if (Func = nil) or
     (RedirectFunc = nil) or
     (Func = RedirectFunc) then
    exit; // nothing to redirect to
  NewJump.Code := $e9;
  NewJump.Distance := integer(PtrUInt(RedirectFunc) - PtrUInt(Func) - SizeOf(NewJump));
  PatchCode(Func, @NewJump, SizeOf(NewJump));
  assert(PByte(Func)^ = $e9);
end;
{$endif CPUX64}

function ClassPropertiesGet(ObjectClass: TClass): pointer;
begin
  result := PPointer(PAnsiChar(ObjectClass) + vmtAutoTable)^;
end;

function ClassPropertiesAdd(ObjectClass: TClass; PropertiesInstance: TObject;
  FreeExistingPropertiesInstance: boolean): TObject;
var
  vmt: PPointer;
begin
  EnterCriticalSection(AutoSlotsLock);
  try
    vmt := Pointer(PAnsiChar(ObjectClass) + vmtAutoTable);
    result := vmt^;
    if result <> nil then
    begin
      // thread-safe registration
      if FreeExistingPropertiesInstance and
         (PropertiesInstance <> result) then
        PropertiesInstance.Free;
      exit;
    end;
    // actually store the properties into the unused VMT AutoTable slot
    result := PropertiesInstance;
    PatchCodePtrUInt(pointer(vmt), PtrUInt(result), {leaveunprotected=}true);
    if vmt^ <> result then
      raise EOSException.CreateFmt('ClassPropertiesAdd: mprotect failed for %s',
        [ClassNameShort(ObjectClass)^]);
  finally
    LeaveCriticalSection(AutoSlotsLock);
  end;
end;


{ ****************** Unicode, Time, File, Console, Library process }

procedure InitializeCriticalSectionIfNeededAndEnter(var cs: TRTLCriticalSection);
begin
  if not IsInitializedCriticalSection(cs) then
    InitializeCriticalSection(cs);
  EnterCriticalSection(cs);
end;

procedure DeleteCriticalSectionIfNeeded(var cs: TRTLCriticalSection);
begin
  if IsInitializedCriticalSection(cs) then
    DeleteCriticalSection(cs);
end;

const
  ENGLISH_LANGID = $0409;
  // see http://msdn.microsoft.com/en-us/library/windows/desktop/aa383770
  ERROR_WINHTTP_CANNOT_CONNECT = 12029;
  ERROR_WINHTTP_TIMEOUT = 12002;
  ERROR_WINHTTP_INVALID_SERVER_RESPONSE = 12152;

function SysErrorMessagePerModule(Code: DWORD; ModuleName: PChar): string;
{$ifdef OSWINDOWS}
var
  tmpLen: DWORD;
  err: PChar;
{$endif OSWINDOWS}
begin
  result := '';
  if Code = 0 then
    exit;
  {$ifdef OSWINDOWS}
  tmpLen := FormatMessage(
    FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_ALLOCATE_BUFFER,
    pointer(GetModuleHandle(ModuleName)), Code, ENGLISH_LANGID, @err, 0, nil);
  try
    while (tmpLen > 0) and
          (ord(err[tmpLen - 1]) in [0..32, ord('.')]) do
      dec(tmpLen);
    SetString(result, err, tmpLen);
  finally
    LocalFree(HLOCAL(err));
  end;
  {$endif OSWINDOWS}
  if result = '' then
  begin
    result := SysErrorMessage(Code);
    if result = '' then
      if Code = ERROR_WINHTTP_CANNOT_CONNECT then
        result := 'cannot connect'
      else if Code = ERROR_WINHTTP_TIMEOUT then
        result := 'timeout'
      else if Code = ERROR_WINHTTP_INVALID_SERVER_RESPONSE then
        result := 'invalid server response'
      else
        result := IntToHex(Code, 8);
  end;
end;

procedure RaiseLastModuleError(ModuleName: PChar; ModuleException: ExceptClass);
var
  LastError: integer;
  Error: Exception;
begin
  LastError := GetLastError;
  if LastError <> 0 then
    Error := ModuleException.CreateFmt('%s error %x (%s)',
      [ModuleName, LastError, SysErrorMessagePerModule(LastError, ModuleName)])
  else
    Error := ModuleException.CreateFmt('Undefined %s error', [ModuleName]);
  raise Error;
end;

function Unicode_CodePage: integer;
begin
  result := GetACP;
end;

function Unicode_CompareString(PW1, PW2: PWideChar; L1, L2: PtrInt;
  IgnoreCase: boolean): integer;
const
  _CASEFLAG: array[boolean] of DWORD = (0, NORM_IGNORECASE);
begin
  result := CompareStringW(LOCALE_USER_DEFAULT, _CASEFLAG[IgnoreCase], PW1, L1, PW2, L2);
end;

procedure Unicode_WideToShort(W: PWideChar; LW, CodePage: PtrInt;
  var res: shortstring);
var
  i: PtrInt;
begin
  if LW <= 0 then
    res[0] := #0
  else if (LW <= 255) and
          IsAnsiCompatibleW(W, LW) then
  begin
    // fast handling of pure English content
    res[0] := AnsiChar(LW);
    i := 1;
    repeat
      res[i] := AnsiChar(W^);
      if i = LW then
        break;
      inc(W);
      inc(i);
    until false;
  end
  else
    // use ICU or cwstring/RTL for accurate conversion
    res[0] := AnsiChar(
      Unicode_WideToAnsi(W, PAnsiChar(@res[1]), LW, 255, CodePage));
end;

function NowUtc: TDateTime;
begin
  result := UnixMSTimeUtcFast / MSecsPerDay + UnixDelta;
end;

function DateTimeToWindowsFileTime(DateTime: TDateTime): integer;
var
  YY, MM, DD, H, m, s, ms: word;
begin
  DecodeDate(DateTime, YY, MM, DD);
  DecodeTime(DateTime, h, m, s, ms);
  if (YY < 1980) or
     (YY > 2099) then
    result := 0
  else
    result := (s shr 1) or (m shl 5) or (h shl 11) or
              integer((DD shl 16) or (MM shl 21) or (word(YY - 1980) shl 25));
end;

function ValidHandle(Handle: THandle): boolean;
begin
  result := PtrInt(Handle) > 0;
end;

function SearchRecToDateTime(const F: TSearchRec): TDateTime;
begin
  {$ifdef ISDELPHIXE}
  result := F.Timestamp; // use new API
  {$else}
  result := FileDateToDateTime(F.Time);
  {$endif ISDELPHIXE}
end;

function SearchRecValidFile(const F: TSearchRec): boolean;
begin
  result := (F.Name <> '') and
            (F.Attr and faInvalidFile = 0);
end;

function SearchRecValidFolder(const F: TSearchRec): boolean;
begin
  result := (F.Attr and faDirectoryMask = faDirectory) and
            (F.Name <> '') and
            (F.Name <> '.') and
            (F.Name <> '..');
end;

{$ifdef FPC}
type
  // FPC TFileStream miss a Create(aHandle) constructor like Delphi
  TFileStreamFromHandle = class(THandleStream)
  public
    destructor Destroy; override;
  end;

destructor TFileStreamFromHandle.Destroy;
begin
  FileClose(Handle); // otherwise file is still opened
end;

{$else}

type
  TFileStreamFromHandle = TFileStream;

{$endif FPC}

function FileStreamSequentialRead(const FileName: string): THandleStream;
begin
  result := TFileStreamFromHandle.Create(FileOpenSequentialRead(FileName));
end;

function StringFromFile(const FileName: TFileName; HasNoSize: boolean): RawByteString;
var
  F: THandle;
  Read, Size, Chunk: integer;
  P: PUtf8Char;
  tmp: array[0..$7fff] of AnsiChar; // 32KB stack buffer
begin
  result := '';
  if FileName = '' then
    exit;
  F := FileOpenSequentialRead(FileName);
  if ValidHandle(F) then
  begin
    if HasNoSize then
    begin
      Size := 0;
      repeat
        Read := FileRead(F, tmp, SizeOf(tmp));
        if Read <= 0 then
          break;
        SetLength(result, Size + Read); // in-place resize
        MoveFast(tmp, PByteArray(result)^[Size], Read);
        inc(Size, Read);
      until false;
    end
    else
    begin
      Size := FileSize(F);
      if Size > 0 then
      begin
        SetLength(result, Size);
        P := pointer(result);
        repeat
          Chunk := Size;
          Read := FileRead(F, P^, Chunk);
          if Read <= 0 then
          begin
            result := '';
            break;
          end;
          inc(P, Read);
          dec(Size, Read);
        until Size = 0;
      end;
    end;
    FileClose(F);
  end;
end;

function FileFromString(const Content: RawByteString; const FileName: TFileName;
  FlushOnDisk: boolean; FileDate: TDateTime): boolean;
var
  F: THandle;
  P: PByte;
  L, written: integer;
begin
  result := false;
  if FileName = '' then
    exit;
  F := FileCreate(FileName);
  if PtrInt(F) < 0 then
    exit;
  L := length(Content);
  P := pointer(Content);
  while L > 0 do
  begin
    written := FileWrite(F, P^, L);
    if written < 0 then
    begin
      FileClose(F);
      exit;
    end;
    dec(L, written);
    inc(P, written);
  end;
  if FlushOnDisk then
    FlushFileBuffers(F);
  {$ifdef OSWINDOWS}
  if FileDate <> 0 then
    FileSetDate(F, DateTimeToFileDate(FileDate));
  FileClose(F);
  {$else}
  FileClose(F); // POSIX expects the file to be closed to set the date
  if FileDate <> 0 then
    FileSetDate(FileName, DateTimeToFileDate(FileDate));
  {$endif OSWINDOWS}
  result := true;
end;

var
  _TmpCounter: integer;

function TemporaryFileName: TFileName;
var
  folder: TFileName;
  retry: integer;
begin
  // fast cross-platform implementation
  folder := GetSystemPath(spTempFolder);
  if _TmpCounter = 0 then
    _TmpCounter := Random32;
  retry := 10;
  repeat
    // thread-safe unique file name generation
    result := Format('%s%s_%x.tmp', [folder, Executable.ProgramName,
      InterlockedIncrement(_TmpCounter)]);
    if not FileExists(result) then
      exit;
    dec(retry); // no endless loop
  until retry = 0;
  raise EOSException.Create('TemporaryFileName failed');
end;

function DirectoryDelete(const Directory: TFileName; const Mask: TFileName;
  DeleteOnlyFilesNotDirectory: boolean; DeletedCount: PInteger): boolean;
var
  F: TSearchRec;
  Dir: TFileName;
  n: integer;
begin
  n := 0;
  result := true;
  if DirectoryExists(Directory) then
  begin
    Dir := IncludeTrailingPathDelimiter(Directory);
    if FindFirst(Dir + Mask, faAnyFile - faDirectory, F) = 0 then
    begin
      repeat
        if SearchRecValidFile(F) then
          if DeleteFile(Dir + F.Name) then
            inc(n)
          else
            result := false;
      until FindNext(F) <> 0;
      FindClose(F);
    end;
    if not DeleteOnlyFilesNotDirectory and
       not RemoveDir(Dir) then
      result := false;
  end;
  if DeletedCount <> nil then
    DeletedCount^ := n;
end;

function DirectoryDeleteOlderFiles(const Directory: TFileName;
  TimePeriod: TDateTime; const Mask: TFileName; Recursive: boolean;
  TotalSize: PInt64): boolean;
var
  F: TSearchRec;
  Dir: TFileName;
  old: TDateTime;
begin
  if not Recursive and
     (TotalSize <> nil) then
    TotalSize^ := 0;
  result := true;
  if (Directory = '') or
     not DirectoryExists(Directory) then
    exit;
  Dir := IncludeTrailingPathDelimiter(Directory);
  if FindFirst(Dir + Mask, faAnyFile, F) = 0 then
  begin
    old := Now - TimePeriod;
    repeat
      if SearchRecValidFolder(F) then
      begin
        if Recursive then
          DirectoryDeleteOlderFiles(
            Dir + F.Name, TimePeriod, Mask, true, TotalSize);
      end
      else if SearchRecValidFile(F) and
              (SearchRecToDateTime(F) < old) then
        if not DeleteFile(Dir + F.Name) then
          result := false
        else if TotalSize <> nil then
          inc(TotalSize^, F.Size);
    until FindNext(F) <> 0;
    FindClose(F);
  end;
end;

function IsDirectoryWritable(const Directory: TFileName): boolean;
var
  dir, fn: TFileName;
  f: THandle;
  retry: integer;
begin
  dir := ExcludeTrailingPathDelimiter(Directory);
  result := false;
  if FileIsReadOnly(dir) then
    exit;
  retry := 20;
  repeat
    fn := Format('%s' + PathDelim + '%x.test', [dir, Random32]);
    if not FileExists(fn) then
      break;
    dec(retry); // never loop forever
    if retry = 0 then
      exit;
  until false;
  f := FileCreate(fn);
  if PtrInt(f) < 0 then
    exit;
  FileClose(f);
  result := DeleteFile(fn);
end;

{$ifndef NOEXCEPTIONINTERCEPT}

{$ifdef WITH_RAISEPROC} // for FPC on Win32 + Linux (Win64=WITH_VECTOREXCEPT)
var
  OldRaiseProc: TExceptProc;

procedure SynRaiseProc(Obj: TObject; Addr: CodePointer;
  FrameCount: integer; Frame: PCodePointer);
var
  ctxt: TSynLogExceptionContext;
  backuplasterror: DWORD;
  backuphandler: TOnRawLogException;
begin
  if Assigned(_RawLogException) then
    if (Obj <> nil) and
       Obj.InheritsFrom(Exception) then
    begin
      backuplasterror := GetLastError;
      backuphandler := _RawLogException;
      try
        _RawLogException := nil; // disable exception
        ctxt.EClass := PPointer(Obj)^;
        ctxt.EInstance := Exception(Obj);
        ctxt.EAddr := PtrUInt(Addr);
        if Obj.InheritsFrom(EExternal) then
          ctxt.ELevel := sllExceptionOS
        else
          ctxt.ELevel := sllException;
        ctxt.ETimestamp := UnixTimeUtc;
        ctxt.EStack := pointer(Frame);
        ctxt.EStackCount := FrameCount;
        backuphandler(ctxt);
      except
        { ignore any nested exception }
      end;
      _RawLogException := backuphandler;
      SetLastError(backuplasterror); // may have changed above
    end;
  if Assigned(OldRaiseProc) then
    OldRaiseProc(Obj, Addr, FrameCount, Frame);
end;

{$endif WITH_RAISEPROC}

procedure RawExceptionIntercept(const Handler: TOnRawLogException);
begin
  _RawLogException := Handler;
  if not Assigned(Handler) then
    exit;
  {$ifdef WITH_RAISEPROC} // FPC RTL redirection function
  if @RaiseProc <> @SynRaiseProc then
  begin
    OldRaiseProc := RaiseProc;
    RaiseProc := @SynRaiseProc; // register once
  end;
  {$endif WITH_RAISEPROC}
  {$ifdef WITH_VECTOREXCEPT} // Win64 official API
  // RemoveVectoredContinueHandler() is available under 64 bit editions only
  if Assigned(AddVectoredExceptionHandler) then
  begin
    AddVectoredExceptionHandler(0, @SynLogVectoredHandler);
    AddVectoredExceptionHandler := nil; // register once
  end;
  {$endif WITH_VECTOREXCEPT}
  {$ifdef WITH_RTLUNWINDPROC} // Delphi x86 RTL redirection function
  if @RTLUnwindProc <> @SynRtlUnwind then
  begin
    oldUnWindProc := RTLUnwindProc;
    RTLUnwindProc := @SynRtlUnwind;
  end;
  {$endif WITH_RTLUNWINDPROC}
end;

{$endif NOEXCEPTIONINTERCEPT}


{ TMemoryMap }

function TMemoryMap.Map(aFile: THandle; aCustomSize: PtrUInt;
  aCustomOffset: Int64; aFileOwned: boolean): boolean;
var
  Available: Int64;
begin
  fBuf := nil;
  fBufSize := 0;
  {$ifdef OSWINDOWS}
  fMap := 0;
  {$endif OSWINDOWS}
  fFileLocal := aFileOwned;
  fFile := aFile;
  fFileSize := FileSeek64(fFile, 0, soFromEnd);
  if fFileSize = 0 then
  begin
    result := true; // handle 0 byte file without error (but no memory map)
    exit;
  end;
  result := false;
  if (fFileSize <= 0)
     {$ifdef CPU32} or (fFileSize > maxInt){$endif} then
    // maxInt = $7FFFFFFF = 1.999 GB (2GB would induce PtrInt errors on CPU32)
    exit;
  if aCustomSize = 0 then
    fBufSize := fFileSize
  else
  begin
    Available := fFileSize - aCustomOffset;
    if Available < 0 then
      exit;
    if aCustomSize > Available then
      fBufSize := Available;
    fBufSize := aCustomSize;
  end;
  fLoadedNotMapped := fBufSize < 1 shl 20;
  if fLoadedNotMapped then
  begin
    // mapping is not worth it for size < 1MB which can be just read at once
    GetMem(fBuf, fBufSize);
    FileSeek64(fFile, aCustomOffset, soFromBeginning);
    result := PtrUInt(FileRead(fFile, fBuf^, fBufSize)) = fBufSize;
    if not result then
    begin
      Freemem(fBuf);
      fBuf := nil;
      fLoadedNotMapped := false;
    end;
  end
  else
    // call actual Windows/POSIX map API
    result := DoMap(aCustomOffset);
end;

procedure TMemoryMap.Map(aBuffer: pointer; aBufferSize: PtrUInt);
begin
  fBuf := aBuffer;
  fFileSize := aBufferSize;
  fBufSize := aBufferSize;
  {$ifdef OSWINDOWS}
  fMap := 0;
  {$endif OSWINDOWS}
  fFile := 0;
  fFileLocal := false;
end;

function TMemoryMap.Map(const aFileName: TFileName): boolean;
var
  F: THandle;
begin
  result := false;
  // Memory-mapped file access does not go through the cache manager so
  // using FileOpenSequentialRead() is pointless here
  F := FileOpen(aFileName, fmOpenRead or fmShareDenyNone);
  if not ValidHandle(F) then
    exit;
  if Map(F) then
    result := true
  else
    FileClose(F);
  fFileLocal := result;
end;

procedure TMemoryMap.UnMap;
begin
  if fLoadedNotMapped then
    // mapping was not worth it
    Freemem(fBuf)
  else
    // call actual Windows/POSIX map API
    DoUnMap;
  fBuf := nil;
  fBufSize := 0;
  if fFile <> 0 then
  begin
    if fFileLocal then
      FileClose(fFile);
    fFile := 0;
  end;
end;

function TMemoryMap.TextFileKind: TTextFileKind;
begin
  result := isAnsi;
  if (fBuf <> nil) and
     (fBufSize >= 3) then
    if PWord(fBuf)^ = $FEFF then
      result := isUnicode
    else if (PWord(fBuf)^ = $BBEF) and
            (PByteArray(fBuf)[2] = $BF) then
      result := isUtf8;
end;


{ TSynMemoryStreamMapped }

constructor TSynMemoryStreamMapped.Create(const aFileName: TFileName;
  aCustomSize: PtrUInt; aCustomOffset: Int64);
begin
  fFileName := aFileName;
  // Memory-mapped file access does not go through the cache manager so
  // using FileOpenSequentialRead() is pointless here
  fFileStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyNone);
  Create(fFileStream.Handle, aCustomSize, aCustomOffset);
end;

constructor TSynMemoryStreamMapped.Create(aFile: THandle;
  aCustomSize: PtrUInt; aCustomOffset: Int64);
begin
  if not fMap.Map(aFile, aCustomSize, aCustomOffset) then
    raise EOSException.CreateFmt('%s.Create(%s) mapping error',
      [ClassNameShort(self)^, fFileName]);
  inherited Create(fMap.fBuf, fMap.fBufSize);
end;

destructor TSynMemoryStreamMapped.Destroy;
begin
  fMap.UnMap;
  fFileStream.Free;
  inherited;
end;


{ TExecutableResource }

function TExecutableResource.Open(const ResourceName: string; ResType: PChar;
  Instance: THandle): boolean;
begin
  result := false;
  if Instance = 0 then
    Instance := HInstance;
  HResInfo := FindResource(Instance, PChar(ResourceName), ResType);
  if HResInfo = 0 then
    exit;
  HGlobal := LoadResource(Instance, HResInfo);
  if HGlobal = 0 then // direct decompression from memory mapped .exe content
    exit;
  Buffer := LockResource(HGlobal);
  Size := SizeofResource(Instance, HResInfo);
  result := true;
end;

procedure TExecutableResource.Close;
begin
  if HGlobal <> 0 then
  begin
    UnlockResource(HGlobal); // only needed outside of Windows
    FreeResource(HGlobal);
    HGlobal := 0;
  end;
end;


{ ReserveExecutableMemory() / TFakeStubBuffer }

type
  // internal memory buffer created with PAGE_EXECUTE_READWRITE flags
  TFakeStubBuffer = class
  protected
    fStub: PByteArray;
    fStubUsed: cardinal;
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  CurrentFakeStubBuffer: TFakeStubBuffer;
  CurrentFakeStubBuffers: array of TFakeStubBuffer;
  {$ifdef UNIX}
  MemoryProtection: boolean = false; // set to true if PROT_EXEC seems to fail
  {$endif UNIX}

constructor TFakeStubBuffer.Create;
begin
  {$ifdef OSWINDOWS}
  fStub := VirtualAlloc(nil, STUB_SIZE, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  if fStub = nil then
  {$else OSWINDOWS}
  if not MemoryProtection then
    fStub := StubCallAllocMem(STUB_SIZE, PROT_READ or PROT_WRITE or PROT_EXEC);
  if (fStub = MAP_FAILED) or
     MemoryProtection then
  begin
    // i.e. on OpenBSD, we can have w^x protection
    fStub := StubCallAllocMem(STUB_SIZE, PROT_READ OR PROT_WRITE);
    if fStub <> MAP_FAILED then
      MemoryProtection := True;
  end;
  if fStub = MAP_FAILED then
  {$endif OSWINDOWS}
    raise EOSException.Create('ReserveExecutableMemory(): OS memory allocation failed');
end;

destructor TFakeStubBuffer.Destroy;
begin
  {$ifdef OSWINDOWS}
  VirtualFree(fStub, 0, MEM_RELEASE);
  {$else}
  fpmunmap(fStub, STUB_SIZE);
  {$endif OSWINDOWS}
  inherited;
end;

function ReserveExecutableMemory(size: cardinal): pointer;
begin
  if size > STUB_SIZE then
    raise EOSException.CreateFmt('ReserveExecutableMemory(size=%d>%d)',
      [size, STUB_SIZE]);
  GlobalLock;
  try
    if (CurrentFakeStubBuffer <> nil) and
       (CurrentFakeStubBuffer.fStubUsed + size > STUB_SIZE) then
      CurrentFakeStubBuffer := nil;
    if CurrentFakeStubBuffer = nil then
    begin
      CurrentFakeStubBuffer := TFakeStubBuffer.Create;
      ObjArrayAdd(CurrentFakeStubBuffers, CurrentFakeStubBuffer);
    end;
    with CurrentFakeStubBuffer do
    begin
      result := @fStub[fStubUsed];
      inc(fStubUsed, size);
    end;
  finally
    GlobalUnLock;
  end;
end;

{$ifdef UNIX}
procedure ReserveExecutableMemoryPageAccess(Reserved: pointer; Exec: boolean);
var
  PageAlignedFakeStub: pointer;
  flags: cardinal;
begin
  if not MemoryProtection then
    // nothing to be done on this platform
    exit;
  // toggle execution permission of memory to be able to write into memory
  PageAlignedFakeStub := Pointer(
    (PtrUInt(Reserved) div SystemInfo.dwPageSize) * SystemInfo.dwPageSize);
  if Exec then
    flags := PROT_READ OR PROT_EXEC
  else
    flags := PROT_READ or PROT_WRITE;
  if SynMProtect(PageAlignedFakeStub, SystemInfo.dwPageSize shl 1, flags) < 0 then
     raise EOSException.Create('ReserveExecutableMemoryPageAccess(: SynMProtect write failure');
end;
{$else}
procedure ReserveExecutableMemoryPageAccess(Reserved: pointer; Exec: boolean);
begin
  // nothing to be done
end;
{$endif UNIX}

{$ifndef PUREMORMOT2}

function GetDelphiCompilerVersion: RawUtf8;
begin
  result := COMPILER_VERSION;
end;

{$endif PUREMORMOT2}

function ConsoleReadBody: RawByteString;
var
  len, n: integer;
  P: PByte;
begin
  result := '';
  len := ConsoleStdInputLen;
  SetLength(result, len);
  P := pointer(result);
  while len > 0 do
  begin
    n := FileRead(StdInputHandle, P^, len);
    if n <= 0 then
    begin
      result := ''; // read error
      break;
    end;
    dec(len, n);
    inc(P, n);
  end;
end;

{$I-}

procedure ConsoleWrite(const Text: RawUtf8; Color: TConsoleColor;
  NoLineFeed, NoColor: boolean);
begin
  if not NoColor then
    TextColor(Color);
  write(Utf8ToConsole(Text));
  if not NoLineFeed then
    writeln;
  ioresult;
end;

{$I+}


{ TSynLibrary }

function TSynLibrary.Resolve(ProcName: PAnsiChar; Entry: PPointer;
  RaiseExceptionOnFailure: ExceptionClass): boolean;
begin
  if (Entry = nil) or
     (fHandle = 0) or
     (ProcName = nil) then
    result := false // avoid GPF
  else
  begin
    Entry^ := LibraryResolve(fHandle, ProcName);
    result := Entry^ <> nil;
  end;
  if (RaiseExceptionOnFailure <> nil) and
     not result then
  begin
    FreeLib;
    raise RaiseExceptionOnFailure.CreateFmt('%s.Resolve(''%s''): not found in %s',
      [ClassNameShort(self)^, ProcName, LibraryPath]);
  end;
end;

procedure TSynLibrary.FreeLib;
begin
  if fHandle = 0 then
    exit; // nothing to free
  LibraryClose(fHandle);
  fHandle := 0;
end;

function TSynLibrary.TryLoadLibrary(const aLibrary: array of TFileName;
  aRaiseExceptionOnFailure: ExceptionClass): boolean;
var
  i: integer;
  lib, libs {$ifdef OSWINDOWS} , nwd, cwd {$endif}: TFileName;
begin
  for i := 0 to high(aLibrary) do
  begin
    lib := aLibrary[i];
    if lib = '' then
      continue;
    {$ifdef OSWINDOWS}
    nwd := ExtractFilePath(lib);
    if nwd <> '' then
    begin
      cwd := GetCurrentDir;
      SetCurrentDir(nwd); // change the current folder at loading on Windows
    end;
    fHandle := SafeLoadLibrary(lib);
    if nwd <> '' then
      SetCurrentDir(cwd{%H-});
    {$else}
    fHandle := LibraryOpen(lib); // use regular .so loading behavior
    {$endif OSWINDOWS}
    if fHandle <> 0 then
    begin
      fLibraryPath := GetModuleName(fHandle);
      if length(fLibraryPath) < length(lib) then
        fLibraryPath := lib;
      result := true;
      exit;
    end;
    if {%H-}libs = '' then
      libs := lib
    else
      libs := libs + ', ' + lib;
  end;
  result := false;
  if aRaiseExceptionOnFailure <> nil then
    raise aRaiseExceptionOnFailure.CreateFmt('%s.TryLoadLibray failed' +
      ' - searched in %s', [ClassNameShort(self)^, libs]);
end;

destructor TSynLibrary.Destroy;
begin
  FreeLib;
  inherited Destroy;
end;


{ TFileVersion }

function TFileVersion.Version32: integer;
begin
  result := Major shl 16 + Minor shl 8 + Release;
end;

procedure TFileVersion.SetVersion(aMajor, aMinor, aRelease, aBuild: integer);
begin
  Major := aMajor;
  Minor := aMinor;
  Release := aRelease;
  Build := aBuild;
  Main := Format('%d.%d', [Major, Minor]);
  fDetailed := Format('%d.%d.%d.%d', [Major, Minor, Release, Build]);
  fVersionInfo :=  '';
  fUserAgent := '';
end;

function TFileVersion.BuildDateTimeString: string;
begin
  result := DateTimeToIsoString(fBuildDateTime);
end;

function TFileVersion.DetailedOrVoid: string;
begin
  if (self = nil) or
     (Major or Minor or Release or Build = 0) then
    result := ''
  else
    result := fDetailed;
end;

function TFileVersion.VersionInfo: RawUtf8;
begin
  if self = nil then
    result := ''
  else
  begin
    if fVersionInfo = '' then
      fVersionInfo := RawUtf8(Format('%s %s (%s)', [ExtractFileName(fFileName),
        DetailedOrVoid, BuildDateTimeString]));
    result := fVersionInfo;
  end;
end;

function TFileVersion.UserAgent: RawUtf8;
begin
  if self = nil then
    result := ''
  else
  begin
    if fUserAgent = '' then
    begin
      fUserAgent := RawUtf8(Format('%s/%s%s', [GetFileNameWithoutExt(
        ExtractFileName(fFileName)), DetailedOrVoid, OS_INITIAL[OS_KIND]]));
      {$ifdef OSWINDOWS}
      if OSVersion in WINDOWS_32 then
        fUserAgent := fUserAgent + '32';
      {$endif OSWINDOWS}
    end;
    result := fUserAgent;
  end;
end;

class function TFileVersion.GetVersionInfo(const aFileName: TFileName): RawUtf8;
begin
  with Create(aFileName, 0, 0, 0, 0) do
  try
    result := VersionInfo;
  finally
    Free;
  end;
end;

procedure SetExecutableVersion(const aVersionText: RawUtf8);
var
  P: PAnsiChar;
  i: integer;
  ver: array[0..3] of integer;
begin
  P := pointer(aVersionText);
  for i := 0 to 3 do
    ver[i] := GetNextCardinal(P);
  SetExecutableVersion(ver[0], ver[1], ver[2], ver[3]);
end;

procedure SetExecutableVersion(aMajor, aMinor, aRelease, aBuild: integer);
begin
  with Executable do
  begin
    if Version = nil then
    begin
      {$ifdef OSWINDOWS}
      ProgramFileName := paramstr(0);
      {$else}
      ProgramFileName := GetModuleName(HInstance);
      if ProgramFileName = '' then
        ProgramFileName := ExpandFileName(paramstr(0));
      {$endif OSWINDOWS}
      ProgramFilePath := ExtractFilePath(ProgramFileName);
      if IsLibrary then
        InstanceFileName := GetModuleName(HInstance)
      else
        InstanceFileName := ProgramFileName;
      ProgramName := RawUtf8(GetFileNameWithoutExt(ExtractFileName(ProgramFileName)));
      GetUserHost(User, Host);
      if Host = '' then
        Host := 'unknown';
      if User = '' then
        User := 'unknown';
      Version := TFileVersion.Create(
        InstanceFileName, aMajor, aMinor, aRelease, aBuild);
    end
    else
      Version.SetVersion(aMajor, aMinor, aRelease, aBuild);
    ProgramFullSpec := RawUtf8(Format('%s %s (%s)', [ProgramFileName,
      Version.Detailed, Version.BuildDateTimeString]));
    Hash.c0 := Version.Version32;
    {$ifdef CPUINTEL}
    Hash.c0 := crc32c(Hash.c0, @CpuFeatures, SizeOf(CpuFeatures));
    {$endif CPUINTEL}
    Hash.c0 := crc32c(Hash.c0, pointer(Host), length(Host));
    Hash.c1 := crc32c(Hash.c0, pointer(User), length(User));
    Hash.c2 := crc32c(Hash.c1, pointer(ProgramFullSpec), length(ProgramFullSpec));
    Hash.c3 := crc32c(Hash.c2, pointer(InstanceFileName), length(InstanceFileName));
  end;
end;

const
  // hexstr() is not available on Delphi -> use our own simple version
  HexCharsLower: array[0..15] of AnsiChar = '0123456789abcdef';

function _GetExecutableLocation(aAddress: pointer): shortstring;
var
  i: PtrInt;
  b: PByte;
begin
  result[0] := AnsiChar(SizeOf(aAddress) * 2);
  b := @aAddress;
  for i := SizeOf(aAddress) - 1 downto 0 do
  begin
    result[i * 2 + 1] := HexCharsLower[b^ shr 4];
    result[i * 2 + 2] := HexCharsLower[b^ and $F];
    inc(b);
  end;
end;


{ **************** TSynLocker Threading Features }

var
  GlobalCriticalSection: TRTLCriticalSection;

procedure GlobalLock;
begin
  EnterCriticalSection(GlobalCriticalSection);
end;

procedure GlobalUnLock;
begin
  LeaveCriticalSection(GlobalCriticalSection);
end;

procedure _SetThreadName(ThreadID: TThreadID; const Format: RawUtf8;
  const Args: array of const);
begin
  // do nothing - properly implemented in mormot.core.log
end;

procedure SetCurrentThreadName(const Format: RawUtf8; const Args: array of const);
begin
  SetThreadName(GetCurrentThreadId, Format, Args);
end;

procedure SetCurrentThreadName(const Name: RawUtf8);
begin
  SetThreadName(GetCurrentThreadId, '%', [Name]);
end;

function GetCurrentThreadName: RawUtf8;
begin
  ShortStringToAnsi7String(CurrentThreadName, result);
end;


function NewSynLocker: PSynLocker;
begin
  result := AllocMem(SizeOf(TSynLocker));
  InitializeCriticalSection(result^.fSection);
  result^.fInitialized := true;
end;


{ TAutoLock }

constructor TAutoLock.Create(aLock: PSynLocker);
begin
  fLock := aLock;
  fLock^.Lock;
end;

destructor TAutoLock.Destroy;
begin
  fLock^.UnLock;
end;


{ TSynLocker }

procedure TSynLocker.Init;
begin
  fSectionPadding := 0;
  PaddingUsedCount := 0;
  InitializeCriticalSection(fSection);
  fLocked := false;
  fInitialized := true;
end;

procedure TSynLocker.Done;
var
  i: PtrInt;
begin
  for i := 0 to PaddingUsedCount - 1 do
    if not (integer(Padding[i].VType) in VTYPE_SIMPLE) then
      VarClear(variant(Padding[i]));
  DeleteCriticalSection(fSection);
  fInitialized := false;
end;

procedure TSynLocker.DoneAndFreeMem;
begin
  Done;
  FreeMem(@self);
end;

procedure TSynLocker.Lock;
begin
  EnterCriticalSection(fSection);
  fLocked := true;
end;

procedure TSynLocker.UnLock;
begin
  fLocked := false;
  LeaveCriticalSection(fSection);
end;

function TSynLocker.TryLock: boolean;
begin
  result := not fLocked and
            (TryEnterCriticalSection(fSection) <> 0);
end;

function TSynLocker.TryLockMS(retryms: integer): boolean;
begin
  repeat
    result := TryLock;
    if result or
       (retryms <= 0) then
      break;
    SleepHiRes(1);
    dec(retryms);
  until false;
end;

function TSynLocker.ProtectMethod: IUnknown;
begin
  result := TAutoLock.Create(@self);
end;

function TSynLocker.GetVariant(Index: integer): Variant;
begin
  if cardinal(Index) < cardinal(PaddingUsedCount) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    result := variant(Padding[Index]);
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    VarClear(result);
end;

procedure TSynLocker.SetVariant(Index: integer; const Value: Variant);
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    if Index >= PaddingUsedCount then
      PaddingUsedCount := Index + 1;
    variant(Padding[Index]) := Value;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end;
end;

function TSynLocker.GetInt64(Index: integer): Int64;
begin
  if cardinal(Index) < cardinal(PaddingUsedCount) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    if not VariantToInt64(variant(Padding[Index]), result) then
      result := 0;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := 0;
end;

procedure TSynLocker.SetInt64(Index: integer; const Value: Int64);
begin
  SetVariant(Index, Value);
end;

function TSynLocker.GetBool(Index: integer): boolean;
begin
  if cardinal(Index) < cardinal(PaddingUsedCount) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    if not VariantToboolean(variant(Padding[Index]), result) then
      result := false;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := false;
end;

procedure TSynLocker.SetBool(Index: integer; const Value: boolean);
begin
  SetVariant(Index, Value);
end;

function TSynLocker.GetUnLockedInt64(Index: integer): Int64;
begin
  if (cardinal(Index) >= cardinal(PaddingUsedCount)) or
     not VariantToInt64(variant(Padding[Index]), result) then
    result := 0;
end;

procedure TSynLocker.SetUnlockedInt64(Index: integer; const Value: Int64);
begin
  if cardinal(Index) <= high(Padding) then
  begin
    if Index >= PaddingUsedCount then
      PaddingUsedCount := Index + 1;
    variant(Padding[Index]) := Value;
  end;
end;

function TSynLocker.GetPointer(Index: integer): Pointer;
begin
  if cardinal(Index) < cardinal(PaddingUsedCount) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    with Padding[Index] do
      if VType = varUnknown then
        result := VUnknown
      else
        result := nil;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := nil;
end;

procedure TSynLocker.SetPointer(Index: integer; const Value: Pointer);
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    if Index >= PaddingUsedCount then
      PaddingUsedCount := Index + 1;
    with Padding[Index] do
    begin
      if not (integer(VType) in VTYPE_SIMPLE) then
        VarClear(PVariant(@VType)^);
      VType := varUnknown;
      VUnknown := Value;
    end;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end;
end;

function TSynLocker.GetUtf8(Index: integer): RawUtf8;
begin
  if cardinal(Index) < cardinal(PaddingUsedCount) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    VariantStringToUtf8(variant(Padding[Index]), result);
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := '';
end;

procedure TSynLocker.SetUtf8(Index: integer; const Value: RawUtf8);
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    if Index >= PaddingUsedCount then
      PaddingUsedCount := Index + 1;
    RawUtf8ToVariant(Value, variant(Padding[Index]));
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end;
end;

function TSynLocker.LockedInt64Increment(Index: integer; const Increment: Int64): Int64;
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    result := 0;
    if Index < PaddingUsedCount then
      VariantToInt64(variant(Padding[Index]), result)
    else
      PaddingUsedCount := Index + 1;
    variant(Padding[Index]) := Int64(result + Increment);
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := 0;
end;

function TSynLocker.LockedExchange(Index: integer; const Value: Variant): Variant;
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    with Padding[Index] do
    begin
      if Index < PaddingUsedCount then
        result := PVariant(@VType)^
      else
      begin
        PaddingUsedCount := Index + 1;
        VarClear(result);
      end;
      PVariant(@VType)^ := Value;
    end;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    VarClear(result);
end;

function TSynLocker.LockedPointerExchange(Index: integer; Value: pointer): pointer;
begin
  if cardinal(Index) <= high(Padding) then
  try
    EnterCriticalSection(fSection);
    fLocked := true;
    with Padding[Index] do
    begin
      if Index < PaddingUsedCount then
        if VType = varUnknown then
          result := VUnknown
        else
        begin
          VarClear(PVariant(@VType)^);
          result := nil;
        end
      else
      begin
        PaddingUsedCount := Index + 1;
        result := nil;
      end;
      VType := varUnknown;
      VUnknown := Value;
    end;
  finally
    fLocked := false;
    LeaveCriticalSection(fSection);
  end
  else
    result := nil;
end;


{ TSynLocked }

constructor TSynLocked.Create;
begin
  fSafe := NewSynLocker;
end;

destructor TSynLocked.Destroy;
begin
  inherited Destroy;
  fSafe^.DoneAndFreeMem;
end;



{ ****************** Unix Daemon and Windows Service Support }

function ParseCommandArgs(const cmd: RawUtf8; argv: PParseCommandsArgs;
  argc: PInteger; temp: PRawUtf8; posix: boolean): TParseCommands;
var
  n: PtrInt;
  state: set of (sWhite, sInArg, sInSQ, sInDQ, sSpecial, sBslash);
  c: AnsiChar;
  D, P: PAnsiChar;
begin
  result := [pcInvalidCommand];
  if argv <> nil then
    argv[0] := nil;
  if argc <> nil then
    argc^ := 0;
  if cmd = '' then
    exit;
  if argv = nil then
    D := nil
  else
  begin
    if temp = nil then
      exit;
    SetLength(temp^, length(cmd));
    D := pointer(temp^);
  end;
  state := [];
  n := 0;
  P := pointer(cmd);
  repeat
    c := P^;
    if D <> nil then
      D^ := c;
    inc(P);
    case c of
      #0:
        begin
          if sInSQ in state then
            include(result, pcUnbalancedSingleQuote);
          if sInDQ in state then
            include(result, pcUnbalancedDoubleQuote);
          exclude(result, pcInvalidCommand);
          if argv <> nil then
            argv[n] := nil;
          if argc <> nil then
            argc^ := n;
          exit;
        end;
      #1 .. ' ':
        begin
         if state = [sInArg] then
         begin
           state := [];
           if D <> nil then
           begin
             D^ := #0;
             inc(D);
           end;
           continue;
         end;
         if state * [sInSQ, sInDQ] = [] then
           continue;
        end;
      '\':
        if posix and
           (state * [sInSQ, sBslash] = []) then
          if sInDQ in state then
          begin
            case P^ of
              '"', '\', '$', '`':
                begin
                  include(state, sBslash);
                  continue;
                end;
            end;
          end
          else if P^ = #0 then
          begin
            include(result, pcHasEndingBackSlash);
            exit;
          end
          else
          begin
            if D <> nil then
              D^ := P^;
            inc(P);
          end;
      '^':
        if not posix and
           (state * [sInSQ, sInDQ, sBslash] = []) then
          if PWord(P)^ = $0a0d then
          begin
            inc(P, 2);
            continue;
          end
          else if P^ = #0 then
          begin
            include(result, pcHasEndingBackSlash);
            exit;
          end
          else
          begin
            if D <> nil then
              D^ := P^;
            inc(P);
          end;
      '''':
        if posix and
           not(sInDQ in state) then
          if sInSQ in state then
          begin
            exclude(state, sInSQ);
            continue;
          end else if state = [] then
          begin
            if argv <> nil then
            begin
              argv[n] := D;
              inc(n);
              if n = high(argv^) then
                exit;
            end;
            state := [sInSQ, sInArg];
            continue;
          end else if state = [sInArg] then
          begin
            state := [sInSQ, sInArg];
            continue;
          end;
      '"':
        if not(sInSQ in state) then
          if sInDQ in state then
          begin
            exclude(state, sInDQ);
            continue;
          end else if state = [] then
          begin
            if argv <> nil then
            begin
              argv[n] := D;
              inc(n);
              if n = high(argv^) then
                exit;
            end;
            state := [sInDQ, sInArg];
            continue;
          end
          else if state = [sInArg] then
          begin
            state := [sInDQ, sInArg];
            continue;
          end;
      '|', '<', '>':
        if state * [sInSQ, sInDQ] = [] then
          include(result, pcHasRedirection);
      '&', ';':
        if posix and
           (state * [sInSQ, sInDQ] = []) then
        begin
          include(state, sSpecial);
          include(result, pcHasJobControl);
        end;
      '`':
        if posix and
           (state * [sInSQ, sBslash] = []) then
           include(result, pcHasSubCommand);
      '(', ')':
        if posix and
           (state * [sInSQ, sInDQ] = []) then
          include(result, pcHasParenthesis);
      '$':
        if posix and
           (state * [sInSQ, sBslash] = []) then
          if p^ = '(' then
            include(result, pcHasSubCommand)
          else
            include(result, pcHasShellVariable);
      '*', '?':
        if posix and
           (state * [sInSQ, sInDQ] = []) then
          include(result, pcHasWildcard);
    end;
    exclude(state, sBslash);
    if state = [] then
    begin
      if argv <> nil then
      begin
        argv[n] := D;
        inc(n);
        if n = high(argv^) then
          exit;
      end;
      state := [sInArg];
    end;
    if D <> nil then
      inc(D);
  until false;
end;


procedure FinalizeUnit;
begin
  ObjArrayClear(CurrentFakeStubBuffers);
  Executable.Version.Free;
  DeleteCriticalSection(AutoSlotsLock);
  DeleteCriticalSection(GlobalCriticalSection);
  FinalizeSpecificUnit; // in mormot.core.os.posix/windows.inc files
end;

initialization
  {$ifdef ISFPC27}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  {$endif ISFPC27}
  InitializeCriticalSection(GlobalCriticalSection);
  InitializeCriticalSection(AutoSlotsLock);
  InitializeUnit; // in mormot.core.os.posix/windows.inc files
  OSVersionShort := ToTextOS(OSVersionInt32);
  SetExecutableVersion(0,0,0,0);
  GetExecutableLocation := _GetExecutableLocation;
  SetThreadName := _SetThreadName;

finalization
  FinalizeUnit;

end.


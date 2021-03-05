/// Framework Core Cryptographic Process using OpenSSL
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.core.crypto.openssl;

{
  *****************************************************************************

   High-Performance Cryptographic Features using OpenSSL 1.1.1
    - OpenSSL Cryptographic Pseudorandom Number Generator (CSPRNG)
    - AES Cypher/Uncypher in various Modes
    - Hashers and Signers OpenSSL Wrappers
    - OpenSSL Asymetric Cryptography
    - JWT Implementation using any OpenSSL Algorithm
    - Register OpenSSL to our General Cryptography Catalog

  *****************************************************************************

  TL;DR: On x86_64, our mormot.core.crypto.pas asm is stand-alone and faster
         than OpenSSL for most algorithms, and only 20% slower for AES-GCM.
         For ECC, our mormot.core.ecc256r1 is noticeably slower than OpenSSL.

   Legal Notice: as stated by our LICENSE.md terms, make sure that you comply
   to any restriction about the use of cryptographic software in your country.
}

interface

{$I ..\mormot.defines.inc}

{$ifdef USE_OPENSSL}

// compile as a void unit if USE_OPENSSL is not defined

uses
  classes,
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.crypto,
  mormot.core.ecc256r1,
  mormot.core.secure,
  mormot.core.jwt,
  mormot.lib.openssl11;


{ ************** OpenSSL Cryptographic Pseudorandom Number Generator (CSPRNG) }

type
  /// exception class raised by the AES classes of this unit
  EOpenSslCrypto = class(EOpenSsl);

  /// TAesPrng-compatible class using OpenSSL 1.1.1
  // - we abbreviate OpenSsl as Osl in class names for brevity
  // - may be used instead of TAesPrng if a "proven" generator is required -
  // you could override MainAesPrng global variable
  // - but mormot.core.crypto TAesPrng is faster, especially for small output,
  // and use a similar and proven 256-bit AES-CTR source of randomness:
  // $  OpenSSL Random32 in 288.71ms i.e. 346,363/s, aver. 2us, 1.3 MB/s
  // $  mORMot Random32 in 3.95ms i.e. 25,303,643/s, aver. 0us, 96.5 MB/s
  // $  OpenSSL FillRandom in 240us, 397.3 MB/s
  // $  mORMot FillRandom in 46us, 2 GB/s
  TAesPrngOsl = class(TAesPrngAbstract)
  public
    /// initialize the CSPRNG using OpenSSL 1.1.1
    // - if the library is not available, will raise an Exception
    constructor Create; override;
    /// wrapper around function OpenSslIsAvailable
    class function IsAvailable: boolean; override;
    /// fill a binary buffer with some pseudorandom data
    // - this method is thread-safe
    // - is just a wrapper around RAND_bytes() API call
    procedure FillRandom(Buffer: pointer; Len: PtrInt); override;
    /// returns the single system-wide instance of TAesPrngOsl
    // - if you need to generate some random content, just call the
    // TAesPrngOsl.Main.FillRandom() overloaded methods, or directly
    // TAesPrngOsl.Fill() class methods
    class function Main: TAesPrngAbstract; override;
  end;


{ ************** AES Cypher/Uncypher in various Modes }

type
  /// reusable wrapper around OpenSSL Cipher process
  TAesOsl = object
  public
    Owner: TAesAbstract;
    Cipher: PEVP_CIPHER; // computed from TAesAbstractOsl.AlgoName
    Ctx: array[boolean] of PEVP_CIPHER_CTX; // set and reused in CallEvp()
    procedure Init(aOwner: TAesAbstract; aCipherName: PUtf8Char);
    procedure Done;
    procedure SetEvp(DoEncrypt: boolean; const method: string);
    procedure UpdEvp(DoEncrypt: boolean; BufIn, BufOut: pointer; Count: cardinal);
    procedure Clone(ToOwner: TAesAbstract; out ToAesOsl: TAesOsl);
  end;

  /// handle AES cypher/uncypher with chaining with OpenSSL 1.1
  // - we abbreviate OpenSsl as Osl in class names for brevity
  // - use any of the inherited implementation, corresponding to the chaining
  // mode required - TAesEcbOsl, TAesCbcOsl, TAesCfbOsl, TAesOfbOsl and TAesCtrOsl
  // classes to handle in ECB, CBC, CFB, OFB and CTR mode (including PKCS7-like padding)
  // - those classes are re-entrant, i.e. that you can call the Encrypt*
  // or Decrypt* methods on the same instance several times
  TAesAbstractOsl = class(TAesAbstract)
  protected
    fAes: TAesOsl;
    procedure AfterCreate; override; // circumvent Delphi bug about const aKey
  public
    /// creates a new instance with the very same values
    // - directly copy the existing OpenSSL context for efficiency
    function Clone: TAesAbstract; override;
    /// compute a class instance similar to this one, for performing the
    // reverse encryption/decryption process
    // - will return self to avoid creating two instances
    function CloneEncryptDecrypt: TAesAbstract; override;
    /// release the used instance memory and resources
    destructor Destroy; override;
    /// wrapper around function OpenSslIsAvailable
    // - actual cipher won't be checked until Create() since we need the keysize
    class function IsAvailable: boolean; override;
    /// perform the AES cypher in the corresponding mode
    procedure Encrypt(BufIn, BufOut: pointer; Count: cardinal); override;
    /// perform the AES un-cypher in the corresponding mode
    procedure Decrypt(BufIn, BufOut: pointer; Count: cardinal); override;
  end;

  /// OpenSSL AES cypher/uncypher without chaining (ECB)
  // - this mode is known to be less secure than the others
  TAesEcbOsl = class(TAesAbstractOsl)
  protected
    procedure AfterCreate; override;
  end;

  /// OpenSSL AES cypher/uncypher with Cipher-block chaining (CBC)
  TAesCbcOsl = class(TAesAbstractOsl)
  protected
    procedure AfterCreate; override;
  end;

  /// OpenSSL AES cypher/uncypher with Cipher feedback (CFB)
  // - our TAesCfb class is faster than OpenSSL on x86_64:
  // $  mormot aes-128-cfb in 6.95ms i.e. 359247/s or 764.5 MB/s
  // $  mormot aes-256-cfb in 9.40ms i.e. 265816/s or 565.7 MB/s
  // $  openssl aes-128-cfb in 10.53ms i.e. 237326/s or 505 MB/s
  // $  openssl aes-256-cfb in 13.18ms i.e. 189652/s or 403.6 MB/s
  TAesCfbOsl = class(TAesAbstractOsl)
  protected
    procedure AfterCreate; override;
  end;

  /// OpenSSL AES cypher/uncypher with Output feedback (OFB)
  // - our TAesOfb class is faster than OpenSSL on x86_64:
  // $  mormot aes-128-ofb in 6.88ms i.e. 363002/s or 772.5 MB/s
  // $  mormot aes-256-ofb in 9.37ms i.e. 266808/s or 567.8 MB/s
  // $  openssl aes-128-ofb in 7.82ms i.e. 319693/s or 680.3 MB/s
  // $  openssl aes-256-ofb in 10.39ms i.e. 240523/s or 511.8 MB/s
  TAesOfbOsl = class(TAesAbstractOsl)
  protected
    procedure AfterCreate; override;
  end;

  /// OpenSSL AES cypher/uncypher with 128-bit Counter mode (CTR)
  // - similar to TAesCtrNist, not our proprietary TAesCtrAny with a 64-bit CTR
  // - our TAesCtrNist class is faster than OpenSSL on x86_64:
  // $  mormot aes-128-ctr in 1.99ms i.e. 1254390/s or 2.6 GB/s
  // $  mormot aes-256-ctr in 2.64ms i.e. 945179/s or 1.9 GB/s
  // $  openssl aes-128-ctr in 2.23ms i.e. 1121076/s or 2.3 GB/s
  // $  openssl aes-256-ctr in 2.80ms i.e. 891901/s or 1.8 GB/s
  TAesCtrOsl = class(TAesAbstractOsl)
  protected
    procedure AfterCreate; override;
  end;

  /// OpenSSL AES-GCM cypher/uncypher
  // - implements AEAD (authenticated-encryption with associated-data) process
  // via MacSetNonce/MacEncrypt or AesGcmAad/AesGcmFinal methods
  // - OpenSSL is faster than our TAesGcm class, but not so much:
  // $  openssl aes-128-gcm in 2.86ms i.e. 874125/s or 1.8 GB/s
  // $  openssl aes-256-gcm in 3.43ms i.e. 727590/s or 1.5 GB/s
  // $  mormot aes-128-gcm in 3.45ms i.e. 722752/s or 1.5 GB/s
  // $  mormot aes-256-gcm in 4.11ms i.e. 607385/s or 1.2 GB/s
  TAesGcmOsl = class(TAesGcmAbstract)
  protected
    fAes: TAesOsl;
    function AesGcmInit: boolean; override; // from fKey/fKeySize
    procedure AesGcmDone; override;
    procedure AesGcmReset; override; // from fIV/CTR_POS
    function AesGcmProcess(BufIn, BufOut: pointer; Count: cardinal): boolean; override;
  public
    /// creates a new instance with the very same values
    // - by design, our classes will use TAesGcmEngine stateless context, so
    // this method will just copy the current fields to a new instance,
    // by-passing the key creation step
    function Clone: TAesAbstract; override;
    /// compute a class instance similar to this one, for performing the
    // reverse encryption/decryption process
    // - will return self to avoid creating two instances
    function CloneEncryptDecrypt: TAesAbstract; override;
    /// AES-GCM pure alternative to MacSetNonce()
    // - set the IV as usual (only the first 12 bytes will be used for GCM),
    // then optionally append any AEAD data with this method; warning: you need
    // to call Encrypt() once before - perhaps as Encrypt(nil, nil, 0)
    procedure AesGcmAad(Buf: pointer; Len: integer); override;
    /// AES-GCM pure alternative to MacEncryptGetTag/MacDecryptCheckTag
    // - after Encrypt, fill tag with the GCM value of the data and return true
    // - after Decrypt, return true only if the GCM value of the data match tag
    function AesGcmFinal(var tag: TAesBlock): boolean; override;
  end;


{ ************** Hashers and Signers OpenSSL Wrappers }

type
  /// exception class raised by the hashing classes of this unit
  EOpenSslHash = class(EOpenSsl);

  /// abstract parent multi-algorithm hashing/HMAC wrapper for OpenSSL
  TOpenSslDigestAbstract = class
  private
    fDigestSize: cardinal;
    fDigestValue: THash512Rec;
  public
    /// wrapper around function OpenSslIsAvailable
    class function IsAvailable: boolean;
    /// call this method for each continuous message block
    // - iterate over all message blocks, then call Digest to retrieve the HMAC
    procedure Update(Data: pointer; DataLength: integer); overload; virtual; abstract;
    /// call this method for each continuous message block
    procedure Update(const Data: RawByteString); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// computes the hash of all supplied messages
    // - store it internally the DigestValue buffer, or copy it into Dest buffer
    // which is typically a THash256 or THash512 variable
    // - returns actual DigestValue/Dest buffer length, i.e. DigestSize
    function Digest(Dest: pointer = nil): cardinal; virtual; abstract;
    /// computes the Hash/HMAC of all supplied message as lowercase hexa chars
    function DigestHex: RawUtf8;
    /// raw access to the final Message Digest, after a call to the Digest method
    // - if HashSize as supplied to Create() is bigger than 64, first bytes will
    // be truncated in this field - you should specify a buffer to Digest() call
    property DigestValue: THash512Rec
      read fDigestValue;
    /// how many bytes have been stored in DigestValues, after a call to Digest
    property DigestSize: cardinal
      read fDigestSize;
  end;

  /// convenient multi-algorithm wrapper for OpenSSL Hash algorithms
  TOpenSslHash = class(TOpenSslDigestAbstract)
  private
    fCtx: PEVP_MD_CTX;
    fXof: boolean;
  public
    /// initialize the internal hashing structure for a specific algorithm
    // - Algorithm is one of `openssl list -digest-algorithms`
    // - if Algorithm is not specified, EVP_sha256 will be used
    // - for XOF hash functions such as 'shake256', the hashSize option
    // can be used to specify the desired output length in bytes
    // - raise an EOpenSslHash exception on unknown/unsupported algorithm
    constructor Create(const Algorithm: RawUtf8; HashSize: cardinal = 0);
    /// call this method for each continuous message block
    // - iterate over all message blocks, then call Digest to retrieve the Hash
    procedure Update(Data: pointer; DataLength: integer); override;
    /// computes the hash of all supplied messages
    // - store it internally the DigestValue buffer, or copy it into Dest buffer
    // which is typically a THash256 or THash512 variable
    // - returns actual DigestValue/Dest buffer length, i.e. DigestSize
    function Digest(Dest: pointer = nil): cardinal; override;
    /// compute the message authentication code using `Algorithm` as hash function
    class function Hash(const Algorithm: RawUtf8; const Data: RawByteString;
      HashSize: cardinal = 0): RawUtf8;
    /// release the digest context
    destructor Destroy; override;
  end;

  /// convenient multi-algorithm wrapper for OpenSSL HMAC algorithms
  TOpenSslHmac = class(TOpenSslDigestAbstract)
  private
    fCtx: PHMAC_CTX;
  public
    /// initialize the internal HMAC structure for a specific Algorithm and Key
    // - Algorithm is one of `openssl list -digest-algorithms`
    // - if Algorithm is not specified, EVP_sha256 will be used
    // - Key/KeyLen define the HMAC associated salt
    // - raise an EOpenSslHash exception on unknown/unsupported algorithm
    constructor Create(const Algorithm: RawUtf8;
      Key: pointer; KeyLength: cardinal); overload;
    /// initialize the internal HMAC structure for a specific Algorithm and Key
    constructor Create(const Algorithm: RawUtf8;
      const Key: RawByteString); overload;
    /// call this method for each continuous message block
    // - iterate over all message blocks, then call Digest to retrieve the Hash
    procedure Update(Data: pointer; DataLength: integer); override;
    /// computes the HMAC of all supplied messages
    // - store it internally the DigestValue buffer, or copy it into Dest buffer
    // which is typically a THash256 or THash512 variable
    // - returns actual DigestValue/Dest buffer length, i.e. DigestSize
    function Digest(Dest: pointer = nil): cardinal; override;
    /// compute the HMAC using `algorithm` as hash function
    class function Hmac(const Algorithm: RawUtf8; const Data: RawByteString;
      Key: pointer; KeyLength: cardinal): RawUtf8; overload;
    /// compute the HMAC using `algorithm` as hash function
    class function Hmac(const Algorithm: RawUtf8;
      const Data, Key: RawByteString): RawUtf8; overload;
    /// release the digest context
    destructor Destroy; override;
  end;


{ ************** OpenSSL Asymetric Cryptography }

type
  /// exception class raised by the sign/verify classes of this unit
  EOpenSslAsymetric = class(EOpenSsl);

/// asymetric digital signature of some Message using a given PrivateKey
// - if Algorithm is '', EVP_sha256 will be used as message Digest
// - if Algorithm is 'null', no Digest is done before signature - which is
// mandatory e.g. for ed25519 which uses internally SHA-512
// - returns 0 on error, or the result Signature size in bytes
function OpenSslSign(const Algorithm: RawUtf8;
  Message, PrivateKey: pointer; MessageLen, PrivateKeyLen: integer;
  out Signature: RawByteString; const PrivateKeyPassword: RawUtf8 = '';
  const Engine: RawUtf8 = ''): cardinal;

/// asymetric digital verification of some Message using a given PublicKey
// - if Algorithm is '', EVP_sha256 will be used as message Digest
// - if Algorithm is 'null', no Digest is done before signature - which is
// mandatory e.g. for ed25519 which uses internally SHA-512
// - returns false on error, or true if the Message has been authenticated
function OpenSslVerify(const Algorithm, PublicKeyPassword: RawUtf8;
  Message, PublicKey, Signature: pointer;
  MessageLen, PublicKeyLen, SignatureLen: integer;
  const Engine: RawUtf8 = ''): boolean;

/// generate a public/private pair of keys
// - if EvpType is EVP_PKEY_DSA, EVP_PKEY_DH or EVP_PKEY_RSA or EVP_PKEY_RSA_PSS,
// BitsOrCurve is the number of bits of the key
// - if EvpType is EVP_PKEY_EC, BitsOrCurve is the curve NID (e.g.
// NID_X9_62_prime256v1)
// - if EvpType is EVP_PKEY_ED25519, BitsOrCurve is ignored
// - caller should EVP_PKEY_free() the result
function OpenSslGenerateKeys(EvpType, BitsOrCurve: integer): PEVP_PKEY; overload;

/// persist a public/private pair of keys
procedure OpenSslSaveKeys(Keys: PEVP_PKEY;
  out PrivateKey, PublicKey: RawByteString);

/// generate a public/private pair of keys in PEM text format
// - if EvpType is EVP_PKEY_DSA, EVP_PKEY_DH or EVP_PKEY_RSA or EVP_PKEY_RSA_PSS,
// BitsOrCurve is the number of bits of the key
// - if EvpType is EVP_PKEY_EC, BitsOrCurve is the Elliptic curve NID (e.g.
// NID_X9_62_prime256v1)
// - if EvpType is EVP_PKEY_ED25519, BitsOrCurve is ignored
procedure OpenSslGenerateKeys(EvpType, BitsOrCurve: integer;
  out PrivateKey, PublicKey: RawByteString); overload;


/// mormot.core.ecc256r1 compatible function for asymetric key generation
// - this OpenSSL-powered function will replace our slower mormot.core.ecc256r1
// $ OpenSSL: 300 Ecc256r1MakeKey in 7.75ms i.e. 38,664/s, aver. 25us
// $ mORMot:  300 Ecc256r1MakeKey in 255ms i.e. 1,176/s, aver. 850us
// - directly access OpenSSL prime256v1, so faster than OpenSslGenerateKeys()
function ecc_make_key_osl(out PublicKey: TEccPublicKey;
  out PrivateKey: TEccPrivateKey): boolean;

/// mormot.core.ecc256r1 compatible function for asymetric key signature
// - this OpenSSL-powered function will replace our slower pascal/c code
// $ OpenSSL: 300 Ecc256r1Sign in 11.66ms i.e. 25,711/s, aver. 38us
// $ mORMot:  300 Ecc256r1Sign in 262.72ms i.e. 1,141/s, aver. 875us
// - directly access OpenSSL prime256v1, so faster than OpenSslSign()
function ecdsa_sign_osl(const PrivateKey: TEccPrivateKey; const Hash: TEccHash;
  out Signature: TEccSignature): boolean;

/// mormot.core.ecc256r1 compatible function for asymetric key verification
// - this OpenSSL-powered function will replace our slower pascal/c code
// $ OpenSSL: 300 Ecc256r1Verify in 41.32ms i.e. 7,260/s, aver. 137us
// $ mORMot:  300 Ecc256r1Verify in 319.32ms i.e. 939/s, aver. 1.06ms
// - directly access OpenSSL prime256v1, so faster than OpenSslVerify()
function ecdsa_verify_osl(const PublicKey: TEccPublicKey; const Hash: TEccHash;
  const Signature: TEccSignature): boolean;

/// mormot.core.ecc256r1 compatible function for ECDH shared secret computation
// - this OpenSSL-powered function will replace our slower pascal/c code
// $ OpenSSL: 598 Ecc256r1SharedSecret in 67.98ms i.e. 8,796/s, aver. 113us
// $ mORMot:  598 Ecc256r1SharedSecret in 537.95ms i.e. 1,111/s, aver. 899us
function ecdh_shared_secret_osl(const PublicKey: TEccPublicKey;
  const PrivateKey: TEccPrivateKey; out Secret: TEccSecretKey): boolean;



{ ************** JWT Implementation using any OpenSSL Algorithm }

type
  /// implements JSON Web Tokens using OpenSSL Algorithms
  TJwtOpenSsl = class(TJwtAbstract)
  protected
    fPrivateKey, fPublicKey: RawByteString;
    fPrivateKeyPassword, fPublicKeyPassword: RawUtf8;
    fHashAlgorithm: RawUtf8;
    fGenEvpType: integer;
    fGenBitsOrCurve: integer;
    function ComputeSignature(const headpayload: RawUtf8): RawUtf8; override;
    procedure CheckSignature(const headpayload: RawUtf8; const signature: RawByteString;
      var JWT: TJwtContent); override;
  public
    /// initialize the JWT processing instance using any supported OpenSSL algorithm
    constructor Create(const aJwtAlgorithm, aHashAlgorithm: RawUtf8;
      aGenEvpType, aGenBitsOrCurve: integer;
      const aPrivateKey, aPublicKey: RawByteString;
      const aPrivateKeyPassword, aPublicKeyPassword: RawUtf8;
      aClaims: TJwtClaims; const aAudience: array of RawUtf8;
      aExpirationMinutes: integer = 0; aIDIdentifier: TSynUniqueIdentifierProcess = 0;
      aIDObfuscationKey: RawUtf8 = ''; aIDObfuscationKeyNewKdf: integer = 0);
      reintroduce;
    /// finalize the instance
    destructor Destroy; override;
    /// wrapper around function OpenSslIsAvailable
    class function IsAvailable: boolean;
    /// the OpenSSL hash algorithm, as supplied to the constructor
    property HashAlgorithm: RawUtf8
      read fHashAlgorithm;
  end;

  /// abstract parent for OpenSSL JWT algorithms - never use this plain class!
  // - inherited classes implement all official algorithms from https://jwt.io
  // - we abbreviate OpenSsl as Osl in class names for brevity
  // - some numbers from our regresssion tests on Linux x86_64 for JWT validation:
  // $ 100 RS256 in 5.11ms i.e. 19,550/s, aver. 51us
  // $ 100 RS384 in 5.09ms i.e. 19,642/s, aver. 50us
  // $ 100 RS512 in 5.12ms i.e. 19,508/s, aver. 51us
  // $ 100 PS256 in 5.41ms i.e. 18,474/s, aver. 54us
  // $ 100 PS384 in 5.38ms i.e. 18,563/s, aver. 53us
  // $ 100 PS512 in 5.33ms i.e. 18,740/s, aver. 53us
  // $ 100 ES256 in 13.75ms i.e. 7,270/s, aver. 137us
  // $ 100 ES384 in 118.64ms i.e. 842/s, aver. 1.18ms
  // $ 100 ES512 in 93.95ms i.e. 1,064/s, aver. 939us
  // $ 100 ES256K in 62.19ms i.e. 1,607/s, aver. 621us
  // $ 100 EdDSA in 18.08ms i.e. 5,529/s, aver. 180us
  TJwtAbstractOsl = class(TJwtOpenSsl)
  protected
    procedure SetAlgorithms; virtual; abstract; // set fHashAlgo+fHashAlgorithm
  public
    /// initialize the JWT processing instance calling SetAlgorithms abstract method
    // - the supplied set of claims are expected to be defined in the JWT payload
    // - aAudience are the allowed values for the jrcAudience claim
    // - aExpirationMinutes is the deprecation time for the jrcExpirationTime claim
    // - aIDIdentifier and aIDObfuscationKey/aIDObfuscationKeyNewKdf are passed
    // to a TSynUniqueIdentifierGenerator instance used for jrcJwtID claim
    constructor Create(
      const aPrivateKey, aPublicKey: RawByteString;
      const aPrivateKeyPassword, aPublicKeyPassword: RawUtf8;
      aClaims: TJwtClaims; const aAudience: array of RawUtf8;
      aExpirationMinutes: integer = 0; aIDIdentifier: TSynUniqueIdentifierProcess = 0;
      aIDObfuscationKey: RawUtf8 = ''; aIDObfuscationKeyNewKdf: integer = 0);
      reintroduce;
    /// generate a private/public keys pair for this algorithm in PEM text format
    class procedure GenerateKeys(out PrivateKey, PublicKey: RawByteString);
  end;

  /// meta-class of all OpenSSL JWT algorithms
  TJwtAbstractOslClass = class of TJwtAbstractOsl;

  /// implements 'ES256' secp256r1 ECC algorithm over SHA-256 using OpenSSL
  TJwtES256Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'ES384' secp384r1 ECC algorithm over SHA-384 using OpenSSL
  TJwtES384Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'ES512' ecp521r1 ECC algorithm over SHA-512 using OpenSSL
  TJwtES512Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'ES256K' secp256k1 ECC algorithm using OpenSSL
  TJwtES256KOsl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'RS256' RSA 2048-bit algorithm over SHA-256 using OpenSSL
  TJwtRS256Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'RS384' RSA 2048-bit algorithm over SHA-384 using OpenSSL
  TJwtRS384Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'RS512' RSA 2048-bit algorithm over SHA-512 using OpenSSL
  TJwtRS512Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'PS256' RSA-PSS 2048-bit algorithm over SHA-256 using OpenSSL
  TJwtPS256Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'PS384' RSA-PSS 2048-bit algorithm over SHA-384 using OpenSSL
  TJwtPS384Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'PS512' RSA-PSS 2048-bit algorithm over SHA-512 using OpenSSL
  TJwtPS512Osl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;

  /// implements 'EdDSA' Ed25519 algorithm using OpenSSL
  TJwtEdDSAOsl = class(TJwtAbstractOsl)
  protected
    procedure SetAlgorithms; override;
  end;


{ ************** Register OpenSSL to our General Cryptography Catalog }

/// call once at program startup to use OpenSSL when its performance matters
// - redirects TAesGcmFast (and TAesCtrFast on i386) globals to OpenSSL
// - redirects raw mormot.core.ecc256r1 functions to use OpenSSL which is much
// faster than our stand-alone C/pascal version
procedure RegisterOpenSsl;


implementation


{ TAesOsl }

procedure TAesOsl.Init(aOwner: TAesAbstract; aCipherName: PUtf8Char);
begin
  Owner := aOwner;
  EOpenSslCrypto.CheckAvailable(PClass(Owner)^, 'Create');
  Cipher := EVP_get_cipherbyname(aCipherName);
  if Cipher = nil then
    raise EOpenSslCrypto.CreateFmt('%s.Create: unknown ''%s'' cipher',
      [ClassNameShort(Owner)^, aCipherName]);
end;

procedure TAesOsl.Done;
begin
  if Ctx[false] <> nil then
    EVP_CIPHER_CTX_free(Ctx[false]);
  if Ctx[true] <> nil then
    EVP_CIPHER_CTX_free(Ctx[true]);
end;

procedure TAesOsl.SetEvp(DoEncrypt: boolean; const method: string);
var
  c: PEVP_CIPHER_CTX;
begin
  c := Ctx[DoEncrypt];
  if c = nil then
  begin
    // setup encrypt/decrypt context, with the proper key and no padding
    c := EVP_CIPHER_CTX_new;
    EOpenSslCrypto.Check(Owner, method,
      EVP_CipherInit_ex(c, Cipher, nil,
        @TAesAbstractOsl(Owner).fKey, nil, ord(DoEncrypt)));
    EOpenSslCrypto.Check(Owner, method,
      EVP_CIPHER_CTX_set_padding(c, 0));
    Ctx[DoEncrypt] := c;
  end;
  // OpenSSL allows to reuse the previous Ctxt[], just setting the (new) IV
  EOpenSslCrypto.Check(Owner, method,
    EVP_CipherInit_ex(c, nil, nil, nil, @Owner.IV, ord(DoEncrypt)));
end;

procedure TAesOsl.UpdEvp(DoEncrypt: boolean; BufIn, BufOut: pointer; Count: cardinal);
var
  outl: integer;
begin
  if (BufOut <> nil) and
     (Count and AesBlockMod <> 0) then
    raise ESynCrypto.CreateUtf8('%.%: Count=% is not a multiple of 16',
      [Owner, 'UpdEvp', Count]);
  EOpenSslCrypto.Check(Owner, 'UpdEvp',
    EVP_CipherUpdate(Ctx[DoEncrypt], BufOut, @outl, BufIn, Count));
  // no need to call EVP_CipherFinal_ex() since we expect no padding
end;

procedure TAesOsl.Clone(ToOwner: TAesAbstract; out ToAesOsl: TAesOsl);
var
  enc: boolean;
begin
  TAesAbstractOsl(ToOwner).fKeySize := TAesAbstractOsl(Owner).fKeySize;
  TAesAbstractOsl(ToOwner).fKeySizeBytes := TAesAbstractOsl(Owner).fKeySizeBytes;
  TAesAbstractOsl(ToOwner).fKey := TAesAbstractOsl(Owner).fKey;
  TAesAbstractOsl(ToOwner).fAlgoMode := TAesAbstractOsl(Owner).fAlgoMode;
  ToAesOsl.Owner := ToOwner;
  ToAesOsl.Cipher := Cipher;
  for enc := false to true do
    if Ctx[enc] <> nil then
    begin
      // efficient Ctx[] copy
      ToAesOsl.Ctx[enc] := EVP_CIPHER_CTX_new;
      EVP_CIPHER_CTX_copy(ToAesOsl.Ctx[enc], Ctx[enc]);
    end;
end;



{ ************** OpenSSL Cryptographic Pseudorandom Number Generator (CSPRNG) }

{ TAesPrngOsl }

class function TAesPrngOsl.IsAvailable: boolean;
begin
  result := OpenSslIsAvailable;
end;

constructor TAesPrngOsl.Create;
begin
  inherited Create;
  EOpenSslCrypto.CheckAvailable(PClass(self)^, 'Create');
end;

procedure TAesPrngOsl.FillRandom(Buffer: pointer; Len: PtrInt);
begin
  inc(fTotalBytes, Len);
  RAND_bytes(Buffer, Len);
end;

var
  MainAesPrngOsl: TAesPrngOsl;

class function TAesPrngOsl.Main: TAesPrngAbstract;
begin
  result := MainAesPrngOsl;
  if result <> nil then
    exit;
  EOpenSslCrypto.CheckAvailable(self, 'Main');
  GlobalLock;
  try
    if MainAesPrngOsl = nil then
      MainAesPrngOsl := TAesPrngOsl.Create;
  finally
    GlobalUnLock;
  end;
  result := MainAesPrngOsl;
end;


{ ************** AES Cypher/Uncypher in various Modes }

{ TAesAbstractOsl }

procedure TAesAbstractOsl.AfterCreate;
var
  nam: TShort16;
begin
  AlgoName(nam); // always #0 terminated
  fAes.Init(self, pointer(@nam[1]));
end;

destructor TAesAbstractOsl.Destroy;
begin
  fAes.Done;
  inherited Destroy;
end;

class function TAesAbstractOsl.IsAvailable: boolean;
begin
  result := OpenSslIsAvailable;
end;

procedure TAesAbstractOsl.Encrypt(BufIn, BufOut: pointer; Count: cardinal);
begin
  fAes.SetEvp({doencrypt=}true, 'Encrypt');
  fAes.UpdEvp({doencrypt=}true, BufIn, BufOut, Count);
end;

procedure TAesAbstractOsl.Decrypt(BufIn, BufOut: pointer; Count: cardinal);
begin
  fAes.SetEvp({doencrypt=}false, 'Decrypt');
  fAes.UpdEvp({doencrypt=}false, BufIn, BufOut, Count);
end;

function TAesAbstractOsl.Clone: TAesAbstract;
begin
  result := TAesAbstractOsl(NewInstance);
  fAes.Clone(result, TAesAbstractOsl(result).fAes); // efficient Ctx[] copy
end;

function TAesAbstractOsl.CloneEncryptDecrypt: TAesAbstract;
begin
  result := self; // there is one Ctx[] for each direction
end;


{ TAesEcbOsl }

procedure TAesEcbOsl.AfterCreate;
begin
  fAlgoMode := mEcb;
  inherited AfterCreate;
end;

{ TAesCbcOsl }

procedure TAesCbcOsl.AfterCreate;
begin
  fAlgoMode := mCbc;
  inherited AfterCreate;
end;

{ TAesCfbOsl }

procedure TAesCfbOsl.AfterCreate;
begin
  fAlgoMode := mCfb;
  inherited AfterCreate;
end;


{ TAesOfbOsl }

procedure TAesOfbOsl.AfterCreate;
begin
  fAlgoMode := mOfb;
  inherited AfterCreate;
end;

{ TAesCtrOsl }

procedure TAesCtrOsl.AfterCreate;
begin
  fAlgoMode := mCtr;
  inherited AfterCreate;
end;

{ TAesGcmOsl }

function TAesGcmOsl.AesGcmInit: boolean;
var
  nam: TShort16;
begin
  AlgoName(nam); // always #0 terminated
  fAes.Init(self, pointer(@nam[1]));
  result := nam[0] <> #0;
end;

procedure TAesGcmOsl.AesGcmDone;
begin
  fAes.Done;
end;

procedure TAesGcmOsl.AesGcmReset;
begin
  fAes.SetEvp(fStarted = stEnc, 'AesGcmProcess');
end;

function TAesGcmOsl.AesGcmProcess(BufIn, BufOut: pointer; Count: cardinal): boolean;
begin
  fAes.UpdEvp(fStarted = stEnc, BufIn, BufOut, Count);
  result := true;
end;

procedure TAesGcmOsl.AesGcmAad(Buf: pointer; Len: integer);
begin
  fAes.UpdEvp({encrypt=}true, Buf, nil, Len);
end;

function TAesGcmOsl.AesGcmFinal(var tag: TAesBlock): boolean;
var
  outl: integer;
  dummy: TAesBlock;
begin
  case fStarted of
    stEnc:
      begin
        EOpenSslCrypto.Check(self, 'AesGcmFinal enc',
          EVP_CipherFinal_ex(fAes.Ctx[true], @dummy, @outl));
        EOpenSslCrypto.Check(self, 'AesGcmFinal enctag',
          EVP_CIPHER_CTX_ctrl(fAes.Ctx[true], EVP_CTRL_GCM_GET_TAG, 16, @tag));
        result := true;
      end;
    stDec:
      begin
        EOpenSslCrypto.Check(self, 'AesGcmFinal dectag',
          EVP_CIPHER_CTX_ctrl(fAes.Ctx[false], EVP_CTRL_GCM_SET_TAG, 16, @tag));
        outl := 16;
        result := (EVP_CipherFinal_ex(fAes.Ctx[false], @dummy, @outl) > 0) and
                  (outl = 0);
      end
  else
    result := false;
  end;
  fStarted := stNone; // allow reuse of this fAes instance
end;

function TAesGcmOsl.Clone: TAesAbstract;
begin
  result := TAesGcmOsl(NewInstance);
  fAes.Clone(result, TAesGcmOsl(result).fAes); // efficient Ctx[] copy
end;

function TAesGcmOsl.CloneEncryptDecrypt: TAesAbstract;
begin
  result := self;
end;


{ ************** Hashers and Signers OpenSSL Wrappers }

{ TOpenSslDigestAbstract }

class function TOpenSslDigestAbstract.IsAvailable: boolean;
begin
  result := OpenSslIsAvailable;
end;

procedure TOpenSslDigestAbstract.Update(const Data: RawByteString);
begin
  Update(pointer(Data), length(Data));
end;

function TOpenSslDigestAbstract.DigestHex: RawUtf8;
begin
  BinToHexLower(@fDigestValue, Digest(nil), result{%H-});
end;


{ TOpenSslHash }

constructor TOpenSslHash.Create(const Algorithm: RawUtf8; HashSize: cardinal);
var
  md: PEVP_MD;
begin
  EOpenSslHash.CheckAvailable(PClass(self)^, 'Create');
  if Algorithm = '' then
    md := EVP_sha256
  else
    md := EVP_get_digestbyname(pointer(Algorithm));
  if md = nil then
    raise EOpenSslHash.CreateFmt(
      'TOpenSslHash.Create(''%s''): Unknown algorithm', [Algorithm]);
  fCtx := EVP_MD_CTX_new;
  EOpenSslHash.Check(self, 'Create',
    EVP_DigestInit_ex(fCtx, md, nil));
  fDigestSize := EVP_MD_size(md);
  fXof := EVP_MD_flags(md) and EVP_MD_FLAG_XOF <> 0;
  if (hashSize <> 0)  and
     (fDigestSize <> HashSize) then
    if fXof then
      // custom size in XOF mode
      fDigestSize := hashSize
    else
      raise EOpenSslHash.CreateFmt('TOpenSslHash.Create: Incorrect hashSize ' +
        'option passed to a non-XOF hash function "%s"', [Algorithm]);
end;

procedure TOpenSslHash.Update(Data: pointer; DataLength: integer);
begin
  EOpenSslHash.Check(self, 'Update',
    EVP_DigestUpdate(fCtx, Data, DataLength));
end;

function TOpenSslHash.Digest(Dest: pointer): cardinal;
begin
  result := EVP_MD_CTX_size(fCtx);
  if Dest = nil then
    if result > SizeOf(fDigestValue) then
      raise EOpenSslHash.CreateFmt(
        'TOpenSslHash.Digest(nil): size=%d overflow', [result])
    else
      Dest := @fDigestValue;
  if fXof then
    EOpenSslHash.Check(self, 'DigestXof',
      EVP_DigestFinalXOF(fCtx, Dest, fDigestSize))
  else
    EOpenSslHash.Check(self, 'Digest',
      EVP_DigestFinal_ex(fCtx, Dest, @fDigestSize));
  if Dest <> @fDigestValue then
  begin
    if fDigestSize > SizeOf(fDigestValue) then
      result := SizeOf(fDigestValue) // truncate to local copy in fXof mode
    else
      result := fDigestSize;
    MoveFast(Dest^, fDigestValue, result);
  end;
  result := fDigestSize;
end;

destructor TOpenSslHash.Destroy;
begin
   if fCtx <> nil then
     EVP_MD_CTX_free(fCtx);
  inherited Destroy;
end;

class function TOpenSslHash.Hash(const Algorithm: RawUtf8;
  const Data: RawByteString; HashSize: cardinal): RawUtf8;
begin
  with Create(Algorithm, HashSize) do
    try
      Update(Data);
      result := DigestHex;
    finally
      Free;
    end;
end;


{ TOpenSslHmac }

constructor TOpenSslHmac.Create(const Algorithm: RawUtf8;
  Key: pointer; KeyLength: cardinal);
var
  md: PEVP_MD;
begin
  EOpenSslHash.CheckAvailable(PClass(self)^, 'Create');
   if Algorithm = '' then
     md := EVP_sha256
   else
     md := EVP_get_digestbyname(pointer(Algorithm));
  if md = nil then
    raise EOpenSslHash.CreateFmt(
      'TOpenSslHmac.Create(''%s''): Unknown algorithm', [Algorithm]);
  fDigestSize := EVP_MD_size(md);
  fCtx := HMAC_CTX_new;
  EOpenSslHash.Check(self, 'Create',
    HMAC_Init_ex(fCtx, Key, KeyLength, md, nil));
end;

constructor TOpenSslHmac.Create(const Algorithm: RawUtf8;
  const Key: RawByteString);
begin
  Create(Algorithm, pointer(Key), length(Key));
end;

procedure TOpenSslHmac.Update(Data: pointer; DataLength: integer);
begin
  EOpenSslHash.Check(self, 'Update',
    HMAC_Update(fCtx, Data, DataLength));
end;

function TOpenSslHmac.Digest(Dest: pointer): cardinal;
begin
  EOpenSslHash.Check(self, 'Digest',
    HMAC_Final(fCtx, @fDigestValue, @fDigestSize));
  if Dest <> nil then
    MoveFast(fDigestValue, Dest^, fDigestSize);
  result := fDigestSize;
end;

class function TOpenSslHmac.Hmac(const Algorithm: RawUtf8;
  const Data: RawByteString; Key: pointer; KeyLength: cardinal): RawUtf8;
begin
  with Create(Algorithm, Key, KeyLength) do
    try
      Update(Data);
      result := DigestHex;
    finally
      Free;
    end;
end;

class function TOpenSslHmac.Hmac(const Algorithm: RawUtf8;
  const Data, Key: RawByteString): RawUtf8;
begin
  result := HMac(Algorithm, Data, pointer(Key), length(Key));
end;

destructor TOpenSslHmac.Destroy;
begin
  if fCtx <> nil then
    HMAC_CTX_free(fCtx);
  inherited Destroy;
end;


{ ************** OpenSSL Asymetric Cryptography }

function GetMd(const Algorithm, Caller: RawUtf8): PEVP_MD;
begin
  EOpenSslAsymetric.CheckAvailable(nil, Caller);
  if Algorithm = 'null' then
    result := nil // e.g. for ed25519
  else
    begin
      if Algorithm = '' then
        result := EVP_sha256
      else
        result := EVP_get_digestbyname(pointer(Algorithm));
      if result = nil then
        raise EOpenSslAsymetric.CreateFmt(
          '%: unknown [%] algorithm', [Caller, Algorithm]);
    end;
end;

function OpenSslSign(const Algorithm: RawUtf8;
  Message, PrivateKey: pointer; MessageLen, PrivateKeyLen: integer;
  out Signature: RawByteString; const PrivateKeyPassword, Engine: RawUtf8): cardinal;
var
  md: PEVP_MD;
  priv: PBIO;
  pkey: PEVP_PKEY;
  ctx: PEVP_MD_CTX;
  size: PtrUInt;
begin
  result := 0;
  md := GetMd(Algorithm, 'OpenSslSign');
  if (PrivateKey = nil) or
     (PrivateKeyLen = 0) then
  begin
    priv := nil;
    pkey := nil;
  end
  else
  begin
    priv := BIO_new_mem_buf(PrivateKey, PrivateKeyLen);
    pkey := PEM_read_bio_PrivateKey(priv, nil, nil, pointer(PrivateKeyPassword));
  end;
  ctx := EVP_MD_CTX_new;
  try
    // note: ED25519 requires single-pass EVP_DigestSign()
    if (EVP_DigestSignInit(ctx, nil, md, nil, pkey) = OPENSSLSUCCESS) and
       (EVP_DigestSign(ctx, nil, size, Message, MessageLen) = OPENSSLSUCCESS) then
    begin
      SetLength(Signature, size); // here size is maximum size
      if EVP_DigestSign(ctx, pointer(Signature), size,
           Message, MessageLen) = OPENSSLSUCCESS then
      begin
        if size <> length(Signature) then
          SetLength(Signature, size); // leading zeros may trim the size
        result := size;
      end
      else
        Signature := '';
    end {else WritelnSSL_error};
  finally
    EVP_MD_CTX_free(ctx);
    if pkey <> nil then
      EVP_PKEY_free(pkey);
    if priv <> nil then
      BIO_free(priv);
  end;
end;

function OpenSslVerify(const Algorithm, PublicKeyPassword: RawUtf8;
  Message, PublicKey, Signature: pointer;
  MessageLen, PublicKeyLen, SignatureLen: integer; const Engine: RawUtf8): boolean;
var
  md: PEVP_MD;
  pub: PBIO;
  pkey: PEVP_PKEY;
  ctx: PEVP_MD_CTX;
begin
  result := false;
  md := GetMd(Algorithm, 'OpenSslSign');
  if (PublicKey = nil) or
     (PublicKeyLen <= 0) or
     (SignatureLen <= 0)  then
    exit;
  pub := BIO_new_mem_buf(PublicKey, PublicKeyLen);
  if IdemPChar(PublicKey, '-----BEGIN RSA PUBLIC KEY-----') then
    pkey := PEM_read_bio_RSAPublicKey(pub, nil, nil, pointer(PublicKeyPassword))
  else
    pkey := PEM_read_bio_PUBKEY(pub, nil, nil, pointer(PublicKeyPassword));
  ctx := EVP_MD_CTX_new;
  try
    // note: ED25519 requires single-pass EVP_DigestVerify()
    if (EVP_DigestVerifyInit(ctx, nil, md, nil, pkey) = OPENSSLSUCCESS) and
       (EVP_DigestVerify(ctx, Signature, SignatureLen,
          Message, MessageLen) = OPENSSLSUCCESS) then
      result := true {else WritelnSSL_error};
  finally
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    BIO_free(pub);
  end;
end;

function OpenSslGenerateKeys(EvpType, BitsOrCurve: integer): PEVP_PKEY;
var
  ctx, kctx: PEVP_PKEY_CTX;
  par: PEVP_PKEY;
  ctrl: integer;
begin
  result := nil;
  EOpenSslAsymetric.CheckAvailable(nil, 'OpenSslGenerateKeys');
  ctx := EVP_PKEY_CTX_new_id(EvpType, nil);
  if ctx <> nil then
  try
    // see https://wiki.openssl.org/index.php/EVP_Key_and_Parameter_Generation
    case EvpType of
      EVP_PKEY_EC, EVP_PKEY_DSA, EVP_PKEY_DH:
        begin
          EOpenSsl.Check(EVP_PKEY_paramgen_init(ctx));
          case EvpType of
            EVP_PKEY_EC:
              ctrl := EVP_PKEY_CTRL_EC_PARAMGEN_CURVE_NID;
            EVP_PKEY_DSA, EVP_PKEY_DH:
              ctrl := EVP_PKEY_CTRL_DSA_PARAMGEN_BITS;
          end;
          EOpenSsl.Check(EVP_PKEY_CTX_ctrl(
            ctx, EvpType, EVP_PKEY_OP_PARAMGEN, ctrl, BitsOrCurve, nil));
          par := nil;
          EOpenSsl.Check(EVP_PKEY_paramgen(ctx, @par));
          kctx := EVP_PKEY_CTX_new(par, nil);
          if kctx = nil then
            EOpenSsl.Check(-1);
          try
            EOpenSsl.Check(EVP_PKEY_keygen_init(kctx));
            EOpenSsl.Check(EVP_PKEY_keygen(kctx, @result));
          finally
            EVP_PKEY_CTX_free(kctx);
          end;
        end;
      EVP_PKEY_RSA, EVP_PKEY_RSA_PSS, EVP_PKEY_ED25519:
        begin
          EOpenSsl.Check(EVP_PKEY_keygen_init(ctx));
          case EvpType of
            EVP_PKEY_RSA, EVP_PKEY_RSA_PSS:
              EOpenSsl.Check(EVP_PKEY_CTX_ctrl(ctx, EvpType, EVP_PKEY_OP_KEYGEN,
                EVP_PKEY_CTRL_RSA_KEYGEN_BITS, BitsOrCurve, nil));
          end;
          EOpenSsl.Check(EVP_PKEY_keygen(ctx, @result));
        end
      else
        exit; // unsupported type
    end;
  finally
    EVP_PKEY_CTX_free(ctx);
  end;
end;

procedure OpenSslSaveKeys(Keys: PEVP_PKEY;
  out PrivateKey, PublicKey: RawByteString);
var
  bio: PBIO;
  mem: BUF_MEM;
begin
  if (Keys = nil) or
     not OpenSslIsAvailable then
    exit;
  bio := BIO_new(BIO_s_mem);
  try
    EOpenSsl.Check(PEM_write_bio_PrivateKey(bio, Keys, nil, nil, 0, nil, nil));
    BIO_ToString(bio, PrivateKey);
    BIO_free(bio);
    bio := BIO_new(BIO_s_mem);
    EOpenSsl.Check(PEM_write_bio_PUBKEY(bio, Keys));
    BIO_ToString(bio, PublicKey);
  finally
    BIO_free(bio);
  end;
end;

procedure OpenSslGenerateKeys(EvpType, BitsOrCurve: integer;
  out PrivateKey, PublicKey: RawByteString);
var
  keys: PEVP_PKEY;
begin
  keys := OpenSslGenerateKeys(EvpType, BitsOrCurve);
  if keys = nil then
    raise EOpenSslHash.CreateFmt(
      'OpenSslGenerateKeys(%d,%d) failed', [EvpType, BitsOrCurve]);
  try
    OpenSslSaveKeys(keys, PrivateKey, PublicKey);
  finally
    EVP_PKEY_free(keys);
  end;
end;


var
  prime256v1grp: PEC_GROUP;

function NewPrime256v1Key(out key: PEC_KEY): boolean;
begin
  result := false;
  if prime256v1grp = nil then
    if OpenSslIsAvailable then
    begin
      GlobalLock;
      try
        if prime256v1grp = nil then
        begin
          prime256v1grp := EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1);
          if prime256v1grp = nil then
            prime256v1grp := pointer(1);
        end;
      finally
        GlobalUnLock;
      end;
    end
    else
      prime256v1grp := pointer(1);
  if prime256v1grp <> pointer(1) then
  begin
    key := EC_KEY_new;
    if EC_KEY_set_group(key, prime256v1grp) = OPENSSLSUCCESS then
      result := true
    else
    begin
      EC_GROUP_free(prime256v1grp);
      prime256v1grp := pointer(1);
      EC_KEY_free(key);
    end;
  end;
end;

function ecc_make_key_osl(out PublicKey: TEccPublicKey;
  out PrivateKey: TEccPrivateKey): boolean;
var
  key: PEC_KEY;
  pub: PPByte;
  priv: PBIGNUM;
  publen, privlen: integer;
begin
  result := false;
  if not NewPrime256v1Key(key) then
    exit;
  if EC_KEY_generate_key(key) = OPENSSLSUCCESS then
  begin
    priv := EC_KEY_get0_private_key(key);
    privlen := BN_num_bytes(priv);
    pub := nil;
    publen := EC_POINT_point2buf(prime256v1grp,
      EC_KEY_get0_public_key(key), POINT_CONVERSION_COMPRESSED, @pub, nil);
    if (publen = SizeOf(PublicKey)) and
       (privlen <= SizeOf(PrivateKey)) then
    begin
      FillZero(PrivateKey); // may be padded with zeros
      BN_bn2bin(priv, @PrivateKey[SizeOf(PrivateKey) - privlen]);
      MoveFast(pub^, PublicKey, publen);
      result := true;
    end;
    OPENSSL_free(pub);
  end;
  EC_KEY_free(key);
end;

function ecdsa_sign_osl(const PrivateKey: TEccPrivateKey; const Hash: TEccHash;
  out Signature: TEccSignature): boolean;
var
  key: PEC_KEY;
  bn: PBIGNUM;
  derlen: cardinal;
  der: TEccSignatureDer;
begin
  result := false;
  if not NewPrime256v1Key(key) then
    exit;
  bn := BN_bin2bn(@PrivateKey, SizeOf(PrivateKey), nil);
  derlen := 0;
  if (ECDSA_size(key) <= SizeOf(der)) and
     (EC_KEY_set_private_key(key, bn) = OPENSSLSUCCESS) and
     (ECDSA_Sign(0, @Hash, SizeOf(Hash), @der, @derlen, key) = OPENSSLSUCCESS) then
    result := DerToEccSign(der, Signature);
  BN_free(bn);
  EC_KEY_free(key);
end;

function PublicKeyToPoint(const PublicKey: TEccPublicKey; out pt: PEC_POINT): boolean;
begin
  pt := EC_POINT_new(prime256v1grp);
  result := EC_POINT_oct2point(prime256v1grp,
    pt, @PublicKey, SizeOf(PublicKey), nil) = OPENSSLSUCCESS;
end;

function ecdsa_verify_osl(const PublicKey: TEccPublicKey; const Hash: TEccHash;
  const Signature: TEccSignature): boolean;
var
  key: PEC_KEY;
  pt: PEC_POINT;
  derlen: integer;
  der: TEccSignatureDer;
begin
  result := false;
  if not NewPrime256v1Key(key) then
    exit;
  if PublicKeyToPoint(PublicKey, pt) and
     (EC_KEY_set_public_key(key, pt) = OPENSSLSUCCESS) then
  begin
    derlen := EccSignToDer(Signature, der);
    result := ECDSA_verify(0, @Hash, SizeOf(Hash), @der, derlen, key) = OPENSSLSUCCESS;
  end;
  EC_POINT_free(pt);
  EC_KEY_free(key);
end;

function ecdh_shared_secret_osl(const PublicKey: TEccPublicKey;
  const PrivateKey: TEccPrivateKey; out Secret: TEccSecretKey): boolean;
var
  key: PEC_KEY;
  pub: PEC_POINT;
  priv: PBIGNUM;
begin
  FillZero(Secret);
  result := false;
  if not NewPrime256v1Key(key) then
    exit;
  priv := BN_bin2bn(@PrivateKey, SizeOf(PrivateKey), nil);
  if PublicKeyToPoint(PublicKey, pub) and
     (EC_KEY_set_private_key(key, priv) = OPENSSLSUCCESS) and
     (ECDH_compute_key(@Secret, SizeOf(Secret), pub, key, nil) = SizeOf(Secret)) then
    result := true;
  BN_free(priv);
  EC_POINT_free(pub);
  EC_KEY_free(key);
end;


{ ************** JWT Implementation using any OpenSSL Algorithm }

{ TJwtOpenSsl }

constructor TJwtOpenSsl.Create(const aJwtAlgorithm, aHashAlgorithm: RawUtf8;
  aGenEvpType, aGenBitsOrCurve: integer;
  const aPrivateKey, aPublicKey: RawByteString;
  const aPrivateKeyPassword, aPublicKeyPassword: RawUtf8;
  aClaims: TJwtClaims; const aAudience: array of RawUtf8;
  aExpirationMinutes: integer; aIDIdentifier: TSynUniqueIdentifierProcess;
  aIDObfuscationKey: RawUtf8; aIDObfuscationKeyNewKdf: integer);
begin
  EOpenSsl.CheckAvailable(PClass(self)^, 'Create');
  fHashAlgorithm := aHashAlgorithm;
  fGenEvpType := aGenEvpType;
  fGenBitsOrCurve := aGenBitsOrCurve;
  fPrivateKey := aPrivateKey;
  fPrivateKeyPassword := aPrivateKeyPassword;
  fPublicKey := aPublicKey;
  fPublicKeyPassword := aPublicKeyPassword;
  inherited Create(aJwtAlgorithm, aClaims, aAudience, aExpirationMinutes,
    aIDIdentifier, aIDObfuscationKey, aIDObfuscationKeyNewKdf);
end;

destructor TJwtOpenSsl.Destroy;
begin
  FillZero(fPrivateKey);
  FillZero(fPrivateKeyPassword);
  FillZero(fPublicKey);
  FillZero(fPublicKeyPassword);
  inherited Destroy;
end;

class function TJwtOpenSsl.IsAvailable: boolean;
begin
  result := OpenSslIsAvailable;
end;

function TJwtOpenSsl.ComputeSignature(const headpayload: RawUtf8): RawUtf8;
var
  sign: RawByteString;
  signlen: integer;
begin
  signlen := OpenSslSign(fHashAlgorithm,
    pointer(headpayload), pointer(fPrivateKey),
    length(headpayload), length(fPrivateKey), sign, fPrivateKeyPassword);
  if signlen = 0 then
    raise EJwtException.CreateUtf8('%.ComputeSignature: OpenSslSign failed [%]',
      [self, SSL_error_short(ERR_get_error)]);
  result := BinToBase64Uri(sign);
end;

procedure TJwtOpenSsl.CheckSignature(const headpayload: RawUtf8;
  const signature: RawByteString; var JWT: TJwtContent);
begin
  if OpenSslVerify(fHashAlgorithm, fPublicKeyPassword,
       pointer(headpayload), pointer(fPublicKey), pointer(signature),
       length(headpayload), length(fPublicKey), length(signature)) then
    JWT.result := jwtValid
  else
    JWT.result := jwtInvalidSignature;
end;


{ TJwtAbstractOsl }

constructor TJwtAbstractOsl.Create(const aPrivateKey, aPublicKey: RawByteString;
  const aPrivateKeyPassword, aPublicKeyPassword: RawUtf8; aClaims: TJwtClaims;
  const aAudience: array of RawUtf8; aExpirationMinutes: integer;
  aIDIdentifier: TSynUniqueIdentifierProcess; aIDObfuscationKey: RawUtf8;
  aIDObfuscationKeyNewKdf: integer);
begin
  SetAlgorithms;
  inherited Create(fAlgorithm, fHashAlgorithm, fGenEvpType, fGenBitsOrCurve,
    aPrivateKey, aPublicKey, aPrivateKeyPassword, aPublicKeyPassword,
    aClaims, aAudience, aExpirationMinutes, aIDIdentifier,
    aIDObfuscationKey, aIDObfuscationKeyNewKdf);
end;

class procedure TJwtAbstractOsl.GenerateKeys(
  out PrivateKey, PublicKey: RawByteString);
begin
  with TJwtAbstractOsl(NewInstance) do // no need to call Create
    try
      SetAlgorithms;
      OpenSslGenerateKeys(fGenEvpType, fGenBitsOrCurve, PrivateKey, PublicKey);
    finally
      Free;
    end;
end;


{ TJwtES256Osl }

procedure TJwtES256Osl.SetAlgorithms;
begin
  fAlgorithm := 'ES256';
  fHashAlgorithm := ''; // sha256
  fGenEvpType := EVP_PKEY_EC;
  fGenBitsOrCurve := NID_X9_62_prime256v1; // = secp256r1
end;

{ TJwtES384Osl }

procedure TJwtES384Osl.SetAlgorithms;
begin
  fAlgorithm := 'ES384';
  fHashAlgorithm := 'SHA384';
  fGenEvpType := EVP_PKEY_EC;
  fGenBitsOrCurve := NID_secp384r1;
end;

{ TJwtES512Osl }

procedure TJwtES512Osl.SetAlgorithms;
begin
  fAlgorithm := 'ES512';
  fHashAlgorithm := 'SHA512';
  fGenEvpType := EVP_PKEY_EC;
  fGenBitsOrCurve := NID_secp521r1;
end;

{ TJwtES256KOsl }

procedure TJwtES256KOsl.SetAlgorithms;
begin
  fAlgorithm := 'ES256K';
  fHashAlgorithm := ''; // sha256
  fGenEvpType := EVP_PKEY_EC;
  fGenBitsOrCurve := NID_secp256k1;
end;

{ TJwtRS256Osl }

procedure TJwtRS256Osl.SetAlgorithms;
begin
  fAlgorithm := 'RS256';
  fHashAlgorithm := ''; // sha256
  fGenEvpType := EVP_PKEY_RSA;
  fGenBitsOrCurve := 2048;
end;

{ TJwtRS384Osl }

procedure TJwtRS384Osl.SetAlgorithms;
begin
  fAlgorithm := 'RS384';
  fHashAlgorithm := 'SHA384';
  fGenEvpType := EVP_PKEY_RSA;
  fGenBitsOrCurve := 2048;
end;

{ TJwtRS512Osl }

procedure TJwtRS512Osl.SetAlgorithms;
begin
  fAlgorithm := 'RS512';
  fHashAlgorithm := 'SHA512';
  fGenEvpType := EVP_PKEY_RSA;
  fGenBitsOrCurve := 2048;
end;

{ TJwtPS256Osl }

procedure TJwtPS256Osl.SetAlgorithms;
begin
  fAlgorithm := 'PS256';
  fHashAlgorithm := ''; // sha256
  fGenEvpType := EVP_PKEY_RSA_PSS;
  fGenBitsOrCurve := 2048;
end;

{ TJwtPS384Osl }

procedure TJwtPS384Osl.SetAlgorithms;
begin
  fAlgorithm := 'PS384';
  fHashAlgorithm := 'SHA384';
  fGenEvpType := EVP_PKEY_RSA_PSS;
  fGenBitsOrCurve := 2048;
end;

{ TJwtPS512Osl }

procedure TJwtPS512Osl.SetAlgorithms;
begin
  fAlgorithm := 'PS512';
  fHashAlgorithm := 'SHA512';
  fGenEvpType := EVP_PKEY_RSA_PSS;
  fGenBitsOrCurve := 2048;
end;

{ TJwtEdDSAOsl }

procedure TJwtEdDSAOsl.SetAlgorithms;
begin
  fAlgorithm := 'EdDSA';
  fHashAlgorithm := 'null'; // Ed25519 includes its own SHA-512
  fGenEvpType := EVP_PKEY_ED25519;
end;


{ ************** Register OpenSSL to our General Cryptography Catalog }

procedure RegisterOpenSsl;
begin
  if (TAesFast[mGcm] = TAesGcmOsl) or
     not OpenSslIsAvailable then
    exit;
  // set the fastest AES implementation classes
  TAesFast[mGcm] := TAesGcmOsl;
  {$ifdef HASAESNI}
    // mormot.core.crypto x86_64 asm is faster than OpenSSL - but GCM
    {$ifndef CPUX64}
    // our AES-CTR x86_64 asm is faster than OpenSSL's
    TAesFast[mCtr] := TAesCtrOsl;
    {$endif CPUX64}
  {$else}
  // ARM/Aarch64 would rather use OpenSSL than our purepascal code
  TAesFast[mEcb] := TAesEcbOsl;
  TAesFast[mCbc] := TAesCbcOsl;
  TAesFast[mCfb] := TAesCfbOsl;
  TAesFast[mOfb] := TAesOfbOsl;
  TAesFast[mCtr] := TAesCtrOsl;
  {$endif HASAESNI}
  // redirects raw mormot.core.ecc256r1 functions to the much faster OpenSSL
  @Ecc256r1MakeKey := @ecc_make_key_osl;
  @Ecc256r1Sign := @ecdsa_sign_osl;
  @Ecc256r1Verify := @ecdsa_verify_osl;
  @Ecc256r1SharedSecret := @ecdh_shared_secret_osl;
end;



procedure FinalizeUnit;
begin
  FreeAndNil(MainAesPrngOsl);
  if (prime256v1grp <> nil) and
     (prime256v1grp <> pointer(1)) then
    EC_GROUP_free(prime256v1grp);
end;


initialization

finalization
  FinalizeUnit;

{$else}

implementation

{$endif USE_OPENSSL}

end.

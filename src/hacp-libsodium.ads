--  Hacp.Libsodium — thin Ada bindings to libsodium (Ed25519 + SHA-256).

with Interfaces.C;
with System;

package Hacp.Libsodium is

   use type Interfaces.C.int;

   SHA256_Bytes : constant := 32;

   type SHA256_Digest is
     array (1 .. SHA256_Bytes) of Interfaces.Unsigned_8;

   function Crypto_Hash_SHA256
     (Output : out SHA256_Digest;
      Input  : System.Address;
      Len    : Interfaces.Unsigned_64) return Interfaces.C.int
     with Import => True,
          Convention => C,
          External_Name => "crypto_hash_sha256";

   CRYPTO_SIGN_ED25519_PUBLICKEYBYTES : constant := 32;
   CRYPTO_SIGN_ED25519_BYTES          : constant := 64;

   type Ed25519_PK is
     array (1 .. CRYPTO_SIGN_ED25519_PUBLICKEYBYTES)
     of Interfaces.Unsigned_8;
   type Ed25519_Sig is
     array (1 .. CRYPTO_SIGN_ED25519_BYTES)
     of Interfaces.Unsigned_8;

   function Crypto_Sign_Verify_Detached
     (Sig  : Ed25519_Sig;
      Msg  : System.Address;
      Mlen : Interfaces.Unsigned_64;
      Pk   : Ed25519_PK) return Interfaces.C.int
     with Import => True,
          Convention => C,
          External_Name => "crypto_sign_verify_detached";

   function Sodium_Init return Interfaces.C.int
     with Import => True,
          Convention => C,
          External_Name => "sodium_init";

end Hacp.Libsodium;
--  Hacp.Crypto — high-level Ed25519 + SHA-256 + hex + base64url.

with Interfaces;
with Hacp.Libsodium;  use Hacp.Libsodium;

package Hacp.Crypto is

   subtype Byte is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of Byte;

   --  SHA-256 → lowercase hex
   function SHA256_Hex (Data : String) return String;
   function SHA256_Hex (Data : Byte_Array) return String;

   --  Load Ed25519 public key from 64-char hex string
   function Load_Public_Key (Hex : String)
     return Hacp.Libsodium.Ed25519_PK;

   --  Verify base64url-encoded Ed25519 signature
   function Verify_Signature
     (PK       : Hacp.Libsodium.Ed25519_PK;
      Payload  : String;
      Sig_B64  : String) return Boolean;

   --  Decode base64url (no padding) to byte array
   function Base64url_Decode (S : String) return Byte_Array;

   --  Encode bytes to lowercase hex
   function Hex_Encode (Data : Byte_Array) return String;

   --  Decode hex string to bytes
   function Hex_Decode (S : String) return Byte_Array;

   --  Convert String to byte array (Latin-1)
   function To_Bytes (S : String) return Byte_Array;

end Hacp.Crypto;
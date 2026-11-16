--  Hacp.Crypto — body.

with Interfaces;        use Interfaces;
with Interfaces.C;      use Interfaces.C;
with System;
with Hacp.Libsodium;    use Hacp.Libsodium;

package body Hacp.Crypto is

   Initialized : Boolean := False;

   procedure Ensure_Init is
   begin
      if not Initialized then
         if Sodium_Init < 0 then
            raise Program_Error with "sodium_init failed";
         end if;
         Initialized := True;
      end if;
   end Ensure_Init;

   Hex_Chars : constant String := "0123456789abcdef";

   function Hex_Encode (Data : Byte_Array) return String is
      Result : String (1 .. Data'Length * 2);
      J      : Positive := 1;
   begin
      for I in Data'Range loop
         Result (J)     := Hex_Chars (Natural (Data (I) / 16) + 1);
         Result (J + 1) := Hex_Chars (Natural (Data (I) mod 16) + 1);
         J := J + 2;
      end loop;
      return Result;
   end Hex_Encode;

   function Hex_Val (C : Character) return Byte is
   begin
      case C is
         when '0' .. '9' =>
            return Byte (Character'Pos (C) - Character'Pos ('0'));
         when 'a' .. 'f' =>
            return Byte (Character'Pos (C) - Character'Pos ('a') + 10);
         when 'A' .. 'F' =>
            return Byte (Character'Pos (C) - Character'Pos ('A') + 10);
         when others => return 0;
      end case;
   end Hex_Val;

   function Hex_Decode (S : String) return Byte_Array is
      Len : constant Natural := S'Length / 2;
      Result : Byte_Array (0 .. Len - 1);
   begin
      for I in 0 .. Len - 1 loop
         Result (I) :=
           Hex_Val (S (S'First + I * 2)) * 16 +
           Hex_Val (S (S'First + I * 2 + 1));
      end loop;
      return Result;
   end Hex_Decode;

   function To_Bytes (S : String) return Byte_Array is
      Result : Byte_Array (0 .. S'Length - 1);
   begin
      for I in S'Range loop
         Result (I - S'First) := Byte (Character'Pos (S (I)));
      end loop;
      return Result;
   end To_Bytes;

   function SHA256_Hex (Data : String) return String is
   begin
      return SHA256_Hex (To_Bytes (Data));
   end SHA256_Hex;

   function SHA256_Hex (Data : Byte_Array) return String is
      Dgst  : SHA256_Digest;
      Dummy : int;
   begin
      Ensure_Init;
      if Data'Length = 0 then
         declare
            Empty : aliased Byte_Array (0 .. 0) := (others => 0);
         begin
            Dummy := Crypto_Hash_SHA256 (Dgst, Empty (0)'Address, 0);
         end;
      else
         declare
            Tmp : aliased Byte_Array (Data'Range) := Data;
         begin
            Dummy := Crypto_Hash_SHA256
              (Dgst, Tmp (Tmp'First)'Address,
               Unsigned_64 (Data'Length));
         end;
      end if;
      declare
         Raw : Byte_Array (0 .. 31);
      begin
         for I in 0 .. 31 loop
            Raw (I) := Dgst (I + 1);
         end loop;
         return Hex_Encode (Raw);
      end;
   end SHA256_Hex;

   function B64_Val (C : Character) return Byte is
   begin
      case C is
         when 'A' .. 'Z' =>
            return Byte (Character'Pos (C) - Character'Pos ('A'));
         when 'a' .. 'z' =>
            return Byte (Character'Pos (C) - Character'Pos ('a') + 26);
         when '0' .. '9' =>
            return Byte (Character'Pos (C) - Character'Pos ('0') + 52);
         when '+' | '-'  => return 62;
         when '/' | '_'  => return 63;
         when '='        => return 0;
         when others     => return 0;
      end case;
   end B64_Val;

   function Base64url_Decode (S : String) return Byte_Array is
      Len : constant Natural := S'Length;
      --  Precise output length for no-padding base64url
      Out_Len : Natural;
   begin
      --  Standard formula, adjusted for no-padding
      case Len mod 4 is
         when 0      => Out_Len := (Len / 4) * 3;
         when 2      => Out_Len := (Len / 4) * 3 + 1;
         when 3      => Out_Len := (Len / 4) * 3 + 2;
         when others => Out_Len := (Len / 4) * 3;  --  1: invalid, treat as 0
      end case;

      --  Subtract for explicit '=' padding (unusual in base64url but possible)
      if Len >= 1 and then S (S'Last) = '=' then
         Out_Len := Out_Len - 1;
      end if;
      if Len >= 2 and then S (S'Last - 1) = '=' then
         Out_Len := Out_Len - 1;
      end if;

      if Out_Len <= 0 then
         return (1 .. 0 => 0);
      end if;

      declare
         Result : Byte_Array (0 .. Out_Len - 1);
         J      : Natural := 0;
         I      : Natural := S'First;
      begin
         --  Process full groups of 4
         while I + 3 <= Len + S'First - 1 and then J < Out_Len loop
            declare
               A : constant Byte := B64_Val (S (I));
               B : constant Byte := B64_Val (S (I + 1));
               C : constant Byte := B64_Val (S (I + 2));
               D : constant Byte := B64_Val (S (I + 3));
            begin
               if J < Out_Len then
                  Result (J) := A * 4 + B / 16;
                  J := J + 1;
               end if;
               if J < Out_Len then
                  Result (J) := (B mod 16) * 16 + C / 4;
                  J := J + 1;
               end if;
               if J < Out_Len then
                  Result (J) := (C mod 4) * 64 + D;
                  J := J + 1;
               end if;
            end;
            I := I + 4;
         end loop;

         --  Handle remaining 2 or 3 chars (no-padding)
         if I < Len + S'First and then J < Out_Len then
            declare
               A : constant Byte := B64_Val (S (I));
               B : constant Byte :=
                 (if I + 1 <= Len + S'First - 1
                  then B64_Val (S (I + 1)) else 0);
               C : constant Byte :=
                 (if I + 2 <= Len + S'First - 1
                  then B64_Val (S (I + 2)) else 0);
            begin
               if J < Out_Len then
                  Result (J) := A * 4 + B / 16;
                  J := J + 1;
               end if;
               if J < Out_Len and then Len mod 4 = 3 then
                  Result (J) := (B mod 16) * 16 + C / 4;
                  J := J + 1;
               end if;
            end;
         end if;

         return Result (0 .. J - 1);
      end;
   end Base64url_Decode;

   function Load_Public_Key (Hex : String) return Ed25519_PK is
      Bytes : constant Byte_Array := Hex_Decode (Hex);
      PK    : Ed25519_PK;
   begin
      if Bytes'Length /= 32 then
         raise Constraint_Error with "Ed25519 key must be 32 bytes";
      end if;
      for I in 1 .. 32 loop
         PK (I) := Bytes (Bytes'First + I - 1);
      end loop;
      return PK;
   end Load_Public_Key;

   function Verify_Signature
     (PK       : Ed25519_PK;
      Payload  : String;
      Sig_B64  : String) return Boolean
   is
      Sig_Bytes : constant Byte_Array := Base64url_Decode (Sig_B64);
      Msg_Bytes : constant Byte_Array := To_Bytes (Payload);
      Sig       : Ed25519_Sig;
      Result    : int;
   begin
      Ensure_Init;
      if Sig_Bytes'Length /= 64 then
         return False;
      end if;
      for I in 1 .. 64 loop
         Sig (I) := Sig_Bytes (Sig_Bytes'First + I - 1);
      end loop;
      if Msg_Bytes'Length = 0 then
         declare
            Dummy : aliased Byte := 0;
         begin
            Result := Crypto_Sign_Verify_Detached
              (Sig, Dummy'Address, 0, PK);
         end;
      else
         declare
            Tmp : aliased Byte_Array (Msg_Bytes'Range) := Msg_Bytes;
         begin
            Result := Crypto_Sign_Verify_Detached
              (Sig, Tmp (Tmp'First)'Address,
               Unsigned_64 (Msg_Bytes'Length), PK);
         end;
      end if;
      return Result = 0;
   end Verify_Signature;

end Hacp.Crypto;
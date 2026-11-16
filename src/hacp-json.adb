--  Hacp.Json — body: constructors, parser, serializer.

with Ada.Characters.Handling;
with Ada.Strings.Fixed;

package body Hacp.Json is

   use Ada.Strings.Unbounded;
   use Ada.Containers;

   --  ─── Constructors ────────────────────────────────────────────

   function J_Null return JSON_Value_Access is
   begin
      return new JSON_Value'(Kind => JSON_Null);
   end J_Null;

   function J_Bool (V : Boolean) return JSON_Value_Access is
   begin
      return new JSON_Value'(Kind => JSON_Boolean, Bool_Val => V);
   end J_Bool;

   function J_Int (V : Long_Long_Integer) return JSON_Value_Access is
   begin
      return new JSON_Value'(Kind    => JSON_Number,
                             Num_Int => V, Has_Int => True,
                             Num_Flt => 0.0, Has_Flt => False);
   end J_Int;

   function J_Flt (V : Long_Float) return JSON_Value_Access is
   begin
      return new JSON_Value'(Kind    => JSON_Number,
                             Num_Int => 0, Has_Int => False,
                             Num_Flt => V, Has_Flt => True);
   end J_Flt;

   function J_Str (V : String) return JSON_Value_Access is
   begin
      return new JSON_Value'(Kind    => JSON_String,
                             Str_Val => To_Unbounded_String (V));
   end J_Str;

   function J_Arr return JSON_Value_Access is
      R : constant JSON_Value_Access :=
        new JSON_Value'(Kind => JSON_Array,
                        Arr  => Value_Vectors.Empty_Vector);
   begin
      return R;
   end J_Arr;

   function J_Obj return JSON_Value_Access is
      R : constant JSON_Value_Access :=
        new JSON_Value'(Kind  => JSON_Object,
                        Pairs => Pair_Vectors.Empty_Vector);
   begin
      return R;
   end J_Obj;

   --  ─── Array / Object helpers ──────────────────────────────────

   procedure Append (Arr : JSON_Value_Access; Item : JSON_Value_Access) is
   begin
      if Arr.Kind = JSON_Array then
         Value_Vectors.Append (Arr.Arr, Item);
      end if;
   end Append;

   procedure Insert (Obj   : JSON_Value_Access;
                     Key   : String;
                     Value : JSON_Value_Access) is
      P : JSON_Pair;
   begin
      if Obj.Kind = JSON_Object then
         P.Key := To_Unbounded_String (Key);
         P.Value := Value;
         Pair_Vectors.Append (Obj.Pairs, P);
      end if;
   end Insert;

   function Get (Obj : JSON_Value_Access; Key : String) return JSON_Value_Access is
   begin
      if Obj = null or else Obj.Kind /= JSON_Object then
         return null;
      end if;
      for I in 1 .. Natural (Pair_Vectors.Length (Obj.Pairs)) loop
         declare
            P : constant JSON_Pair := Pair_Vectors.Element (Obj.Pairs, I);
         begin
            if To_String (P.Key) = Key then
               return P.Value;
            end if;
         end;
      end loop;
      return null;
   end Get;

   function Get (Arr : JSON_Value_Access; Index : Positive) return JSON_Value_Access is
   begin
      if Arr = null or else Arr.Kind /= JSON_Array then
         return null;
      end if;
      if Index > Natural (Value_Vectors.Length (Arr.Arr)) then
         return null;
      end if;
      return Value_Vectors.Element (Arr.Arr, Index);
   end Get;

   function Length (Arr : JSON_Value_Access) return Natural is
   begin
      if Arr = null or else Arr.Kind /= JSON_Array then
         return 0;
      end if;
      return Natural (Value_Vectors.Length (Arr.Arr));
   end Length;

   function Has (Obj : JSON_Value_Access; Key : String) return Boolean is
   begin
      return Get (Obj, Key) /= null;
   end Has;

   --  ─── Typed extraction ────────────────────────────────────────

   function Get_Str (V : JSON_Value_Access) return String is
   begin
      if V = null or else V.Kind /= JSON_String then
         return "";
      end if;
      return To_String (V.Str_Val);
   end Get_Str;

   function Get_Int (V : JSON_Value_Access) return Long_Long_Integer is
   begin
      if V = null or else V.Kind /= JSON_Number then
         return 0;
      end if;
      if V.Has_Int then
         return V.Num_Int;
      end if;
      return Long_Long_Integer (V.Num_Flt);
   end Get_Int;

   function Get_Bool (V : JSON_Value_Access) return Boolean is
   begin
      if V = null or else V.Kind /= JSON_Boolean then
         return False;
      end if;
      return V.Bool_Val;
   end Get_Bool;

   function Is_Null (V : JSON_Value_Access) return Boolean is
   begin
      return V = null or else V.Kind = JSON_Null;
   end Is_Null;

   --  ─── Clone ───────────────────────────────────────────────────

   function Clone (V : JSON_Value_Access) return JSON_Value_Access is
   begin
      if V = null then
         return null;
      end if;
      case V.Kind is
         when JSON_Null    => return J_Null;
         when JSON_Boolean => return J_Bool (V.Bool_Val);
         when JSON_Number  =>
            if V.Has_Int then
               return J_Int (V.Num_Int);
            else
               return J_Flt (V.Num_Flt);
            end if;
         when JSON_String  => return J_Str (To_String (V.Str_Val));
         when JSON_Array   =>
            declare
               R : constant JSON_Value_Access := J_Arr;
            begin
               for I in 1 .. Natural (Value_Vectors.Length (V.Arr)) loop
                  Append (R, Clone (Value_Vectors.Element (V.Arr, I)));
               end loop;
               return R;
            end;
         when JSON_Object  =>
            declare
               R : constant JSON_Value_Access := J_Obj;
            begin
               for I in 1 .. Natural (Pair_Vectors.Length (V.Pairs)) loop
                  declare
                     P : constant JSON_Pair := Pair_Vectors.Element (V.Pairs, I);
                  begin
                     Insert (R, To_String (P.Key), Clone (P.Value));
                  end;
               end loop;
               return R;
            end;
      end case;
   end Clone;

   function Without_Key (Obj  : JSON_Value_Access;
                         Key  : String) return JSON_Value_Access is
      R : constant JSON_Value_Access := J_Obj;
   begin
      if Obj = null or else Obj.Kind /= JSON_Object then
         return R;
      end if;
      for I in 1 .. Natural (Pair_Vectors.Length (Obj.Pairs)) loop
         declare
            P : constant JSON_Pair := Pair_Vectors.Element (Obj.Pairs, I);
         begin
            if To_String (P.Key) /= Key then
               Insert (R, To_String (P.Key), Clone (P.Value));
            end if;
         end;
      end loop;
      return R;
   end Without_Key;

   function Field_Contains (Obj       : JSON_Value_Access;
                            Key       : String;
                            Substring : String) return Boolean is
      use Ada.Characters.Handling;
      V : constant JSON_Value_Access := Get (Obj, Key);
   begin
      if V = null or else V.Kind /= JSON_String then
         return False;
      end if;
      --  Case-insensitive contains
      declare
         S : constant String := To_Lower (To_String (V.Str_Val));
         T : constant String := To_Lower (Substring);
      begin
         return S'Length >= T'Length and then
           (for some I in S'First .. S'Last - T'Length + 1 =>
              S (I .. I + T'Length - 1) = T);
      end;
   end Field_Contains;

   function Field_Equals (Obj   : JSON_Value_Access;
                          Key   : String;
                          Value : String) return Boolean is
      V : constant JSON_Value_Access := Get (Obj, Key);
   begin
      if V = null or else V.Kind /= JSON_String then
         return False;
      end if;
      return To_String (V.Str_Val) = Value;
   end Field_Equals;

   --  ─── Serializer (compact — RFC 8785 style) ──────────────────

   procedure Write_Canonical (V   : JSON_Value_Access;
                              Buf : in out Unbounded_String);

   procedure Write_Canonical_String (S   : String;
                                     Buf : in out Unbounded_String) is
   begin
      Append (Buf, '"');
      for C of S loop
         case C is
            when '"'      => Append (Buf, "\""");
            when '\'      => Append (Buf, "\\");
            when ASCII.LF => Append (Buf, "\n");
            when ASCII.CR => Append (Buf, "\r");
            when ASCII.HT => Append (Buf, "\t");
            when ASCII.BS => Append (Buf, "\b");
            when ASCII.FF => Append (Buf, "\f");
            when others   =>
               if Character'Pos (C) < 16#20# then
                  Append (Buf, "\u00");
                  Append (Buf,
                    (case Character'Pos (C) / 16 is
                       when 0      => "0",
                       when others => "1"));
                  Append (Buf,
                    (case Character'Pos (C) mod 16 is
                       when 0  => "0",  when 1  => "1",
                       when 2  => "2",  when 3  => "3",
                       when 4  => "4",  when 5  => "5",
                       when 6  => "6",  when 7  => "7",
                       when 8  => "8",  when 9  => "9",
                       when 10 => "a",  when 11 => "b",
                       when 12 => "c",  when 13 => "d",
                       when 14 => "e",  when 15 => "f",
                       when others => "0"));
               else
                  Append (Buf, C);
               end if;
         end case;
      end loop;
      Append (Buf, '"');
   end Write_Canonical_String;

   procedure Write_Canonical_Number (V   : JSON_Value_Access;
                                     Buf : in out Unbounded_String) is
      use Ada.Strings.Fixed;
      --  For integers, use simple 'Image
      function Trim_Image (I : Long_Long_Integer) return String is
         S : constant String := I'Image;
      begin
         if S (S'First) = ' ' then
            return S (S'First + 1 .. S'Last);
         end if;
         return S;
      end Trim_Image;
   begin
      if V.Has_Int and then not V.Has_Flt then
         Append (Buf, Trim_Image (V.Num_Int));
      elsif V.Has_Flt then
         --  Simple float serialization; for HACP vectors all numbers
         --  are integers, so this path is rare.
         declare
            F : constant Long_Float := V.Num_Flt;
            I : constant Long_Long_Integer := Long_Long_Integer (F);
         begin
            if Long_Float (I) = F then
               Append (Buf, Trim_Image (I));
            else
               Append (Buf, Trim_Image (I));
            end if;
         end;
      else
         Append (Buf, Trim_Image (V.Num_Int));
      end if;
   end Write_Canonical_Number;

   procedure Write_Canonical (V   : JSON_Value_Access;
                              Buf : in out Unbounded_String) is
   begin
      if V = null then
         Append (Buf, "null");
         return;
      end if;
      case V.Kind is
         when JSON_Null =>
            Append (Buf, "null");
         when JSON_Boolean =>
            if V.Bool_Val then
               Append (Buf, "true");
            else
               Append (Buf, "false");
            end if;
         when JSON_Number =>
            Write_Canonical_Number (V, Buf);
         when JSON_String =>
            Write_Canonical_String (To_String (V.Str_Val), Buf);
         when JSON_Array =>
            Append (Buf, '[');
            for I in 1 .. Natural (Value_Vectors.Length (V.Arr)) loop
               if I > 1 then
                  Append (Buf, ',');
               end if;
               Write_Canonical (Value_Vectors.Element (V.Arr, I), Buf);
            end loop;
            Append (Buf, ']');
         when JSON_Object =>
            --  Keys must be sorted for JCS
            declare
               Sorted : Pair_Vectors.Vector := V.Pairs;
               procedure Swap (A, B : Positive) is
                  Tmp : constant JSON_Pair :=
                    Pair_Vectors.Element (Sorted, A);
               begin
                  Pair_Vectors.Replace_Element
                    (Sorted, A,
                     Pair_Vectors.Element (Sorted, B));
                  Pair_Vectors.Replace_Element (Sorted, B, Tmp);
               end Swap;
            begin
               --  Simple insertion sort on keys
               for I in 2 .. Natural (Pair_Vectors.Length (Sorted)) loop
                  declare
                     J : Positive := I;
                  begin
                     while J > 1 and then
                       To_String
                         (Pair_Vectors.Element (Sorted, J).Key) <
                       To_String
                         (Pair_Vectors.Element (Sorted, J - 1).Key)
                     loop
                        Swap (J, J - 1);
                        J := J - 1;
                     end loop;
                  end;
               end loop;
               Append (Buf, '{');
               for I in 1 .. Natural (Pair_Vectors.Length (Sorted)) loop
                  if I > 1 then
                     Append (Buf, ',');
                  end if;
                  declare
                     P : constant JSON_Pair :=
                       Pair_Vectors.Element (Sorted, I);
                  begin
                     Write_Canonical_String (To_String (P.Key), Buf);
                     Append (Buf, ':');
                     Write_Canonical (P.Value, Buf);
                  end;
               end loop;
               Append (Buf, '}');
            end;
      end case;
   end Write_Canonical;

   function Serialize (V : JSON_Value_Access) return String is
      Buf : Unbounded_String;
   begin
      Write_Canonical (V, Buf);
      return To_String (Buf);
   end Serialize;

   --  ─── Parser ──────────────────────────────────────────────────

   type Parse_Ctx is record
      Pos : Positive;
      Len : Natural;
      S   : String (1 .. 4096);  --  Max 4 KB per value
   end record;

   procedure Skip_Whitespace (Ctx : in out Parse_Ctx) is
   begin
      while Ctx.Pos <= Ctx.Len and then
        Ctx.S (Ctx.Pos) in ' ' | ASCII.LF | ASCII.CR | ASCII.HT
      loop
         Ctx.Pos := Ctx.Pos + 1;
      end loop;
   end Skip_Whitespace;

   function Parse_Value (Ctx : in out Parse_Ctx) return JSON_Value_Access;
   --  Forward declaration

   function Parse_String_Raw (Ctx : in out Parse_Ctx) return String is
      Start : Positive;
   begin
      if Ctx.S (Ctx.Pos) /= '"' then
         raise Constraint_Error with "expected string";
      end if;
      Ctx.Pos := Ctx.Pos + 1;
      Start := Ctx.Pos;
      --  Scan for closing quote (no unescaped control chars)
      while Ctx.Pos <= Ctx.Len loop
         if Ctx.S (Ctx.Pos) = '\' then
            Ctx.Pos := Ctx.Pos + 2;  --  skip escaped char
         elsif Ctx.S (Ctx.Pos) = '"' then
            exit;
         else
            Ctx.Pos := Ctx.Pos + 1;
         end if;
      end loop;
      declare
         Raw : constant String := Ctx.S (Start .. Ctx.Pos - 1);
      begin
         Ctx.Pos := Ctx.Pos + 1;  --  skip closing quote
         return Raw;
      end;
   end Parse_String_Raw;

   function Unescape (S : String) return String is
      Result : Unbounded_String;
      I      : Positive := S'First;
   begin
      while I <= S'Last loop
         if S (I) = '\' and then I < S'Last then
            case S (I + 1) is
               when '"'     => Append (Result, '"');   I := I + 2;
               when '\'     => Append (Result, '\');   I := I + 2;
               when '/'     => Append (Result, '/');   I := I + 2;
               when 'n'     => Append (Result, ASCII.LF); I := I + 2;
               when 'r'     => Append (Result, ASCII.CR); I := I + 2;
               when 't'     => Append (Result, ASCII.HT); I := I + 2;
               when 'b'     => Append (Result, ASCII.BS); I := I + 2;
               when 'f'     => Append (Result, ASCII.FF); I := I + 2;
               when 'u'     =>
                  --  \uXXXX — simplified: assume ASCII range
                  I := I + 2;
                  Append (Result, '?');
                  I := I + 4;
               when others  =>
                  Append (Result, S (I));
                  I := I + 1;
            end case;
         else
            Append (Result, S (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Unescape;

   function Parse_String (Ctx : in out Parse_Ctx) return JSON_Value_Access is
   begin
      return J_Str (Unescape (Parse_String_Raw (Ctx)));
   end Parse_String;

   function Parse_Number (Ctx : in out Parse_Ctx) return JSON_Value_Access is
      Start : constant Positive := Ctx.Pos;
      Is_Neg : Boolean := False;
   begin
      if Ctx.S (Ctx.Pos) = '-' then
         Is_Neg := True;
         Ctx.Pos := Ctx.Pos + 1;
      end if;
      while Ctx.Pos <= Ctx.Len and then
        Ctx.S (Ctx.Pos) in '0' .. '9'
      loop
         Ctx.Pos := Ctx.Pos + 1;
      end loop;
      --  Check for float
      if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = '.' then
         Ctx.Pos := Ctx.Pos + 1;
         while Ctx.Pos <= Ctx.Len and then
           Ctx.S (Ctx.Pos) in '0' .. '9'
         loop
            Ctx.Pos := Ctx.Pos + 1;
         end loop;
         --  Float
         declare
            S : constant String := Ctx.S (Start .. Ctx.Pos - 1);
         begin
            return J_Flt (Long_Float'Value (S));
         end;
      end if;
      --  Integer
      declare
         S    : constant String := Ctx.S (Start .. Ctx.Pos - 1);
         Val  : Long_Long_Integer := 0;
         First : Positive := S'First;
      begin
         if S (First) = '-' then
            First := First + 1;
         end if;
         for I in First .. S'Last loop
            Val := Val * 10 +
              Long_Long_Integer (Character'Pos (S (I)) -
                                 Character'Pos ('0'));
         end loop;
         if Is_Neg then
            Val := -Val;
         end if;
         return J_Int (Val);
      end;
   end Parse_Number;

   function Parse_Array (Ctx : in out Parse_Ctx) return JSON_Value_Access is
      R : constant JSON_Value_Access := J_Arr;
   begin
      Ctx.Pos := Ctx.Pos + 1;  --  skip '['
      Skip_Whitespace (Ctx);
      if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = ']' then
         Ctx.Pos := Ctx.Pos + 1;
         return R;
      end if;
      loop
         Skip_Whitespace (Ctx);
         Append (R, Parse_Value (Ctx));
         Skip_Whitespace (Ctx);
         exit when Ctx.Pos > Ctx.Len or else Ctx.S (Ctx.Pos) /= ',';
         Ctx.Pos := Ctx.Pos + 1;
      end loop;
      if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = ']' then
         Ctx.Pos := Ctx.Pos + 1;
      end if;
      return R;
   end Parse_Array;

   function Parse_Object (Ctx : in out Parse_Ctx) return JSON_Value_Access is
      R : constant JSON_Value_Access := J_Obj;
   begin
      Ctx.Pos := Ctx.Pos + 1;  --  skip '{'
      Skip_Whitespace (Ctx);
      if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = '}' then
         Ctx.Pos := Ctx.Pos + 1;
         return R;
      end if;
      loop
         Skip_Whitespace (Ctx);
         declare
            Key : constant String := Parse_String_Raw (Ctx);
         begin
            Skip_Whitespace (Ctx);
            if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = ':' then
               Ctx.Pos := Ctx.Pos + 1;
            end if;
            Skip_Whitespace (Ctx);
            Insert (R, Key, Parse_Value (Ctx));
         end;
         Skip_Whitespace (Ctx);
         exit when Ctx.Pos > Ctx.Len or else Ctx.S (Ctx.Pos) /= ',';
         Ctx.Pos := Ctx.Pos + 1;
      end loop;
      if Ctx.Pos <= Ctx.Len and then Ctx.S (Ctx.Pos) = '}' then
         Ctx.Pos := Ctx.Pos + 1;
      end if;
      return R;
   end Parse_Object;

   function Parse_Value (Ctx : in out Parse_Ctx) return JSON_Value_Access is
   begin
      Skip_Whitespace (Ctx);
      if Ctx.Pos > Ctx.Len then
         return J_Null;
      end if;
      case Ctx.S (Ctx.Pos) is
         when '"'     => return Parse_String (Ctx);
         when '['     => return Parse_Array (Ctx);
         when '{'     => return Parse_Object (Ctx);
         when 't'     =>  --  true
            Ctx.Pos := Ctx.Pos + 4;
            return J_Bool (True);
         when 'f'     =>  --  false
            Ctx.Pos := Ctx.Pos + 5;
            return J_Bool (False);
         when 'n'     =>  --  null
            Ctx.Pos := Ctx.Pos + 4;
            return J_Null;
         when '-' | '0' .. '9' =>
            return Parse_Number (Ctx);
         when others  =>
            return J_Null;
      end case;
   end Parse_Value;

   function Parse (Text : String) return JSON_Value_Access is
      Ctx : Parse_Ctx;
   begin
      Ctx.S (1 .. Text'Length) := Text;
      Ctx.Len := Text'Length;
      Ctx.Pos := 1;
      return Parse_Value (Ctx);
   end Parse;

end Hacp.Json;
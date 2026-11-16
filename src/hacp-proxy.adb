--  Hacp.Proxy — body.

with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;

package body Hacp.Proxy is

   function Method_To_Verb (Method : String) return String is
      U : constant String := To_Upper (Method);
   begin
      if U = "GET" or else U = "HEAD" then
         return "read";
      elsif U = "POST" or else U = "PUT" or else U = "PATCH" then
         return "write";
      elsif U = "DELETE" then
         return "delete";
      else
         return "unknown";
      end if;
   end Method_To_Verb;

   function Extract_Hacp_Header
     (Header_Line : String;
      Header_Name : String) return JSON_Value_Access
   is
      use Ada.Strings.Fixed;
      Sep : Natural;
   begin
      Sep := Index (Header_Line, ":");
      if Sep = 0 then
         return null;
      end if;
      declare
         Key   : constant String :=
           To_Lower (Header_Line (Header_Line'First .. Sep - 1));
         Value : constant String :=
           Ada.Strings.Fixed.Trim
             (Header_Line (Sep + 1 .. Header_Line'Last),
              Ada.Strings.Both);
      begin
         if Key = To_Lower (Header_Name) then
            begin
               declare
                  Bytes : constant Byte_Array :=
                    Base64url_Decode (Value);
                  Text  : String (1 .. Bytes'Length);
               begin
                  for I in Bytes'Range loop
                     Text (I - Bytes'First + 1) :=
                       Character'Val (Bytes (I));
                  end loop;
                  return Parse (Text);
               end;
            exception
               when others => return null;
            end;
         end if;
         return null;
      end;
   end Extract_Hacp_Header;

   function Build_Evaluate_Input
     (Envelope       : JSON_Value_Access;
      Token          : JSON_Value_Access;
      Method         : String;
      Request_Target : String;
      Body_Hash      : String;
      Clock          : Long_Long_Integer)
     return JSON_Value_Access
   is
      function First_Scope (Key : String) return String is
         Scope : constant JSON_Value_Access := Get (Envelope, "scope");
         Arr   : JSON_Value_Access;
      begin
         if Scope = null then return ""; end if;
         Arr := Get (Scope, Key);
         if Arr = null or else Arr.Kind /= JSON_Array or else
           Length (Arr) = 0
         then
            return "";
         end if;
         return Get_Str (Get (Arr, 1));
      end First_Scope;

      PA    : constant JSON_Value_Access := J_Obj;
      Http  : constant JSON_Value_Access := J_Obj;
      Inputs : constant JSON_Value_Access := J_Obj;
      Ctx   : constant JSON_Value_Access := J_Obj;
   begin
      Insert (PA, "hacp_version",    J_Str ("0.9"));
      Insert (PA, "verb",            J_Str (Method_To_Verb (Method)));
      Insert (PA, "resource_class",  J_Str (First_Scope ("resource_classes")));
      Insert (PA, "resource_id",     J_Str (Request_Target));
      Insert (PA, "audience",        J_Str (First_Scope ("audiences")));
      Insert (PA, "reversibility",   J_Str (First_Scope ("reversibility")));
      Insert (PA, "externality",     J_Str (First_Scope ("externality")));
      Insert (PA, "data_class",      J_Str (First_Scope ("data_classes")));
      Insert (PA, "payload_hash",    J_Str (Body_Hash));

      Insert (Http, "method",          J_Str (Method));
      Insert (Http, "request_target",  J_Str (Request_Target));

      Insert (Inputs, "intent_envelope", Envelope);
      Insert (Inputs, "proposed_action", PA);
      Insert (Inputs, "decision_token",  Token);
      Insert (Inputs, "http_request",    Http);

      Insert (Ctx, "clock", J_Int (Clock));

      --  Return inputs as a wrapper (the caller uses Get on it)
      declare
         Wrapper : constant JSON_Value_Access := J_Obj;
      begin
         Insert (Wrapper, "_inputs", Inputs);
         Insert (Wrapper, "_context", Ctx);
         return Wrapper;
      end;
   end Build_Evaluate_Input;

   function Proxy_Evaluate
     (Envelope       : JSON_Value_Access;
      Token          : JSON_Value_Access;
      Method         : String;
      Request_Target : String;
      Body           : String;
      PK_Hex         : String;
      Clock          : Long_Long_Integer)
     return Eval_Result
   is
      Body_Hash : constant String := SHA256_Hex (Body);
      Wrapper   : constant JSON_Value_Access :=
        Build_Evaluate_Input
          (Envelope, Token, Method, Request_Target, Body_Hash, Clock);
      Inputs    : constant JSON_Value_Access := Get (Wrapper, "_inputs");
      Ctx       : constant JSON_Value_Access := Get (Wrapper, "_context");
   begin
      return Hacp.Evaluate.Evaluate (Inputs, Ctx, PK_Hex);
   end Proxy_Evaluate;

end Hacp.Proxy;
--  Hacp.Http — managed HTTP server using Ada Web Server (AWS).
--
--  HTTP parsing, framing, connection handling and socket lifecycle
--  are delegated to AWS. HACP source contains no direct socket API dependency.
--  dependency.

with Ada.Characters.Handling;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AWS.Config;
with AWS.Config.Set;
with AWS.Headers;
with AWS.Messages;
with AWS.Response;
with AWS.Response.Set;
with AWS.Server;
with AWS.Status;

with Hacp.Json;             use Hacp.Json;
with Hacp.Crypto;           use Hacp.Crypto;
with Hacp.Evaluate;         use Hacp.Evaluate;

package body Hacp.Http is

   function Upper (S : String) return String
     renames Ada.Characters.Handling.To_Upper;

   function Method_To_Verb (M : String) return String is
      U : constant String := Upper (M);
   begin
      if U = "GET" or else U = "HEAD" then
         return "read";
      elsif U = "POST" or else
            U = "PUT" or else
            U = "PATCH"
      then
         return "write";
      elsif U = "DELETE" then
         return "delete";
      else
         return "unknown";
      end if;
   end Method_To_Verb;


   function Is_Base64url_Syntax (S : String) return Boolean is
   begin
      if S'Length = 0 or else S'Length mod 4 = 1 then
         return False;
      end if;

      for C of S loop
         if not
           (C in 'A' .. 'Z' or else
            C in 'a' .. 'z' or else
            C in '0' .. '9' or else
            C = '-' or else
            C = '_' or else
            C = '=')
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Base64url_Syntax;


   function Request_Body
     (Request : AWS.Status.Data) return String
   is
      use Ada.Streams;
      use Ada.Strings.Unbounded;

      Data : constant Stream_Element_Array :=
        AWS.Status.Binary_Data (Request);

      Result : Unbounded_String;
   begin
      for B of Data loop
         Append
           (Result,
            Character'Val (Integer (B)));
      end loop;

      return To_String (Result);
   end Request_Body;


   function HACP_Response
     (Status_Code        : AWS.Messages.Status_Code;
      Decision           : String;
      Payload            : String;
      Reason             : String := "";
      Include_Request_Id : Boolean := False)
      return AWS.Response.Data
   is
      Result : AWS.Response.Data :=
        AWS.Response.Build
          (Content_Type => "application/json",
           Message_Body => Payload,
           Status_Code  => Status_Code);
   begin
      AWS.Response.Set.Add_Header
        (Result,
         "X-HACP-Decision",
         Decision);

      if Reason'Length > 0 then
         AWS.Response.Set.Add_Header
           (Result,
            "X-HACP-Reason",
            Reason);
      end if;

      if Include_Request_Id then
         AWS.Response.Set.Add_Header
           (Result,
            "X-HACP-Request-Id",
            "proxy-001");
      end if;

      return Result;
   end HACP_Response;


   function Header_Value
     (Request : AWS.Status.Data;
      Name    : String) return String
   is
      Headers : constant AWS.Headers.List :=
        AWS.Status.Header (Request);
   begin
      return AWS.Headers.Get_Values
        (Headers,
         Name);
   end Header_Value;


   procedure Run_Server
     (Port   : Natural;
      PK_Hex : String)
   is
      WS   : AWS.Server.HTTP;
      Conf : AWS.Config.Object := AWS.Config.Default_Config;

      function Service
        (Request : AWS.Status.Data)
         return AWS.Response.Data
      is
         Method : constant String :=
           AWS.Status.Method (Request);

         Path : constant String :=
           AWS.Status.URI (Request);

         Env_B64 : constant String :=
           Header_Value
             (Request,
              "X-HACP-Intent-Token");

         Env_B64A : constant String :=
           (if Env_B64'Length = 0
            then Header_Value
              (Request,
               "X-HACP-Intent-Envelope")
            else Env_B64);

         Tok_B64 : constant String :=
           Header_Value
             (Request,
              "X-HACP-Decision-Token");

         Body_Str : constant String :=
           Request_Body (Request);

         Env_Val : JSON_Value_Access;
         Tok_Val : JSON_Value_Access;

         Clock : constant Long_Long_Integer := 0;

         R : Eval_Result;

      begin
         --  Required HACP headers.
         if Env_B64A'Length = 0 or else
           Tok_B64'Length = 0
         then
            return HACP_Response
              (Status_Code => AWS.Messages.S403,
               Decision    => "DENY",
               Payload     =>
                 "{""decision"":""DENY""," &
                 """reason"":""INVALID_ENVELOPE""}");
         end if;


         --  Decode and parse HACP envelope/token.
         begin
            if not Is_Base64url_Syntax (Env_B64A) or else
              not Is_Base64url_Syntax (Tok_B64)
            then
               raise Constraint_Error
                 with "invalid HACP base64url header syntax";
            end if;

            declare
               Env_Bytes : constant Byte_Array :=
                 Base64url_Decode (Env_B64A);

               Env_Str :
                 String (1 .. Env_Bytes'Length);

               Tok_Bytes : constant Byte_Array :=
                 Base64url_Decode (Tok_B64);

               Tok_Str :
                 String (1 .. Tok_Bytes'Length);
            begin
               for I in Env_Bytes'Range loop
                  Env_Str
                    (I - Env_Bytes'First + 1) :=
                    Character'Val (Env_Bytes (I));
               end loop;

               for I in Tok_Bytes'Range loop
                  Tok_Str
                    (I - Tok_Bytes'First + 1) :=
                    Character'Val (Tok_Bytes (I));
               end loop;

               Env_Val := Parse (Env_Str);
               Tok_Val := Parse (Tok_Str);

               if Env_Val = null or else
                 Env_Val.Kind /= JSON_Object or else
                 Tok_Val = null or else
                 Tok_Val.Kind /= JSON_Object
               then
                  raise Constraint_Error
                    with
                      "HACP envelope/token must be JSON objects";
               end if;
            end;

         exception
            when others =>
               return HACP_Response
                 (Status_Code => AWS.Messages.S403,
                  Decision    => "DENY",
                  Payload     =>
                    "{""decision"":""DENY""," &
                    """reason"":""SIGNATURE_FAILURE""}");
         end;


         --  Build existing HACP Evaluate inputs.
         declare
            Body_Hash : constant String :=
              SHA256_Hex (Body_Str);

            PA     : constant JSON_Value_Access := J_Obj;
            Http   : constant JSON_Value_Access := J_Obj;
            Inputs : constant JSON_Value_Access := J_Obj;
            Ctx    : constant JSON_Value_Access := J_Obj;

            function First_Scope
              (Key : String) return String
            is
               Scope : constant JSON_Value_Access :=
                 Get (Env_Val, "scope");

               Arr : JSON_Value_Access;
            begin
               if Scope = null then
                  return "";
               end if;

               Arr := Get (Scope, Key);

               if Arr = null or else
                 Arr.Kind /= JSON_Array or else
                 Length (Arr) = 0
               then
                  return "";
               end if;

               return Get_Str (Get (Arr, 1));
            end First_Scope;

         begin
            Insert
              (PA,
               "hacp_version",
               J_Str ("0.9"));

            Insert
              (PA,
               "verb",
               J_Str (Method_To_Verb (Method)));

            Insert
              (PA,
               "resource_class",
               J_Str (First_Scope ("resource_classes")));

            Insert
              (PA,
               "resource_id",
               J_Str (Path));

            Insert
              (PA,
               "audience",
               J_Str (First_Scope ("audiences")));

            Insert
              (PA,
               "reversibility",
               J_Str (First_Scope ("reversibility")));

            Insert
              (PA,
               "externality",
               J_Str (First_Scope ("externality")));

            Insert
              (PA,
               "data_class",
               J_Str (First_Scope ("data_classes")));

            Insert
              (PA,
               "payload_hash",
               J_Str (Body_Hash));

            Insert
              (Http,
               "method",
               J_Str (Method));

            Insert
              (Http,
               "request_target",
               J_Str (Path));

            Insert
              (Inputs,
               "intent_envelope",
               Env_Val);

            Insert
              (Inputs,
               "proposed_action",
               PA);

            Insert
              (Inputs,
               "decision_token",
               Tok_Val);

            Insert
              (Inputs,
               "http_request",
               Http);

            Insert
              (Ctx,
               "clock",
               J_Int (Clock));

            R :=
              Hacp.Evaluate.Evaluate
                (Inputs,
                 Ctx,
                 PK_Hex);
         end;


         if R.Decision = Allow then
            return HACP_Response
              (Status_Code        => AWS.Messages.S200,
               Decision           => "ALLOW",
               Payload            =>
                 "{""decision"":""ALLOW""," &
                 """request_id"":""proxy-001""}",
               Include_Request_Id => True);

         else
            declare
               Reason : constant String :=
                 Reason_Str (R);
            begin
               return HACP_Response
                 (Status_Code        => AWS.Messages.S403,
                  Decision           => "DENY",
                  Reason             => Reason,
                  Payload            =>
                    "{""decision"":""DENY""," &
                    """reason"":""" & Reason & """," &
                    """request_id"":""proxy-001""}",
                  Include_Request_Id => True);
            end;
         end if;

      end Service;

   begin
      --  Bind only to loopback. AWS owns the complete HTTP and
      --  connection lifecycle below this boundary.
      AWS.Config.Set.Server_Name
        (Conf,
         "hacp-ada-proxy");

      AWS.Config.Set.Protocol_Family
        (Conf,
         "FAMILY_INET");

      AWS.Config.Set.Server_Host
        (Conf,
         "127.0.0.1");

      AWS.Config.Set.Server_Port
        (Conf,
         Port);

      AWS.Config.Set.Reuse_Address
        (Conf,
         True);

      AWS.Server.Start
        (WS,
         Service'Unrestricted_Access,
         Conf);

      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hacp-ada-proxy listening on 127.0.0.1:" &
         Natural'Image (Port));

      --  The server owns worker/connection lifecycle.
      --  Run_Server intentionally never returns.
      loop
         delay 3_600.0;
      end loop;
   end Run_Server;

end Hacp.Http;
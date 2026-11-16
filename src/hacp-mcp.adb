--  Hacp.Mcp — body.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Exceptions;
with Hacp.Crypto;           use Hacp.Crypto;

package body Hacp.Mcp is

   function Extract_Hacp_Param
     (Params : JSON_Value_Access;
      Key    : String) return JSON_Value_Access
   is
      V : constant JSON_Value_Access := Get (Params, Key);
   begin
      if V = null then
         return null;
      end if;
      --  Raw JSON object
      if V.Kind = JSON_Object then
         return V;
      end if;
      --  Base64url-encoded string
      if V.Kind = JSON_String then
         begin
            declare
               Bytes : constant Hacp.Crypto.Byte_Array :=
                 Base64url_Decode (Get_Str (V));
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
   end Extract_Hacp_Param;

   function Handle_Request
     (Request  : JSON_Value_Access;
      PK_Hex   : String;
      Clock    : Long_Long_Integer)
     return JSON_Value_Access
   is
      Id      : constant JSON_Value_Access := Get (Request, "id");
      Method  : constant String :=
        Get_Str (Get (Request, "method"));
      Params  : constant JSON_Value_Access :=
        Get (Request, "params");
      Resp    : JSON_Value_Access;
   begin
      if Method = "initialize" then
         Resp := J_Obj;
         Insert (Resp, "jsonrpc", J_Str ("2.0"));
         Insert (Resp, "id", (if Id /= null then Clone (Id) else J_Null));
         declare
            Result : constant JSON_Value_Access := J_Obj;
            Caps   : constant JSON_Value_Access := J_Obj;
            Tools  : constant JSON_Value_Access := J_Obj;
            SI     : constant JSON_Value_Access := J_Obj;
         begin
            Insert (Result, "protocolVersion",
                    J_Str ("2024-11-05"));
            Insert (Caps, "tools", Tools);
            Insert (Result, "capabilities", Caps);
            Insert (SI, "name", J_Str ("hacp-ada-mcp"));
            Insert (SI, "version", J_Str ("1.1.0"));
            Insert (Result, "serverInfo", SI);
            Insert (Resp, "result", Result);
         end;
         return Resp;

      elsif Method = "notifications/initialized" then
         return null;  --  Notification, no response

      elsif Method = "tools/list" then
         Resp := J_Obj;
         Insert (Resp, "jsonrpc", J_Str ("2.0"));
         Insert (Resp, "id", (if Id /= null then Clone (Id) else J_Null));
         declare
            Result : constant JSON_Value_Access := J_Obj;
            TA     : constant JSON_Value_Access := J_Arr;
         begin
            Insert (Result, "tools", TA);
            Insert (Resp, "result", Result);
         end;
         return Resp;

      elsif Method = "tools/call" then
         declare
            Tool_Name : constant String :=
              Get_Str (Get (Params, "name"));
            Envelope  : constant JSON_Value_Access :=
              Extract_Hacp_Param (Params, "hacp_intent_envelope");
            Token     : constant JSON_Value_Access :=
              Extract_Hacp_Param (Params, "hacp_decision_token");
         begin
            --  Fail-closed: missing envelope → DENY
            if Envelope = null then
               Resp := J_Obj;
               Insert (Resp, "jsonrpc", J_Str ("2.0"));
               Insert (Resp, "id",
                 (if Id /= null then Clone (Id) else J_Null));
               declare
                  Err : constant JSON_Value_Access := J_Obj;
               begin
                  Insert (Err, "code", J_Int (-32000));
                  Insert (Err, "message",
                    J_Str ("HACP DENY: INVALID_ENVELOPE"));
                  Insert (Resp, "error", Err);
               end;
               return Resp;
            end if;

            --  Fail-closed: missing token → DENY
            if Token = null then
               Resp := J_Obj;
               Insert (Resp, "jsonrpc", J_Str ("2.0"));
               Insert (Resp, "id",
                 (if Id /= null then Clone (Id) else J_Null));
               declare
                  Err : constant JSON_Value_Access := J_Obj;
               begin
                  Insert (Err, "code", J_Int (-32000));
                  Insert (Err, "message",
                    J_Str ("HACP DENY: SIGNATURE_FAILURE"));
                  Insert (Resp, "error", Err);
               end;
               return Resp;
            end if;

            --  Build evaluate input (MCP synthesis)
            declare
               use Ada.Strings.Unbounded;
               function First_Scope (K : String) return String is
                  Scope : constant JSON_Value_Access :=
                    Get (Envelope, "scope");
                  Arr   : JSON_Value_Access;
               begin
                  if Scope = null then return ""; end if;
                  Arr := Get (Scope, K);
                  if Arr = null or else Arr.Kind /= JSON_Array or else
                    Length (Arr) = 0
                  then
                     return "";
                  end if;
                  return Get_Str (Get (Arr, 1));
               end First_Scope;

               PA     : constant JSON_Value_Access := J_Obj;
               Inputs : constant JSON_Value_Access := J_Obj;
               Ctx    : constant JSON_Value_Access := J_Obj;
               R      : Eval_Result;
            begin
               Insert (PA, "hacp_version",  J_Str ("0.9"));
               Insert (PA, "verb",          J_Str ("call"));
               Insert (PA, "resource_class",
                       J_Str (First_Scope ("resource_classes")));
               Insert (PA, "resource_id",   J_Str (Tool_Name));
               Insert (PA, "audience",
                       J_Str (First_Scope ("audiences")));
               Insert (PA, "reversibility",
                       J_Str (First_Scope ("reversibility")));
               Insert (PA, "externality",
                       J_Str (First_Scope ("externality")));
               Insert (PA, "data_class",
                       J_Str (First_Scope ("data_classes")));
               Insert (PA, "tool_name",     J_Str (Tool_Name));

               Insert (Inputs, "intent_envelope", Envelope);
               Insert (Inputs, "proposed_action", PA);
               Insert (Inputs, "decision_token", Token);

               Insert (Ctx, "clock", J_Int (Clock));

               R := Hacp.Evaluate.Evaluate (Inputs, Ctx, PK_Hex);

               Resp := J_Obj;
               Insert (Resp, "jsonrpc", J_Str ("2.0"));
               Insert (Resp, "id",
                 (if Id /= null then Clone (Id) else J_Null));

               if R.Decision = Allow then
                  declare
                     Result : constant JSON_Value_Access := J_Obj;
                     Content : constant JSON_Value_Access := J_Arr;
                     Item    : constant JSON_Value_Access := J_Obj;
                  begin
                     Insert (Item, "type", J_Str ("text"));
                     Insert (Item, "text", J_Str ("HACP ALLOW"));
                     Append (Content, Item);
                     Insert (Result, "content", Content);
                     Insert (Resp, "result", Result);
                  end;
               else
                  declare
                     Err : constant JSON_Value_Access := J_Obj;
                  begin
                     Insert (Err, "code", J_Int (-32000));
                     Insert (Err, "message",
                       J_Str ("HACP DENY: " &
                              Reason_Str (R)));
                     Insert (Resp, "error", Err);
                  end;
               end if;
               return Resp;
            end;
         end;

      else
         --  Unknown method
         Resp := J_Obj;
         Insert (Resp, "jsonrpc", J_Str ("2.0"));
         Insert (Resp, "id",
           (if Id /= null then Clone (Id) else J_Null));
         declare
            Err : constant JSON_Value_Access := J_Obj;
         begin
            Insert (Err, "code", J_Int (-32601));
            Insert (Err, "message",
              J_Str ("Method not found: " & Method));
            Insert (Resp, "error", Err);
         end;
         return Resp;
      end if;
   end Handle_Request;

   procedure Run (PK_Hex : String) is
      Clock : constant Long_Long_Integer := 0;
      --  In production: use Ada.Calendar.Clock
   begin
      loop
         declare
            Line : constant String := Get_Line;
            Req  : JSON_Value_Access;
            Resp : JSON_Value_Access;
         begin
            if Line'Length = 0 then
               goto Continue;
            end if;
            begin
               Req := Parse (Line);
               Resp := Handle_Request (Req, PK_Hex, Clock);
               if Resp /= null then
                  Put_Line (Serialize (Resp));
               end if;
            exception
               when E : others =>
                  declare
                     Err : constant JSON_Value_Access := J_Obj;
                  begin
                     Insert (Err, "jsonrpc", J_Str ("2.0"));
                     Insert (Err, "id", J_Null);
                     declare
                        Err_Obj : constant JSON_Value_Access := J_Obj;
                     begin
                        Insert (Err_Obj, "code", J_Int (-32700));
                        Insert (Err_Obj, "message",
                          J_Str ("Parse error: " &
                                 Ada.Exceptions.Exception_Message (E)));
                        Insert (Err, "error", Err_Obj);
                     end;
                     Put_Line (Serialize (Err));
                  end;
            end;
         end;
         <<Continue>>
      end loop;
   exception
      when End_Error => null;
   end Run;

end Hacp.Mcp;
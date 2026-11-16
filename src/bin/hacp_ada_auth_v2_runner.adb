--  hacp-ada-auth-v2-runner — Authorization-v2 successor test runner.
--  Protocol v1 stdin/stdout JSON lines.
--
--  This binary is additive and does not replace the canonical Core runner.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Exceptions;
with Hacp.Json;             use Hacp.Json;
with Hacp.Evaluate;         use Hacp.Evaluate;

procedure Hacp_Ada_Auth_V2_Runner is

   Test_Pubkey_Hex : constant String :=
     "9d17f1bbcc0845865e670f526413fb7a510380798fe300b6c98e28f3a3b0fdb3";

   function Decision_Str (D : Decision_Kind) return String is
   begin
      case D is
         when Allow      => return "ALLOW";
         when Deny       => return "DENY";
         when Checkpoint => return "CHECKPOINT";
      end case;
   end Decision_Str;

   function Handle_Line
     (Line   : String;
      PK_Hex : String) return String
   is
      Req   : constant JSON_Value_Access := Parse (Line);
      Resp  : constant JSON_Value_Access := J_Obj;
      Ctx   : JSON_Value_Access;
      Input : constant JSON_Value_Access := Get (Req, "input");
      PID   : JSON_Value_Access;
      R     : Eval_Result;
   begin
      Ctx := Get (Req, "policy_context");

      if Ctx = null or else Is_Null (Ctx) then
         Ctx := Get (Input, "policy_context");
      end if;

      if Ctx = null or else Is_Null (Ctx) then
         Ctx := J_Obj;
      end if;

      R :=
        Hacp.Evaluate.Evaluate_Authorization_V2
          (Input, Ctx, PK_Hex);

      Insert (Resp, "protocol_version", J_Str ("1"));
      Insert (Resp, "decision", J_Str (Decision_Str (R.Decision)));

      declare
         RC : constant JSON_Value_Access := J_Arr;
      begin
         if R.Reason_Len > 0 then
            Append (RC, J_Str (Reason_Str (R)));
         end if;
         Insert (Resp, "reason_codes", RC);
      end;

      if R.AH_Len > 0 then
         Insert
           (Resp,
            "action_hash",
            J_Str (Action_Hash_Str (R)));
      end if;

      PID := Get (Input, "provenance_event");

      if PID /= null and then not Is_Null (PID) then
         declare
            EID : constant JSON_Value_Access :=
              Get (PID, "event_id");
         begin
            if EID /= null and then not Is_Null (EID) then
               Insert (Resp, "provenance_id", Clone (EID));
            end if;
         end;
      end if;

      return Serialize (Resp);
   end Handle_Line;

begin
   loop
      declare
         Line : constant String := Get_Line;
      begin
         if Line'Length > 0 then
            begin
               Put_Line (Handle_Line (Line, Test_Pubkey_Hex));
            exception
               when E : others =>
                  Put_Line
                    (Standard_Error,
                     "{""error"":""EVALUATE_ERROR"",""message"":""" &
                     Ada.Exceptions.Exception_Message (E) &
                     """}");
            end;
         end if;
      end;
   end loop;

exception
   when End_Error => null;

end Hacp_Ada_Auth_V2_Runner;
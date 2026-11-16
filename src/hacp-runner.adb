--  Hacp.Runner — body.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Exceptions;
with Hacp.Json;             use Hacp.Json;
with Hacp.Evaluate;         use Hacp.Evaluate;

package body Hacp.Runner is

   function Decision_Str (D : Decision_Kind) return String is
   begin
      case D is
         when Allow      => return "ALLOW";
         when Deny       => return "DENY";
         when Checkpoint => return "CHECKPOINT";
      end case;
   end Decision_Str;

   function Handle_Line (Line : String; PK_Hex : String) return String is
      Req   : constant JSON_Value_Access := Parse (Line);
      Resp  : constant JSON_Value_Access := J_Obj;
      Ctx   : JSON_Value_Access;
      Input : constant JSON_Value_Access := Get (Req, "input");
      PID   : JSON_Value_Access;
      R     : Eval_Result;
   begin
      --  Get policy_context: top-level or nested in input
      Ctx := Get (Req, "policy_context");
      if Ctx = null or else Is_Null (Ctx) then
         Ctx := Get (Input, "policy_context");
      end if;
      if Ctx = null or else Is_Null (Ctx) then
         Ctx := J_Obj;
      end if;

      R := Hacp.Evaluate.Evaluate (Input, Ctx, PK_Hex);

      --  Build response
      Insert (Resp, "protocol_version", J_Str ("1"));
      Insert (Resp, "decision", J_Str (Decision_Str (R.Decision)));
      --  reason_codes as array
      declare
         RC : constant JSON_Value_Access := J_Arr;
      begin
         if R.Reason_Len > 0 then
            Append (RC, J_Str (Reason_Str (R)));
         end if;
         Insert (Resp, "reason_codes", RC);
      end;
      if R.AH_Len > 0 then
         Insert (Resp, "action_hash",
                 J_Str (Action_Hash_Str (R)));
      end if;

      --  provenance_id
      PID := Get (Input, "provenance_event");
      if PID /= null and then not Is_Null (PID) then
         declare
            EID : constant JSON_Value_Access := Get (PID, "event_id");
         begin
            if EID /= null and then not Is_Null (EID) then
               Insert (Resp, "provenance_id", Clone (EID));
            end if;
         end;
      end if;

      return Serialize (Resp);
   end Handle_Line;

   procedure Run (PK_Hex : String) is
   begin
      loop
         declare
            Line : constant String := Get_Line;
         begin
            if Line'Length = 0 then
               goto Continue;
            end if;
            begin
               declare
                  Resp : constant String := Handle_Line (Line, PK_Hex);
               begin
                  Put_Line (Resp);
               end;
            exception
               when E : others =>
                  Put_Line (Standard_Error,
                    "{""error"":""EVALUATE_ERROR"",""message"":""" &
                    Ada.Exceptions.Exception_Message (E) & """}");
            end;
         end;
         <<Continue>>
      end loop;
   exception
      when End_Error => null;
   end Run;

end Hacp.Runner;
with Ada.Text_IO; use Ada.Text_IO;

with Hacp.Json; use Hacp.Json;
with Hacp.Evaluate; use Hacp.Evaluate;

with Hacp.Controlplane.Journal;
use Hacp.Controlplane.Journal;

with Hacp.Controlplane.State;

procedure Hacp_Ada_Integrated is

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

   J : Journal_Type := Create;

begin
   declare
      Line : constant String := Get_Line;
      Req  : constant JSON_Value_Access := Parse (Line);

      Input : constant JSON_Value_Access :=
        Get (Req, "input");

      Baseline_Ctx : constant JSON_Value_Access := J_Obj;

      Baseline : Eval_Result;
      After    : Eval_Result;

      Token     : JSON_Value_Access;
      Token_Id  : JSON_Value_Access;

      Revoked   : Boolean;

      Snap      : Revocation_Snapshot;
      Revoked_Ctx : JSON_Value_Access;

      Resp : constant JSON_Value_Access := J_Obj;
   begin
      Insert (Baseline_Ctx, "clock", J_Int (0));

      Baseline :=
        Hacp.Evaluate.Evaluate
          (Input,
           Baseline_Ctx,
           Test_Pubkey_Hex);

      Token := Get (Input, "decision_token");
      Token_Id := Get (Token, "token_id");

      Revoked :=
        Revoke
          (J,
           Hacp.Controlplane.Journal.Token,
           Get_Str (Token_Id));

      Snap := Snapshot (J);

      Revoked_Ctx :=
        Hacp.Controlplane.State.To_Policy_Context
          (Snap,
           0);

      After :=
        Hacp.Evaluate.Evaluate
          (Input,
           Revoked_Ctx,
           Test_Pubkey_Hex);

      Insert
        (Resp,
         "baseline_decision",
         J_Str (Decision_Str (Baseline.Decision)));

      Insert
        (Resp,
         "revoke_committed",
         J_Bool (Revoked));

      Insert
        (Resp,
         "snapshot_revision",
         J_Int (Long_Long_Integer (Snap.Revision)));

      Insert
        (Resp,
         "post_revoke_decision",
         J_Str (Decision_Str (After.Decision)));

      if After.Reason_Len > 0 then
         Insert
           (Resp,
            "post_revoke_reason",
            J_Str (Reason_Str (After)));
      end if;

      Insert
        (Resp,
         "pass",
         J_Bool
           (Baseline.Decision = Allow
            and then
            After.Decision = Deny
            and then
            Reason_Str (After) = "TOKEN_REVOKED"));

      Put_Line (Serialize (Resp));
   end;

end Hacp_Ada_Integrated;

--  Hacp.Evaluate — Core 38 + HC2-55 request binding.
--  Normative evaluation semantics per HACP spec §5.1.
--  One evaluate for all binaries.

with Hacp.Json;    use Hacp.Json;
with Hacp.Crypto;  use Hacp.Crypto;
with Hacp.Jcs;

package Hacp.Evaluate is

   type Decision_Kind is (Allow, Deny, Checkpoint);

   type Eval_Result is record
      Decision     : Decision_Kind;
      Reason       : String (1 .. 32) := (others => ' ');
      Reason_Len   : Natural := 0;
      Action_Hash  : String (1 .. 64) := (others => ' ');
      AH_Len       : Natural := 0;
   end record;

   --  Convenience: reason code as String
   function Reason_Str (R : Eval_Result) return String;
   function Action_Hash_Str (R : Eval_Result) return String;

   --  Single entry point: evaluate with all invariants.
   --  Inputs:  inputs (proposed_action, intent_envelope, decision_token, ...)
   --  Context: policy_context (clock, revoked_*, trusted_keys, ...)
   --  PK_Hex:  64-char hex Ed25519 public key.
   function Evaluate
     (Inputs  : JSON_Value_Access;
      Context : JSON_Value_Access;
      PK_Hex  : String) return Eval_Result;

   --  Additive Authorization-v2 successor evaluation.
   --  Existing Evaluate remains the Core / HC2-compatible entry point.
   function Evaluate_Authorization_V2
     (Inputs  : JSON_Value_Access;
      Context : JSON_Value_Access;
      PK_Hex  : String) return Eval_Result;

end Hacp.Evaluate;
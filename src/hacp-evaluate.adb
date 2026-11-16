--  Hacp.Evaluate — body: Core 38 + HC2-55.

with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Hacp.Libsodium;

package body Hacp.Evaluate is

   --  ─── Helpers ─────────────────────────────────────────────────

   function Reason_Str (R : Eval_Result) return String is
   begin
      return R.Reason (1 .. R.Reason_Len);
   end Reason_Str;

   function Action_Hash_Str (R : Eval_Result) return String is
   begin
      return R.Action_Hash (1 .. R.AH_Len);
   end Action_Hash_Str;

   procedure Set_Reason (R : in out Eval_Result; S : String) is
   begin
      R.Reason_Len := S'Length;
      R.Reason (1 .. S'Length) := S;
   end Set_Reason;

   procedure Set_Action_Hash (R : in out Eval_Result; H : String) is
   begin
      R.AH_Len := H'Length;
      R.Action_Hash (1 .. H'Length) := H;
   end Set_Action_Hash;

   function Make_Deny (Reason : String; AH : String) return Eval_Result is
      R : Eval_Result;
   begin
      R.Decision := Deny;
      Set_Reason (R, Reason);
      Set_Action_Hash (R, AH);
      return R;
   end Make_Deny;

   function Make_Checkpoint
     (AH     : String;
      Reason : String := "") return Eval_Result
   is
      R : Eval_Result;
   begin
      R.Decision := Checkpoint;
      if Reason'Length > 0 then
         Set_Reason (R, Reason);
      end if;
      Set_Action_Hash (R, AH);
      return R;
   end Make_Checkpoint;

   function Make_Allow (AH : String) return Eval_Result is
      R : Eval_Result;
   begin
      R.Decision := Allow;
      Set_Action_Hash (R, AH);
      return R;
   end Make_Allow;

   --  Check if string array contains value
   function Arr_Contains (Arr : JSON_Value_Access; Val : String)
     return Boolean is
   begin
      if Arr = null or else Arr.Kind /= JSON_Array then
         return False;
      end if;
      for I in 1 .. Length (Arr) loop
         if Get_Str (Get (Arr, I)) = Val then
            return True;
         end if;
      end loop;
      return False;
   end Arr_Contains;

   --  HC2 normalize request target (uppercase percent-encoded hex)
   function HC2_Normalize (Target : String) return String is
      Result : String (1 .. Target'Length * 3);
      J      : Positive := 1;
      I      : Positive := Target'First;
   begin
      while I <= Target'Last loop
         if Target (I) = '%'
           and then I + 2 <= Target'Last
           and then Target (I + 1) in '0' .. '9' | 'a' .. 'f' |
                                      'A' .. 'F'
           and then Target (I + 2) in '0' .. '9' | 'a' .. 'f' |
                                      'A' .. 'F'
         then
            Result (J)     := '%';
            Result (J + 1) := To_Upper (Target (I + 1));
            Result (J + 2) := To_Upper (Target (I + 2));
            J := J + 3;
            I := I + 3;
         else
            Result (J) := Target (I);
            J := J + 1;
            I := I + 1;
         end if;
      end loop;
      return Result (1 .. J - 1);
   end HC2_Normalize;

   --  Verify provenance event (INV-4)
   function Verify_Provenance
     (Event : JSON_Value_Access;
      Prior : JSON_Value_Access;
      PK    : Hacp.Libsodium.Ed25519_PK) return Boolean
   is
      Payload      : constant JSON_Value_Access := Get (Event, "payload");
      Payload_Hash : constant String := Get_Str (Get (Event, "payload_hash"));
      Prev_Hash    : constant String :=
        Get_Str (Get (Event, "prev_event_hash"));
      Sig          : constant String :=
        Get_Str (Get (Event, "signature"));
      Genesis      : constant String := (1 .. 64 => '0');
   begin
      if Is_Null (Payload) then
         return False;
      end if;
      declare
         Canon    : constant String := Jcs.Canonicalize (Payload);
         Computed : constant String := SHA256_Hex (Canon);
      begin
         if Payload_Hash /= Computed then
            return False;
         end if;
      end;
      declare
         Expected_Prev : String (1 .. 64);
      begin
         if Is_Null (Prior) then
            Expected_Prev := Genesis;
         else
            Expected_Prev :=
              SHA256_Hex (Jcs.Canonicalize (Prior));
         end if;
         if Prev_Hash /= Expected_Prev then
            return False;
         end if;
      end;
      declare
         No_Sig : constant JSON_Value_Access :=
           Without_Key (Event, "signature");
         Canon  : constant String := Jcs.Canonicalize (No_Sig);
      begin
         return Verify_Signature (PK, Canon, Sig);
      end;
   end Verify_Provenance;

   --  ─── Main Evaluate ──────────────────────────────────────────

   function Evaluate_Internal
     (Inputs           : JSON_Value_Access;
      Context          : JSON_Value_Access;
      PK_Hex           : String;
      Authorization_V2 : Boolean) return Eval_Result
   is
      Empty_Obj  : constant JSON_Value_Access := J_Obj;
      Action     : constant JSON_Value_Access :=
        (if Has (Inputs, "proposed_action")
         then Get (Inputs, "proposed_action") else Empty_Obj);
      Envelope   : constant JSON_Value_Access :=
        (if Has (Inputs, "intent_envelope")
         then Get (Inputs, "intent_envelope") else Empty_Obj);
      Token      : constant JSON_Value_Access :=
        (if Has (Inputs, "decision_token")
         then Get (Inputs, "decision_token") else null);
      Checkpoint      : constant JSON_Value_Access :=
        (if Has (Inputs, "checkpoint")
         then Get (Inputs, "checkpoint") else null);
      Checkpoint_St   : constant JSON_Value_Access :=
        (if Has (Inputs, "checkpoint_state")
         then Get (Inputs, "checkpoint_state") else null);
      Has_Token       : constant Boolean :=
        Token /= null and then not Is_Null (Token);

      PK       : Hacp.Libsodium.Ed25519_PK;
      Action_H : String (1 .. 64) := (others => '0');

      procedure Compute_Action_Hash is
         Canon : constant String := Jcs.Canonicalize (Action);
      begin
         Action_H := SHA256_Hex (Canon);
      end Compute_Action_Hash;

      function Clock return Long_Long_Integer is
         C : JSON_Value_Access;
      begin
         C := Get (Context, "clock");
         if C /= null and then not Is_Null (C) then
            return Get_Int (C);
         end if;
         C := Get (Context, "current_time");
         if C /= null and then not Is_Null (C) then
            return Get_Int (C);
         end if;
         C := Get (Envelope, "issued_at");
         if C /= null and then not Is_Null (C) then
            return Get_Int (C);
         end if;
         return 0;
      end Clock;

   begin
      begin
         PK := Load_Public_Key (PK_Hex);
      exception
         when Constraint_Error =>
            return Make_Deny ("SIGNATURE_FAILURE", "");
      end;

      Compute_Action_Hash;

      --  Authorization-v2 successor boundary.
      --
      --  Authenticate the IntentEnvelope before trusting signed
      --  authorization claims or entering Core evaluation.
      --
      --  This path is additive. Legacy Evaluate does not execute it.
      if Authorization_V2 then

         --  Envelope signing-key revocation.
         declare
            Revoked_Keys : constant JSON_Value_Access :=
              Get (Context, "revoked_keys");
            Env_Key : constant String :=
              Get_Str (Get (Envelope, "signer_key_id"));
         begin
            if Arr_Contains (Revoked_Keys, Env_Key) then
               return Make_Deny ("KEY_REVOKED", Action_H);
            end if;
         end;

         --  HMAC is not accepted as an Authorization-v2 signature.
         if Field_Contains (Envelope, "signer_key_id", "hmac") then
            return Make_Deny ("SIGNATURE_FAILURE", Action_H);
         end if;

         --  Trusted-key boundary.
         declare
            Env_Key : constant String :=
              Get_Str (Get (Envelope, "signer_key_id"));
            Trusted : constant JSON_Value_Access :=
              Get (Context, "trusted_keys");
         begin
            if Trusted /= null and then not Is_Null (Trusted) then
               if not Arr_Contains (Trusted, Env_Key) then
                  return Make_Deny ("SIGNATURE_FAILURE", Action_H);
               end if;
            end if;
         end;

         --  Authenticate complete signed IntentEnvelope.
         declare
            Envelope_No_Sig : constant JSON_Value_Access :=
              Without_Key (Envelope, "signature");
            Canon           : constant String :=
              Jcs.Canonicalize (Envelope_No_Sig);
            Sig             : constant String :=
              Get_Str (Get (Envelope, "signature"));
         begin
            if not Verify_Signature (PK, Canon, Sig) then
               return Make_Deny ("SIGNATURE_FAILURE", Action_H);
            end if;
         end;

         --  Revocation is evaluated only after envelope authentication.
         declare
            Revoked_Envs : constant JSON_Value_Access :=
              Get (Context, "revoked_envelopes");
            Env_ID : constant String :=
              Get_Str (Get (Envelope, "envelope_id"));
            Parent : constant String :=
              Get_Str (Get (Envelope, "parent_envelope_id"));
         begin
            if Arr_Contains (Revoked_Envs, Env_ID) or else
              (Parent'Length > 0 and then
                 Arr_Contains (Revoked_Envs, Parent))
            then
               return Make_Deny ("ENVELOPE_REVOKED", Action_H);
            end if;
         end;

      end if;

      --  Step 1: Checkpoint pre-evaluation
      if Checkpoint /= null and then not Is_Null (Checkpoint) then
         declare
            State : Unbounded_String :=
              To_Unbounded_String (Get_Str (Get (Checkpoint, "state")));
            Exp   : Long_Long_Integer;
         begin
            if To_String (State) = "" then
               State := To_Unbounded_String
                 (Get_Str (Get (Checkpoint, "status")));
            end if;
            Exp := Get_Int (Get (Checkpoint, "expires_at"));
            if To_String (State) = "OPEN" and then Clock > Exp then
               State := To_Unbounded_String ("EXPIRED");
            end if;
            if To_String (State) = "EXPIRED" then
               return Make_Deny ("CHECKPOINT_TIMEOUT", Action_H);
            elsif To_String (State) = "RESOLVED_DENY" then
               return Make_Deny ("CHECKPOINT_DENIED", Action_H);
            elsif To_String (State) = "OPEN" then
               return Make_Checkpoint (Action_H);
            elsif To_String (State) = "RESOLVED_ALLOW" then
               declare
                  Kind  : constant String :=
                    Get_Str (Get (Checkpoint, "resolver_principal_kind"));
                  Alt   : constant String :=
                    Get_Str (Get (Checkpoint, "resolved_by_kind"));
                  Resolver : constant String :=
                    (if Kind'Length > 0 then Kind else Alt);
               begin
                  if Resolver = "system" then
                     return Make_Deny
                       ("HUMAN_RESOLUTION_REQUIRED", Action_H);
                  end if;
               end;
            else
               return Make_Deny ("INVALID_CHECKPOINT_STATE", Action_H);
            end if;
         end;
      end if;

      --  Step 1b: Checkpoint state
      if Checkpoint_St /= null and then not Is_Null (Checkpoint_St) then
         declare
            Created : constant Long_Long_Integer :=
              Get_Int (Get (Checkpoint_St, "created_at"));
            Timeout : Long_Long_Integer :=
              Get_Int (Get (Checkpoint_St, "timeout_seconds"));
         begin
            if Timeout = 0 then
               Timeout := Get_Int
                 (Get (Context, "checkpoint_timeout_seconds"));
            end if;
            if Timeout > 0 and then Clock > Created + Timeout then
               return Make_Deny ("CHECKPOINT_TIMEOUT", Action_H);
            end if;
         end;
      end if;

      --  Step 2: Clock, token expiry, envelope expiry
      if Checkpoint_St = null or else Is_Null (Checkpoint_St) then
         declare
            Timeout : constant Long_Long_Integer :=
              Get_Int (Get (Context, "checkpoint_timeout_seconds"));
         begin
            if Timeout > 0 then
               declare
                  Verb      : constant String :=
                    Get_Str (Get (Action, "verb"));
                  Is_System : constant Boolean :=
                    Get_Str (Get (Envelope, "principal_kind")) = "system";
                  Needs_Human : Boolean := False;
                  HRV : constant JSON_Value_Access :=
                    Get (Context, "human_required_verbs");
               begin
                  if HRV /= null and then HRV.Kind = JSON_Array then
                     for I in 1 .. Length (HRV) loop
                        if Get_Str (Get (HRV, I)) = Verb then
                           Needs_Human := True;
                           exit;
                        end if;
                     end loop;
                  end if;
                  if Is_System and then Needs_Human then
                     declare
                        Wait_Start : Long_Long_Integer :=
                          Get_Int (Get (Action, "proposed_at"));
                     begin
                        if Wait_Start = 0 then
                           Wait_Start := Get_Int
                             (Get (Envelope, "issued_at"));
                        end if;
                        if Wait_Start > 0 and then
                          Clock > Wait_Start + Timeout
                        then
                           return Make_Deny
                             ("CHECKPOINT_TIMEOUT", Action_H);
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end if;

      --  Token expiry
      if Has_Token then
         declare
            Tok_Exp : constant Long_Long_Integer :=
              Get_Int (Get (Token, "expires_at"));
         begin
            if Tok_Exp > 0 and then Clock > Tok_Exp then
               return Make_Deny ("TOKEN_EXPIRED", Action_H);
            end if;
         end;
      end if;

      --  Envelope expiry
      declare
         Env_Exp : constant Long_Long_Integer :=
           Get_Int (Get (Envelope, "expires_at"));
      begin
         if Env_Exp > 0 and then Clock > Env_Exp then
            return Make_Deny ("ENVELOPE_EXPIRED", Action_H);
         end if;
      end;

      --  Step 3: Envelope revocation
      declare
         Revoked_Envs : constant JSON_Value_Access :=
           Get (Context, "revoked_envelopes");
         Env_ID : constant String :=
           Get_Str (Get (Envelope, "envelope_id"));
         Parent : constant String :=
           Get_Str (Get (Envelope, "parent_envelope_id"));
      begin
         if Arr_Contains (Revoked_Envs, Env_ID) or else
           (Parent'Length > 0 and then Arr_Contains (Revoked_Envs, Parent))
         then
            return Make_Deny ("ENVELOPE_REVOKED", Action_H);
         end if;
      end;

      --  Step 4: Key revocation
      declare
         Revoked_Keys : constant JSON_Value_Access :=
           Get (Context, "revoked_keys");
         Env_Key : constant String :=
           Get_Str (Get (Envelope, "signer_key_id"));
      begin
         if Arr_Contains (Revoked_Keys, Env_Key) then
            return Make_Deny ("KEY_REVOKED", Action_H);
         end if;
         if Has_Token then
            declare
               Tok_Key : constant String :=
                 Get_Str (Get (Token, "signer_key_id"));
            begin
               if Arr_Contains (Revoked_Keys, Tok_Key) then
                  return Make_Deny ("KEY_REVOKED", Action_H);
               end if;
            end;
         end if;
      end;

      --  Step 5: HMAC rejection
      if Field_Contains (Envelope, "signer_key_id", "hmac") then
         return Make_Deny ("SIGNATURE_FAILURE", Action_H);
      end if;
      if Has_Token then
         if Field_Contains (Token, "signer_key_id", "hmac") then
            return Make_Deny ("SIGNATURE_FAILURE", Action_H);
         end if;
      end if;

      --  Step 6: Token revocation
      if Has_Token then
         declare
            Revoked_Toks : constant JSON_Value_Access :=
              Get (Context, "revoked_tokens");
            Tok_ID : constant String :=
              Get_Str (Get (Token, "token_id"));
         begin
            if Arr_Contains (Revoked_Toks, Tok_ID) then
               return Make_Deny ("TOKEN_REVOKED", Action_H);
            end if;
         end;
      end if;

      --  Step 7: Trusted keys
      declare
         Env_Key : constant String :=
           Get_Str (Get (Envelope, "signer_key_id"));
         Trusted : constant JSON_Value_Access :=
           Get (Context, "trusted_keys");
      begin
         if Trusted /= null and then not Is_Null (Trusted) then
            if not Arr_Contains (Trusted, Env_Key) then
               return Make_Deny ("SIGNATURE_FAILURE", Action_H);
            end if;
            if Has_Token then
               declare
                  Tok_Key : constant String :=
                    Get_Str (Get (Token, "signer_key_id"));
               begin
                  if not Arr_Contains (Trusted, Tok_Key) then
                     return Make_Deny ("SIGNATURE_FAILURE", Action_H);
                  end if;
               end;
            end if;
         end if;
      end;

      --  Step 8: Human final decision (INV-1)
      declare
         HRV    : constant JSON_Value_Access :=
           Get (Context, "human_required_verbs");
         Verb   : constant String :=
           Get_Str (Get (Action, "verb"));
         PKind  : constant String :=
           Get_Str (Get (Envelope, "principal_kind"));
         Parent : constant String :=
           Get_Str (Get (Envelope, "parent_envelope_id"));
      begin
         if HRV /= null and then HRV.Kind = JSON_Array then
            for I in 1 .. Length (HRV) loop
               if Get_Str (Get (HRV, I)) = Verb and then PKind = "system"
               then
                  if Parent'Length = 0 then
                     return Make_Checkpoint (Action_H, "HUMAN_REQUIRED");
                  end if;
                  exit;
               end if;
            end loop;
         end if;
      end;

      --  Step 9: Bounded autonomy (INV-7)
      declare
         Budget     : constant JSON_Value_Access :=
           Get (Envelope, "autonomy_budget");
         Has_Budget : Boolean := False;
      begin
         if Budget /= null and then not Is_Null (Budget) then
            declare
               Max_Actions : constant Long_Long_Integer :=
                 Get_Int (Get (Budget, "max_actions"));
               Cur_Count   : constant Long_Long_Integer :=
                 Get_Int (Get (Context, "current_action_count"));
            begin
               if Max_Actions > 0 then
                  Has_Budget := True;
                  if Cur_Count >= Max_Actions then
                     return Make_Deny ("BUDGET_EXHAUSTED", Action_H);
                  end if;
               end if;
            end;
         end if;

         --  Step 10: Boundary re-authorization (INV-2)
         declare
            Scope : constant JSON_Value_Access := Get (Envelope, "scope");
         begin
            if Scope = null or else Is_Null (Scope) or else
              Scope.Kind /= JSON_Object
            then
               return Make_Deny ("BOUNDARY_CROSSING", Action_H);
            end if;

            --  Scope attribute checks
            declare
               type Check_Info is record
                  Attr : String (1 .. 16);
                  ALen : Natural;
                  Key  : String (1 .. 16);
                  KLen : Natural;
               end record;
               Checks : constant array (1 .. 6) of Check_Info :=
                 (("verb            ", 4,  "verbs           ", 5),
                  ("resource_class  ", 14, "resource_classes", 16),
                  ("audience        ", 8,  "audiences       ", 9),
                  ("reversibility   ", 13, "reversibility   ", 13),
                  ("externality     ", 11, "externality     ", 11),
                  ("data_class      ", 10, "data_classes    ", 12));
            begin
               for Ch of Checks loop
                  declare
                     Allowed : constant JSON_Value_Access :=
                       Get (Scope, Ch.Key (1 .. Ch.KLen));
                  begin
                     if Allowed /= null and then
                       Allowed.Kind = JSON_Array
                     then
                        declare
                           Val : constant JSON_Value_Access :=
                             Get (Action, Ch.Attr (1 .. Ch.ALen));
                        begin
                           if Val = null or else Val.Kind /= JSON_String
                           then
                              return Make_Deny
                                ("UNKNOWN_ATTRIBUTE", Action_H);
                           end if;
                           if not Arr_Contains (Allowed, Get_Str (Val))
                           then
                              return Make_Deny
                                ("BOUNDARY_CROSSING", Action_H);
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end;

            --  Quantity check
            declare
               Q     : constant JSON_Value_Access :=
                 Get (Action, "quantity");
               Max_Q : constant JSON_Value_Access :=
                 Get (Scope, "max_quantity");
            begin
               if Q /= null and then not Is_Null (Q) and then
                 Max_Q /= null and then not Is_Null (Max_Q)
               then
                  if Get_Int (Q) > Get_Int (Max_Q) then
                     return Make_Deny ("SCOPE_EXCEEDED", Action_H);
                  end if;
               end if;
            end;

            --  Destination allowlist
            declare
               Dests : constant JSON_Value_Access :=
                 Get (Scope, "destinations");
            begin
               if Dests /= null and then Dests.Kind = JSON_Array
                 and then Length (Dests) > 0
               then
                  declare
                     Dest : constant JSON_Value_Access :=
                       Get (Action, "destination");
                  begin
                     if Dest = null or else Dest.Kind /= JSON_String then
                        return Make_Deny
                          ("UNKNOWN_ATTRIBUTE", Action_H);
                     end if;
                     if not Arr_Contains (Dests, Get_Str (Dest)) then
                        return Make_Deny
                          ("BOUNDARY_CROSSING", Action_H);
                     end if;
                  end;
               end if;
            end;

            --  Tool allowlist
            declare
               Tools : constant JSON_Value_Access :=
                 Get (Scope, "tool_names");
            begin
               if Tools /= null and then Tools.Kind = JSON_Array
                 and then Length (Tools) > 0
               then
                  declare
                     TN : constant JSON_Value_Access :=
                       Get (Action, "tool_name");
                  begin
                     if TN = null or else TN.Kind /= JSON_String then
                        return Make_Deny
                          ("UNKNOWN_ATTRIBUTE", Action_H);
                     end if;
                     if not Arr_Contains (Tools, Get_Str (TN)) then
                        return Make_Deny
                          ("BOUNDARY_CROSSING", Action_H);
                     end if;
                  end;
               end if;
            end;
         end;
      end;

      --  Step 11: Token crypto verification (INV-3, INV-5)
      if Has_Token then
         if Get_Str (Get (Token, "envelope_id")) /=
           Get_Str (Get (Envelope, "envelope_id"))
         then
            return Make_Deny ("TOKEN_ENVELOPE_MISMATCH", Action_H);
         end if;

         if Authorization_V2 then

            --  Successor semantics: authenticate the complete signed
            --  token before trusting any signed authorization claim.
            declare
               Token_No_Sig : constant JSON_Value_Access :=
                 Without_Key (Token, "signature");
               Canon        : constant String :=
                 Jcs.Canonicalize (Token_No_Sig);
               Sig          : constant String :=
                 Get_Str (Get (Token, "signature"));
            begin
               if not Verify_Signature (PK, Canon, Sig) then
                  return Make_Deny ("SIGNATURE_FAILURE", Action_H);
               end if;
            end;

            --  Authorization-v2 action binding.
            declare
               Canon    : constant String := Jcs.Canonicalize (Action);
               Computed : constant String := SHA256_Hex (Canon);
            begin
               if Get_Str (Get (Token, "action_hash")) /= Computed then
                  return Make_Deny ("SIGNATURE_FAILURE", Computed);
               end if;
            end;

            --  Authenticated applicable signed DENY is authoritative.
            if Get_Str (Get (Token, "decision")) = "DENY" then
               return Make_Deny ("POLICY_DENIED", Action_H);
            end if;

         else

            --  Legacy Core semantics remain unchanged.
            declare
               Canon    : constant String := Jcs.Canonicalize (Action);
               Computed : constant String := SHA256_Hex (Canon);
            begin
               if Get_Str (Get (Token, "action_hash")) /= Computed then
                  return Make_Deny ("HASH_MISMATCH", Computed);
               end if;
            end;

            declare
               Token_No_Sig : constant JSON_Value_Access :=
                 Without_Key (Token, "signature");
               Canon        : constant String :=
                 Jcs.Canonicalize (Token_No_Sig);
               Sig          : constant String :=
                 Get_Str (Get (Token, "signature"));
            begin
               if not Verify_Signature (PK, Canon, Sig) then
                  return Make_Deny ("SIGNATURE_FAILURE", Action_H);
               end if;
            end;

         end if;
      end if;

      --  Step 12: No-token path
      if not Has_Token then
         declare
            Budget     : constant JSON_Value_Access :=
              Get (Envelope, "autonomy_budget");
            Has_Budget : Boolean := False;
            Prov       : constant JSON_Value_Access :=
              Get (Inputs, "provenance_event");
         begin
            if Budget /= null and then not Is_Null (Budget) then
               if Get_Int (Get (Budget, "max_actions")) > 0 then
                  Has_Budget := True;
               end if;
            end if;
            if not Has_Budget then
               if Is_Null (Prov) then
                  return Make_Deny ("TRACEABILITY_MISSING", Action_H);
               end if;
            end if;
         end;
      end if;

      --  Step 13: Provenance verification (INV-4)
      declare
         Prov  : constant JSON_Value_Access :=
           Get (Inputs, "provenance_event");
         Prior : constant JSON_Value_Access :=
           Get (Inputs, "prior_provenance_event");
         Omit  : constant JSON_Value_Access :=
           Get (Inputs, "omit_provenance");
      begin
         if Omit /= null and then Get_Bool (Omit) then
            return Make_Deny ("TRACEABILITY_MISSING", Action_H);
         end if;
         if Prov /= null and then not Is_Null (Prov) then
            if not Verify_Provenance (Prov, Prior, PK) then
               return Make_Deny ("TRACEABILITY_FAILURE", Action_H);
            end if;
         end if;
      end;

      --  Step 14: HC2-55 request binding
      declare
         Http_Req : constant JSON_Value_Access :=
           Get (Inputs, "http_request");
      begin
         if Http_Req /= null and then not Is_Null (Http_Req) then
            declare
               Req_Target : constant String :=
                 Get_Str (Get (Http_Req, "request_target"));
               Tok_Constraints : constant JSON_Value_Access :=
                 (if Has_Token then Get (Token, "constraints")
                  else null);
            begin
               if Tok_Constraints /= null and then
                 not Is_Null (Tok_Constraints)
               then
                  declare
                     Constraint_Path : constant String :=
                       Get_Str (Get (Tok_Constraints, "path"));
                  begin
                     if Constraint_Path'Length > 0 then
                        if HC2_Normalize (Req_Target) /=
                          HC2_Normalize (Constraint_Path)
                        then
                           return Make_Deny
                             ("SCOPE_EXCEEDED", Action_H);
                        end if;
                     end if;
                  end;
               end if;
            end;
         end if;
      end;

      --  Final: ALLOW
      return Make_Allow (Action_H);
   end Evaluate_Internal;

   --  Legacy Core / HC2-compatible entry point.
   function Evaluate
     (Inputs  : JSON_Value_Access;
      Context : JSON_Value_Access;
      PK_Hex  : String) return Eval_Result
   is
   begin
      return Evaluate_Internal
        (Inputs           => Inputs,
         Context          => Context,
         PK_Hex           => PK_Hex,
         Authorization_V2 => False);
   end Evaluate;

   --  Additive Authorization-v2 successor entry point.
   function Evaluate_Authorization_V2
     (Inputs  : JSON_Value_Access;
      Context : JSON_Value_Access;
      PK_Hex  : String) return Eval_Result
   is
   begin
      return Evaluate_Internal
        (Inputs           => Inputs,
         Context          => Context,
         PK_Hex           => PK_Hex,
         Authorization_V2 => True);
   end Evaluate_Authorization_V2;

end Hacp.Evaluate;

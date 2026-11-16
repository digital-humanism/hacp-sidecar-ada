with Hacp.Json; use Hacp.Json;
with Hacp.Controlplane.Journal; use Hacp.Controlplane.Journal;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Hacp.Controlplane.State is

   function To_Policy_Context
     (S     : Revocation_Snapshot;
      Clock : Long_Long_Integer)
      return JSON_Value_Access
   is
      Ctx       : constant JSON_Value_Access := J_Obj;
      Keys      : constant JSON_Value_Access := J_Arr;
      Tokens    : constant JSON_Value_Access := J_Arr;
      Envelopes : constant JSON_Value_Access := J_Arr;
   begin
      Insert (Ctx, "clock", J_Int (Clock));

      for I in 1 .. Natural (Entry_Vectors.Length (S.Entries)) loop
         declare
            E : constant Revocation_Entry :=
              Entry_Vectors.Element (S.Entries, I);

            Subject : constant String :=
              To_String (E.Subject_Id);
         begin
            case E.Kind is
               when Key =>
                  Append (Keys, J_Str (Subject));

               when Token =>
                  Append (Tokens, J_Str (Subject));

               when Envelope | Parent_Envelope =>
                  Append (Envelopes, J_Str (Subject));
            end case;
         end;
      end loop;

      Insert (Ctx, "revoked_keys", Keys);
      Insert (Ctx, "revoked_tokens", Tokens);
      Insert (Ctx, "revoked_envelopes", Envelopes);

      return Ctx;
   end To_Policy_Context;

end Hacp.Controlplane.State;

--  Hacp.Controlplane.Server — body.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Exceptions;
with Hacp.Json;             use Hacp.Json;

package body Hacp.Controlplane.Server is

   procedure Run (J : in out Journal_Type) is
   begin
      loop
         declare
            Line  : constant String := Get_Line;
            Req   : JSON_Value_Access;
            Resp  : JSON_Value_Access;
            Id    : JSON_Value_Access;
            Method : String (1 .. 32);
            MLen  : Natural := 0;
         begin
            if Line'Length = 0 then
               goto Continue;
            end if;
            begin
               Req := Parse (Line);
               Id := Get (Req, "id");
               declare
                  M : constant String :=
                    Get_Str (Get (Req, "method"));
               begin
                  Method (1 .. M'Length) := M;
                  MLen := M'Length;
               end;

               Resp := J_Obj;
               if Id /= null then
                  Insert (Resp, "id", Clone (Id));
               end if;

               if Method (1 .. MLen) = "revoke" then
                  declare
                     Kind : constant Natural :=
                       Natural (Get_Int (Get (Req, "kind")));
                     Subj : constant String :=
                       Get_Str (Get (Req, "subject_id"));
                     K    : Revocation_Kind;
                     OK   : Boolean;
                  begin
                     K := Int_To_Kind (Kind);
                     OK := Revoke (J, K, Subj);
                     Insert (Resp, "ok", J_Bool (True));
                     if not OK then
                        Insert (Resp, "duplicate", J_Bool (True));
                     end if;
                  end;

               elsif Method (1 .. MLen) = "snapshot" then
                  declare
                     S     : constant Revocation_Snapshot :=
                       Snapshot (J);
                     S_Obj : constant JSON_Value_Access := J_Obj;
                     E_Arr : constant JSON_Value_Access := J_Arr;
                  begin
                     Insert (S_Obj, "revision",
                             J_Int (Long_Long_Integer (S.Revision)));
                     for I in 1 ..
                       Natural (Entry_Vectors.Length (S.Entries))
                     loop
                        declare
                           E : constant Revocation_Entry :=
                             Entry_Vectors.Element (S.Entries, I);
                           E_Obj : constant JSON_Value_Access := J_Obj;
                        begin
                           Insert (E_Obj, "kind",
                             J_Int (Long_Long_Integer
                               (Kind_Int (E.Kind))));
                           Insert (E_Obj, "subject_id",
                             J_Str (To_String (E.Subject_Id)));
                           Append (E_Arr, E_Obj);
                        end;
                     end loop;
                     Insert (S_Obj, "entries", E_Arr);
                     Insert (Resp, "ok", J_Bool (True));
                     Insert (Resp, "snapshot", S_Obj);
                  end;

               elsif Method (1 .. MLen) = "events_after" then
                  declare
                     After : constant Natural :=
                       Natural (Get_Int
                         (Get (Req, "after_revision")));
                     Events : constant Event_Vectors.Vector :=
                       Events_After (J, After);
                     E_Arr  : constant JSON_Value_Access := J_Arr;
                  begin
                     for I in 1 ..
                       Natural (Event_Vectors.Length (Events))
                     loop
                        declare
                           E : constant Revocation_Event :=
                             Event_Vectors.Element (Events, I);
                           E_Obj : constant JSON_Value_Access := J_Obj;
                        begin
                           Insert (E_Obj, "revision",
                             J_Int (Long_Long_Integer (E.Revision)));
                           Insert (E_Obj, "event_id",
                             J_Str (To_String (E.Event_Id)));
                           Insert (E_Obj, "kind",
                             J_Int (Long_Long_Integer
                               (Kind_Int (E.Kind))));
                           Insert (E_Obj, "subject_id",
                             J_Str (To_String (E.Subject_Id)));
                           Insert (E_Obj, "issued_at_ms",
                             J_Int (E.Issued_At_Ms));
                           Append (E_Arr, E_Obj);
                        end;
                     end loop;
                     Insert (Resp, "ok", J_Bool (True));
                     Insert (Resp, "events", E_Arr);
                  end;

               elsif Method (1 .. MLen) = "revision" then
                  Insert (Resp, "ok", J_Bool (True));
                  Insert (Resp, "revision",
                    J_Int (Long_Long_Integer (Revision (J))));

               else
                  Insert (Resp, "ok", J_Bool (False));
                  Insert (Resp, "error",
                    J_Str ("unknown method: " &
                           Method (1 .. MLen)));
               end if;

               Put_Line (Serialize (Resp));
            exception
               when E : others =>
                  declare
                     Err : constant JSON_Value_Access := J_Obj;
                  begin
                     Insert (Err, "ok", J_Bool (False));
                     Insert (Err, "error",
                       J_Str (Ada.Exceptions.Exception_Message (E)));
                     Put_Line (Serialize (Err));
                  end;
            end;
         end;
         <<Continue>>
      end loop;
   exception
      when End_Error => null;
   end Run;

end Hacp.Controlplane.Server;
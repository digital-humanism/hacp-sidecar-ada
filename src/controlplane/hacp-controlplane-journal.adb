--  Hacp.Controlplane.Journal — body.

with Ada.Calendar;           use Ada.Calendar;
with Ada.Calendar.Conversions;

package body Hacp.Controlplane.Journal is

   function Kind_Int (K : Revocation_Kind) return Natural is
   begin
      case K is
         when Key              => return 1;
         when Token            => return 2;
         when Envelope         => return 3;
         when Parent_Envelope  => return 4;
      end case;
   end Kind_Int;

   function Int_To_Kind (V : Natural) return Revocation_Kind is
   begin
      case V is
         when 1 => return Key;
         when 2 => return Token;
         when 3 => return Envelope;
         when 4 => return Parent_Envelope;
         when others => return Key;
      end case;
   end Int_To_Kind;

   function Epoch_Ms return Long_Long_Integer is
      Now : constant Time := Clock;
      S   : constant Long_Long_Integer :=
        Long_Long_Integer (Conversions.To_Unix_Time (Now));
   begin
      return S * 1000;
   end Epoch_Ms;

   function Create return Journal_Type is
   begin
      return (Rev => 0, Events => Event_Vectors.Empty_Vector,
              Revoked => (others => String_Sets.Empty_Map));
   end Create;

   function Revision (J : Journal_Type) return Natural is
   begin
      return J.Rev;
   end Revision;

   function Revoke
     (J       : in out Journal_Type;
      Kind    : Revocation_Kind;
      Subject : String) return Boolean
   is
      Subj : constant Unbounded_String :=
        To_Unbounded_String (Subject);
   begin
      if Subject'Length = 0 then
         return False;
      end if;
      if String_Sets.Contains (J.Revoked (Kind), Subj) then
         return False;  --  Duplicate
      end if;
      J.Rev := J.Rev + 1;
      String_Sets.Include (J.Revoked (Kind), Subj, True);
      Event_Vectors.Append
        (J.Events,
         Revocation_Event'
           (Revision     => J.Rev,
            Event_Id     => To_Unbounded_String
              ("revocation-" & J.Rev'Image),
            Kind         => Kind,
            Subject_Id   => Subj,
            Issued_At_Ms => Epoch_Ms));
      return True;
   end Revoke;

   function Snapshot (J : Journal_Type) return Revocation_Snapshot is
      S : Revocation_Snapshot;
   begin
      S.Revision := J.Rev;
      for K in Revocation_Kind loop
         declare
            use String_Sets;
            C : Cursor := First (J.Revoked (K));
         begin
            while Has_Element (C) loop
               Entry_Vectors.Append
                 (S.Entries,
                  Revocation_Entry'
                    (Kind       => K,
                     Subject_Id => Key (C)));
               Next (C);
            end loop;
         end;
      end loop;
      S.Generated_Ms := Epoch_Ms;
      return S;
   end Snapshot;

   function Events_After (J : Journal_Type; After : Natural)
     return Event_Vectors.Vector
   is
      R : Event_Vectors.Vector;
   begin
      for I in 1 .. Natural (Event_Vectors.Length (J.Events)) loop
         declare
            E : constant Revocation_Event :=
              Event_Vectors.Element (J.Events, I);
         begin
            if E.Revision > After then
               Event_Vectors.Append (R, E);
            end if;
         end;
      end loop;
      return R;
   end Events_After;

   function Oldest_Available (J : Journal_Type) return Natural is
   begin
      if Event_Vectors.Is_Empty (J.Events) then
         return J.Rev + 1;
      end if;
      return Event_Vectors.Element (J.Events, 1).Revision;
   end Oldest_Available;

end Hacp.Controlplane.Journal;
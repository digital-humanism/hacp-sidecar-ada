--  Hacp.Controlplane.Journal — authoritative in-memory revocation journal.
--  Revision is globally monotonic; state is monotonic.

with Ada.Containers.Vectors;
with Ada.Containers.Hashed_Maps;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Hash;

package Hacp.Controlplane.Journal is

   type Revocation_Kind is (Key, Token, Envelope, Parent_Envelope);
   function Kind_Int (K : Revocation_Kind) return Natural;
   function Int_To_Kind (V : Natural) return Revocation_Kind;

   type Revocation_Event is record
      Revision     : Natural := 0;
      Event_Id     : Unbounded_String := Null_Unbounded_String;
      Kind         : Revocation_Kind := Key;
      Subject_Id   : Unbounded_String := Null_Unbounded_String;
      Issued_At_Ms : Long_Long_Integer := 0;
   end record;

   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Revocation_Event);

   type Revocation_Entry is record
      Kind       : Revocation_Kind := Key;
      Subject_Id : Unbounded_String := Null_Unbounded_String;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Revocation_Entry);

   type Revocation_Snapshot is record
      Revision       : Natural := 0;
      Entries        : Entry_Vectors.Vector;
      Generated_Ms   : Long_Long_Integer := 0;
   end record;

   --  The journal (thread-safe for single-threaded Ada)
   type Journal_Type is tagged private;

   function Create return Journal_Type;

   function Revision (J : Journal_Type) return Natural;

   --  Commit revocation. Returns True for new, False for duplicate.
   function Revoke
     (J         : in out Journal_Type;
      Kind      : Revocation_Kind;
      Subject   : String) return Boolean;

   function Snapshot (J : Journal_Type) return Revocation_Snapshot;

   function Events_After (J : Journal_Type; After : Natural)
     return Event_Vectors.Vector;

   function Oldest_Available (J : Journal_Type) return Natural;

private

   package String_Sets is new Ada.Containers.Hashed_Maps
     (Key_Type        => Unbounded_String,
      Element_Type    => Boolean,
      Hash            => Ada.Strings.Unbounded.Hash,
      Equivalent_Keys => "=");

   type Kind_Set_Array is array (Revocation_Kind) of String_Sets.Map;

   type Journal_Type is tagged record
      Rev     : Natural := 0;
      Events  : Event_Vectors.Vector;
      Revoked : Kind_Set_Array;
   end record;

end Hacp.Controlplane.Journal;
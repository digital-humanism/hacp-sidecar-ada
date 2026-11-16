--  Hacp.Json — minimal JSON value type and recursive-descent parser.
--  No external dependency. Ada 2012.

with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Hacp.Json is

   type JSON_Value_Kind is
     (JSON_Null, JSON_Boolean, JSON_Number,
      JSON_String, JSON_Array, JSON_Object);

   type JSON_Value (Kind : JSON_Value_Kind := JSON_Null);
   type JSON_Value_Access is access all JSON_Value;
   type JSON_Value_Array is array (Positive range <>) of JSON_Value_Access;

   --  Key-value pair for objects
   type JSON_Pair is record
      Key   : Unbounded_String := Null_Unbounded_String;
      Value : JSON_Value_Access := null;
   end record;

   package Pair_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => JSON_Pair);

   package Value_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => JSON_Value_Access);

   type JSON_Value (Kind : JSON_Value_Kind := JSON_Null) is record
      case Kind is
         when JSON_Null    => null;
         when JSON_Boolean => Bool_Val : Boolean := False;
         when JSON_Number  =>
            --  Store as string to preserve JCS fidelity
            Num_Int  : Long_Long_Integer := 0;
            Has_Int  : Boolean := True;
            Num_Flt  : Long_Float := 0.0;
            Has_Flt  : Boolean := False;
         when JSON_String  => Str_Val  : Unbounded_String := Null_Unbounded_String;
         when JSON_Array   => Arr      : Value_Vectors.Vector;
         when JSON_Object  => Pairs    : Pair_Vectors.Vector;
      end case;
   end record;

   --  Constructors
   function J_Null return JSON_Value_Access;
   function J_Bool (V : Boolean) return JSON_Value_Access;
   function J_Int  (V : Long_Long_Integer) return JSON_Value_Access;
   function J_Flt  (V : Long_Float) return JSON_Value_Access;
   function J_Str  (V : String) return JSON_Value_Access;
   function J_Arr  return JSON_Value_Access;
   function J_Obj  return JSON_Value_Access;

   --  Array helpers
   procedure Append (Arr : JSON_Value_Access; Item : JSON_Value_Access);

   --  Object helpers
   procedure Insert (Obj       : JSON_Value_Access;
                     Key       : String;
                     Value     : JSON_Value_Access);

   --  Query
   function Get (Obj : JSON_Value_Access; Key : String) return JSON_Value_Access;
   function Get (Arr : JSON_Value_Access; Index : Positive) return JSON_Value_Access;
   function Length (Arr : JSON_Value_Access) return Natural;
   function Has (Obj : JSON_Value_Access; Key : String) return Boolean;

   --  Extract typed values
   function Get_Str  (V : JSON_Value_Access) return String;
   function Get_Int  (V : JSON_Value_Access) return Long_Long_Integer;
   function Get_Bool (V : JSON_Value_Access) return Boolean;
   function Is_Null  (V : JSON_Value_Access) return Boolean;

   --  Parser
   function Parse (Text : String) return JSON_Value_Access;

   --  Serializer (compact, no whitespace — for JCS)
   function Serialize (V : JSON_Value_Access) return String;

   --  Clone (deep copy)
   function Clone (V : JSON_Value_Access) return JSON_Value_Access;

   --  Object without key (for signature computation)
   function Without_Key (Obj  : JSON_Value_Access;
                         Key  : String) return JSON_Value_Access;

   --  Utility: check if string field contains substring (case-insensitive)
   function Field_Contains (Obj       : JSON_Value_Access;
                            Key       : String;
                            Substring : String) return Boolean;

   --  Check if an object has a string field equal to value
   function Field_Equals (Obj   : JSON_Value_Access;
                          Key   : String;
                          Value : String) return Boolean;

end Hacp.Json;
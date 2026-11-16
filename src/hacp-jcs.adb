--  Hacp.Jcs — body.

package body Hacp.Jcs is

   function Canonicalize (V : JSON_Value_Access) return String is
   begin
      return Serialize (V);
   end Canonicalize;

   function Canonicalize (Text : String) return String is
      V : constant JSON_Value_Access := Parse (Text);
   begin
      return Serialize (V);
   end Canonicalize;

end Hacp.Jcs;
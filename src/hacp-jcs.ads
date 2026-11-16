--  Hacp.Jcs — JSON Canonicalization Scheme (RFC 8785).
--  Wraps Hacp.Json.Serialize which already produces sorted-key,
--  no-whitespace output.

with Hacp.Json;  use Hacp.Json;

package Hacp.Jcs is

   --  Canonicalize a JSON value to RFC 8785 bytes.
   --  Returns the compact serialization with sorted object keys.
   function Canonicalize (V : JSON_Value_Access) return String;

   --  Canonicalize raw JSON text.
   function Canonicalize (Text : String) return String;

end Hacp.Jcs;
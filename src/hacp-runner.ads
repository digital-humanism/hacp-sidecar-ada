--  Hacp.Runner — Protocol v1 stdin/stdout JSON lines.

with Hacp.Json;     use Hacp.Json;
with Hacp.Evaluate; use Hacp.Evaluate;

package Hacp.Runner is

   --  Process one request line, return response JSON line.
   function Handle_Line (Line : String; PK_Hex : String) return String;

   --  Run the main loop (never returns normally).
   procedure Run (PK_Hex : String);

end Hacp.Runner;
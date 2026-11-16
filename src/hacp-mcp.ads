--  Hacp.Mcp — MCP transport adapter (JSON-RPC 2.0 over stdio).
--  Same evaluate as runner and proxy. Fail-closed.

with Hacp.Json;    use Hacp.Json;
with Hacp.Evaluate; use Hacp.Evaluate;

package Hacp.Mcp is

   --  Process a single MCP JSON-RPC request, return response JSON.
   function Handle_Request
     (Request  : JSON_Value_Access;
      PK_Hex   : String;
      Clock    : Long_Long_Integer)
     return JSON_Value_Access;

   --  Run the MCP server loop (JSON-RPC over stdin/stdout).
   procedure Run (PK_Hex : String);

end Hacp.Mcp;
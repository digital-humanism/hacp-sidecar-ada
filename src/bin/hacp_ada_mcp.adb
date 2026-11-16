--  hacp-ada-mcp — MCP transport adapter (JSON-RPC over stdio).

with Hacp.Mcp;

procedure Hacp_Ada_Mcp is
   Test_Pubkey_Hex : constant String :=
     "9d17f1bbcc0845865e670f526413fb7a510380798fe300b6c98e28f3a3b0fdb3";
begin
   Hacp.Mcp.Run (Test_Pubkey_Hex);
end Hacp_Ada_Mcp;
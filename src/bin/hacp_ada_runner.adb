--  hacp-ada-runner — Protocol v1 conformance runner binary.
--  Reads JSON requests from stdin, writes JSON responses to stdout.

with Hacp.Runner;

procedure Hacp_Ada_Runner is
   --  Embedded conformance test public key (harness/keys/KEYS.md). TEST ONLY.
   Test_Pubkey_Hex : constant String :=
     "9d17f1bbcc0845865e670f526413fb7a510380798fe300b6c98e28f3a3b0fdb3";
begin
   Hacp.Runner.Run (Test_Pubkey_Hex);
end Hacp_Ada_Runner;
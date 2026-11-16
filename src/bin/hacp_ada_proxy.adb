--  hacp-ada-proxy — HTTP proxy transport adapter binary.
--  Same evaluate, fail-closed.

with Ada.Command_Line; use Ada.Command_Line;
with Hacp.Http;

procedure Hacp_Ada_Proxy is
   Test_Pubkey_Hex : constant String :=
     "9d17f1bbcc0845865e670f526413fb7a510380798fe300b6c98e28f3a3b0fdb3";
   Port : Natural := 8080;
begin
   --  Check environment for port override
   begin
      Port := Natural'Value
        (Ada.Command_Line.Argument (1));
   exception
      when others => null;
   end;
   Hacp.Http.Run_Server (Port, Test_Pubkey_Hex);
end Hacp_Ada_Proxy;
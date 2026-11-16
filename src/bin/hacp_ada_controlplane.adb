--  hacp-ada-controlplane — Gate E control plane (JSON-RPC over stdio).

with Hacp.Controlplane.Journal; use Hacp.Controlplane.Journal;
with Hacp.Controlplane.Server;  use Hacp.Controlplane.Server;

procedure Hacp_Ada_Controlplane is
   J    : Journal_Type := Create;
   Dummy : Boolean;
begin
   --  Seed with test revocation for demonstration
   Dummy := Revoke (J, Key, "test-revoked-key-001");
   Run (J);
end Hacp_Ada_Controlplane;
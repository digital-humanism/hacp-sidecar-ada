--  Hacp.Controlplane.Server — JSON-RPC stdio server for control plane.

with Hacp.Controlplane.Journal; use Hacp.Controlplane.Journal;

package Hacp.Controlplane.Server is

   --  Run the control plane JSON-RPC server over stdio.
   procedure Run (J : in out Journal_Type);

end Hacp.Controlplane.Server;
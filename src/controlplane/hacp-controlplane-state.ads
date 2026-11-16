with Hacp.Json;
with Hacp.Controlplane.Journal;

package Hacp.Controlplane.State is

   function To_Policy_Context
     (S     : Hacp.Controlplane.Journal.Revocation_Snapshot;
      Clock : Long_Long_Integer)
      return Hacp.Json.JSON_Value_Access;

end Hacp.Controlplane.State;

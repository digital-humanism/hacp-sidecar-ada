--  Hacp.Http — managed HTTP server using Ada Web Server (AWS).
--  Fail-closed. Same HACP evaluator as runner.
--
--  IMPORTANT:
--  HACP source does not manage sockets directly.
--  HTTP connection lifecycle is owned by AWS.Server.

package Hacp.Http is

   --  Run the HTTP proxy server on loopback at the given port.
   --  Never returns normally.
   procedure Run_Server (Port : Natural; PK_Hex : String);

end Hacp.Http;
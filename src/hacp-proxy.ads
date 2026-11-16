--  Hacp.Proxy — HTTP proxy transport adapter.
--  Same evaluate as runner. Fail-closed.
--  Headers: X-HACP-Intent-Envelope, X-HACP-Decision-Token (base64url).

with Hacp.Json;    use Hacp.Json;
with Hacp.Crypto;  use Hacp.Crypto;
with Hacp.Evaluate; use Hacp.Evaluate;

package Hacp.Proxy is

   --  Method → verb mapping
   function Method_To_Verb (Method : String) return String;

   --  Extract HACP header from "Key: Value" line
   function Extract_Hacp_Header
     (Header_Line : String;
      Header_Name : String) return JSON_Value_Access;

   --  Build evaluate input from HTTP components
   function Build_Evaluate_Input
     (Envelope       : JSON_Value_Access;
      Token          : JSON_Value_Access;
      Method         : String;
      Request_Target : String;
      Body_Hash      : String;
      Clock          : Long_Long_Integer)
     return JSON_Value_Access;

   --  Run proxy evaluation (fail-closed)
   function Proxy_Evaluate
     (Envelope       : JSON_Value_Access;
      Token          : JSON_Value_Access;
      Method         : String;
      Request_Target : String;
      Body           : String;
      PK_Hex         : String;
      Clock          : Long_Long_Integer)
     return Eval_Result;

end Hacp.Proxy;
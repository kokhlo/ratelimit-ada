--  Token bucket and fixed window rate limiters for Ada.
--
--  This package provides two complementary admission-control policies:
--
--    * Rate_Limit.Token_Bucket: smooth average-rate control with burst
--      tolerance. Tokens accrue at Rate per second up to Burst capacity;
--      each allowed request consumes one token.
--
--    * Rate_Limit.Fixed_Window: hard per-window quotas (e.g. 100 requests
--      per 60 seconds). Simple and predictable, with the usual boundary
--      burst of up to 2x quota across a window edge.
--
--  Both limiters are deterministic given the clock values the caller
--  supplies, which keeps them unit-testable without sleeping.
with Ada.Containers;
with Ada.Strings;

package Rate_Limit is

   --  Common result of an admission check.
   type Decision is
     (Allowed,          --  request admitted; budget consumed
      Denied,           --  budget exhausted; retry after Retry_After
      Rejected);        --  parameters invalid; limiter not configured

   --  Denied decisions carry a recommended wait time (seconds) after
   --  which the caller may retry.
   type Limiter_Result is record
      Outcome     : Decision := Rejected;
      Retry_After : Duration := 0.0;
   end record;

   Version : constant String := "0.1.0";

   --  Shared key helpers used by the child policies. Keys are compared
   --  case-insensitively (API-token ergonomics: "Client-1" and
   --  "CLIENT-1" share one budget).
   function Key_Hash (Key : String) return Ada.Containers.Hash_Type;
   function Same_Key (Left, Right : String) return Boolean;

end Rate_Limit;

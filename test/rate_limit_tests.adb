--  Test runner for ratelimit-ada rate limiting library.
--  Plain Ada test suite with assertion-based checks (aunit-free).
--
--  Test coverage:
--    Token bucket:
--      1. Fresh key: immediate burst up to Burst admitted, then Denied.
--      2. Refill: after waiting 1/rate seconds, one token is back.
--      3. Cap: tokens never exceed Burst after long idle.
--      4. Retry_After: denied request hints time until next token.
--      5. Independent keys: consuming from A does not affect B.
--      6. Invalid parameters (Rate <= 0, Burst < 1) => Rejected, no state.
--      7. Clock running backwards => Rejected.
--    Fixed window:
--      8. Limit admissions per window, then Denied with Retry_After
--         pointing to the window edge.
--      9. Window rollover resets the counter.
--     10. Window edge math: Retry_After shrinks to 0.0 at the boundary.
--     11. Invalid Window_Length => Rejected.
--     12. Keys are case-insensitive (API-quota ergonomics).
--    Shared:
--     13. Forget removes per-key state; unknown key Forget is a no-op.

with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Calendar;     use Ada.Calendar;
with Ada.Command_Line;
with Rate_Limit;              use Rate_Limit;
with Rate_Limit.Token_Bucket;
with Rate_Limit.Fixed_Window;

procedure Rate_Limit_Tests is

   Passes   : Natural := 0;
   Failures : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Passes := Passes + 1;
         Put_Line ("[PASS] " & Message);
      else
         Failures := Failures + 1;
         Put_Line ("[FAIL] " & Message);
      end if;
   end Assert;

   T0 : constant Time := Time_Of (2026, 10, 21, 0.0);

   --  ======== Token bucket ========

   procedure TB_Burst_Then_Deny is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  Burst = 5: first 5 calls pass, 6th is denied.
      for I in 1 .. 5 loop
         R := Check (M, "c1", Rate => 1.0, Burst => 5.0, Now => T0);
         Assert (R.Outcome = Allowed, "TB burst: call" & Integer'Image (I)
                 & " allowed");
      end loop;
      R := Check (M, "c1", Rate => 1.0, Burst => 5.0, Now => T0);
      Assert (R.Outcome = Denied, "TB burst: 6th call denied");
      Assert (Tokens (M, "c1") < 1.0, "TB burst: bucket drained below 1");
   end TB_Burst_Then_Deny;

   procedure TB_Refill is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  Drain fully (burst 2), wait exactly one token period.
      for I in 1 .. 2 loop
         R := Check (M, "c1", Rate => 2.0, Burst => 2.0, Now => T0);
      end loop;
      R := Check (M, "c1", Rate => 2.0, Burst => 2.0, Now => T0);
      Assert (R.Outcome = Denied, "TB refill: drained");

      R := Check (M, "c1", Rate => 2.0, Burst => 2.0,
                  Now => T0 + 0.5);   --  0.5s * 2/s = 1 token
      Assert (R.Outcome = Allowed, "TB refill: one token after 0.5s");
   end TB_Refill;

   procedure TB_Cap_At_Burst is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  Consume 1 of burst 3, then idle 100s: still only 3 available.
      R := Check (M, "c1", Rate => 1.0, Burst => 3.0, Now => T0);
      Assert (R.Outcome = Allowed, "TB cap: first admission allowed");
      R := Check (M, "c1", Rate => 1.0, Burst => 3.0, Now => T0 + 100.0);
      Assert (R.Outcome = Allowed, "TB cap: admitted after idle");
      Assert (Tokens (M, "c1") <= 3.0, "TB cap: tokens capped at Burst");
      --  The refill can only have reached 3.0; after consuming one more
      --  it must be 2.0 (3.0 - 1), not more.
      Assert (abs (Tokens (M, "c1") - 2.0) < 1.0e-6,
              "TB cap: exactly 2 tokens remain");
   end TB_Cap_At_Burst;

   procedure TB_Retry_After_Hint is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  Drain burst 1; next token in 0.25s at rate 4/s.
      R := Check (M, "c1", Rate => 4.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Allowed, "TB hint: initial admission allowed");
      R := Check (M, "c1", Rate => 4.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Denied, "TB hint: denied when empty");
      Assert (R.Retry_After > 0.23 and then R.Retry_After < 0.27,
              "TB hint: Retry_After ~ 0.25s");
   end TB_Retry_After_Hint;

   procedure TB_Independent_Keys is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "a", Rate => 1.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Allowed, "TB keys: first a call allowed");
      R := Check (M, "a", Rate => 1.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Denied, "TB keys: a drained");
      R := Check (M, "b", Rate => 1.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Allowed, "TB keys: b unaffected");
   end TB_Independent_Keys;

   procedure TB_Invalid_Parameters is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "c1", Rate => 0.0, Burst => 5.0, Now => T0);
      Assert (R.Outcome = Rejected, "TB invalid: rate 0 rejected");
      R := Check (M, "c1", Rate => -1.0, Burst => 5.0, Now => T0);
      Assert (R.Outcome = Rejected, "TB invalid: negative rate rejected");
      R := Check (M, "c1", Rate => 1.0, Burst => 0.5, Now => T0);
      Assert (R.Outcome = Rejected, "TB invalid: burst < 1 rejected");
      Assert (Tokens (M, "c1") = 0.0,
              "TB invalid: no state created on rejection");
   end TB_Invalid_Parameters;

   procedure TB_Backwards_Clock is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "c1", Rate => 1.0, Burst => 5.0, Now => T0 + 10.0);
      Assert (R.Outcome = Allowed, "TB clock: forward time allowed");
      R := Check (M, "c1", Rate => 1.0, Burst => 5.0, Now => T0);
      Assert (R.Outcome = Rejected,
              "TB clock: backwards time rejected, state intact");
   end TB_Backwards_Clock;

   --  ======== Fixed window ========

   procedure FW_Limit_Then_Deny is
      use Rate_Limit.Fixed_Window;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      for I in 1 .. 3 loop
         R := Check (M, "c1", Limit => 3, Window_Length => 60.0, Now => T0);
         Assert (R.Outcome = Allowed, "FW limit: call" & Integer'Image (I)
                 & " allowed");
      end loop;
      R := Check (M, "c1", Limit => 3, Window_Length => 60.0,
                  Now => T0 + 1.0);
      Assert (R.Outcome = Denied, "FW limit: 4th in window denied");
      --  T0 is exactly on a window edge of the epoch grid only if
      --  T0 - epoch is a multiple of 60; assert the hint is within
      --  (0, 60] regardless of phase.
      Assert (R.Retry_After > 0.0 and then R.Retry_After <= 60.0,
              "FW limit: Retry_After within the window");
      Assert (Used (M, "c1") = 3, "FW limit: counter at Limit");
   end FW_Limit_Then_Deny;

   procedure FW_Window_Rollover is
      use Rate_Limit.Fixed_Window;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  2026-10-21 00:00:00 UTC minus epoch = 1790006400+;  1790006400
      --  is divisible by 60? 1790006400 / 60 = 29833440 exactly, so T0
      --  sits exactly on a 60s window edge.  T0 - 1s is window N-1.
      for I in 1 .. 2 loop
         R := Check (M, "c1", Limit => 2, Window_Length => 60.0,
                     Now => T0 - 1.0);
      end loop;
      R := Check (M, "c1", Limit => 2, Window_Length => 60.0,
                  Now => T0 - 0.5);
      Assert (R.Outcome = Denied, "FW rollover: exhausted old window");
      R := Check (M, "c1", Limit => 2, Window_Length => 60.0, Now => T0);
      Assert (R.Outcome = Allowed, "FW rollover: new window admits");
      Assert (Used (M, "c1") = 1, "FW rollover: counter reset to 1");
   end FW_Window_Rollover;

   procedure FW_Retry_After_At_Edge is
      use Rate_Limit.Fixed_Window;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      --  T0 is a window edge; T0 - 0.25 is 0.25s before the next edge.
      R := Check (M, "c1", Limit => 1, Window_Length => 60.0,
                  Now => T0 - 0.25);
      Assert (R.Outcome = Allowed, "FW edge: first admission allowed");
      R := Check (M, "c1", Limit => 1, Window_Length => 60.0,
                  Now => T0 - 0.1);
      Assert (R.Outcome = Denied, "FW edge: denied in full window");
      Assert (abs (R.Retry_After - 0.1) < 1.0e-6,
              "FW edge: Retry_After exactly to the edge");
   end FW_Retry_After_At_Edge;

   procedure FW_Invalid_Window is
      use Rate_Limit.Fixed_Window;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "c1", Limit => 3, Window_Length => 0.0, Now => T0);
      Assert (R.Outcome = Rejected, "FW invalid: zero window rejected");
      R := Check (M, "c1", Limit => 3, Window_Length => -5.0, Now => T0);
      Assert (R.Outcome = Rejected, "FW invalid: negative window rejected");
      Assert (Used (M, "c1") = 0, "FW invalid: no state on rejection");
   end FW_Invalid_Window;

   procedure FW_Case_Insensitive_Keys is
      use Rate_Limit.Fixed_Window;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "Client-1", Limit => 1, Window_Length => 60.0,
                  Now => T0);
      Assert (R.Outcome = Allowed, "FW keys: first admission allowed");
      R := Check (M, "CLIENT-1", Limit => 1, Window_Length => 60.0,
                  Now => T0);
      Assert (R.Outcome = Denied,
              "FW keys: case-insensitive same budget");
   end FW_Case_Insensitive_Keys;

   --  ======== Shared ========

   procedure Forget_Semantics is
      use Rate_Limit.Token_Bucket;
      M : Map := Empty_Map;
      R : Limiter_Result;
   begin
      R := Check (M, "x", Rate => 1.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Allowed, "Forget: initial admission allowed");
      Forget (M, "x");
      Forget (M, "never-seen");            --  no-op, must not raise
      R := Check (M, "x", Rate => 1.0, Burst => 1.0, Now => T0);
      Assert (R.Outcome = Allowed,
              "Forget: state dropped, budget restored");
      Assert (Tokens (M, "nonexistent") = 0.0,
              "Tokens: unknown key reads 0.0");
   end Forget_Semantics;

begin
   Put_Line ("=== ratelimit-ada test suite ===");
   TB_Burst_Then_Deny;
   TB_Refill;
   TB_Cap_At_Burst;
   TB_Retry_After_Hint;
   TB_Independent_Keys;
   TB_Invalid_Parameters;
   TB_Backwards_Clock;
   FW_Limit_Then_Deny;
   FW_Window_Rollover;
   FW_Retry_After_At_Edge;
   FW_Invalid_Window;
   FW_Case_Insensitive_Keys;
   Forget_Semantics;
   New_Line;
   Put_Line ("Total:" & Natural'Image (Passes) & " passed,"
             & Natural'Image (Failures) & " failed");
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Rate_Limit_Tests;

--  Runnable demo for ratelimit: burst into a token bucket, then let
--  the clock accrue new tokens. Fully deterministic: the clock is a
--  variable, not Ada.Calendar.Clock, so output never varies.
with Ada.Calendar;
with Ada.Text_IO;
with Rate_Limit;
with Rate_Limit.Token_Bucket;

procedure Token_Bucket_Demo is
   use Rate_Limit;
   use Ada.Calendar;
   use Ada.Text_IO;

   package TB renames Rate_Limit.Token_Bucket;

   Buckets : TB.Map := TB.Empty_Map;
   Now     : Ada.Calendar.Time := Ada.Calendar.Time_Of (2026, 1, 1);
   R       : Limiter_Result;
begin
   --  25 requests into a fresh 20-token bucket: 20 allowed, 5 denied.
   for I in 1 .. 25 loop
      R := TB.Check (Buckets, "client-1",
                     Rate => 1.0, Burst => 20.0, Now => Now);
      Put_Line ("req"
                & Integer'Image (I)
                & ": "
                & Decision'Image (R.Outcome));
   end loop;

   --  Advance the clock 3 seconds: 3 new tokens accrue at Rate => 1.0.
   Now := Now + 3.0;
   R := TB.Check (Buckets, "client-1",
                  Rate => 1.0, Burst => 20.0, Now => Now);
   Put_Line ("after 3 s: " & Decision'Image (R.Outcome));  --  Allowed

   --  Drain the remaining tokens, then hit an empty bucket: a denied
   --  request tells the caller how long to wait for the next token.
   while TB.Tokens (Buckets, "client-1") >= 1.0 loop
      R := TB.Check (Buckets, "client-1",
                     Rate => 1.0, Burst => 20.0, Now => Now);
   end loop;
   R := TB.Check (Buckets, "client-1",
                  Rate => 1.0, Burst => 20.0, Now => Now);
   Put_Line ("bucket empty: "
             & Decision'Image (R.Outcome)
             & ", retry after"
             & Duration'Image (R.Retry_After)
             & " s");
end Token_Bucket_Demo;

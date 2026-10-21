package body Rate_Limit.Token_Bucket is

   use type Ada.Calendar.Time;

   function Check
     (Buckets : in out Map;
      Key     : String;
      Rate    : Long_Float;
      Burst   : Long_Float;
      Now     : Ada.Calendar.Time)
      return Limiter_Result
   is
      Rejected_Result : constant Limiter_Result :=
        (Outcome => Rejected, Retry_After => 0.0);
   begin
      --  Reject invalid configuration up front; state untouched.
      if Rate <= 0.0 or else Burst < 1.0 then
         return Rejected_Result;
      end if;

      declare
         use Key_Maps;
         Cur : constant Cursor := Buckets.Find (Key);
      begin
         --  Unknown key: start from a full bucket, consume one token.
         if Cur = No_Element then
            Buckets.Insert
              (Key, (Tokens => Burst - 1.0, Updated => Now));
            return (Outcome => Allowed, Retry_After => 0.0);
         end if;

         --  Known key: refill according to elapsed time, then try to
         --  consume one token.
         declare
            B       : constant Bucket  := Element (Cur);
            Elapsed : constant Long_Float :=
              Long_Float (Now - B.Updated);
            Filled  : constant Long_Float :=
              Long_Float'Min (Burst, B.Tokens + Elapsed * Rate);
         begin
            if Now < B.Updated then
               --  Clock running backwards: refuse rather than corrupt.
               return Rejected_Result;
            end if;

            if Filled >= 1.0 then
               Buckets.Replace_Element
                 (Cur, (Tokens => Filled - 1.0, Updated => Now));
               return (Outcome => Allowed, Retry_After => 0.0);
            else
               --  Keep the refilled state so accrued progress is kept.
               Buckets.Replace_Element
                 (Cur, (Tokens => Filled, Updated => Now));
               return (Outcome => Denied,
                       Retry_After => Duration ((1.0 - Filled) / Rate));
            end if;
         end;
      end;
   end Check;

   function Tokens (Buckets : Map; Key : String) return Long_Float is
      use Key_Maps;
      Cur : constant Cursor := Buckets.Find (Key);
   begin
      if Cur = No_Element then
         return 0.0;
      else
         return Element (Cur).Tokens;
      end if;
   end Tokens;

   procedure Forget (Buckets : in out Map; Key : String) is
      use Key_Maps;
   begin
      Buckets.Exclude (Key);
   end Forget;

end Rate_Limit.Token_Bucket;

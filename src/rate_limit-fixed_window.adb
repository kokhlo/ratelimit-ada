package body Rate_Limit.Fixed_Window is

   --  Anchor fixing the window phase grid. Any constant time works;
   --  the anchor's own representation error is common to every call,
   --  so it can never split one true window into two.
   Anchor : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);

   --  Nanoseconds per second; at least as fine as any platform's
   --  Duration'Small, so tick counts are always exact integers.
   Ns_Per_S : constant := 10**9;

   --  Start of the window containing Now (floor-aligned to Anchor).
   function Window_Start
     (Now : Ada.Calendar.Time; Length : Duration) return Ada.Calendar.Time;

   function Window_Start
     (Now : Ada.Calendar.Time; Length : Duration) return Ada.Calendar.Time
   is
      use type Ada.Calendar.Time;
      --  Duration -> integer conversion rounds, which would move times
      --  near a window edge across it.  Split into whole seconds (where
      --  rounding is harmless) plus the exact sub-second remainder.
      S      : constant Duration := Now - Anchor;
      Whole  : constant Long_Integer := Long_Integer (S);
      Frac   : constant Duration := S - Duration (Whole);
      E      : constant Long_Integer :=
        Whole * Ns_Per_S + Long_Integer (Frac * Ns_Per_S);
      L      : constant Long_Integer := Long_Integer (Length) * Ns_Per_S;
      Q : Long_Integer := E / L;          --  truncates toward zero
      R : Long_Integer := E - Q * L;      --  sign of E
   begin
      --  Floored division: remainder must be in [0, L) so that window
      --  indexes are non-decreasing in Now.
      if R < 0 then
         R := R + L;
         Q := Q - 1;
      end if;
      return Anchor + Duration (Q) * Length;
   end Window_Start;

   function Check
     (Windows       : in out Map;
      Key           : String;
      Limit         : Positive;
      Window_Length : Duration;
      Now           : Ada.Calendar.Time)
      return Limiter_Result
   is
      use type Ada.Calendar.Time;
   begin
      if Window_Length <= 0.0 then
         return (Outcome => Rejected, Retry_After => 0.0);
      end if;

      declare
         use Key_Maps;
         Cur   : constant Cursor := Windows.Find (Key);
         Start : constant Ada.Calendar.Time :=
           Window_Start (Now, Window_Length);
      begin
         if Cur = No_Element then
            Windows.Insert (Key, (Count => 1, Start => Start));
            return (Outcome => Allowed, Retry_After => 0.0);
         end if;

         declare
            W : constant Window_Count := Element (Cur);
         begin
            if W.Start /= Start then
               --  New window: the old counter is stale, start fresh.
               --  Limit is Positive, so the first admission always fits.
               Windows.Replace_Element
                 (Cur, (Count => 1, Start => Start));
               return (Outcome => Allowed, Retry_After => 0.0);
            elsif W.Count < Limit then
               Windows.Replace_Element
                 (Cur, (Count => W.Count + 1, Start => Start));
               return (Outcome => Allowed, Retry_After => 0.0);
            else
               --  Quota exhausted; retry at the next window edge.
               return (Outcome => Denied,
                       Retry_After => (Start + Window_Length) - Now);
            end if;
         end;
      end;
   end Check;

   function Used (Windows : Map; Key : String) return Natural is
      use Key_Maps;
      Cur : constant Cursor := Windows.Find (Key);
   begin
      if Cur = No_Element then
         return 0;
      else
         return Element (Cur).Count;
      end if;
   end Used;

   procedure Forget (Windows : in out Map; Key : String) is
   begin
      Windows.Exclude (Key);
   end Forget;

end Rate_Limit.Fixed_Window;

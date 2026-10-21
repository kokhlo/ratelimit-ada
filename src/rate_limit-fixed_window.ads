--  Fixed window rate limiter.
--
--  Divides time into windows of Window_Length seconds and keeps a
--  per-key counter of admissions in the current window. Once the
--  counter reaches Limit, further requests in the same window are
--  Denied with a Retry_After pointing at the window edge. A key's
--  counter resets automatically when a new window begins.
--
--  Window boundaries are computed with exact Duration arithmetic, so
--  times that fall exactly on a window edge always start a new window,
--  regardless of the platform's Ada.Calendar tick quantization.
--
--  Deterministic given caller-supplied time. Classic caveat applies:
--  up to 2 * Limit requests can pass across a single window boundary.
--  When smoothness matters, prefer Rate_Limit.Token_Bucket.
with Ada.Calendar;
with Ada.Containers.Indefinite_Hashed_Maps;

package Rate_Limit.Fixed_Window is

   --  Per-key state: admissions consumed in the window starting at
   --  Start. Managed by Check; visible but to be treated as opaque.
   type Window_Count is record
      Count : Natural          := 0;   --  admissions in this window
      Start : Ada.Calendar.Time;       --  when this window began
   end record;

   package Key_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Window_Count,
      Hash            => Key_Hash,
      Equivalent_Keys => Same_Key);

   subtype Map is Key_Maps.Map;

   Empty_Map : Map renames Key_Maps.Empty_Map;

   --  Check (and consume) budget for Key.
   --
   --  Limit         : admissions allowed per window (>= 1)
   --  Window_Length : window size in seconds (> 0)
   --  Now           : current time
   function Check
     (Windows       : in out Map;
      Key           : String;
      Limit         : Positive;
      Window_Length : Duration;
      Now           : Ada.Calendar.Time)
      return Limiter_Result;

   --  Admissions consumed by Key in its most recent window (0 if
   --  unknown). Note: does not roll the window forward; the value
   --  becomes stale once Check sees a newer time.
   function Used (Windows : Map; Key : String) return Natural;

   --  Drop all state for Key.
   procedure Forget (Windows : in out Map; Key : String);

   --  Erase all windows.
   procedure Clear (Windows : in out Map) renames Key_Maps.Clear;

end Rate_Limit.Fixed_Window;

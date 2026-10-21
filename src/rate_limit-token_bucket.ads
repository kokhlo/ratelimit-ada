--  Token bucket rate limiter.
--
--  Tokens accrue continuously at Rate tokens/second into a bucket of
--  capacity Burst. Each Allowed request consumes one token. When the
--  bucket is empty, requests are Denied with a Retry_After hint telling
--  how long until one full token has accrued.
--
--  The caller supplies the current time (Ada.Calendar.Clock or any
--  monotonic source), so behaviour is fully deterministic in tests.
--
--  Typical use (allow 10 requests/s with bursts of 20):
--
--     Buckets : Token_Bucket.Map := Token_Bucket.Empty_Map;
--     ...
--     R : constant Limiter_Result :=
--           Token_Bucket.Check (Buckets, "client-1",
--                               Rate  => 10.0,
--                               Burst => 20.0,
--                               Now   => Ada.Calendar.Clock);
--     if R.Outcome = Allowed then ... end if;
with Ada.Calendar;
with Ada.Containers.Indefinite_Hashed_Maps;

package Rate_Limit.Token_Bucket is

   --  Per-key bucket state. Managed internally by Check; the record
   --  is visible but callers should treat it as opaque.
   type Bucket is record
      Tokens  : Long_Float;        --  current fill
      Updated : Ada.Calendar.Time; --  last refill point
   end record;

   --  A map from client key to bucket state. Not task-safe by itself:
   --  guard with a protected object when shared between tasks.
   package Key_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Bucket,
      Hash            => Key_Hash,
      Equivalent_Keys => Same_Key);

   subtype Map is Key_Maps.Map;

   Empty_Map : Map renames Key_Maps.Empty_Map;

   --  Check (and consume) budget for Key.
   --
   --  Rate  : sustained requests per second (> 0)
   --  Burst : bucket capacity in tokens (>= 1); the initial fill equals
   --          Burst, so a fresh key tolerates an immediate burst of
   --          Integer (Burst) requests.
   --  Now   : current time; must be non-decreasing across calls for the
   --          same key (monotonic sources are ideal).
   --
   --  Returns Rejected for invalid parameters (Rate <= 0, Burst < 1) or
   --  a clock running backwards (bucket state stays untouched).
   function Check
     (Buckets : in out Map;
      Key     : String;
      Rate    : Long_Float;
      Burst   : Long_Float;
      Now     : Ada.Calendar.Time)
      return Limiter_Result;

   --  Number of tokens currently available for Key (0.0 if unknown).
   function Tokens (Buckets : Map; Key : String) return Long_Float;

   --  Drop all state for Key. Has no effect if the key is unknown.
   procedure Forget (Buckets : in out Map; Key : String);

   --  Erase all buckets.
   procedure Clear (Buckets : in out Map) renames Key_Maps.Clear;

end Rate_Limit.Token_Bucket;
